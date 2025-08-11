#!/usr/bin/env swift
import Cocoa
import Foundation
import UserNotifications

class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var updateTimer: Timer?
    private var hasUpdates = false
    private var logoImage: NSImage?
    private var statusMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loadLogo()
        setupMenuBar()
        setupUpdateTimer()
        checkForUpdatesAsync()
    }
    
    private func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set initial icon
        if let button = statusItem.button {
            button.image = logoImage
            button.imagePosition = .imageOnly
            button.toolTip = "Sparkdock - Up to date"
        }
        
        // Create menu
        menu = NSMenu()
        
        // Title at the very top (non-clickable)
        let titleItem = NSMenuItem(title: "Sparkdock", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Status message (non-clickable)
        statusMenuItem = NSMenuItem(title: "Checking for updates...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Menu items
        let checkUpdatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)
        
        let updateNowItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
        updateNowItem.target = self
        updateNowItem.tag = 1 // Tag to identify this item
        menu.addItem(updateNowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let openSjustItem = NSMenuItem(title: "Open sjust", action: #selector(openSjust), keyEquivalent: "")
        openSjustItem.target = self
        menu.addItem(openSjustItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func setupUpdateTimer() {
        // Check for updates every 4 hours
        updateTimer = Timer.scheduledTimer(withTimeInterval: 4 * 60 * 60, repeats: true) { _ in
            self.checkForUpdatesAsync()
        }
    }
    
    @objc private func checkForUpdates() {
        statusMenuItem.title = "⏳ Checking for updates..."
        checkForUpdatesAsync()
    }
    
    private func checkForUpdatesAsync() {
        DispatchQueue.global(qos: .background).async {
            let hasUpdates = self.runSparkdockCheck()
            
            DispatchQueue.main.async {
                self.updateMenuBarIcon(hasUpdates: hasUpdates)
            }
        }
    }
    
    private func runSparkdockCheck() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/sparkdock/bin/sparkdock.macos")
        process.arguments = ["check-updates"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func updateMenuBarIcon(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates
        
        if let button = statusItem.button {
            if hasUpdates {
                // Create orange tinted version for updates
                let tintedLogo = logoImage?.copy() as? NSImage
                tintedLogo?.isTemplate = false
                tintedLogo?.lockFocus()
                NSColor.systemOrange.set()
                NSRect(origin: .zero, size: tintedLogo?.size ?? .zero).fill(using: .sourceAtop)
                tintedLogo?.unlockFocus()
                button.image = tintedLogo
                button.toolTip = "Sparkdock - Updates available"
            } else {
                button.image = logoImage
                button.toolTip = "Sparkdock - Up to date"
            }
        }
        
        updateStatusMessage(hasUpdates: hasUpdates)
    }
    
    private func updateStatusMessage(hasUpdates: Bool) {
        if hasUpdates {
            statusMenuItem.title = "🔄 Updates Available"
        } else {
            statusMenuItem.title = "✅ Sparkdock is up to date"
        }
        
        // Update "Update Now" menu item
        if let updateNowItem = menu.items.first(where: { $0.tag == 1 }) {
            if hasUpdates {
                updateNowItem.title = "Update Now"
                updateNowItem.isEnabled = true
            } else {
                updateNowItem.title = "Already up to date"
                updateNowItem.isEnabled = false
            }
        }
    }
    
    @objc private func updateNow() {
        // Only run if updates are available (menu item should be disabled otherwise)
        guard hasUpdates else {
            return
        }
        
        // Run sparkdock update in Terminal
        let script = """
            tell application "Terminal"
                activate
                do script "sparkdock"
            end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    @objc private func openSjust() {
        let script = """
            tell application "Terminal"
                activate
                do script "sjust"
            end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
    
    private func loadLogo() {
        if let path = Bundle.main.path(forResource: "sparkfabrik-logo", ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        } else if let path = Bundle.module.path(forResource: "sparkfabrik-logo", ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        }
        
        // Set template rendering for menu bar
        logoImage?.isTemplate = true
        logoImage?.size = NSSize(width: 18, height: 18)
    }
    
    
    private func showNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                
                center.add(request) { _ in }
            }
        }
    }
}

// Main application entry point
let app = NSApplication.shared
let delegate = SparkdockMenubarApp()
app.delegate = delegate

// Keep the app running
app.run()