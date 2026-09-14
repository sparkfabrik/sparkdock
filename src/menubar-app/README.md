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
  - Login Items settings (manage macOS background-item approval)
  - Quit
- **Smart Updates**: Event-driven checking (system wake + network changes)
- **CLI Support**: Status checking with `sparkdock-manager --status`
- **Lightweight**: Pure Swift, minimal dependencies

## Building

```bash
cd src/menubar-app
make build
```

## Installation

The app is automatically built and installed during Sparkdock provisioning via Ansible with verification checks.

## Manual Installation

```bash
make install
```

This uses the Ansible `menubar` tasks to install `~/Applications/Sparkdock Manager.app` and its user LaunchAgent without sudo. `/opt/homebrew/bin/sparkdock-manager` is a symlink to the bundle executable. `make uninstall` removes the agent, bundle, and symlink.

The LaunchAgent starts `Contents/MacOS/sparkdock-manager` directly. The app opens Login Items settings for background-item approval; it does not separately register `SMAppService.mainApp`.

## Adding Custom Logo

To use your SparkFabrik logo:

1. Add your logo file as `sparkfabrik-logo.png` to `Sources/SparkdockManager/Resources/`
2. Rebuild the bundle: `make build`

`make build` assembles `.build/Sparkdock Manager.app`, copies both resources into `Contents/Resources`, and ad-hoc signs the complete bundle. `Bundle.main` is the primary resource source; the CLI symlink is resolved to its enclosing app before resource lookup. Embedded bytes remain only for raw SwiftPM test/development executables; an application bundle with missing or invalid resources fails `--status`.

The bundle identifier is `com.sparkfabrik.sparkdock.menubar`. The numeric version is `0.0.<git revision count>`, with the full Git revision in `SparkdockRevision`. Builds from exported trees supply `BUNDLE_VERSION` and `BUNDLE_REVISION`. `BUNDLE_IDENTIFIER` can isolate a development bundle; rebuilding re-signs it. Ad-hoc signing is for local use and does not bypass Gatekeeper or endpoint-security policy.

`NSRunningApplication` checks the bundle identifier, excluding the current PID. Copies with the same identifier conflict regardless of path; use a distinct identifier for an independent test app. Old bare executables without a bundle identifier cannot be discovered by this lookup and are stopped during installation through the legacy executable path.

Run `make test` for unit tests and a relocated-bundle smoke test, including the CLI symlink and missing/corrupt resource failures. Install and LaunchAgent behavior must be tested in a disposable macOS environment.

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

- macOS 15.0+ (Sequoia)
- Sparkdock installed at `/opt/sparkdock`
