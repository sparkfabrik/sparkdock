#!/usr/bin/env swift

import Cocoa
import Foundation
import ServiceManagement
import os.log
import Network

// MARK: - Configuration Constants
private struct AppConstants {
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    static let checkUpdatesExecutablePath = "/opt/sparkdock/bin/sparkdock-check-updates"
    static let logoResourceName = "sparkfabrik-logo"
    static let menuConfigResourceName = "menu"
    static let iconSize = NSSize(width: 18, height: 18)
    static let bundleIdentifier = "com.sparkfabrik.sparkdock.menubar"
    static let processTimeout: TimeInterval = 30.0
    /// The `brew` check downloads from the Homebrew API, and `vulns` queries OSV.dev per
    /// formula: about ten seconds each, more on a slow network.
    static let brewCheckTimeout: TimeInterval = 120.0
    static let loggerSubsystem = "com.sparkfabrik.sparkdock.manager"
    static let logger = Logger(subsystem: loggerSubsystem, category: "MenuBar")
}

// MARK: - Configuration Models
fileprivate struct MenuConfig: Codable {
    let version: String
    let menu: MenuStructure
}

fileprivate struct MenuStructure: Codable {
    let sections: [MenuSection]
}

fileprivate struct MenuSection: Codable {
    let name: String
    let items: [MenuItem]
}

fileprivate struct MenuItem: Codable {
    let title: String
    let type: MenuItemType
    let command: String?
    let url: String?
    /// Name of an executable this item depends on. When set and that executable is
    /// not on the machine, the item is left out of the menu entirely: an entry that
    /// only produces "command not found" is worse than no entry, and every developer
    /// would otherwise carry menu items for tools they have not installed.
    let requiresBinary: String?

    enum MenuItemType: String, Codable {
        case command = "command"
        case url = "url"
    }

    enum CodingKeys: String, CodingKey {
        case title, type, command, url
        case requiresBinary = "requires_binary"
    }
}

// MARK: - Darwin Notification Names (for post-upgrade recheck)
private enum RecheckNotification {
    static let prefix = "com.sparkfabrik.sparkdock.recheck"
    static let sparkdock = "\(prefix).sparkdock"
    static let brew = "\(prefix).brew"
    static let httpProxy = "\(prefix).http-proxy"
    static let agents = "\(prefix).agents"
    static let timetracker = "\(prefix).timetracker"
    static let engram = "\(prefix).engram"
    static let all = [sparkdock, brew, httpProxy, agents, timetracker, engram]
}

// MARK: - Menu Item Tags
private enum MenuItemTag: Int {
    case loginItem = 1
}

// MARK: - Async Utilities
enum ProcessTimeoutError: Error {
    case timedOut
}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ProcessTimeoutError.timedOut
        }

        guard let result = try await group.next() else {
            throw ProcessTimeoutError.timedOut
        }

        group.cancelAll()
        return result
    }
}

private final class ProcessExecutionState: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancellationRequested = false

    init(process: Process) {
        self.process = process
    }

    func run() async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            lock.lock()

            guard !cancellationRequested else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }

            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                lock.unlock()
            } catch {
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        if process.isRunning {
            process.terminate()
        }
        lock.unlock()
    }
}

func runProcessWithTimeout(_ process: Process, seconds: TimeInterval) async throws -> Int32 {
    let execution = ProcessExecutionState(process: process)
    return try await withTimeout(seconds: seconds) {
        try await withTaskCancellationHandler(
            operation: {
                try await execution.run()
            },
            onCancel: {
                execution.cancel()
            }
        )
    }
}

/// Runs a check and returns its exit code and output. Output is read only when
/// `capturesOutput` is set: it is read after exit, so a command that prints more than
/// the pipe holds (64 KB) would block until the timeout.
func runCheckProcess(_ process: Process, capturesOutput: Bool, seconds: TimeInterval) async throws -> (exitCode: Int32, output: String) {
    let outputPipe = capturesOutput ? Pipe() : nil
    process.standardOutput = outputPipe ?? FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let exitCode = try await runProcessWithTimeout(process, seconds: seconds)
    let output = outputPipe.map { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" } ?? ""
    return (exitCode, output)
}

// MARK: - Darwin Notification Callback (C-compatible, must be top-level)
private let darwinRecheckCallback: CFNotificationCallback = { _, observer, name, _, _ in
    guard let observer = observer else { return }
    let app = Unmanaged<SparkdockMenubarApp>.fromOpaque(observer).takeUnretainedValue()
    guard let notificationName = name?.rawValue as String? else { return }
    AppConstants.logger.info("Received Darwin recheck notification: \(notificationName)")
    app.handleRecheckNotification(notificationName)
}

private final class MenuSectionHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")

    var title: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(title: String, trailingView: NSView? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 34))
        autoresizingMask = [.width]

        label.stringValue = title
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        var constraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]

        if let trailingView = trailingView {
            trailingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(trailingView)
            constraints.append(contentsOf: [
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingView.leadingAnchor, constant: -8),
                trailingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                trailingView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            constraints.append(label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12))
        }

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

private final class ClaudeUsageRowView: NSView {
    private let statusImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let badgeField = NSTextField(labelWithString: "")
    private var badgeWidthConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        autoresizingMask = [.width]

        statusImageView.translatesAutoresizingMaskIntoConstraints = false
        statusImageView.imageScaling = .scaleProportionallyDown

        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        subtitleField.font = NSFont.systemFont(ofSize: 13)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        badgeField.translatesAutoresizingMaskIntoConstraints = false
        badgeField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        badgeField.textColor = .labelColor
        badgeField.alignment = .center
        badgeField.wantsLayer = true
        badgeField.layer?.cornerRadius = 11
        badgeField.layer?.masksToBounds = true

        addSubview(statusImageView)
        addSubview(textStack)
        addSubview(badgeField)

        badgeWidthConstraint = badgeField.widthAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            statusImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            statusImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusImageView.widthAnchor.constraint(equalToConstant: 10),
            statusImageView.heightAnchor.constraint(equalToConstant: 10),
            textStack.leadingAnchor.constraint(equalTo: statusImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: badgeField.leadingAnchor, constant: -12),
            badgeField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badgeField.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeField.heightAnchor.constraint(equalToConstant: 22),
            badgeWidthConstraint
        ])

        updateBadgeAppearance()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBadgeAppearance()
    }

    func update(title: String, badge: String, subtitle: String?, statusImage: NSImage) {
        titleField.stringValue = title
        badgeField.stringValue = badge
        subtitleField.stringValue = subtitle ?? ""
        subtitleField.isHidden = subtitle == nil
        statusImageView.image = statusImage
        badgeWidthConstraint.constant = max(44, ceil(badgeField.intrinsicContentSize.width) + 16)
    }

    private func updateBadgeAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            badgeField.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }
}

