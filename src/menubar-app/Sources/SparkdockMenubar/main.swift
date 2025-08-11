#!/usr/bin/env swift

import Cocoa
import Foundation
import UserNotifications
import ServiceManagement

// MARK: - Configuration Constants
private struct AppConstants {
    static let updateInterval: TimeInterval = 4 * 60 * 60 // 4 hours
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    static let logoResourceName = "sparkfabrik-logo"
    static let iconSize = NSSize(width: 18, height: 18)
}

class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var menu: NSMenu?
    var hasUpdates = false
    var statusMenuItem: NSMenuItem?
    var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Title
        let titleItem = NSMenuItem(title: "Sparkdock", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Status - clickable to trigger manual check
        statusMenuItem = NSMenuItem(title: "Checking for updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        statusMenuItem?.target = self
        if let statusMenuItem = statusMenuItem {
            menu.addItem(statusMenuItem)
        }
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = 1
        menu.addItem(updateItem)

        menu.addItem(.separator())
        let sjustItem = NSMenuItem(title: "Open sjust", action: #selector(openSjust), keyEquivalent: "")
        sjustItem.target = self
        menu.addItem(sjustItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = 2
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.updateInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    @objc private func checkForUpdatesAction() {
        // Update the status immediately in the non-clickable status item
        statusMenuItem?.title = "⏳ Checking for updates..."

        // Start the check
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppConstants.sparkdockExecutablePath)
        process.arguments = ["check-updates"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func updateUI(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates

        // Update icon
        statusItem?.button?.image = loadIcon(hasUpdates: hasUpdates)
        statusItem?.button?.toolTip = hasUpdates ? "Sparkdock - Updates available" : "Sparkdock - Up to date"

        // Update status message
        statusMenuItem?.title = hasUpdates ? "🔄 Updates Available" : "✅ Sparkdock is up to date"

        // Update menu items - hide "Update Now" when no updates
        if let menu = menu,
           let updateItem = menu.items.first(where: { $0.tag == 1 }) {
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

    private func executeTerminalCommand(_ command: String) {
        let script = """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                showNotification(title: "Sparkdock", message: "Could not update login item setting")
            }
        } else {
            showNotification(title: "Sparkdock", message: "Login item managed by LaunchAgent")
        }
        updateLoginItemStatus()
    }

    private func updateLoginItemStatus() {
        guard let loginMenuItem = menu?.items.first(where: { $0.tag == 2 }) else { return }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            loginMenuItem.state = service.status == .enabled ? .on : .off
        } else {
            loginMenuItem.title = "Start at Login (via LaunchAgent)"
            loginMenuItem.isEnabled = false
        }
    }

    private func showNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            center.add(request)
        }
    }

    private func loadIcon(hasUpdates: Bool) -> NSImage? {
        // Try to load the custom logo
        var logoImage: NSImage?

        if let path = Bundle.main.path(forResource: AppConstants.logoResourceName, ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        } else if let path = Bundle.module.path(forResource: AppConstants.logoResourceName, ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        }

        // If custom logo not found, create a default gear icon
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
        // Use system symbol if available (macOS 11+), otherwise create a simple shape
        if #available(macOS 11.0, *) {
            if let systemImage = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Sparkdock") {
                let config = NSImage.SymbolConfiguration(pointSize: AppConstants.iconSize.width, weight: .medium)
                return systemImage.withSymbolConfiguration(config) ?? systemImage
            }
        }

        // Fallback: create a simple filled circle
        return NSImage(size: AppConstants.iconSize, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            NSColor.controlAccentColor.setFill()
            path.fill()
            return true
        }
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