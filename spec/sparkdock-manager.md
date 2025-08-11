# Sparkdock Manager - Technical Specification

A macOS menu bar app that monitors Sparkdock updates and provides quick access to development tools.

## Overview

Sparkdock Manager is a native macOS menu bar application built with Swift that provides visual indicators for Sparkdock system updates and quick access to common development tasks. It follows macOS design patterns and integrates seamlessly with the system's menu bar interface.

## Architecture

### Component Hierarchy
- NSApplication → SparkdockMenubarApp (NSApplicationDelegate)
  - NSStatusItem (menu bar presence)
  - NSMenu (dropdown interface)
  - Timer (update scheduler)
  - Process (external command execution)

### Design Patterns
- **Delegate Pattern**: NSApplicationDelegate for lifecycle management
- **Target-Action**: Menu item event handling
- **Observation**: Timer-based polling (no KVO/Combine)
- **Caching**: Icon state caching for performance

### State Management
- Single source of truth: `hasUpdates` boolean property
- UI updates synchronized through MainActor
- No persistent state between launches
- Menu configuration loaded from bundled JSON resources

## Key Files and Structure

**Core Implementation:**
- `Sources/SparkdockManager/main.swift` - Complete application implementation (~400 lines)
- `Sources/SparkdockManager/Resources/menu.json` - Menu structure configuration
- `Sources/SparkdockManager/Resources/sparkfabrik-logo.png` - Custom logo asset
- `com.sparkfabrik.sparkdock.menubar.plist` - LaunchAgent configuration

**Configuration Models:**
```swift
// JSON-based menu configuration with Codable
struct MenuConfig { let version: String; let menu: MenuStructure }
struct MenuSection { let name: String; let items: [MenuItem] }
struct MenuItem { let title: String; let type: MenuItemType; let command/url: String? }
```

## Data Flow

### Update Check Sequence
1. Timer fires every 4 hours → `checkForUpdates()`
2. Background Task spawned with `.background` priority
3. Process executes `/opt/sparkdock/bin/sparkdock.macos check-updates` with 30s timeout
4. Exit code interpreted (0 = updates available, non-zero = no updates)
5. MainActor synchronizes UI component updates

### Menu Interaction Flow
1. User clicks menu item → Target-action invokes handler
2. Dynamic items route through `handleDynamicMenuItem(_:)`
3. Commands executed via AppleScript in Terminal.app
4. URLs opened in default browser via NSWorkspace

## Update Detection

The app executes `/opt/sparkdock/bin/sparkdock.macos check-updates` to detect available updates:
- **Exit code 0**: Updates available (shows orange tinted icon)
- **Non-zero exit**: No updates (shows template gray icon)  
- **Timeout/Error**: Assumes no updates, logs error

**Timeout Protection:**
```swift
// Uses DispatchSemaphore for 30-second timeout
let semaphore = DispatchSemaphore(value: 0)
process.terminationHandler = { proc in
    terminationStatus = proc.terminationStatus
    semaphore.signal()
}
```

## Menu Structure

**Static Items:**
- Title: "Sparkdock Manager" (disabled, visual header)
- Status indicator: Shows "⏳ Checking...", "🔄 Updates Available", or "✅ Up to date"
- Update Now button: Hidden when no updates available
- Login item toggle: Uses modern SMAppService framework

**Dynamic Items:**
Loaded from `menu.json` with configurable sections. Each item supports:
- `"type": "command"` - Executes terminal command via AppleScript
- `"type": "url"` - Opens URL in default browser

**Example menu.json structure:**
```json
{
  "version": "1.0",
  "menu": {
    "sections": [
      {
        "name": "Tools",
        "items": [{"title": "Open sjust", "type": "command", "command": "sjust"}]
      }
    ]
  }
}
```

## Technical Details

**Requirements:** macOS 14.0+ (Sonoma)

**Dependencies:**
- **System Frameworks**: Cocoa, ServiceManagement, os.log
- **External Dependencies**: None (pure Swift, no SPM dependencies)
- **Resource Dependencies**: Optional logo PNG, required menu.json

**Bundle and Resource Management:**
```swift
// SPM resource loading with fallback pattern
Bundle.module.path(forResource: name, ofType: "png") ?? 
Bundle.main.path(forResource: name, ofType: "png")
```

**Icon Management:**
- Custom logo from `sparkfabrik-logo.png` resource (18x18 recommended)
- Fallback to SF Symbols `gearshape.fill` with configuration
- Orange tint overlay for update state using `NSColor.systemOrange`
- Caching with `cachedNormalIcon`, `cachedUpdateIcon`, `cachedLogoImage` properties
- Template mode for normal state, colored for updates

