#!/usr/bin/env swift

import Cocoa
import Foundation
import ServiceManagement

// MARK: - Configuration Constants
private struct AppConstants {
    static let updateInterval: TimeInterval = 4 * 60 * 60
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    static let logoResourceName = "sparkfabrik-logo"
    static let iconSize = NSSize(width: 18, height: 18)
    static let bundleIdentifier = "com.sparkfabrik.sparkdock.manager"
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: AppConstants.sparkdockExecutablePath) {
            print("Warning: Sparkdock executable not found at \(AppConstants.sparkdockExecutablePath)")
        }

        setupMenuBar()
        setupUpdateTimer()
        checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
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

        statusMenuItem = NSMenuItem(title: "Checking for updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        statusMenuItem?.target = self
        if let statusMenuItem = statusMenuItem {
            menu.addItem(statusMenuItem)
        }
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = MenuItemTag.updateNow.rawValue
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.isEnabled = false
        menu.addItem(toolsItem)

        let sjustItem = NSMenuItem(title: "Open sjust", action: #selector(openSjust), keyEquivalent: "")
        sjustItem.target = self
        menu.addItem(sjustItem)
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

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = MenuItemTag.loginItem.rawValue
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.updateInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }

        updateTimer?.tolerance = 60.0
    }

    @objc private func checkForUpdatesAction() {
        statusMenuItem?.title = "⏳ Checking for updates..."
        checkForUpdates()
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
            print("Failed to run sparkdock check: \(error)")
            return false
        }
    }

    private func updateUI(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates

        statusItem?.button?.image = loadIcon(hasUpdates: hasUpdates)
        statusItem?.button?.toolTip = hasUpdates ? "Sparkdock - Updates available" : "Sparkdock - Up to date"

        statusMenuItem?.title = hasUpdates ? "🔄 Updates Available" : "✅ Sparkdock is up to date"
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

    @objc private func openSjust() {
        executeTerminalCommand("sjust")
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

        // Try iTerm first, fallback to Terminal
        let iTermScript = """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "\(escapedCommand)"
                end tell
            end tell
        """

        let terminalScript = """
            tell application "Terminal"
                activate
                do script "\(escapedCommand)"
            end tell
        """

        // Check if iTerm is available
        let workspace = NSWorkspace.shared
        if workspace.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil {
            if let appleScript = NSAppleScript(source: iTermScript) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)

                if error == nil {
                    return // iTerm worked successfully
                }
            }
        }

        // Fallback to Terminal
        if let appleScript = NSAppleScript(source: terminalScript) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print("Failed to execute terminal command: \(error)")
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
            print("Failed to toggle login item: \(error)")
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