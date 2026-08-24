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
    static let bundleIdentifier = "com.sparkfabrik.sparkdock.manager"
    static let processTimeout: TimeInterval = 30.0
    static let logger = Logger(subsystem: bundleIdentifier, category: "MenuBar")
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
    static let all = [sparkdock, brew, httpProxy, agents, timetracker]
}

// MARK: - Menu Item Tags
private enum MenuItemTag: Int {
    case updateNow = 1
    case loginItem = 2
    case upgradeBrew = 3
    case upgradeHttpProxy = 4
    case upgradeAgents = 5
    case upgradeTimetracker = 6
}

// MARK: - Brew Package Types
private enum BrewPackageType {
    case formulae
    case casks

    var commandSuffix: String {
        switch self {
        case .formulae:
            return "--formula"
        case .casks:
            return "--cask"
        }
    }

    var description: String {
        switch self {
        case .formulae:
            return "formulae"
        case .casks:
            return "casks"
        }
    }
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
    var hasUpdates = false
    var hasHttpProxyUpdates = false
    var hasAgentUpdates = false
    var agentsLastStatus: Int32? = nil
    var claudeUsageStatus: ClaudeUsageStatus?
    var hasTimetrackerUpdates = false
    var timetrackerLastStatus: Int32? = nil
    var outdatedBrewFormulaeCount = 0
    var outdatedBrewCasksCount = 0
    var totalOutdatedBrewCount: Int { outdatedBrewFormulaeCount + outdatedBrewCasksCount }
    /// Generation counter to discard stale full-check results after a per-subsystem recheck
    private var checkGeneration: Int = 0
    private var claudeUsageCheckGeneration: Int = 0
    var statusMenuItem: NSMenuItem?
    var sparkdockStatusMenuItem: NSMenuItem?
    var brewStatusMenuItem: NSMenuItem?
    var httpProxyStatusMenuItem: NSMenuItem?
    var agentsStatusMenuItem: NSMenuItem?
    var claudeUsageSectionMenuItem: NSMenuItem?
    var claudeCurrentUsageMenuItem: NSMenuItem?
    var claudeWeeklyUsageMenuItem: NSMenuItem?
    var refreshClaudeUsageButton: NSButton?
    var claudeUsageSectionSeparator: NSMenuItem?
    var timetrackerStatusMenuItem: NSMenuItem?
    var updateActionsSectionMenuItem: NSMenuItem?
    var updateActionsSectionSeparator: NSMenuItem?
    var updateNowMenuItem: NSMenuItem?
    var upgradeBrewMenuItem: NSMenuItem?
    var upgradeHttpProxyMenuItem: NSMenuItem?
    var upgradeAgentsMenuItem: NSMenuItem?
    var upgradeTimetrackerMenuItem: NSMenuItem?
    private var pathMonitor: NWPathMonitor?
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

    private func showAllStatusesChecking() {
        updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Current session", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(claudeWeeklyUsageMenuItem, title: "Weekly limit", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Checking", color: .systemYellow)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set proper activation policy for menu bar apps
        NSApp.setActivationPolicy(.accessory)

        loadMenuConfiguration()
        setupMenuBar()
        setupUpdateObservers()
        setupRecheckObservers()

