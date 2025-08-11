# Technical Specification - Sparkdock Manager

## Implementation Details

This document provides code-level implementation details for AI agents working on the Sparkdock Manager codebase.

## File Structure

```
src/menubar-app/
├── Package.swift                           # Swift Package Manager configuration
├── Sources/SparkdockMenubar/
│   ├── main.swift                         # Main application implementation
│   └── Resources/
│       └── sparkfabrik-logo.png           # Custom logo asset
├── Tests/SparkdockMenubarTests/
│   └── SparkdockMenubarTests.swift        # Unit tests
├── com.sparkfabrik.sparkdock.menubar.plist # LaunchAgent configuration
├── Makefile                               # Build and installation automation
└── spec/                                  # This documentation
```

## Code Architecture

### Main Application Class

```swift
class SparkdockMenubarApp: NSObject, NSApplicationDelegate {
    // UI Components
    var statusItem: NSStatusItem?           # Menu bar icon
    var menu: NSMenu?                       # Dropdown menu
    var statusMenuItem: NSMenuItem?         # Dynamic status item
    
    // State Management
    var hasUpdates = false                  # Current update status
    var updateTimer: Timer?                 # Background check timer
}
```

### Configuration Constants

```swift
private struct AppConstants {
    static let updateInterval: TimeInterval = 4 * 60 * 60  # 4 hours
    static let sparkdockExecutablePath = "/opt/sparkdock/bin/sparkdock.macos"
    static let logoResourceName = "sparkfabrik-logo"
    static let iconSize = NSSize(width: 18, height: 18)
}
```

## Core Methods

### Application Lifecycle

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenuBar()      # Create status item and menu
    setupUpdateTimer()  # Start 4-hour check cycle
    checkForUpdates()   # Immediate initial check
}

func applicationWillTerminate(_ notification: Notification) {
    updateTimer?.invalidate()  # Clean up timer
}
```

### Menu Bar Setup

```swift
private func setupMenuBar() {
    # Create status item with variable length
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    # Configure button appearance
    button.image = loadIcon(hasUpdates: false)
    button.imagePosition = .imageOnly
    button.toolTip = "Sparkdock - Up to date"
    
    # Attach menu and update login item status
    setupMenu()
    statusItem.menu = menu
    updateLoginItemStatus()
}
```

### Menu Structure Implementation

```swift
private func setupMenu() {
    menu = NSMenu()
    
    # Title (non-clickable)
    let titleItem = NSMenuItem(title: "Sparkdock", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    
    # Status (clickable to trigger check)
    statusMenuItem = NSMenuItem(title: "Checking...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
    statusMenuItem?.target = self
    
    # Update Now (conditionally visible)
    let updateItem = NSMenuItem(title: "Update Now", action: #selector(updateNow), keyEquivalent: "")
    updateItem.target = self
    updateItem.tag = 1  # For programmatic access
    
    # Additional menu items...
}
```

## Update Detection System

### Background Check Implementation

```swift
private func checkForUpdates() {
    DispatchQueue.global(qos: .background).async { [weak self] in
        let hasUpdates = self?.runSparkdockCheck() ?? false
        
        DispatchQueue.main.async {
            self?.updateUI(hasUpdates: hasUpdates)
        }
    }
}
```

### Sparkdock CLI Integration

```swift
private func runSparkdockCheck() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: AppConstants.sparkdockExecutablePath)
    process.arguments = ["check-updates"]
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0  # 0 = updates available
    } catch {
        return false  # Assume no updates on error
    }
}
```

### UI State Management

```swift
private func updateUI(hasUpdates: Bool) {
    self.hasUpdates = hasUpdates
    
    # Update menu bar icon
    statusItem?.button?.image = loadIcon(hasUpdates: hasUpdates)
    statusItem?.button?.toolTip = hasUpdates ? 
        "Sparkdock - Updates available" : 
        "Sparkdock - Up to date"
    
    # Update status message  
    statusMenuItem?.title = hasUpdates ? 
        "🔄 Updates Available" : 
        "✅ Sparkdock is up to date"
    
    # Show/hide Update Now button
    if let menu = menu,
       let updateItem = menu.items.first(where: { $0.tag == 1 }) {
        if hasUpdates {
            updateItem.title = "Update Now"
            updateItem.isEnabled = true
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true  # Hide when no updates
        }
    }
}
```

## Icon Management System

### Modern Icon Drawing

```swift
private func loadIcon(hasUpdates: Bool) -> NSImage? {
    # Try to load custom logo with fallback
    let logo = loadCustomLogo() ?? createDefaultIcon()
    
    # Create icon with modern drawing API
    let icon = NSImage(size: AppConstants.iconSize, flipped: false) { rect in
        logo.draw(in: rect)
        
        if hasUpdates {
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)  # Orange tint overlay
        }
        
        return true
    }
    
    icon.isTemplate = !hasUpdates  # Template when no updates
    return icon
}
```

### Fallback Icon Creation

```swift
private func createDefaultIcon() -> NSImage {
    # Modern macOS: Use system symbol
    if #available(macOS 11.0, *) {
        if let systemImage = NSImage(systemSymbolName: "gearshape.fill", 
                                   accessibilityDescription: "Sparkdock") {
            let config = NSImage.SymbolConfiguration(
                pointSize: AppConstants.iconSize.width, 
                weight: .medium
            )
            return systemImage.withSymbolConfiguration(config) ?? systemImage
        }
    }
    
    # Legacy fallback: Simple circle
    return NSImage(size: AppConstants.iconSize, flipped: false) { rect in
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        NSColor.controlAccentColor.setFill()
        path.fill()
        return true
    }
}
```

## System Integration

### Terminal Command Execution

```swift
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
        
        # Error handling could be added here if needed
    }
}
```

### Login Item Management

```swift
private func updateLoginItemStatus() {
    guard let loginMenuItem = menu?.items.first(where: { $0.tag == 2 }) else { return }
    
    if #available(macOS 13.0, *) {
        # Modern ServiceManagement approach
        let service = SMAppService.mainApp
        loginMenuItem.state = service.status == .enabled ? .on : .off
    } else {
        # Legacy LaunchAgent approach
        loginMenuItem.title = "Start at Login (via LaunchAgent)"
        loginMenuItem.isEnabled = false
    }
}
```

## Timer Management

### Background Update Scheduling

```swift
private func setupUpdateTimer() {
    updateTimer = Timer.scheduledTimer(
        withTimeInterval: AppConstants.updateInterval,
        repeats: true
    ) { [weak self] _ in
        self?.checkForUpdates()  # Automatic background checks
    }
}
```

## Build System

### Swift Package Configuration

```swift
// Package.swift
let package = Package(
    name: "SparkdockManager",
    platforms: [.macOS(.v14)],  # Minimum macOS 14 (Sonoma)
    products: [
        .executable(name: "sparkdock-manager", targets: ["SparkdockMenubar"])
    ],
    targets: [
        .executableTarget(
            name: "SparkdockMenubar",
            resources: [.process("Resources")]  # Include logo resources
        ),
        .testTarget(
            name: "SparkdockMenubarTests", 
            dependencies: ["SparkdockMenubar"]
        )
    ]
)
```

### Makefile Automation

```makefile
build:
    swift build -c release