class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menu: NSMenu?
    var sparkdockStatus: CheckStatus = .unavailable
    var brewStatus: CheckStatus = .unavailable
    /// Counts behind the Homebrew badge and tooltips; nil unless Homebrew needs attention.
    var brewOutdated: BrewOutdatedSummary?
    /// Starts as not configured, so the row stays hidden until a check answers.
    var brewVulnsStatus: CheckStatus = .notConfigured
    var httpProxyStatus: CheckStatus = .unavailable
    var agentsStatus: CheckStatus = .unavailable
    var claudeUsageStatus: ClaudeUsageStatus?
    var timetrackerStatus: CheckStatus = .unavailable
    var engramStatus: CheckStatus = .unavailable
    /// Generation counter to discard stale full-check results after a per-subsystem recheck
    private var checkGeneration: Int = 0
    private var systemStatusCheckGeneration: Int = 0
    private var claudeUsageCheckGeneration: Int = 0
    /// When the last Claude usage check started or landed, used to throttle the
    /// refresh triggered by opening the menu.
    private var claudeUsageLastCheckedAt: Date?
    var statusMenuItem: NSMenuItem?
    var refreshSystemStatusButton: NSButton?
    var sparkdockStatusMenuItem: NSMenuItem?
    var brewStatusMenuItem: NSMenuItem?
    var brewVulnsStatusMenuItem: NSMenuItem?
    var httpProxyStatusMenuItem: NSMenuItem?
    var agentsStatusMenuItem: NSMenuItem?
    var claudeUsageSectionMenuItem: NSMenuItem?
    var claudeCurrentUsageMenuItem: NSMenuItem?
    var claudeWeeklyUsageMenuItem: NSMenuItem?
    var refreshClaudeUsageButton: NSButton?
    var claudeUsageSectionSeparator: NSMenuItem?
    var timetrackerStatusMenuItem: NSMenuItem?
    var engramStatusMenuItem: NSMenuItem?
    private var pathMonitor: NWPathMonitor?
    private var lastNetworkFingerprint: NetworkFingerprint?
    private var dailyCheckScheduler: NSBackgroundActivityScheduler?
    /// The full check in flight, so automatic triggers do not stack overlapping runs.
    private var fullCheckTask: Task<Void, Never>?
    fileprivate var menuConfig: MenuConfig?
    /// Dynamic menu entries gated on `requires_binary`, kept so their visibility can
    /// be re-evaluated on every UI refresh instead of only at menu construction.
    fileprivate var dynamicMenuSections: [(header: NSMenuItem, separator: NSMenuItem, entries: [(menuItem: NSMenuItem, config: MenuItem)])] = []
    // Cache icons to avoid recreating them
    private var cachedNormalIcon: NSImage?
    private var cachedUpdateIcon: NSImage?
    private var cachedLogoImage: NSImage?

    private func showErrorAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func statusDot(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let coloredCircle = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect)
            color.setFill()
            path.fill()
            return true
        }
        coloredCircle.isTemplate = false
        return coloredCircle
    }

    private func updateStatusMenuItem(_ item: NSMenuItem?, title: String, badge: String, subtitle: String? = nil, color: NSColor) {
        guard let item = item else { return }
        let dot = statusDot(color: color)
        if let usageRow = item.view as? ClaudeUsageRowView {
            usageRow.update(title: title, badge: badge, subtitle: subtitle, statusImage: dot)
            return
        }

        item.attributedTitle = nil
        item.title = title
        item.badge = NSMenuItemBadge(string: badge)
        item.image = dot
    }

    private func setStatusMenuItemAction(_ item: NSMenuItem?, action: Selector?) {
        item?.action = action
        item?.target = action == nil ? nil : self
        item?.isEnabled = action != nil
    }

    /// Draws one System status row from its check state. Every state has a default
    /// badge and color; rows pass their actions, a not-configured label, and a tooltip.
    private func renderStatusRow(_ item: NSMenuItem?, title: String, status: CheckStatus, upgradeAction: Selector, okAction: Selector? = nil, notConfiguredBadge: String = "Not configured", notConfiguredAction: Selector? = nil, tooltip: String? = nil) {
        let badge: String
        let color: NSColor
        let action: Selector?
        switch status {
        case .needsAttention(let customBadge):
            badge = customBadge ?? "Upgrade"
            color = .systemOrange
            action = upgradeAction
        case .ok(let customBadge):
            badge = customBadge ?? "Up to date"
            color = .systemGreen
            action = okAction
        case .notConfigured:
            badge = notConfiguredBadge
            color = .systemGray
            action = notConfiguredAction
        case .unavailable:
            badge = "Unavailable"
            color = .systemGray
            action = nil
        }
        updateStatusMenuItem(item, title: title, badge: badge, color: color)
        setStatusMenuItemAction(item, action: action)
        item?.toolTip = tooltip
    }

    private func menuSymbol(named name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private func makeSectionHeader(title: String, trailingView: NSView? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuSectionHeaderView(title: title, trailingView: trailingView)
        return item
    }

    private func showAllStatusesChecking(includeClaudeUsage: Bool = true) {
        refreshSystemStatusButton?.title = "Refreshing…"
        refreshSystemStatusButton?.isEnabled = false
        updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(brewVulnsStatusMenuItem, title: "Homebrew vulnerabilities", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Checking", color: .systemYellow)
        if includeClaudeUsage {
            updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Current session", badge: "Checking", color: .systemYellow)
            updateStatusMenuItem(claudeWeeklyUsageMenuItem, title: "Weekly limit", badge: "Checking", color: .systemYellow)
        }
        updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(engramStatusMenuItem, title: "Engram", badge: "Checking", color: .systemYellow)
        setStatusMenuItemAction(sparkdockStatusMenuItem, action: nil)
        setStatusMenuItemAction(brewStatusMenuItem, action: nil)
        setStatusMenuItemAction(brewVulnsStatusMenuItem, action: nil)
        setStatusMenuItemAction(httpProxyStatusMenuItem, action: nil)
        setStatusMenuItemAction(agentsStatusMenuItem, action: nil)
        setStatusMenuItemAction(timetrackerStatusMenuItem, action: nil)
        setStatusMenuItemAction(engramStatusMenuItem, action: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set proper activation policy for menu bar apps
        NSApp.setActivationPolicy(.accessory)

        loadMenuConfiguration()
        setupMenuBar()
        setupUpdateObservers()
        setupRecheckObservers()

        checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupUpdateObservers()
        // Clear cached images to free memory
        clearImageCache()
    }
    private func clearImageCache() {
        cachedNormalIcon = nil
        cachedUpdateIcon = nil
        cachedLogoImage = nil
    }

    private func loadMenuConfiguration() {
        do {
            menuConfig = try JSONDecoder().decode(MenuConfig.self, from: AppResources.data(named: "menu", extension: "json"))
            AppConstants.logger.info("Successfully loaded menu configuration with \(self.menuConfig?.menu.sections.count ?? 0) sections")
        } catch {
            AppConstants.logger.error("Failed to load menu configuration: \(error.localizedDescription)")
            showErrorAlert("Menu Configuration Error", "Failed to load menu configuration. Using minimal menu.")
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem, let button = statusItem.button else {
            return
        }

        button.image = loadIcon(hasUpdates: false)
        button.imagePosition = .imageOnly
        button.toolTip = "Sparkdock: up to date"

        setupMenu()
        menu?.delegate = self
        statusItem.menu = menu
        updateLoginItemStatus()
    }

    private func setupMenu() {
        menu = NSMenu()
        guard let menu = menu else { return }

        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let titleContainer = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 36))
        titleContainer.autoresizingMask = [.width]
        let titleLabel = NSTextField(labelWithString: "Sparkdock Manager")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleContainer.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor)
        ])
        titleItem.view = titleContainer
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let refreshSystemButton = NSButton(title: "Refresh", target: self, action: #selector(checkForUpdatesAction))
        refreshSystemButton.bezelStyle = .rounded
        refreshSystemButton.controlSize = .small
        refreshSystemButton.image = menuSymbol(named: "arrow.clockwise", description: "Refresh system status")
        refreshSystemButton.imagePosition = .imageLeading
        menu.addItem(makeSectionHeader(title: "System status", trailingView: refreshSystemButton))
        refreshSystemStatusButton = refreshSystemButton

        let sparkdockStatusItem = NSMenuItem(title: "Sparkdock", action: nil, keyEquivalent: "")
        menu.addItem(sparkdockStatusItem)
        self.sparkdockStatusMenuItem = sparkdockStatusItem

        let brewStatusItem = NSMenuItem(title: "Homebrew", action: nil, keyEquivalent: "")
        menu.addItem(brewStatusItem)
        self.brewStatusMenuItem = brewStatusItem

        let brewVulnsStatusItem = NSMenuItem(title: "Homebrew vulnerabilities", action: nil, keyEquivalent: "")
        // Hidden until a check answers, so a Homebrew without `vulns` never shows a row.
        brewVulnsStatusItem.isHidden = true
        menu.addItem(brewVulnsStatusItem)
        self.brewVulnsStatusMenuItem = brewVulnsStatusItem

        let httpProxyStatusItem = NSMenuItem(title: "HTTP proxy", action: nil, keyEquivalent: "")
        menu.addItem(httpProxyStatusItem)
        self.httpProxyStatusMenuItem = httpProxyStatusItem

        let agentsStatusItem = NSMenuItem(title: "Agent skills", action: nil, keyEquivalent: "")
        menu.addItem(agentsStatusItem)
        self.agentsStatusMenuItem = agentsStatusItem

        let timetrackerStatusItem = NSMenuItem(title: "Timetracker", action: nil, keyEquivalent: "")
        // Hidden from construction on machines without the CLI, so non-users never
        // see a transient "Checking..." row before the first check completes.
        timetrackerStatusItem.isHidden = Self.executablePath(for: "timetracker") == nil
        menu.addItem(timetrackerStatusItem)
        self.timetrackerStatusMenuItem = timetrackerStatusItem

        let engramStatusItem = NSMenuItem(title: "Engram", action: nil, keyEquivalent: "")
        // Hidden the same way as the timetracker row: only machines with the CLI see it.
        engramStatusItem.isHidden = Self.executablePath(for: "engram") == nil
        menu.addItem(engramStatusItem)
        self.engramStatusMenuItem = engramStatusItem

        menu.addItem(.separator())

        let claudeUsageInstalled = Self.executablePath(for: "claude-usage") != nil
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(checkClaudeUsageAction))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        refreshButton.image = menuSymbol(named: "arrow.clockwise", description: "Refresh Claude Code usage")
        refreshButton.imagePosition = .imageLeading
        let claudeUsageSectionItem = makeSectionHeader(title: "Claude Code", trailingView: refreshButton)
        claudeUsageSectionItem.isHidden = !claudeUsageInstalled
        menu.addItem(claudeUsageSectionItem)
        claudeUsageSectionMenuItem = claudeUsageSectionItem
        refreshClaudeUsageButton = refreshButton

        let claudeCurrentUsageItem = NSMenuItem(title: "Current session", action: #selector(checkClaudeUsageAction), keyEquivalent: "")
        claudeCurrentUsageItem.target = self
        claudeCurrentUsageItem.view = ClaudeUsageRowView()
        claudeCurrentUsageItem.isHidden = !claudeUsageInstalled
        menu.addItem(claudeCurrentUsageItem)
        claudeCurrentUsageMenuItem = claudeCurrentUsageItem

        let claudeWeeklyUsageItem = NSMenuItem(title: "Weekly limit", action: #selector(checkClaudeUsageAction), keyEquivalent: "")
        claudeWeeklyUsageItem.target = self
        claudeWeeklyUsageItem.view = ClaudeUsageRowView()
        claudeWeeklyUsageItem.isHidden = !claudeUsageInstalled
        menu.addItem(claudeWeeklyUsageItem)
        claudeWeeklyUsageMenuItem = claudeWeeklyUsageItem

        let claudeUsageSeparator = NSMenuItem.separator()
        claudeUsageSeparator.isHidden = !claudeUsageInstalled
        menu.addItem(claudeUsageSeparator)
        claudeUsageSectionSeparator = claudeUsageSeparator

        // Add dynamic menu sections from configuration
        if let config = menuConfig {
            addDynamicMenuSections(config.menu.sections, to: menu)
        }

        let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = MenuItemTag.loginItem.rawValue
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addDynamicMenuSections(_ sections: [MenuSection], to menu: NSMenu) {
        for section in sections {
            let sectionItem = makeSectionHeader(title: section.name)
            menu.addItem(sectionItem)

            var entries: [(menuItem: NSMenuItem, config: MenuItem)] = []
            for item in section.items {
                let menuItem = NSMenuItem(title: item.title, action: #selector(handleDynamicMenuItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item
                switch item.type {
                case .command:
                    menuItem.image = menuSymbol(named: "terminal", description: "Open command")
                case .url:
                    menuItem.image = menuSymbol(named: "arrow.up.right.square", description: "Open link")
                }
                menu.addItem(menuItem)
                entries.append((menuItem, item))
            }

            let separator = NSMenuItem.separator()
            menu.addItem(separator)
            dynamicMenuSections.append((sectionItem, separator, entries))
        }
        refreshDynamicMenuItems()
    }

    /// Re-applies the `requires_binary` gate to the configured menu entries, so
    /// installing (or removing) a tool is reflected on the next refresh without
    /// restarting the app.
    private func refreshDynamicMenuItems() {
        for section in dynamicMenuSections {
            var anyVisible = false
            for (menuItem, config) in section.entries {
                let available = itemIsAvailable(config)
                menuItem.isHidden = !available
                if available { anyVisible = true }
            }
            // A heading with nothing under it is noise, so a section whose every item
            // is gated off is hidden along with its separator.
            section.header.isHidden = !anyVisible
            section.separator.isHidden = !anyVisible
        }
    }

    /// Whether a configured menu item should appear on this machine.
    private func itemIsAvailable(_ item: MenuItem) -> Bool {
        guard let binary = item.requiresBinary else { return true }
        if Self.executablePath(for: binary) != nil { return true }
        // Logged, not silent: "my menu entry is missing" is otherwise indistinguishable
        // from a broken menu file, and this is the answer to that support question.
        AppConstants.logger.info("Hiding menu item '\(item.title, privacy: .public)': \(binary, privacy: .public) is not installed")
        return false
    }

    /// Locates an executable the way the update checks do. The app inherits
    /// launchd's PATH (/usr/bin:/bin:/usr/sbin:/sbin), which contains none of the
    /// places developer tools install to, so the usual prefixes are searched
    /// explicitly rather than trusting the environment.
    static func executablePath(for binary: String) -> String? {
        var prefixes = ["/opt/homebrew/bin", "/usr/local/bin"]
        prefixes.append(NSHomeDirectory() + "/.local/bin")
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            prefixes.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }
        for prefix in prefixes {
            let candidate = prefix + "/" + binary
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    @objc private func handleDynamicMenuItem(_ sender: NSMenuItem) {
        guard let menuItem = sender.representedObject as? MenuItem else { return }

        switch menuItem.type {
        case .command:
            if let command = menuItem.command {
                executeTerminalCommand(command)
            }
        case .url:
            if let urlString = menuItem.url {
                openUrlAsChromeWebApp(urlString)
            }
        }
    }

    private func fallbackToDefaultBrowser(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            AppConstants.logger.info("Fell back to default browser for URL: \(urlString)")
        }
    }

    private func openUrlAsChromeWebApp(_ urlString: String) {
        let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        if FileManager.default.fileExists(atPath: chromePath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: chromePath)

            // Use Google Chrome with --app flag to open as a web app
            process.arguments = [
                "--app=\(urlString)"
            ]

            do {
                try process.run()
                AppConstants.logger.info("Opened URL as Chrome web app: \(urlString)")
            } catch {
                AppConstants.logger.error("Failed to open URL as Chrome web app '\(urlString)': \(error.localizedDescription)")
                fallbackToDefaultBrowser(urlString)
            }
        } else {
            AppConstants.logger.error("Google Chrome not found at path '\(chromePath)'. Falling back to default browser for URL: \(urlString)")
            fallbackToDefaultBrowser(urlString)
        }
    }

    private func setupUpdateObservers() {
        // Observe system wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // Monitor network changes
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let fingerprint = NetworkFingerprint(path: path)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let shouldCheck = NetworkChangePolicy.shouldCheck(previous: self.lastNetworkFingerprint, current: fingerprint)
                self.lastNetworkFingerprint = fingerprint
                if shouldCheck {
                    AppConstants.logger.info("Network connectivity changed - checking for updates")
                    self.checkForUpdates()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        self.pathMonitor = monitor
        // Fallback for a machine that stays awake and connected for days. The system
        // picks the moment inside the tolerance, when running costs the least energy.
        let scheduler = NSBackgroundActivityScheduler(identifier: "\(AppConstants.bundleIdentifier).daily-check")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 60 * 60
        scheduler.qualityOfService = .background
        scheduler.schedule { [weak self] completion in
            DispatchQueue.main.async {
                AppConstants.logger.info("Daily scheduled update check")
                self?.checkForUpdates()
                // Report completion only once the checks end, so the activity keeps
                // its App Nap protection while they run.
                let task = self?.fullCheckTask
                Task {
                    await task?.value
                    completion(.finished)
                }
            }
        }
        self.dailyCheckScheduler = scheduler
        AppConstants.logger.info("Update observers configured")
    }
    private func cleanupUpdateObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pathMonitor?.cancel()
        pathMonitor = nil
        dailyCheckScheduler?.invalidate()
        dailyCheckScheduler = nil
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
        AppConstants.logger.info("Update observers cleaned up")
    }
    @objc private func systemDidWake() {
        AppConstants.logger.info("System woke from sleep - checking for updates")
        checkForUpdates()
    }

    @objc private func checkForUpdatesAction() {
        checkForUpdates(includeClaudeUsage: false, manual: true)
    }

    @objc private func checkClaudeUsageAction() {
        refreshClaudeUsageButton?.title = "Refreshing…"
        refreshClaudeUsageButton?.isEnabled = false
        recheckClaudeUsage(forcePoll: true)
    }

    // MARK: - Darwin Notification Observers (post-upgrade recheck)

    private func setupRecheckObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in RecheckNotification.all {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                darwinRecheckCallback,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        AppConstants.logger.info("Darwin recheck observers configured")
    }

    fileprivate func handleRecheckNotification(_ name: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let handlers: [String: () -> Void] = [
                RecheckNotification.sparkdock: { self.recheck("sparkdock", item: self.sparkdockStatusMenuItem, title: "Sparkdock", into: \.sparkdockStatus) },
                RecheckNotification.brew: self.recheckBrew,
                RecheckNotification.httpProxy: { self.recheck("http-proxy", item: self.httpProxyStatusMenuItem, title: "HTTP proxy", into: \.httpProxyStatus) },
                RecheckNotification.agents: { self.recheck("agents", item: self.agentsStatusMenuItem, title: "Agent skills", into: \.agentsStatus) },
                RecheckNotification.timetracker: { self.recheck("timetracker", item: self.timetrackerStatusMenuItem, title: "Timetracker", into: \.timetrackerStatus) },
                RecheckNotification.engram: { self.recheck("engram", item: self.engramStatusMenuItem, title: "Engram", into: \.engramStatus) }
            ]
            handlers[name]?()
        }
    }

    /// Rechecks one row whose state is a plain `CheckStatus`, after its upgrade command finishes.
    private func recheck(_ subsystem: String, item: NSMenuItem?, title: String, into status: ReferenceWritableKeyPath<SparkdockMenubarApp, CheckStatus>) {
        checkGeneration += 1
        updateStatusMenuItem(item, title: title, badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runStatusCheck(subsystem)
            await MainActor.run {
                self[keyPath: status] = result
                self.refreshUI()
            }
        }
    }

    private func recheckBrew() {
        checkGeneration += 1
        updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Checking", color: .systemYellow)
        // An upgrade can resolve a vulnerability, so the row would otherwise stay stale.
        updateStatusMenuItem(brewVulnsStatusMenuItem, title: "Homebrew vulnerabilities", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            async let brewVulnsStatusTask = self.runBrewVulnsCheck(force: true)
            let brew = await runBrewCheck()
            let brewVulnsStatus = await brewVulnsStatusTask
            await MainActor.run {
                self.brewStatus = brew.status
                self.brewOutdated = brew.summary
                self.brewVulnsStatus = brewVulnsStatus
                self.refreshUI()
            }
        }
    }

    private func recheckClaudeUsage(forcePoll: Bool = false, showsProgress: Bool = true) {
        claudeUsageCheckGeneration += 1
        let expectedClaudeUsageGeneration = claudeUsageCheckGeneration
        // Stamped before the check runs, not only when it lands: menuWillOpen fires
        // on every open, so a window that only closed on completion would let a
        // second open supersede the first check's still-pending result, and a run of
        // quick opens would discard every one of them.
        claudeUsageLastCheckedAt = Date()
        if showsProgress {
            updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Current session", badge: "Checking", color: .systemYellow)
            updateStatusMenuItem(claudeWeeklyUsageMenuItem, title: "Weekly limit", badge: "Checking", color: .systemYellow)
        }
        Task(priority: .background) {
            let result = await runClaudeUsageCheck(forcePoll: forcePoll)
            await MainActor.run {
                guard self.claudeUsageCheckGeneration == expectedClaudeUsageGeneration else {
                    AppConstants.logger.info("Discarding stale Claude usage result (generation \(expectedClaudeUsageGeneration) != \(self.claudeUsageCheckGeneration))")
                    return
                }
                self.claudeUsageStatus = result
                self.claudeUsageLastCheckedAt = Date()
                self.refreshClaudeUsageButton?.title = "Refresh"
                self.refreshClaudeUsageButton?.isEnabled = true
                self.refreshUI(updateClaudeUsage: true)
            }
        }
    }

    /// Redraws every row and the menu bar icon from the stored check states.
    private func refreshUI(updateClaudeUsage: Bool = false) {
        let updateRows: [(status: CheckStatus, name: String)] = [
            (sparkdockStatus, "Sparkdock"),
            (httpProxyStatus, "HTTP proxy"),
            (agentsStatus, "Agent skills"),
            (timetrackerStatus, "Timetracker"),
            (engramStatus, "Engram")
        ]
        statusItem?.button?.image = loadIcon(hasUpdates: brewStatus.needsAction || updateRows.contains { $0.status.needsAction })

        // Create more detailed tooltip
        var tooltipParts = updateRows.filter { $0.status.needsAction }.map { "\($0.name) updates available" }
        let outdatedBrewFormulae = brewOutdated?.formulae ?? 0
        let outdatedBrewCasks = brewOutdated?.casks ?? 0
        if outdatedBrewFormulae > 0 && outdatedBrewCasks > 0 {
            tooltipParts.append("\(outdatedBrewFormulae) formulae, \(outdatedBrewCasks) casks outdated")
        } else if outdatedBrewFormulae > 0 {
            tooltipParts.append("\(outdatedBrewFormulae) brew formulae outdated")
        } else if outdatedBrewCasks > 0 {
            tooltipParts.append("\(outdatedBrewCasks) brew casks outdated")
        }

        if tooltipParts.isEmpty {
            statusItem?.button?.toolTip = "Sparkdock: up to date"
        } else {
            statusItem?.button?.toolTip = "Sparkdock: " + tooltipParts.joined(separator: ", ")
        }

        renderStatusRow(sparkdockStatusMenuItem, title: "Sparkdock", status: sparkdockStatus, upgradeAction: #selector(updateNow))
        renderStatusRow(brewStatusMenuItem, title: "Homebrew", status: brewStatus, upgradeAction: #selector(upgradeBrew),
                        tooltip: brewOutdated.map { "\($0.formulae) formulae, \($0.casks) casks" })

        // Hidden only on a Homebrew without `brew vulns`. Findings are not a pending
        // update, so they stay out of the icon tint above.
        brewVulnsStatusMenuItem?.isHidden = brewVulnsStatus == .notConfigured
        renderStatusRow(brewVulnsStatusMenuItem, title: "Homebrew vulnerabilities", status: brewVulnsStatus,
                        upgradeAction: #selector(showBrewVulns), okAction: #selector(showBrewVulns))

        renderStatusRow(httpProxyStatusMenuItem, title: "HTTP proxy", status: httpProxyStatus, upgradeAction: #selector(upgradeHttpProxy))
        renderStatusRow(agentsStatusMenuItem, title: "Agent skills", status: agentsStatus, upgradeAction: #selector(upgradeAgents),
                        notConfiguredBadge: "Set up", notConfiguredAction: #selector(upgradeAgents))

        if updateClaudeUsage {
            updateClaudeUsageUI(claudeUsageStatus)
        }

        // Timetracker and Engram rows are hidden outright when their CLI is not on the
        // machine: a permanent "not installed" row would sit in every developer's
        // menu advertising a tool they have not adopted.
        timetrackerStatusMenuItem?.isHidden = Self.executablePath(for: "timetracker") == nil
        renderStatusRow(timetrackerStatusMenuItem, title: "Timetracker", status: timetrackerStatus, upgradeAction: #selector(upgradeTimetracker))
        engramStatusMenuItem?.isHidden = Self.executablePath(for: "engram") == nil
        renderStatusRow(engramStatusMenuItem, title: "Engram", status: engramStatus, upgradeAction: #selector(upgradeEngram))

        refreshDynamicMenuItems()
    }

    /// Runs every check, unless a full check is already in flight. Only a manual
    /// refresh runs `brew update` and forces a fresh vulnerability scan; its button
    /// is disabled while a check runs.
    private func checkForUpdates(includeClaudeUsage: Bool = true, manual: Bool = false) {
        guard fullCheckTask == nil else {
            AppConstants.logger.info("Full check already running - skipping trigger")
            return
        }
        showAllStatusesChecking(includeClaudeUsage: includeClaudeUsage)
        checkGeneration += 1
        let expectedGeneration = checkGeneration
        systemStatusCheckGeneration += 1
        let expectedSystemStatusGeneration = systemStatusCheckGeneration
        let expectedClaudeUsageGeneration: Int?
        if includeClaudeUsage {
            claudeUsageCheckGeneration += 1
            expectedClaudeUsageGeneration = claudeUsageCheckGeneration
            refreshClaudeUsageButton?.title = "Refresh"
            refreshClaudeUsageButton?.isEnabled = true
        } else {
            expectedClaudeUsageGeneration = nil
        }
        fullCheckTask = Task(priority: .background) {
            // Started first and awaited last: the OSV scan and the Homebrew data
            // refresh are the slowest checks and must not hold the other rows on "Checking".
            async let brewVulnsStatusTask = self.runBrewVulnsCheck(force: manual)
            async let brewTask = self.runBrewCheck(force: manual)
            let sparkdockStatus = await runStatusCheck("sparkdock")
            let httpProxyStatus = await runStatusCheck("http-proxy")
            let agentsStatus = await runStatusCheck("agents")
            let checkedClaudeUsageStatus: ClaudeUsageStatus?
            if includeClaudeUsage {
                checkedClaudeUsageStatus = await runClaudeUsageCheck()
            } else {
                checkedClaudeUsageStatus = nil
            }
            let timetrackerStatus = await runStatusCheck("timetracker")
            let engramStatus = await runStatusCheck("engram")
            let brew = await brewTask
            let brewVulnsStatus = await brewVulnsStatusTask
            await MainActor.run {
                if self.systemStatusCheckGeneration == expectedSystemStatusGeneration {
                    self.fullCheckTask = nil
                    self.refreshSystemStatusButton?.title = "Refresh"
                    self.refreshSystemStatusButton?.isEnabled = true
                }
                // Discard results if a per-subsystem recheck started after this full check
                guard self.checkGeneration == expectedGeneration else {
                    AppConstants.logger.info("Discarding stale full-check results (generation \(expectedGeneration) != \(self.checkGeneration))")
                    return
                }
                let shouldUpdateClaudeUsage = expectedClaudeUsageGeneration.map {
                    self.claudeUsageCheckGeneration == $0
                } ?? false
                self.sparkdockStatus = sparkdockStatus
                self.brewStatus = brew.status
                self.brewOutdated = brew.summary
                self.brewVulnsStatus = brewVulnsStatus
                self.httpProxyStatus = httpProxyStatus
                self.agentsStatus = agentsStatus
                self.timetrackerStatus = timetrackerStatus
                self.engramStatus = engramStatus
                if shouldUpdateClaudeUsage {
                    self.claudeUsageStatus = checkedClaudeUsageStatus
                    self.claudeUsageLastCheckedAt = Date()
                }
                self.refreshUI(updateClaudeUsage: shouldUpdateClaudeUsage)
            }
        }
    }

    /// Runs `sparkdock-check-updates` for one subsystem. The exit code is nil when the
    /// script is missing, fails to start, or does not finish in time. Only `brew` and
    /// `vulns` capture output: the other checks can print a long pending-commit log.
    private func runCheckUpdates(_ subsystem: String, arguments: [String] = [], capturesOutput: Bool = false, timeout: TimeInterval = AppConstants.processTimeout) async -> (exitCode: Int32?, output: String) {
        let checkUpdatesPath = AppConstants.checkUpdatesExecutablePath
        guard FileManager.default.fileExists(atPath: checkUpdatesPath) else {
            AppConstants.logger.warning("sparkdock-check-updates not found at \(checkUpdatesPath)")
            return (nil, "")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: checkUpdatesPath)
        process.arguments = [subsystem] + arguments
        process.environment = CheckUpdatesEnvironment.make()

        let result: (exitCode: Int32, output: String)
        do {
            result = try await runCheckProcess(process, capturesOutput: capturesOutput, seconds: timeout)
        } catch ProcessTimeoutError.timedOut {
            AppConstants.logger.error("sparkdock-check-updates '\(subsystem, privacy: .public)' timed out after \(timeout) seconds")
            return (nil, "")
        } catch {
            AppConstants.logger.error("sparkdock-check-updates '\(subsystem, privacy: .public)' failed: \(error.localizedDescription)")
            return (nil, "")
        }

        AppConstants.logger.info("sparkdock-check-updates '\(subsystem, privacy: .public)' exited with \(result.exitCode)")
        return (result.exitCode, result.output)
    }

    private func runStatusCheck(_ subsystem: String) async -> CheckStatus {
        return CheckStatus.from(exitCode: await runCheckUpdates(subsystem).exitCode)
    }

    /// `force` runs `brew update` first; otherwise `brew outdated` refreshes stale data itself.
    private func runBrewCheck(force: Bool = false) async -> (status: CheckStatus, summary: BrewOutdatedSummary?) {
        let result = await runCheckUpdates("brew", arguments: force ? ["--force"] : [], capturesOutput: true, timeout: AppConstants.brewCheckTimeout)
        return BrewOutdatedSummary.status(exitCode: result.exitCode, output: result.output)
    }

    /// The script answers from a daily cache unless `force` asks for a fresh scan.
    private func runBrewVulnsCheck(force: Bool = false) async -> CheckStatus {
        let result = await runCheckUpdates("vulns", arguments: force ? ["--force"] : [], capturesOutput: true, timeout: AppConstants.brewCheckTimeout)
        return BrewVulnsSummary.status(exitCode: result.exitCode, output: result.output)
    }

    private func runClaudeUsageCheck(forcePoll: Bool = false) async -> ClaudeUsageStatus? {
        guard let executablePath = Self.executablePath(for: "claude-usage") else {
            AppConstants.logger.info("claude-usage not found, usage check skipped")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = forcePoll ? ["--status", "--force-poll"] : ["--status"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let terminationStatus: Int32
        do {
            terminationStatus = try await runProcessWithTimeout(process, seconds: AppConstants.processTimeout)
        } catch ProcessTimeoutError.timedOut {
            AppConstants.logger.error("Claude usage check timed out after \(AppConstants.processTimeout) seconds")
            return nil
        } catch {
            AppConstants.logger.error("Claude usage check failed: \(error.localizedDescription)")
            return nil
        }
        guard terminationStatus == 0 else {
            AppConstants.logger.warning("Claude usage check failed with exit code \(terminationStatus)")
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        do {
            return try JSONDecoder().decode(ClaudeUsageStatus.self, from: data)
        } catch {
            AppConstants.logger.error("Failed to decode Claude usage status: \(error.localizedDescription)")
            return nil
        }
    }

    private func updateClaudeUsageUI(_ status: ClaudeUsageStatus?) {
        let installed = Self.executablePath(for: "claude-usage") != nil
        claudeUsageSectionMenuItem?.isHidden = !installed
        claudeCurrentUsageMenuItem?.isHidden = !installed
        claudeWeeklyUsageMenuItem?.isHidden = !installed
        claudeUsageSectionSeparator?.isHidden = !installed
        guard installed else { return }

        let sectionTitle = status?.stale == true ? "Claude Code · stale" : "Claude Code"
        claudeUsageSectionMenuItem?.title = sectionTitle
        (claudeUsageSectionMenuItem?.view as? MenuSectionHeaderView)?.title = sectionTitle
        claudeUsageSectionMenuItem?.toolTip = status?.error

        guard let status = status else {
            updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Usage", badge: "Unavailable", color: .systemGray)
            claudeCurrentUsageMenuItem?.toolTip = nil
            claudeWeeklyUsageMenuItem?.isHidden = true
            return
        }

        guard status.isAvailable else {
            updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Usage", badge: status.availabilityText, color: .systemGray)
            claudeCurrentUsageMenuItem?.toolTip = status.error
            claudeWeeklyUsageMenuItem?.isHidden = true
            return
        }

        claudeWeeklyUsageMenuItem?.isHidden = false
        let currentResetSubtitle = status.currentResetText.map { "Resets in \($0)" }
        let weeklyResetSubtitle = status.weeklyResetText.map { "Resets in \($0)" }
        updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Current session", badge: "\(status.currentPercent)%", subtitle: currentResetSubtitle, color: usageColor(for: status.currentPercent))
        updateStatusMenuItem(claudeWeeklyUsageMenuItem, title: "Weekly limit", badge: "\(status.weeklyPercent)%", subtitle: weeklyResetSubtitle, color: usageColor(for: status.weeklyPercent))
        claudeCurrentUsageMenuItem?.toolTip = status.error
        claudeWeeklyUsageMenuItem?.toolTip = status.error
    }

    private func usageColor(for percent: Int) -> NSColor {
        if percent >= 90 {
            return .systemRed
        }
        if percent >= 80 {
            return .systemOrange
        }
        return .systemGreen
    }

    @objc private func updateNow() {
        guard sparkdockStatus.needsAction else { return }
        executeTerminalCommand("sparkdock", recheckNotification: RecheckNotification.sparkdock)
    }

    @objc private func upgradeBrew() {
        guard brewStatus.needsAction else { return }
        // Create a compound command that only runs the second upgrade if the first succeeds
        let upgradeCommand = "brew upgrade && brew upgrade --cask"
        executeTerminalCommand(upgradeCommand, recheckNotification: RecheckNotification.brew)
    }

    @objc private func showBrewVulns() {
        executeTerminalCommand("brew vulns")
    }

    @objc private func upgradeHttpProxy() {
        guard httpProxyStatus.needsAction else { return }
        executeTerminalCommand("sjust http-proxy-install-update", recheckNotification: RecheckNotification.httpProxy)
    }

    @objc private func upgradeAgents() {
        // Allow refresh when agent resources have updates OR are not configured (initial setup)
        guard agentsStatus.needsAction || agentsStatus == .notConfigured else { return }
        executeTerminalCommand("sjust sf-harness-sync", recheckNotification: RecheckNotification.agents)
    }

    @objc private func upgradeTimetracker() {
        guard timetrackerStatus.needsAction else { return }
        // `timetracker update --apply` and not the `timetracker-update` shell
        // function: executeTerminalCommand runs a non-interactive login shell, and
        // zsh sources ~/.zshrc only for interactive shells, so the function is not
        // defined there. The binary knows how to update itself.
        executeTerminalCommand("timetracker update --apply", recheckNotification: RecheckNotification.timetracker)
    }

    @objc private func upgradeEngram() {
        guard engramStatus.needsAction else { return }
        // Same reason as timetracker: the engram-update shell function is not
        // defined in the non-interactive login shell, the binary updates itself.
        executeTerminalCommand("engram update --apply", recheckNotification: RecheckNotification.engram)
    }


    /// Executes a command in a new Ghostty terminal window.
    /// - Parameters:
    ///   - command: The shell command to run. Callers include both hardcoded commands and
    ///     commands loaded from dynamic menu configuration (for example, `menu.json`).
    ///   - recheckNotification: Optional Darwin notification name to post after the command finishes.
    ///     Current callers pass hardcoded notification names only. When set and notifyutil is
    ///     available, a `notifyutil -p` call is appended so the app can recheck the relevant
    ///     subsystem. No sanitization is performed on either parameter; callers must ensure
    ///     values are safe for shell interpolation.
    private func executeTerminalCommand(_ command: String, recheckNotification: String? = nil) {
        // Append Darwin notification trigger if provided (fires after command completes)
        let finalCommand: String
        if let notification = recheckNotification {
            let notifyutilPath = "/usr/bin/notifyutil"
            if FileManager.default.fileExists(atPath: notifyutilPath) {
                finalCommand = "\(command); \(notifyutilPath) -p \(notification)"
            } else {
                AppConstants.logger.warning("Skipping recheck notification '\(notification)' because \(notifyutilPath) is unavailable")
                finalCommand = command
            }
        } else {
            finalCommand = command
        }

        let process = Process()
        // Use the ghostty CLI to open a new window with the command
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Use 'open -n' to force a new instance
        // Set window size (in terminal grid cells - columns x rows)
        // Wrap the command in a login shell to ensure PATH is loaded
        process.arguments = [
            "-n",
            "-a", "Ghostty",
            "--args",
            "--window-width=200",
            "--window-height=40",
            "-e", "/bin/zsh", "-l", "-c", "\(finalCommand); exec zsh"
        ]
        do {
            try process.run()
            AppConstants.logger.info("Executed terminal command: \(finalCommand)")
        } catch {
            AppConstants.logger.error("Failed to execute terminal command '\(finalCommand)': \(error.localizedDescription)")
            showErrorAlert("Command Execution Error", "Failed to execute command: \(command)")
        }
    }

    @objc private func toggleLoginItem() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func updateLoginItemStatus() {
        guard let loginMenuItem = menu?.items.first(where: { $0.tag == MenuItemTag.loginItem.rawValue }) else { return }
        loginMenuItem.state = .off
        loginMenuItem.title = "Login items settings…"
    }

    private func loadIcon(hasUpdates: Bool) -> NSImage? {
        // Return cached icon if available
        if hasUpdates {
            if let cached = cachedUpdateIcon {
                return cached
            }
        } else {
            if let cached = cachedNormalIcon {
                return cached
            }
        }

        // Load logo once and cache it
        if cachedLogoImage == nil {
            cachedLogoImage = (try? AppResources.data(named: "sparkfabrik-logo", extension: "png")).flatMap { NSImage(data: $0) }
            if cachedLogoImage == nil {
                AppConstants.logger.error("Logo could not be loaded from application resources; using the fallback icon")
            }
        }

        let logo = cachedLogoImage ?? createDefaultIcon()

        let icon = NSImage(size: AppConstants.iconSize, flipped: false) { rect in
            logo.draw(in: rect)

            if hasUpdates {
                NSColor.systemOrange.set()
                rect.fill(using: .sourceAtop)
            }

            return true
        }

        icon.isTemplate = !hasUpdates
        // Cache the created icon
        if hasUpdates {
            cachedUpdateIcon = icon
        } else {
            cachedNormalIcon = icon
        }

        return icon
    }

    private func createDefaultIcon() -> NSImage {
        guard let systemImage = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Sparkdock") else {
            AppConstants.logger.warning("System symbol 'gearshape.fill' not available, using fallback icon")
            return createFallbackIcon()
        }

        let config = NSImage.SymbolConfiguration(pointSize: AppConstants.iconSize.width, weight: .medium)
        return systemImage.withSymbolConfiguration(config) ?? systemImage
    }

    private func createFallbackIcon() -> NSImage {
        return NSImage(size: AppConstants.iconSize, flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - Menu Delegate
extension SparkdockMenubarApp: NSMenuDelegate {
    /// Claude usage checks are event-driven (system wake and network change), so
    /// the menu can be opened long after the last one ran and show a reading that
    /// is no longer true. Refresh on open, throttled to the window `claude-usage`
    /// caches for, and without the "Checking" placeholder when a status is
    /// already on screen so the rows do not flicker on every open.
    func menuWillOpen(_ menu: NSMenu) {
        guard Self.executablePath(for: "claude-usage") != nil else { return }
        guard ClaudeUsageRefreshPolicy.shouldRefresh(lastCheckedAt: claudeUsageLastCheckedAt) else { return }
        recheckClaudeUsage(showsProgress: claudeUsageStatus == nil)
    }
}

// MARK: - CLI Handling
/// Handles `--help` and `--status`. Returns the process exit code when an argument
/// was handled, or `nil` to launch the menu bar application.
private func handleCLIArguments() -> Int32? {
    let arguments = CommandLine.arguments

    if arguments.contains("--help") || arguments.contains("-h") {
        print("""
        Sparkdock Manager - macOS menu bar application for development environment management

        Usage: sparkdock-manager [options]

        Options:
          --help, -h       Show this help message
          --status         Show application status

        When run without arguments, launches as a menu bar application.
        """)
        return 0
    }

    if arguments.contains("--status") {
        // Validate the resources used by the real application before installation.
        let menuConfigLine: String
        var healthy = true
        do {
            let config = try JSONDecoder().decode(MenuConfig.self, from: AppResources.data(named: "menu", extension: "json"))
            menuConfigLine = "Menu configuration: ✅ \(config.menu.sections.count) sections (\(AppConstants.menuConfigResourceName).json)"
        } catch {
            menuConfigLine = "Menu configuration: ❌ \(AppConstants.menuConfigResourceName).json failed to decode: \(error.localizedDescription)"
            healthy = false
        }

        let logoLine: String
        if let logoData = try? AppResources.data(named: "sparkfabrik-logo", extension: "png"), NSImage(data: logoData) != nil {
            logoLine = "Logo: ✅ \(logoData.count) bytes (\(AppConstants.logoResourceName).png)"
        } else {
            logoLine = "Logo: ❌ \(AppConstants.logoResourceName).png failed to decode"
            healthy = false
        }

        print("Sparkdock Manager - Status: \(healthy ? "OK" : "ERROR")")
        print("Executable path: \(AppConstants.sparkdockExecutablePath)")
        print("Resource container: \(AppBundle.current.bundleURL.path)")
        print("Bundle identifier: \(AppBundle.current.bundleIdentifier ?? "unbundled")")
        print("Other instances with this identifier: \(AppInstance.otherInstances().count)")
        print(menuConfigLine)
        print(logoLine)

        // Check if sparkdock executable exists
        if FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) {
            print("Sparkdock executable: ✅ Found")
        } else {
            print("Sparkdock executable: ❌ Not found")
        }

        return healthy ? 0 : 1
    }

    return nil
}

// MARK: - Main Entry Point
if let exitCode = handleCLIArguments() {
    exit(exitCode)
}

// Check if another instance is already running
if !AppInstance.otherInstances().isEmpty {
    print("⚠️  Sparkdock menu bar app is already running")
    print("💡 If you need to restart it, quit the app first from the menu bar")
    print("💡 If the app is stuck or not visible, use: pkill -f sparkdock-manager")
    exit(1)
}

let app = NSApplication.shared
let delegate = SparkdockMenubarApp()
app.delegate = delegate
app.run()
