# vim: set ft=make :

# Install or upgrade claude-usage (https://github.com/sparkfabrik/claude-usage).
# Cross-platform: the upstream installer auto-detects macOS/Linux, CPU arch, and
# desktop environment (GNOME extension, KDE plasmoid, Waybar module, or macOS tray).
# Idempotent — re-running upgrades to the latest release.
# Pass a version tag to pin a release: sjust claude-usage-install v1.0.0
[group('claude')]
claude-usage-install $version="":
    #!/usr/bin/env bash
    set -euo pipefail

    install_url="https://raw.githubusercontent.com/sparkfabrik/claude-usage/main/install.sh"

    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required but was not found in PATH" >&2
        exit 1
    fi

    if [[ -n "${version}" ]]; then
        curl -fsSL "${install_url}" | CLAUDE_USAGE_VERSION="${version}" bash
    else
        curl -fsSL "${install_url}" | bash
    fi

# Uninstall claude-usage.
[group('claude')]
claude-usage-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required but was not found in PATH" >&2
        exit 1
    fi

    curl -fsSL "https://raw.githubusercontent.com/sparkfabrik/claude-usage/main/install.sh" | bash -s -- --uninstall