install: build
    sudo cp .build/release/sparkdock-manager /usr/local/bin/
    sudo chmod 755 /usr/local/bin/sparkdock-manager
    cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist

test: build
    swift test
    @if test -x .build/release/sparkdock-manager; then \
        echo "✅ Executable created and is executable"; \
    else \
        echo "❌ Executable not found"; exit 1; \
    fi
```

## LaunchAgent Configuration

```xml
<!-- com.sparkfabrik.sparkdock.menubar.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.sparkfabrik.sparkdock.menubar</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/sparkdock-manager</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <false/>
    
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

## Error Handling Patterns

### Graceful Degradation

```swift
# Logo loading with fallbacks
let logo = primarySource() ?? secondarySource() ?? defaultFallback()

# Command execution with error tolerance
do {
    try riskyOperation()
} catch {
    # Log error but continue operation
    return sensibleDefault()
}

# UI updates with nil checking
statusItem?.button?.image = loadIcon(hasUpdates: state)
```

### Resource Management

```swift
# Timer cleanup
func applicationWillTerminate(_ notification: Notification) {
    updateTimer?.invalidate()
    updateTimer = nil
}

# Weak self references in closures
Timer.scheduledTimer(...) { [weak self] _ in
    self?.performAction()  # Prevents retain cycles
}
```

## Testing Infrastructure

### Unit Test Structure

```swift
final class SparkdockMenubarTests: XCTestCase {
    func testPackageStructure() {
        # Verify basic package integrity
    }
    
    func testResourcesExist() {
        # Verify logo and other resources are bundled correctly
    }
    
    func testSparkdockPath() {
        # Verify executable path construction
    }
    
    func testExecutableName() {
        # Verify correct binary naming
    }
}
```

## Performance Characteristics

### Memory Usage

- **Baseline**: ~5-10MB resident memory
- **During checks**: Temporary increase for Process execution
- **Icon caching**: Minimal impact, icons cached after first load

### CPU Usage

- **Idle**: Nearly zero CPU usage
- **Update checks**: Brief spike every 4 hours
- **UI updates**: Minimal main thread usage

### Network Usage

- **Direct**: None (app doesn't make network calls)
- **Indirect**: Git operations via Sparkdock CLI

This technical specification provides the detailed implementation context needed for AI agents to effectively work with and modify the Sparkdock Manager codebase.