**Process Execution:**
- DispatchSemaphore for timeout handling (30 seconds)
- AppleScript integration via `/usr/bin/osascript` for Terminal commands
- Background Task execution with MainActor UI updates
- Process termination on timeout with proper cleanup

## Swift/macOS Patterns

### Swift Patterns Used
- **Task Concurrency**: Background priority tasks for update checks
- **MainActor**: UI updates from background contexts
- **Property Observers**: Not used, state changes handled manually
- **Guard Statements**: Early returns for validation
- **Weak References**: Timer callbacks to prevent retain cycles

### macOS Integration Patterns
- **Accessory App Policy**: `NSApp.setActivationPolicy(.accessory)` - no dock icon
- **Menu Bar Lifecycle**: NSStatusItem with variable length
- **Modern Login Items**: SMAppService.mainApp for Sonoma+
- **AppleScript Execution**: Escaped command strings via osascript
- **Bundle Resource Processing**: SPM `.process("Resources")` directive

## Error Handling Strategy

**By Component:**
- **Resource Loading**: Graceful fallback to SF Symbols if logo missing
- **Process Execution**: Timeout protection with user alert notifications
- **Menu Configuration**: Continues with minimal menu if JSON invalid
- **Login Item Registration**: User alert on SMAppService failure

**User Notifications:**
```swift
// Structured error alerts with NSAlert
private func showErrorAlert(_ title: String, _ message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
}
```

## Installation and Deployment

**Local Development:**
- Binary installed to `/usr/local/bin/sparkdock-manager`
- LaunchAgent configuration for auto-startup
- Ansible integration with `menubar` tag

**CI/CD Considerations:**
- LaunchAgent installation skipped in CI environments
- Condition: `when: not (ansible_env.CI is defined or ansible_env.GITHUB_ACTIONS is defined)`
- Binary installation continues for testing purposes

## Performance Characteristics

- **Memory Usage**: ~10-15MB baseline, cached icons minimal overhead
- **CPU Usage**: Negligible except during 30-second update checks
- **Update Frequency**: 4-hour intervals with 60-second timer tolerance
- **Process Timeout**: Maximum 30 seconds per update check

## Debugging and Logging

**Structured Logging:**
```swift
// os.log with subsystem and category
private static let logger = Logger(
    subsystem: "com.sparkfabrik.sparkdock.manager", 
    category: "MenuBar"
)
```

**View logs with:**
```bash
# Console.app or command line
log stream --predicate 'subsystem == "com.sparkfabrik.sparkdock.manager"'
```

**Common Issues:**
- Menu not appearing: Check `NSApp.setActivationPolicy(.accessory)`
- Updates not detected: Verify `/opt/sparkdock/bin/sparkdock.macos` exists
- Commands not working: Check AppleScript Terminal integration
- Login item fails: Requires user approval in System Settings > Login Items

## Build & Development

```bash
# Development commands
swift build -c release      # Build release binary
make install                 # Install with LaunchAgent (local only)
make build                  # Build only
make test                   # Run unit tests
swift test                  # Alternative test command
```

**Code Style:**
- MARK comments for section organization
- Private methods with descriptive verb prefixes (setup/load/update)
- Constants grouped in `AppConstants` struct
- Fileprivate visibility for JSON model classes
- Guard early returns for validation

## Testing Strategy

**Current Tests:**
- Package structure validation
- Resource existence checks  
- Path construction verification
- Command escaping validation
- Menu item tag uniqueness

**Testing Limitations:**
- Cannot test actual menu display (requires UI automation)
- Process execution requires mocking or integration tests
- Login item registration needs user interaction

## API Reference

### SparkdockMenubarApp Core Methods

**Lifecycle Management:**
- `applicationDidFinishLaunching(_:)` - Setup menu bar, load config, start timer
- `applicationWillTerminate(_:)` - Cleanup timer, clear image cache

**Update Management:**
- `checkForUpdates()` - Async update check with background Task
- `runSparkdockCheck() -> Bool` - Synchronous process execution with timeout
- `updateUI(hasUpdates: Bool)` - MainActor UI state synchronization

**Menu Event Handlers:**
- `handleDynamicMenuItem(_:)` - Routes dynamic menu items to command/URL handlers
- `toggleLoginItem()` - Modern SMAppService login item registration
- `updateNow()` - Triggers sparkdock update command
- `executeTerminalCommand(_:)` - AppleScript-based Terminal command execution

**Utility Methods:**
- `loadIcon(hasUpdates: Bool) -> NSImage?` - Cached icon generation with state
- `showErrorAlert(_: String, _: String)` - User error presentation
- `loadMenuConfiguration()` - JSON configuration parsing with fallback

This specification provides comprehensive context for LLMs working on Swift macOS development tasks, covering architecture decisions, implementation patterns, and operational considerations.