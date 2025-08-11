#!/usr/bin/env swift

import Cocoa
import Foundation
import ServiceManagement
import os.log
import Network

// MARK: - Configuration Constants
private struct AppConstants {
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
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

    enum MenuItemType: String, Codable {
        case command = "command"
        case url = "url"
    }
}

// MARK: - Menu Item Tags
private enum MenuItemTag: Int {
    case updateNow = 1
    case loginItem = 2
}

class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menu: NSMenu?
    var hasUpdates = false
    var statusMenuItem: NSMenuItem?
    var updateNowMenuItem: NSMenuItem?
    private var pathMonitor: NWPathMonitor?
    fileprivate var menuConfig: MenuConfig?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set proper activation policy for menu bar apps
        NSApp.setActivationPolicy(.accessory)

        loadMenuConfiguration()
        setupMenuBar()
        setupUpdateObservers()

        // Set initial status and check for updates
        statusMenuItem?.title = "⏳ Checking for updates..."
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
        button.toolTip = "Sparkdock - Up to date"

        setupMenu()
        statusItem.menu = menu
        updateLoginItemStatus()
    }

    private func setupMenu() {
        menu = NSMenu()
        guard let menu = menu else { return }

        let titleItem = NSMenuItem(title: "Sparkdock Manager", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Create status menu item
        let statusMenuItem = NSMenuItem(title: "Checking for updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)
        self.statusMenuItem = statusMenuItem
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = MenuItemTag.updateNow.rawValue
        menu.addItem(updateItem)
        updateNowMenuItem = updateItem

        menu.addItem(.separator())

        // Add dynamic menu sections from configuration
        if let config = menuConfig {
            addDynamicMenuSections(config.menu.sections, to: menu)
        }

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = MenuItemTag.loginItem.rawValue
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addDynamicMenuSections(_ sections: [MenuSection], to menu: NSMenu) {
        for section in sections {
            let sectionItem = NSMenuItem(title: section.name, action: nil, keyEquivalent: "")
            sectionItem.isEnabled = false
            menu.addItem(sectionItem)

            for item in section.items {
                let menuItem = NSMenuItem(title: item.title, action: #selector(handleDynamicMenuItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item
                menu.addItem(menuItem)
            }

            menu.addItem(.separator())
        }
    }

    @objc private func handleDynamicMenuItem(_ sender: NSMenuItem) {
        guard let menuItem = sender.representedObject as? MenuItem else { return }

        switch menuItem.type {
        case .command:
            if let command = menuItem.command {
                executeTerminalCommand(command)
            }
        case .url:
            if let urlString = menuItem.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
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
                    self?.statusMenuItem?.title = "⏳ Checking for updates..."
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
        AppConstants.logger.info("Update observers cleaned up")
    }
    @objc private func systemDidWake() {
        AppConstants.logger.info("System woke from sleep - checking for updates")
        statusMenuItem?.title = "⏳ Checking for updates..."
        checkForUpdates()
    }

    @objc private func checkForUpdatesAction() {
        statusMenuItem?.title = "⏳ Checking for updates..."
        checkForUpdates()
    }

    private func checkForUpdates() {
        Task(priority: .background) {
            let hasUpdates = runSparkdockCheck()
            await MainActor.run {
                updateUI(hasUpdates: hasUpdates)
            }
        }
    }

    private func runSparkdockCheck() -> Bool {
        guard FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) else {
            AppConstants.logger.warning("Sparkdock executable not found at \(AppConstants.sparkdockExecutablePath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConstants.sparkdockExecutablePath)
        process.arguments = ["check-updates"]

        // Set up timeout handling
        let semaphore = DispatchSemaphore(value: 0)
        var terminationStatus: Int32 = -1

        process.terminationHandler = { proc in
            terminationStatus = proc.terminationStatus
            semaphore.signal()
        }

        do {
            try process.run()

            // Wait for process completion or timeout
            let timeoutResult = semaphore.wait(timeout: .now() + AppConstants.processTimeout)

            if timeoutResult == .timedOut {
                AppConstants.logger.error("Sparkdock check-updates process timed out after \(AppConstants.processTimeout) seconds")
                process.terminate()
                return false
            }

            return terminationStatus == 0
        } catch {
            AppConstants.logger.error("Failed to run sparkdock check: \(error.localizedDescription)")
            return false
        }
    }

    private func updateUI(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates

        statusItem?.button?.image = loadIcon(hasUpdates: hasUpdates)
        statusItem?.button?.toolTip = hasUpdates ? "Sparkdock - Updates available" : "Sparkdock - Up to date"

        let newTitle = hasUpdates ? "🔄 Updates Available" : "✅ Sparkdock is up to date"

        statusMenuItem?.title = newTitle

        // Update the "Update Now" menu item visibility
        if let updateItem = updateNowMenuItem {
            if hasUpdates {
                updateItem.title = "Update Now"
                updateItem.isEnabled = true
                updateItem.isHidden = false
            } else {
                updateItem.isHidden = true
            }
        }
    }

    @objc private func updateNow() {
        guard hasUpdates else { return }
        executeTerminalCommand("sparkdock")
    }


    private func executeTerminalCommand(_ command: String) {
        let process = Process()
        // Use osascript to run AppleScript more securely
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Create AppleScript to open Terminal and run command
        let appleScript = """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))" in front window
            else
                do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
            end if
        end tell
        """
        process.arguments = ["-e", appleScript]
        do {
            try process.run()
            AppConstants.logger.info("Executed terminal command: \(command)")
        } catch {
            AppConstants.logger.error("Failed to execute terminal command '\(command)': \(error.localizedDescription)")
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
            if let path = Bundle.module.path(forResource: AppConstants.logoResourceName, ofType: "png") {
                cachedLogoImage = NSImage(contentsOfFile: path)
            } else if let path = Bundle.main.path(forResource: AppConstants.logoResourceName, ofType: "png") {
                cachedLogoImage = NSImage(contentsOfFile: path)
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
        let systemImage = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Sparkdock")!
        let config = NSImage.SymbolConfiguration(pointSize: AppConstants.iconSize.width, weight: .medium)
        return systemImage.withSymbolConfiguration(config) ?? systemImage
    }

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = SparkdockMenubarApp()
app.delegate = delegate
app.run()