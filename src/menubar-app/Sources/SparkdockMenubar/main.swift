#!/usr/bin/env swift

import Cocoa
import Foundation
import ServiceManagement
import os.log

// MARK: - Configuration Constants
private struct AppConstants {
    static let updateInterval: TimeInterval = 4 * 60 * 60
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    static let logoResourceName = "sparkfabrik-logo"
    static let iconSize = NSSize(width: 18, height: 18)
    static let bundleIdentifier = "com.sparkfabrik.sparkdock.manager"
    static let logger = Logger(subsystem: bundleIdentifier, category: "MenuBar")

    static var configPath: String {
        // Check for development override first
        if let devPath = ProcessInfo.processInfo.environment["SPARKDOCK_MENU_CONFIG"] {
            return devPath
        }

        // Try local development path (relative to current working directory)
        let localPath = "config/menubar-app/menu.json"
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }

        // Default production path
        return "/opt/sparkdock/config/menubar-app/menu.json"
    }
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
    var updateTimer: Timer?
    fileprivate var menuConfig: MenuConfig?
    private var dynamicMenuItems: [NSMenuItem] = []
    private var allDynamicElements: [NSMenuItem] = []
    private var lastConfigModificationTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) {
            AppConstants.logger.warning("Sparkdock executable not found at \(AppConstants.sparkdockExecutablePath)")
        }

        loadMenuConfiguration()

        // Initialize config file modification time tracking
        initializeConfigTracking()

        setupMenuBar()
        setupUpdateTimer()

        // Set initial status and check for updates
        statusMenuItem?.title = "⏳ Checking for updates..."
        checkForUpdatesAndReloadConfig()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    private func loadMenuConfiguration() {
        let configPath = AppConstants.configPath
        AppConstants.logger.info("Attempting to load menu config from: \(configPath)")

        guard FileManager.default.fileExists(atPath: configPath) else {
            AppConstants.logger.info("Menu config file not found at \(configPath), using fallback configuration")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            menuConfig = try JSONDecoder().decode(MenuConfig.self, from: data)
            AppConstants.logger.info("Successfully loaded menu config with \(self.menuConfig?.menu.sections.count ?? 0) sections")
        } catch {
            AppConstants.logger.error("Failed to load menu configuration: \(error)")
        }
    }


    private func updateMenuItemsOnly() {
        guard let menu = menu, let config = menuConfig else { return }

        // Remove all existing dynamic elements
        allDynamicElements.forEach { menu.removeItem($0) }
        dynamicMenuItems.removeAll(keepingCapacity: true)
        allDynamicElements.removeAll(keepingCapacity: true)

        // Find insertion point after "Update Now" separator
        guard let insertIndex = findDynamicMenuInsertionPoint() else {
            AppConstants.logger.warning("Could not find insertion point for dynamic menu items")
            return
        }

        // Add new dynamic sections
        addDynamicSections(config.menu.sections, to: menu, startingAt: insertIndex)
    }

    private func findDynamicMenuInsertionPoint() -> Int? {
        guard let menu = menu else { return nil }

        for (index, item) in menu.items.enumerated() {
            if item.tag == MenuItemTag.updateNow.rawValue,
               index + 1 < menu.items.count,
               menu.items[index + 1].isSeparatorItem {
                return index + 2
            }
        }
        return nil
    }

    private func addDynamicSections(_ sections: [MenuSection], to menu: NSMenu, startingAt insertIndex: Int) {
        var currentIndex = insertIndex

        for section in sections {
            // Add section header
            let sectionItem = NSMenuItem(title: section.name, action: nil, keyEquivalent: "")
            sectionItem.isEnabled = false
            menu.insertItem(sectionItem, at: currentIndex)
            allDynamicElements.append(sectionItem)
            currentIndex += 1

            // Add section items
            for item in section.items {
                let menuItem = NSMenuItem(title: item.title, action: #selector(handleDynamicMenuItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item
                menu.insertItem(menuItem, at: currentIndex)
                dynamicMenuItems.append(menuItem)
                allDynamicElements.append(menuItem)
                currentIndex += 1
            }

            // Add section separator
            let separator = NSMenuItem.separator()
            menu.insertItem(separator, at: currentIndex)
            allDynamicElements.append(separator)
            currentIndex += 1
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

        // Create status menu item - preserve existing title if rebuilding
        let currentTitle = statusMenuItem?.title ?? "Checking for updates..."
        let newStatusMenuItem = NSMenuItem(title: currentTitle, action: #selector(checkForUpdatesAction), keyEquivalent: "")
        newStatusMenuItem.target = self
        menu.addItem(newStatusMenuItem)
        statusMenuItem = newStatusMenuItem  // Update reference after adding to menu
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = MenuItemTag.updateNow.rawValue
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // Add dynamic menu sections from configuration
        if let config = menuConfig {
            addDynamicMenuSections(config.menu.sections, to: menu)
        } else {
            // Fallback to hardcoded menu items if no config
            addFallbackMenuItems(to: menu)
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
            allDynamicElements.append(sectionItem)

            for item in section.items {
                let menuItem = NSMenuItem(title: item.title, action: #selector(handleDynamicMenuItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item
                menu.addItem(menuItem)
                dynamicMenuItems.append(menuItem)
                allDynamicElements.append(menuItem)
            }

            let separator = NSMenuItem.separator()
            menu.addItem(separator)
            allDynamicElements.append(separator)
        }
    }

    private func addFallbackMenuItems(to menu: NSMenu) {
        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.isEnabled = false
        menu.addItem(toolsItem)

        let sjustItem = NSMenuItem(title: "Open sjust", action: #selector(runSjust), keyEquivalent: "")
        sjustItem.target = self
        menu.addItem(sjustItem)

        let httpProxyItem = NSMenuItem(title: "Open http-proxy dashboard", action: #selector(runHttpProxyDashboard), keyEquivalent: "")
        httpProxyItem.target = self
        menu.addItem(httpProxyItem)
        menu.addItem(.separator())

        let companyItem = NSMenuItem(title: "Company", action: nil, keyEquivalent: "")
        companyItem.isEnabled = false
        menu.addItem(companyItem)

        let playbookItem = NSMenuItem(title: "Company Playbook", action: #selector(openPlaybook), keyEquivalent: "")
        playbookItem.target = self
        menu.addItem(playbookItem)

        let coreSkillsItem = NSMenuItem(title: "Core Skills", action: #selector(openCoreSkills), keyEquivalent: "")
        coreSkillsItem.target = self
        menu.addItem(coreSkillsItem)
        menu.addItem(.separator())
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

    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.updateInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdatesAndReloadConfig()
        }

        updateTimer?.tolerance = 60.0
    }

    @objc private func checkForUpdatesAction() {
        statusMenuItem?.title = "⏳ Checking for updates..."
        checkForUpdatesAndReloadConfig()
    }

    private func checkForUpdatesAndReloadConfig() {
        // Check if menu config has changed and reload if needed
        let configPath = AppConstants.configPath
        let currentModificationTime = getFileModificationTime(configPath)

        if let currentTime = currentModificationTime,
           lastConfigModificationTime != currentTime {
            AppConstants.logger.info("Menu configuration file changed, reloading menu items...")

            DispatchQueue.main.async { [weak self] in
                self?.reloadMenuItemsOnly()
                self?.lastConfigModificationTime = currentTime
            }
        }

        // Check for sparkdock updates
        checkForUpdates()
    }

    private func getFileModificationTime(_ path: String) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    private func initializeConfigTracking() {
        let configPath = AppConstants.configPath
        lastConfigModificationTime = getFileModificationTime(configPath)
        AppConstants.logger.info("Initialized config tracking for: \(configPath)")
    }

    private func reloadMenuItemsOnly() {
        loadMenuConfiguration()
        updateMenuItemsOnly()
        AppConstants.logger.info("Menu items reloaded from configuration")
    }

    private func checkForUpdates() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let hasUpdates = self?.runSparkdockCheck() ?? false

            DispatchQueue.main.async {
                self?.updateUI(hasUpdates: hasUpdates)
            }
        }
    }

    private func runSparkdockCheck() -> Bool {
        // Check if the executable exists before attempting to run it
        guard FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) else {
            NSLog("Sparkdock executable not found at path: \(AppConstants.sparkdockExecutablePath)")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConstants.sparkdockExecutablePath)
        process.arguments = ["check-updates"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            AppConstants.logger.error("Failed to run sparkdock check: \(error)")
            return false
        }
    }

    private func updateUI(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates

        statusItem?.button?.image = loadIcon(hasUpdates: hasUpdates)
        statusItem?.button?.toolTip = hasUpdates ? "Sparkdock - Updates available" : "Sparkdock - Up to date"

        let newTitle = hasUpdates ? "🔄 Updates Available" : "✅ Sparkdock is up to date"

        // Update the status menu item title
        if let statusMenuItem = statusMenuItem {
            statusMenuItem.title = newTitle
            AppConstants.logger.info("Updated status to: \(newTitle)")
        } else {
            AppConstants.logger.warning("statusMenuItem is nil, cannot update title")
        }

        // Update the "Update Now" menu item visibility
        if let menu = menu,
           let updateItem = menu.items.first(where: { $0.tag == MenuItemTag.updateNow.rawValue }) {
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

    @objc private func runSjust() {
        executeTerminalCommand("sjust")
    }

    @objc private func runHttpProxyDashboard() {
        executeTerminalCommand("spark-http-proxy dashboard")
    }

    @objc private func openPlaybook() {
        if let url = URL(string: "https://playbook.sparkfabrik.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openCoreSkills() {
        if let url = URL(string: "https://playbook.sparkfabrik.com/working-at-sparkfabrik/core-skills") {
            NSWorkspace.shared.open(url)
        }
    }

    private func executeTerminalCommand(_ command: String) {
        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Terminal"
                activate
                if (count of windows) > 0 then
                    do script "\(escapedCommand)" in front window
                else
                    do script "\(escapedCommand)"
                end if
            end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                AppConstants.logger.error("Failed to execute terminal command: \(error)")
            }
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            AppConstants.logger.error("Failed to toggle login item: \(error)")
        }
        updateLoginItemStatus()
    }

    private func updateLoginItemStatus() {
        guard let loginMenuItem = menu?.items.first(where: { $0.tag == MenuItemTag.loginItem.rawValue }) else { return }

        let service = SMAppService.mainApp
        loginMenuItem.state = service.status == .enabled ? .on : .off
    }

    private func loadIcon(hasUpdates: Bool) -> NSImage? {
        var logoImage: NSImage?

        // Try Bundle.module first (for executable targets with resources)
        if let path = Bundle.module.path(forResource: AppConstants.logoResourceName, ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        } else if let path = Bundle.main.path(forResource: AppConstants.logoResourceName, ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        }

        let logo = logoImage ?? createDefaultIcon()

        let icon = NSImage(size: AppConstants.iconSize, flipped: false) { rect in
            logo.draw(in: rect)

            if hasUpdates {
                NSColor.systemOrange.set()
                rect.fill(using: .sourceAtop)
            }

            return true
        }

        icon.isTemplate = !hasUpdates
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