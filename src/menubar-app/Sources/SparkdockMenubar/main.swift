#!/usr/bin/env swift
import Cocoa
import Foundation
import UserNotifications

class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var updateTimer: Timer?
    private var hasUpdates = false
    private var logoImage: NSImage? // Cache the logo
    private var statusMenuItem: NSMenuItem! // Status message at top of menu
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loadLogo() // Load logo once at startup
        setupMenuBar()
        setupUpdateTimer()
        checkForUpdatesAsync()
    }
    
    private func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set initial icon (SparkFabrik logo - up to date)
        if let button = statusItem.button {
            // Try to use a custom SparkFabrik icon, fallback to SF Symbol
            let icon = createSparkFabrikIcon(isUpdating: false)
            button.image = icon
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
            print("Error checking for updates: \(error)")
            return false
        }
    }
    
    private func updateMenuBarIcon(hasUpdates: Bool) {
        self.hasUpdates = hasUpdates
        
        if let button = statusItem.button {
            let icon = createSparkFabrikIcon(isUpdating: hasUpdates)
            button.image = icon
            
            if hasUpdates {
                button.toolTip = "Sparkdock - Updates available"
            } else {
                button.toolTip = "Sparkdock - Up to date"
            }
        }
        
        // Update status message in menu
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
        // Load the SparkFabrik logo once at startup
        if let path = Bundle.main.path(forResource: "sparkfabrik-logo", ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
            print("Loaded logo from main bundle: \(path)")
        } else {
            // Try Bundle.module for SwiftPM resources
            if let path = Bundle.module.path(forResource: "sparkfabrik-logo", ofType: "png") {
                logoImage = NSImage(contentsOfFile: path)
                print("Loaded logo from module bundle: \(path)")
            }
        }
        
        if logoImage == nil {
            print("SparkFabrik logo not found in resources")
        }
    }
    
    private func createSparkFabrikIcon(isUpdating: Bool) -> NSImage? {
        // Use cached logo if available
        if let logoImage = logoImage {
            // Resize logo to menu bar size
            let menuBarIcon = NSImage(size: NSSize(width: 18, height: 18))
            menuBarIcon.lockFocus()
            logoImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            menuBarIcon.unlockFocus()
            
            // Tint for update status
            if isUpdating {
                let tintedIcon = menuBarIcon.copy() as? NSImage
                tintedIcon?.lockFocus()
                NSColor.systemOrange.set()
                NSRect(origin: .zero, size: tintedIcon?.size ?? .zero).fill(using: .sourceAtop)
                tintedIcon?.unlockFocus()
                tintedIcon?.isTemplate = false
                return tintedIcon
            } else {
                menuBarIcon.isTemplate = true // Adapts to menu bar appearance
                return menuBarIcon
            }
        }
        
        // Fallback: Create a custom SparkFabrik-style icon
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size)
        
        icon.lockFocus()
        
        // Set the color based on update status
        let color = isUpdating ? NSColor.systemOrange : NSColor.controlAccentColor
        color.setFill()
        
        // Draw a stylized "S" shape (for SparkFabrik) or flame-like icon
        let path = NSBezierPath()
        
        // Create a flame-like shape
        path.move(to: NSPoint(x: 9, y: 2))
        path.curve(to: NSPoint(x: 14, y: 7), 
                  controlPoint1: NSPoint(x: 12, y: 2), 
                  controlPoint2: NSPoint(x: 14, y: 4))
        path.curve(to: NSPoint(x: 11, y: 12), 
                  controlPoint1: NSPoint(x: 14, y: 9), 
                  controlPoint2: NSPoint(x: 13, y: 11))
        path.curve(to: NSPoint(x: 9, y: 16), 
                  controlPoint1: NSPoint(x: 10, y: 13), 
                  controlPoint2: NSPoint(x: 9, y: 14))
        path.curve(to: NSPoint(x: 7, y: 12), 
                  controlPoint1: NSPoint(x: 9, y: 14), 
                  controlPoint2: NSPoint(x: 8, y: 13))
        path.curve(to: NSPoint(x: 4, y: 7), 
                  controlPoint1: NSPoint(x: 5, y: 11), 
                  controlPoint2: NSPoint(x: 4, y: 9))
        path.curve(to: NSPoint(x: 9, y: 2), 
                  controlPoint1: NSPoint(x: 4, y: 4), 
                  controlPoint2: NSPoint(x: 6, y: 2))
        
        path.fill()
        
        icon.unlockFocus()
        icon.isTemplate = !isUpdating // Template icons adapt to menu bar appearance
        
        return icon
    }
    
    private func showNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        
        // Request permission first
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                content.sound = .default
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                
                center.add(request) { error in
                    if let error = error {
                        print("Error showing notification: \(error)")
                    }
                }
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