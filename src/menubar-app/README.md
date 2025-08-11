# Sparkdock Manager

A simple macOS menu bar application that provides visual indicators for Sparkdock updates and quick access to common tasks.

## Features

- **Visual Status**: Menu bar icon shows update status
  - ⚙️ (Gray gear) - System up to date  
  - 🔄 (Orange refresh) - Updates available
- **Menu Actions**:
  - Check for Updates (manual check)
  - Update Now (runs `sparkdock` in Terminal)
  - Open sjust (launches `sjust` in Terminal)
  - Quit
- **Background Checking**: Automatically checks for updates every 4 hours
- **Lightweight**: Pure Swift, minimal dependencies

## Building

```bash
cd src/menubar-app
swift build -c release
```

## Installation

The app is automatically built and installed during Sparkdock provisioning via Ansible.

## Manual Installation

```bash
# Build the app
swift build -c release

# Copy to system location
sudo cp .build/release/sparkdock-manager /usr/local/bin/

# Create launch agent (auto-start at login)
cp com.sparkfabrik.sparkdock.menubar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
```

## Adding Custom Logo

To use your SparkFabrik logo:

1. Add your logo file as `sparkfabrik-logo.png` to `Sources/SparkdockMenubar/Resources/`
2. Rebuild the app: `swift build`

The app will automatically use your custom logo, falling back to a generated flame icon if not found.

## Requirements

- macOS 14.0+ (Sonoma)
- Sparkdock installed at `/opt/sparkdock`