# Sparkdock Manager

A simple macOS menu bar application that provides visual indicators for Sparkdock updates and quick access to common tasks.

## Features

- **Visual Status**: Menu bar icon shows update status
  - ⚙️ (Gray gear) - System up to date  
  - 🔄 (Orange refresh) - Updates available
- **Menu Actions**:
  - Check for Updates (manual check)
  - Update Now (runs `sparkdock` in Terminal)
  - Configurable menu items from JSON (Tools, Company links)
  - URL links open as Chrome web apps (using `--app` flag)
  - Start at Login (enable/disable auto-start)
  - Quit
- **Smart Updates**: Event-driven checking (system wake + network changes)
- **CLI Support**: Status checking with `sparkdock-manager --status`
- **Lightweight**: Pure Swift, minimal dependencies

## Building

```bash
cd src/menubar-app
swift build -c release
```

## Installation

The app is automatically built and installed during Sparkdock provisioning via Ansible with verification checks.

## Manual Installation

```bash
# Build the app
swift build -c release

# Copy to system location
sudo cp .build/release/sparkdock-manager /usr/local/bin/

# Create launch agent (auto-start at login)
cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
launchctl enable gui/$(id -u)/com.sparkfabrik.sparkdock.menubar
launchctl kickstart gui/$(id -u)/com.sparkfabrik.sparkdock.menubar
```

## Adding Custom Logo

To use your SparkFabrik logo:

1. Add your logo file as `sparkfabrik-logo.png` to `Sources/SparkdockManager/Resources/`
2. Rebuild the app: `swift build`

The app will automatically use your custom logo, falling back to a system gear icon if not found.

## Web App Integration

URL menu items (configured in `menu.json`) are opened as Chrome web apps using the `--app` flag. This provides a standalone window experience without browser UI elements.

- URLs are launched via Google Chrome (pre-installed by Sparkdock)
- Falls back to the default browser if Chrome is unavailable
- No additional configuration required

Example from `menu.json`:
```json
{
  "title": "Company Playbook",
  "type": "url",
  "url": "https://playbook.sparkfabrik.com/"
}
```


## CLI Usage

```bash
# Check app status
sparkdock-manager --status

# Show help
sparkdock-manager --help
```

## Requirements

- macOS 14.0+ (Sonoma)
- Sparkdock installed at `/opt/sparkdock`