        // Set initial status and check for updates
        showAllStatusesChecking()
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
        guard let path = Bundle.module.path(forResource: AppConstants.menuConfigResourceName, ofType: "json") ??
                         Bundle.main.path(forResource: AppConstants.menuConfigResourceName, ofType: "json") else {
            AppConstants.logger.info("Menu configuration file not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            menuConfig = try JSONDecoder().decode(MenuConfig.self, from: data)
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

        menu.addItem(makeSectionHeader(title: "System status"))

        // Create separate status menu items (clickable to trigger specific checks)
        let sparkdockStatusItem = NSMenuItem(title: "Sparkdock", action: #selector(checkSparkdockUpdatesAction), keyEquivalent: "")
        sparkdockStatusItem.target = self
        menu.addItem(sparkdockStatusItem)
        self.sparkdockStatusMenuItem = sparkdockStatusItem

        let brewStatusItem = NSMenuItem(title: "Homebrew", action: #selector(checkBrewUpdatesAction), keyEquivalent: "")
        brewStatusItem.target = self
        menu.addItem(brewStatusItem)
        self.brewStatusMenuItem = brewStatusItem

        let httpProxyStatusItem = NSMenuItem(title: "HTTP proxy", action: #selector(checkHttpProxyUpdatesAction), keyEquivalent: "")
        httpProxyStatusItem.target = self
        menu.addItem(httpProxyStatusItem)
        self.httpProxyStatusMenuItem = httpProxyStatusItem

        let agentsStatusItem = NSMenuItem(title: "Agent skills", action: #selector(checkAgentUpdatesAction), keyEquivalent: "")
        agentsStatusItem.target = self
        menu.addItem(agentsStatusItem)
        self.agentsStatusMenuItem = agentsStatusItem

        let timetrackerStatusItem = NSMenuItem(title: "Timetracker", action: #selector(checkTimetrackerUpdatesAction), keyEquivalent: "")
        timetrackerStatusItem.target = self
        // Hidden from construction on machines without the CLI, so non-users never
        // see a transient "Checking..." row before the first check completes.
        timetrackerStatusItem.isHidden = Self.executablePath(for: "timetracker") == nil
        menu.addItem(timetrackerStatusItem)
        self.timetrackerStatusMenuItem = timetrackerStatusItem

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

        let updateActionsSectionItem = makeSectionHeader(title: "Actions")
        updateActionsSectionItem.isHidden = true
        menu.addItem(updateActionsSectionItem)
        updateActionsSectionMenuItem = updateActionsSectionItem

        let updateItem = NSMenuItem(title: "Upgrade Sparkdock", action: #selector(updateNow), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = MenuItemTag.updateNow.rawValue
        updateItem.image = menuSymbol(named: "arrow.up.circle", description: "Upgrade")
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateNowMenuItem = updateItem

        let upgradeBrewItem = NSMenuItem(title: "Upgrade Homebrew", action: #selector(upgradeBrew), keyEquivalent: "")
        upgradeBrewItem.target = self
        upgradeBrewItem.tag = MenuItemTag.upgradeBrew.rawValue
        upgradeBrewItem.image = menuSymbol(named: "arrow.up.circle", description: "Upgrade")
        upgradeBrewItem.isHidden = true
        menu.addItem(upgradeBrewItem)
        upgradeBrewMenuItem = upgradeBrewItem

        let upgradeHttpProxyItem = NSMenuItem(title: "Upgrade HTTP proxy", action: #selector(upgradeHttpProxy), keyEquivalent: "")
        upgradeHttpProxyItem.target = self
        upgradeHttpProxyItem.tag = MenuItemTag.upgradeHttpProxy.rawValue
        upgradeHttpProxyItem.image = menuSymbol(named: "arrow.up.circle", description: "Upgrade")
        upgradeHttpProxyItem.isHidden = true
        menu.addItem(upgradeHttpProxyItem)
        upgradeHttpProxyMenuItem = upgradeHttpProxyItem

        let upgradeAgentsItem = NSMenuItem(title: "Refresh agent skills", action: #selector(upgradeAgents), keyEquivalent: "")
        upgradeAgentsItem.target = self
        upgradeAgentsItem.tag = MenuItemTag.upgradeAgents.rawValue
        upgradeAgentsItem.image = menuSymbol(named: "arrow.up.circle", description: "Refresh")
        upgradeAgentsItem.isHidden = true
        menu.addItem(upgradeAgentsItem)
        upgradeAgentsMenuItem = upgradeAgentsItem

        let upgradeTimetrackerItem = NSMenuItem(title: "Upgrade Timetracker", action: #selector(upgradeTimetracker), keyEquivalent: "")
        upgradeTimetrackerItem.target = self
        upgradeTimetrackerItem.tag = MenuItemTag.upgradeTimetracker.rawValue
        upgradeTimetrackerItem.image = menuSymbol(named: "arrow.up.circle", description: "Upgrade")
        upgradeTimetrackerItem.isHidden = true
        menu.addItem(upgradeTimetrackerItem)
        upgradeTimetrackerMenuItem = upgradeTimetrackerItem

        let updateActionsSeparator = NSMenuItem.separator()
        updateActionsSeparator.isHidden = true
        menu.addItem(updateActionsSeparator)
        updateActionsSectionSeparator = updateActionsSeparator

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
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    self?.showAllStatusesChecking()
                    self?.checkForUpdates()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        self.pathMonitor = monitor
        AppConstants.logger.info("Update observers configured")
    }
    private func cleanupUpdateObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pathMonitor?.cancel()
        pathMonitor = nil
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
        AppConstants.logger.info("Update observers cleaned up")
    }
    @objc private func systemDidWake() {
        AppConstants.logger.info("System woke from sleep - checking for updates")
        showAllStatusesChecking()
        checkForUpdates()
    }

    @objc private func checkForUpdatesAction() {
        showAllStatusesChecking()
        checkForUpdates()
    }

    @objc private func checkSparkdockUpdatesAction() {
        updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Checking", color: .systemYellow)
        checkForUpdates()
    }

    @objc private func checkBrewUpdatesAction() {
        updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Checking", color: .systemYellow)
        checkForUpdates()
    }

    @objc private func checkHttpProxyUpdatesAction() {
        updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Checking", color: .systemYellow)
        checkForUpdates()
    }

    @objc private func checkAgentUpdatesAction() {
        updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Checking", color: .systemYellow)
        checkForUpdates()
    }

    @objc private func checkClaudeUsageAction() {
        refreshClaudeUsageButton?.title = "Refreshing…"
        refreshClaudeUsageButton?.isEnabled = false
        recheckClaudeUsage(forcePoll: true)
    }

    @objc private func checkTimetrackerUpdatesAction() {
        updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Checking", color: .systemYellow)
        checkForUpdates()
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
                RecheckNotification.sparkdock: self.recheckSparkdock,
                RecheckNotification.brew: self.recheckBrew,
                RecheckNotification.httpProxy: self.recheckHttpProxy,
                RecheckNotification.agents: self.recheckAgents,
                RecheckNotification.timetracker: self.recheckTimetracker
            ]
            handlers[name]?()
        }
    }

    private func recheckSparkdock() {
        checkGeneration += 1
        updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runSparkdockCheck()
            await MainActor.run {
                self.hasUpdates = result
                self.refreshUI()
            }
        }
    }

    private func recheckBrew() {
        checkGeneration += 1
        updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let (formulaeCount, casksCount) = await runBrewOutdatedCheck()
            await MainActor.run {
                self.outdatedBrewFormulaeCount = formulaeCount
                self.outdatedBrewCasksCount = casksCount
                self.refreshUI()
            }
        }
    }

    private func recheckHttpProxy() {
        checkGeneration += 1
        updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runHttpProxyCheck()
            await MainActor.run {
                self.hasHttpProxyUpdates = result
                self.refreshUI()
            }
        }
    }

    private func recheckAgents() {
        checkGeneration += 1
        updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runAgentsCheck()
            await MainActor.run {
                self.hasAgentUpdates = result
                self.refreshUI()
            }
        }
    }

    private func recheckClaudeUsage(forcePoll: Bool = false) {
        checkGeneration += 1
        claudeUsageCheckGeneration += 1
        let expectedClaudeUsageGeneration = claudeUsageCheckGeneration
        updateStatusMenuItem(claudeCurrentUsageMenuItem, title: "Current session", badge: "Checking", color: .systemYellow)
        updateStatusMenuItem(claudeWeeklyUsageMenuItem, title: "Weekly limit", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runClaudeUsageCheck(forcePoll: forcePoll)
            await MainActor.run {
                guard self.claudeUsageCheckGeneration == expectedClaudeUsageGeneration else {
                    AppConstants.logger.info("Discarding stale Claude usage result (generation \(expectedClaudeUsageGeneration) != \(self.claudeUsageCheckGeneration))")
                    return
                }
                self.claudeUsageStatus = result
                self.refreshClaudeUsageButton?.title = "Refresh"
                self.refreshClaudeUsageButton?.isEnabled = true
                self.refreshUI()
            }
        }
    }

    private func recheckTimetracker() {
        checkGeneration += 1
        updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Checking", color: .systemYellow)
        Task(priority: .background) {
            let result = await runTimetrackerCheck()
            await MainActor.run {
                self.hasTimetrackerUpdates = result
                self.refreshUI()
            }
        }
    }

    /// Refresh UI using current instance state (safe for per-subsystem updates)
    private func refreshUI() {
        updateUI(
            hasUpdates: hasUpdates,
            outdatedBrewFormulae: outdatedBrewFormulaeCount,
            outdatedBrewCasks: outdatedBrewCasksCount,
            hasHttpProxyUpdates: hasHttpProxyUpdates,
            hasAgentUpdates: hasAgentUpdates,
            agentsConfigured: isAgentsConfigured(),
            claudeUsageStatus: claudeUsageStatus,
            hasTimetrackerUpdates: hasTimetrackerUpdates,
            timetrackerConfigured: isTimetrackerConfigured()
        )
    }

    private func checkForUpdates() {
        checkGeneration += 1
        let expectedGeneration = checkGeneration
        claudeUsageCheckGeneration += 1
        refreshClaudeUsageButton?.title = "Refresh"
        refreshClaudeUsageButton?.isEnabled = true
        Task(priority: .background) {
            let hasUpdates = await runSparkdockCheck()
            let (formulaeCount, casksCount) = await runBrewOutdatedCheck()
            let hasHttpProxyUpdates = await runHttpProxyCheck()
            let hasAgentUpdates = await runAgentsCheck()
            let agentsConfigured = isAgentsConfigured()
            let claudeUsageStatus = await runClaudeUsageCheck()
            let hasTimetrackerUpdates = await runTimetrackerCheck()
            let timetrackerConfigured = isTimetrackerConfigured()
            await MainActor.run {
                // Discard results if a per-subsystem recheck started after this full check
                guard self.checkGeneration == expectedGeneration else {
                    AppConstants.logger.info("Discarding stale full-check results (generation \(expectedGeneration) != \(self.checkGeneration))")
                    return
                }
                updateUI(hasUpdates: hasUpdates, outdatedBrewFormulae: formulaeCount, outdatedBrewCasks: casksCount, hasHttpProxyUpdates: hasHttpProxyUpdates, hasAgentUpdates: hasAgentUpdates, agentsConfigured: agentsConfigured, claudeUsageStatus: claudeUsageStatus, hasTimetrackerUpdates: hasTimetrackerUpdates, timetrackerConfigured: timetrackerConfigured)
            }
        }
    }

    private func findBrewPath() async -> String? {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return nil
    }

    private func runBrewOutdatedCheck() async -> (formulae: Int, casks: Int) {
        AppConstants.logger.info("runBrewOutdatedCheck called")
        guard let brewPath = await findBrewPath() else {
            AppConstants.logger.warning("Homebrew not found at expected locations")
            return (0, 0)
        }

        // Get outdated formulae count
        let formulaeCount = await getBrewOutdatedCount(brewPath: brewPath, type: .formulae)
        // Get outdated casks count
        let casksCount = await getBrewOutdatedCount(brewPath: brewPath, type: .casks)

        let totalCount = formulaeCount + casksCount
        AppConstants.logger.info("Found \(formulaeCount) outdated formulae and \(casksCount) outdated casks (total: \(totalCount))")
        return (formulaeCount, casksCount)
    }

    private func getBrewOutdatedCount(brewPath: String, type: BrewPackageType) async -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")

        let command = "\(brewPath) outdated \(type.commandSuffix) --quiet | wc -l"
        process.arguments = ["-c", command]

        // Set environment variables including PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let terminationStatus: Int32
        do {
            terminationStatus = try await runProcessWithTimeout(process, seconds: AppConstants.processTimeout)
        } catch ProcessTimeoutError.timedOut {
            AppConstants.logger.error("Brew outdated check (\(type.description)) process timed out after \(AppConstants.processTimeout) seconds")
            return 0
        } catch {
            AppConstants.logger.error("Brew outdated check (\(type.description)) failed: \(error.localizedDescription)")
            return 0
        }

        if terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            let count = Int(output) ?? 0
            AppConstants.logger.info("Found \(count) outdated \(type.description)")
            return count
        } else {
            AppConstants.logger.warning("Brew outdated check (\(type.description)) failed with exit code \(terminationStatus)")
            return 0
        }
    }

    private func runSparkdockCommand(_ command: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) else {
            AppConstants.logger.warning("Sparkdock executable not found at \(AppConstants.sparkdockExecutablePath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConstants.sparkdockExecutablePath)
        process.arguments = [command]

        let terminationStatus: Int32
        do {
            terminationStatus = try await runProcessWithTimeout(process, seconds: AppConstants.processTimeout)
        } catch ProcessTimeoutError.timedOut {
            AppConstants.logger.error("Sparkdock command '\(command)' process timed out after \(AppConstants.processTimeout) seconds")
            return false
        } catch {
            AppConstants.logger.error("Sparkdock command '\(command)' failed: \(error.localizedDescription)")
            return false
        }

        return terminationStatus == 0
    }

    private func runSparkdockCheck() async -> Bool {
        return await runSparkdockCommand("check-updates")
    }

    private func runHttpProxyCheck() async -> Bool {
        return await runSparkdockCommand("http-proxy-check-updates")
    }

    private func runCheckUpdatesCommand(_ subsystem: String) async -> Bool {
        let status = await runCheckUpdatesCommandStatus(subsystem)
        return status == 0
    }

    /// Returns the termination status of sparkdock-check-updates, or nil on error/timeout.
    /// Exit codes: 0 = updates available, 1 = no updates, 3 = not configured
    private func runCheckUpdatesCommandStatus(_ subsystem: String) async -> Int32? {
        let checkUpdatesPath = AppConstants.checkUpdatesExecutablePath
        guard FileManager.default.fileExists(atPath: checkUpdatesPath) else {
            AppConstants.logger.warning("sparkdock-check-updates not found at \(checkUpdatesPath)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: checkUpdatesPath)
        process.arguments = [subsystem]

        let terminationStatus: Int32
        do {
            terminationStatus = try await runProcessWithTimeout(process, seconds: AppConstants.processTimeout)
        } catch ProcessTimeoutError.timedOut {
            AppConstants.logger.error("sparkdock-check-updates '\(subsystem)' timed out after \(AppConstants.processTimeout) seconds")
            return nil
        } catch {
            AppConstants.logger.error("sparkdock-check-updates '\(subsystem)' failed: \(error.localizedDescription)")
            return nil
        }

        return terminationStatus
    }

    private func runAgentsCheck() async -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.checkUpdatesExecutablePath) else {
            AppConstants.logger.info("sparkdock-check-updates not found, agents check skipped")
            agentsLastStatus = nil
            return false
        }
        let status = await runCheckUpdatesCommandStatus("agents")
        agentsLastStatus = status
        // Exit code 3 = not configured (cache not synced yet)
        if status == 3 {
            return false
        }
        return status == 0
    }

    private func runTimetrackerCheck() async -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.checkUpdatesExecutablePath) else {
            AppConstants.logger.info("sparkdock-check-updates not found, timetracker check skipped")
            timetrackerLastStatus = nil
            return false
        }
        let status = await runCheckUpdatesCommandStatus("timetracker")
        timetrackerLastStatus = status
        // Exit code 3 = not configured (CLI not installed yet)
        if status == 3 {
            return false
        }
        return status == 0
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

    /// Agent resources are considered configured when script exists AND last check returned a known good status.
    /// Returns false for: missing script, nil (error/timeout), or exit 3 (not configured).
    private func isAgentsConfigured() -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.checkUpdatesExecutablePath) else {
            return false
        }
        guard let status = agentsLastStatus else {
            // Unknown/failed status — treat as not configured to avoid misleading green UI
            return false
        }
        return status != 3
    }

