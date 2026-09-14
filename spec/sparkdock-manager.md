# Sparkdock Manager - Technical Specification

A macOS menu bar app that monitors Sparkdock updates and provides quick access to development tools.

## Overview

Sparkdock Manager is a native macOS menu bar application built with Swift that provides visual indicators for Sparkdock system updates and quick access to common development tasks. It follows macOS design patterns and integrates seamlessly with the system's menu bar interface.

## Architecture

### Component Hierarchy

- NSApplication → SparkdockMenubarApp (NSApplicationDelegate)
  - NSStatusItem (menu bar presence)
  - NSMenu (dropdown interface)
  - Network.NWPathMonitor (network connectivity monitoring)
  - NSWorkspace.didWakeNotification (system wake monitoring)
  - Process (external command execution with async timeout)

### Design Patterns

- **Delegate Pattern**: NSApplicationDelegate for lifecycle management
- **Target-Action**: Menu item event handling
- **Observer Pattern**: System event notifications for efficient monitoring
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
- `com.sparkfabrik.sparkdock.menubar.plist` - Ansible LaunchAgent template for the installed bundle
- `bundle.sh` - Bundle assembly and ad-hoc signing
- `test-bundle.sh` - Relocation, CLI symlink, and resource-failure smoke tests
- `AppBundle.swift`, `AppResources.swift`, `AppInstance.swift` - Bundle resolution, resource loading, and instance identity

**Configuration Models:**

```swift
// JSON-based menu configuration with Codable
struct MenuConfig { let version: String; let menu: MenuStructure }
struct MenuSection { let name: String; let items: [MenuItem] }
struct MenuItem { let title: String; let type: MenuItemType; let command/url: String? }
```

## Data Flow

### Update Check Sequence

1. System event triggers (wake from sleep or network connectivity) → `checkForUpdates()`
2. Background Task spawned with `.background` priority
3. Async process executes `/opt/sparkdock/bin/sparkdock.macos check-updates` with structured concurrency timeout
4. Exit code interpreted (0 = updates available, non-zero = no updates)
5. MainActor synchronizes UI component updates

### Menu Interaction Flow

1. User clicks menu item → Target-action invokes handler
2. Dynamic items route through `handleDynamicMenuItem(_:)`
3. Command items: Executed via AppleScript in Terminal.app
4. URL items: Launched as Chrome web apps via direct binary execution (`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --app=<URL>`), fallback to default browser if Chrome unavailable

## Update Detection

The app executes `/opt/sparkdock/bin/sparkdock.macos check-updates` to detect available updates:

- **Exit code 0**: Updates available (shows orange tinted icon)
- **Non-zero exit**: No updates (shows template gray icon)
- **Timeout/Error**: Assumes no updates, logs error

**Modern Async Timeout Protection:**

```swift
// Uses structured concurrency with withTaskCancellationHandler
let finished = await withTaskCancellationHandler(
    operation: {
        try await withTimeout(seconds: 30) {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { proc in
                    continuation.resume(returning: proc.terminationStatus)
                }
            }
        }
    },
    onCancel: { process.terminate() }
)
```

## Menu Structure

**Static Items:**

- Title: "Sparkdock Manager" (disabled, visual header)
- Status indicator: Shows "⏳ Checking...", "🔄 Updates Available", or "✅ Up to date"
- Update Now button: Hidden when no updates available
- Login Items settings: Opens System Settings Login Items without an on/off checkmark; it no longer toggles `SMAppService.mainApp`, because the LaunchAgent owns launch at login

**Dynamic Items:**
Loaded from `menu.json` with configurable sections. Each item supports:

- `"type": "command"` - Executes terminal command via AppleScript
- `"type": "url"` - Opens URL as Chrome web app (standalone window without browser UI)

**Chrome Web App Integration:**
URL menu items launch as standalone Chrome windows using the `--app` flag, providing a cleaner, app-like experience:

- URLs open in dedicated Chrome windows without browser chrome (no tabs, address bar, or bookmarks)
- Fallback to default browser if Chrome unavailable
- Command: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --app=<URL>`
- Implementation: `openUrlAsChromeWebApp()` function in main.swift

**Example menu.json structure:**

```json
{
  "version": "1.0",
  "menu": {
    "sections": [
      {
        "name": "Tools",
        "items": [
          { "title": "Open sjust", "type": "command", "command": "sjust" }
        ]
      },
      {
        "name": "Company",
        "items": [
          {
            "title": "Company Playbook",
            "type": "url",
            "url": "https://playbook.sparkfabrik.com/"
          }
        ]
      }
    ]
  }
}
```

## Technical Details

**Requirements:** macOS 15.0+ (Sequoia)

**Dependencies:**

- **System Frameworks**: Cocoa, ServiceManagement, os.log, Network
- **External Dependencies**: None (pure Swift, no SPM dependencies)
- **Resource Dependencies**: Both logo PNG and menu.json must decode for `--status` to succeed

**Bundle and Resource Management:**

The signed application bundle contains `Contents/MacOS/sparkdock-manager`, `Contents/Info.plist`, and both files under `Contents/Resources`. `AppResources` uses `Bundle.main` for application bundles and fails on missing files. `AppBundle` resolves the CLI symlink to its enclosing application, because `Bundle.main` otherwise identifies the symlink directory. `.embedInCode` remains a fallback only for raw SwiftPM test/development executables. `--status` reports the resource container, identifier, and other matching instances, and exits non-zero if either resource fails validation.

`bundle.sh`, called by `make build`, assembles the bundle after SwiftPM compilation and signs it with the ad-hoc identity. `CFBundleIdentifier` is `com.sparkfabrik.sparkdock.menubar`; `CFBundleShortVersionString` and `CFBundleVersion` are `0.0.<git revision count>`, and `SparkdockRevision` records the full commit. Without Git metadata they fall back to `0.0.0` and `unknown`. Exported trees can supply `BUNDLE_VERSION` and `BUNDLE_REVISION`; development builds can override `BUNDLE_IDENTIFIER`.

Single-instance detection uses `NSRunningApplication.runningApplications(withBundleIdentifier:)` and excludes the current PID. It matches identity rather than installation path and is not an atomic lock. An old bare executable without a bundle identifier requires the separate legacy-process shutdown during migration.

**Icon Management:**

- Custom logo from `sparkfabrik-logo.png` resource (18x18 recommended)
- Fallback to SF Symbols `gearshape.fill` with configuration
- Orange tint overlay for update state using `NSColor.systemOrange`
- Caching with `cachedNormalIcon`, `cachedUpdateIcon`, `cachedLogoImage` properties
- Template mode for normal state, colored for updates

**Process Execution:**

- Modern async/await with structured concurrency timeout (30 seconds)
- withTaskCancellationHandler for automatic process cleanup on timeout
- AppleScript integration via `/usr/bin/osascript` for Terminal commands
- Background Task execution with MainActor UI updates
- Swift 6 compatible concurrency patterns

## Swift/macOS Patterns

### Swift Patterns Used

- **Structured Concurrency**: Background priority tasks with proper cancellation
- **withTaskCancellationHandler**: Automatic resource cleanup on task cancellation
- **withCheckedContinuation**: Bridging callback-based APIs to async/await
- **MainActor**: UI updates from background contexts
- **TaskGroup**: Timeout implementation using withThrowingTaskGroup
- **Guard Statements**: Early returns for validation
- **Weak References**: Event observer callbacks to prevent retain cycles

### macOS Integration Patterns

- **Accessory App Policy**: `NSApp.setActivationPolicy(.accessory)` - no dock icon
- **Menu Bar Lifecycle**: NSStatusItem with variable length
- **Login Items settings**: SMAppService opens system settings; the LaunchAgent owns startup
- **AppleScript Execution**: Escaped command strings via osascript
- **Bundle Resources**: Explicit resource copies, loaded through `Bundle.main`
- **Network Monitoring**: NWPathMonitor for battery-efficient connectivity detection
- **System Event Observation**: NSWorkspace notifications for wake detection

## Error Handling Strategy

**By Component:**

- **Resource Loading**: Graceful fallback to SF Symbols if logo missing
- **Process Execution**: Timeout protection with user alert notifications
- **Menu Configuration**: Continues with minimal menu if JSON invalid
- **Startup Verification**: LaunchAgent state checked after a settling delay

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

- Bundle installed to `~/Applications/Sparkdock Manager.app` (user-owned, no sudo), with `/opt/homebrew/bin/sparkdock-manager` as a CLI symlink
- LaunchAgent points directly to the installed bundle executable; no parallel SMAppService registration
- Ansible integration with `menubar` tag

**CI/CD Considerations:**

- LaunchAgent installation skipped in CI environments
- Condition: `when: not (ansible_env.CI is defined or ansible_env.GITHUB_ACTIONS is defined)`
- Bundle installation and CLI symlink continue for testing purposes
- The staged bundle is smoke-tested, installed processes are stopped, and the previous bundle is removed before copying; the installed signature and CLI are checked before starting the agent
- Atomic replacement, rollback, toolchain pinning, and conditional rebuilds remain separate work

## Performance Characteristics

- **Memory Usage**: ~10-15MB baseline, cached icons minimal overhead
- **CPU Usage**: Negligible except during 30-second update checks
- **Battery Efficiency**: Event-driven updates only (system wake + network changes)
- **Process Timeout**: Maximum 30 seconds per update check with automatic cleanup
- **Network Monitoring**: Lightweight NWPathMonitor with background queue processing

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
# Development commands (requires the compiler version in .swift-minimum-version)
cd src/menubar-app
make build                  # Build and sign the application bundle
make install                 # Install with LaunchAgent (local only)
make test                   # Unit tests and relocated-bundle smoke checks
swift test      # Unit tests only
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
- `runSparkdockCheck() async -> Bool` - Async process execution with structured concurrency timeout
- `updateUI(hasUpdates: Bool)` - MainActor UI state synchronization

**Menu Event Handlers:**

- `handleDynamicMenuItem(_:)` - Routes dynamic menu items to command/URL handlers
- `openUrlAsChromeWebApp(_:)` - Launches URLs as Chrome web apps with fallback
- `toggleLoginItem()` - Opens macOS Login Items settings
- `updateNow()` - Triggers sparkdock update command
- `executeTerminalCommand(_:)` - AppleScript-based Terminal command execution

**Utility Methods:**

- `loadIcon(hasUpdates: Bool) -> NSImage?` - Cached icon generation with state
- `showErrorAlert(_: String, _: String)` - User error presentation
- `loadMenuConfiguration()` - JSON configuration parsing with fallback

This specification provides comprehensive context for LLMs working on Swift macOS development tasks, covering architecture decisions, implementation patterns, and operational considerations.

## Bundle verification on a working Mac

On 2026-09-14, the bundle built with CLT Swift 6.3.3 on macOS 26.6.2 under `/tmp`. `codesign -dv` reported `com.sparkfabrik.sparkdock.menubar`, an ad-hoc signature, and two sealed resource files. Direct `--status` decoded two menu sections and the 11,918-byte PNG.

A temporary AppKit probe with the production bundle identifier was reported as one other instance by the copied app; changing the copy's identifier produced zero matches. The existing installed bare process had a nil bundle identifier, so neither identifier query found it. Its PID remained unchanged throughout the probes. Both direct and CLI-symlink smoke tests passed, and missing or corrupt resources returned exit 1 without using the embedded fallback. Identifier matching therefore works for app bundles, but does not replace the legacy-process migration step.

The CLT installation did not provide XCTest (`no such module 'XCTest'`). Full unit tests remain for Xcode CI. Service registration, installation into user Applications, CLI-link replacement, and LaunchAgent startup were not exercised on that working Mac; they require a disposable environment.