    /// Timetracker is considered configured when the CLI is installed and reachable.
    /// Returns false for: missing script, nil (error/timeout), or exit 3 (CLI absent or not set up).
    private func isTimetrackerConfigured() -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.checkUpdatesExecutablePath) else {
            return false
        }
        guard let status = timetrackerLastStatus else {
            // Unknown/failed status — treat as not configured to avoid misleading green UI
            return false
        }
        return status != 3
    }

    private func updateUI(hasUpdates: Bool, outdatedBrewFormulae: Int = 0, outdatedBrewCasks: Int = 0, hasHttpProxyUpdates: Bool = false, hasAgentUpdates: Bool = false, agentsConfigured: Bool = true, claudeUsageStatus: ClaudeUsageStatus? = nil, hasTimetrackerUpdates: Bool = false, timetrackerConfigured: Bool = true) {
        self.hasUpdates = hasUpdates
        self.hasHttpProxyUpdates = hasHttpProxyUpdates
        self.hasAgentUpdates = hasAgentUpdates
        self.claudeUsageStatus = claudeUsageStatus
        self.hasTimetrackerUpdates = hasTimetrackerUpdates
        self.outdatedBrewFormulaeCount = outdatedBrewFormulae
        self.outdatedBrewCasksCount = outdatedBrewCasks
        let totalBrewCount = totalOutdatedBrewCount

        let hasAnyUpdates = hasUpdates || totalBrewCount > 0 || hasHttpProxyUpdates || hasAgentUpdates || hasTimetrackerUpdates
        statusItem?.button?.image = loadIcon(hasUpdates: hasAnyUpdates)

        // Create more detailed tooltip
        var tooltipParts: [String] = []
        if hasUpdates {
            tooltipParts.append("Sparkdock updates available")
        }
        if hasHttpProxyUpdates {
            tooltipParts.append("HTTP proxy updates available")
        }
        if hasAgentUpdates {
            tooltipParts.append("Agent skills updates available")
        }
        if hasTimetrackerUpdates {
            tooltipParts.append("Timetracker updates available")
        }
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

        // Update Sparkdock status line
        if hasUpdates {
            updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Update", color: .systemOrange)
        } else {
            updateStatusMenuItem(sparkdockStatusMenuItem, title: "Sparkdock", badge: "Up to date", color: .systemGreen)
        }

        // Update Brew status line
        if totalBrewCount > 0 {
            let updateLabel = totalBrewCount == 1 ? "1 update" : "\(totalBrewCount) updates"
            updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: updateLabel, color: .systemOrange)
            brewStatusMenuItem?.toolTip = "\(outdatedBrewFormulae) formulae, \(outdatedBrewCasks) casks"
        } else {
            updateStatusMenuItem(brewStatusMenuItem, title: "Homebrew", badge: "Up to date", color: .systemGreen)
            brewStatusMenuItem?.toolTip = nil
        }

        // Update HTTP proxy status line
        if hasHttpProxyUpdates {
            updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Update", color: .systemOrange)
        } else {
            updateStatusMenuItem(httpProxyStatusMenuItem, title: "HTTP proxy", badge: "Up to date", color: .systemGreen)
        }

        // Update agent skills status line
        if !agentsConfigured {
            updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Not configured", color: .systemGray)
        } else if hasAgentUpdates {
            updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Update", color: .systemOrange)
        } else {
            updateStatusMenuItem(agentsStatusMenuItem, title: "Agent skills", badge: "Up to date", color: .systemGreen)
        }

        updateClaudeUsageUI(claudeUsageStatus)

        // Update Timetracker status line. Hidden outright when the CLI is not on the
        // machine: a permanent "not installed" row would sit in every developer's
        // menu advertising a tool they have not adopted.
        let timetrackerInstalled = Self.executablePath(for: "timetracker") != nil
        timetrackerStatusMenuItem?.isHidden = !timetrackerInstalled
        if !timetrackerInstalled {
            // nothing to report
        } else if !timetrackerConfigured {
            updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Not configured", color: .systemGray)
        } else if hasTimetrackerUpdates {
            updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Update", color: .systemOrange)
        } else {
            updateStatusMenuItem(timetrackerStatusMenuItem, title: "Timetracker", badge: "Up to date", color: .systemGreen)
        }

        // Update the "Upgrade Sparkdock" menu item visibility
        if let updateItem = updateNowMenuItem {
            if hasUpdates {
                updateItem.title = "Upgrade Sparkdock"
                updateItem.isEnabled = true
                updateItem.isHidden = false
            } else {
                updateItem.isHidden = true
            }
        }

        // Update the "Upgrade Homebrew" menu item visibility
        if let upgradeBrewItem = upgradeBrewMenuItem {
            if totalBrewCount > 0 {
                upgradeBrewItem.title = "Upgrade Homebrew (\(totalBrewCount))"
                upgradeBrewItem.toolTip = "\(outdatedBrewFormulae) formulae, \(outdatedBrewCasks) casks"
                upgradeBrewItem.isEnabled = true
                upgradeBrewItem.isHidden = false
            } else {
                upgradeBrewItem.toolTip = nil
                upgradeBrewItem.isHidden = true
            }
        }

        // Update the "Upgrade HTTP proxy" menu item visibility
        if let upgradeHttpProxyItem = upgradeHttpProxyMenuItem {
            if hasHttpProxyUpdates {
                upgradeHttpProxyItem.title = "Upgrade HTTP proxy"
                upgradeHttpProxyItem.isEnabled = true
                upgradeHttpProxyItem.isHidden = false
            } else {
                upgradeHttpProxyItem.isHidden = true
            }
        }

        // Update the "Refresh agent skills" menu item visibility
        if let upgradeAgentsItem = upgradeAgentsMenuItem {
            if hasAgentUpdates || !agentsConfigured {
                // Show when updates available OR not configured (so user can bootstrap initial sync)
                upgradeAgentsItem.title = hasAgentUpdates ? "Refresh agent skills" : "Set up agent skills"
                upgradeAgentsItem.isEnabled = true
                upgradeAgentsItem.isHidden = false
            } else {
                upgradeAgentsItem.isHidden = true
            }
        }

        // Update the "Upgrade Timetracker" menu item visibility
        if let upgradeTimetrackerItem = upgradeTimetrackerMenuItem {
            if hasTimetrackerUpdates {
                upgradeTimetrackerItem.title = "Upgrade Timetracker"
                upgradeTimetrackerItem.isEnabled = true
                upgradeTimetrackerItem.isHidden = false
            } else {
                upgradeTimetrackerItem.isHidden = true
            }
        }

        let updateActionItems = [updateNowMenuItem, upgradeBrewMenuItem, upgradeHttpProxyMenuItem, upgradeAgentsMenuItem, upgradeTimetrackerMenuItem]
        let hasVisibleUpdateActions = updateActionItems.contains { item in
            guard let item = item else { return false }
            return !item.isHidden
        }
        updateActionsSectionMenuItem?.isHidden = !hasVisibleUpdateActions
        updateActionsSectionSeparator?.isHidden = !hasVisibleUpdateActions

        refreshDynamicMenuItems()
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
        guard hasUpdates else { return }
        executeTerminalCommand("sparkdock", recheckNotification: RecheckNotification.sparkdock)
    }

    @objc private func upgradeBrew() {
        guard totalOutdatedBrewCount > 0 else { return }
        // Create a compound command that only runs the second upgrade if the first succeeds
        let upgradeCommand = "brew upgrade && brew upgrade --cask"
        executeTerminalCommand(upgradeCommand, recheckNotification: RecheckNotification.brew)
    }

    @objc private func upgradeHttpProxy() {
        guard hasHttpProxyUpdates else { return }
        executeTerminalCommand("sjust http-proxy-install-update", recheckNotification: RecheckNotification.httpProxy)
    }

    @objc private func upgradeAgents() {
        // Allow refresh when agent resources have updates OR are not configured (initial setup)
        let agentsConfigured = isAgentsConfigured()
        guard hasAgentUpdates || !agentsConfigured else { return }
        executeTerminalCommand("sjust sf-harness-sync", recheckNotification: RecheckNotification.agents)
    }

    @objc private func upgradeTimetracker() {
        guard hasTimetrackerUpdates else { return }
        // `timetracker update --apply` and not the `timetracker-update` shell
        // function: executeTerminalCommand runs a non-interactive login shell, and
        // zsh sources ~/.zshrc only for interactive shells, so the function is not
        // defined there. The binary knows how to update itself.
        executeTerminalCommand("timetracker update --apply", recheckNotification: RecheckNotification.timetracker)
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
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                AppConstants.logger.info("Disabled login item")
            } else {
                try service.register()
                AppConstants.logger.info("Enabled login item")
            }
        } catch {
            AppConstants.logger.error("Failed to toggle login item: \(error.localizedDescription)")
            showErrorAlert("Login Item Error", "Failed to toggle startup at login setting.")
        }
        updateLoginItemStatus()
    }

    private func updateLoginItemStatus() {
        guard let loginMenuItem = menu?.items.first(where: { $0.tag == MenuItemTag.loginItem.rawValue }) else { return }

        let service = SMAppService.mainApp
        loginMenuItem.state = service.status == .enabled ? .on : .off
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
            var foundLogo = false
            if let path = Bundle.module.path(forResource: AppConstants.logoResourceName, ofType: "png") {
                cachedLogoImage = NSImage(contentsOfFile: path)
                foundLogo = true
            } else if let path = Bundle.main.path(forResource: AppConstants.logoResourceName, ofType: "png") {
                cachedLogoImage = NSImage(contentsOfFile: path)
                foundLogo = true
            }
            if !foundLogo {
                let moduleResourcePath = Bundle.module.resourcePath ?? "<nil>"
                let mainResourcePath = Bundle.main.resourcePath ?? "<nil>"
                let modulePngs = (try? FileManager.default.contentsOfDirectory(atPath: moduleResourcePath).filter { $0.hasSuffix(".png") }) ?? []
                let mainPngs = (try? FileManager.default.contentsOfDirectory(atPath: mainResourcePath).filter { $0.hasSuffix(".png") }) ?? []
                let modulePngList = modulePngs.joined(separator: ", ")
                let mainPngList = mainPngs.joined(separator: ", ")
                AppConstants.logger.error("Logo resource '\(AppConstants.logoResourceName).png' not found. Checked paths: module=\(moduleResourcePath), main=\(mainResourcePath). Available PNGs in module: \(modulePngList). Available PNGs in main: \(mainPngList).")
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

// MARK: - CLI Handling
private func checkForExistingInstance() -> Bool {
    let currentPID = ProcessInfo.processInfo.processIdentifier

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", "sparkdock-manager"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse PIDs from output and check if any other instance is running
        let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .compactMap { Int32($0) }
            .filter { $0 != currentPID }

        return !pids.isEmpty

    } catch {
        AppConstants.logger.warning("Failed to check for existing instances: \(error.localizedDescription)")
        return false
    }
}

private func handleCLIArguments() -> Bool {
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
        return true
    }

    if arguments.contains("--status") {
        print("Sparkdock Manager - Status: OK")
        print("Executable path: /opt/sparkdock/bin/sparkdock.macos")
        print("Config file: Sources/SparkdockManager/Resources/menu.json")

        // Check if sparkdock executable exists
        if FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) {
            print("Sparkdock executable: ✅ Found")
        } else {
            print("Sparkdock executable: ❌ Not found")
        }

        return true
    }

    return false
}

// MARK: - Main Entry Point
if handleCLIArguments() {
    exit(0)
}

// Check if another instance is already running
if checkForExistingInstance() {
    print("⚠️  Sparkdock menu bar app is already running")
    print("💡 If you need to restart it, quit the app first from the menu bar")
    print("💡 If the app is stuck or not visible, use: pkill -f sparkdock-manager")
    exit(1)
}

let app = NSApplication.shared
let delegate = SparkdockMenubarApp()
app.delegate = delegate
app.run()
