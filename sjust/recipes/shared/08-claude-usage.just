# vim: set ft=make :

# Base raw URL for the upstream claude-usage repo.
_claude_usage_repo_raw := "https://raw.githubusercontent.com/sparkfabrik/claude-usage"

# Install or upgrade claude-usage (https://github.com/sparkfabrik/claude-usage).
# Cross-platform: the upstream installer auto-detects macOS/Linux, CPU arch, and
# desktop environment (GNOME extension, KDE plasmoid, Waybar module, or macOS tray).
# Idempotent — re-running upgrades to the latest release.
# Pass a version tag to fully pin the install (installer script + binary are both
# fetched from that tag): sjust claude-usage-install v0.5.0
[group('claude')]
claude-usage-install $version="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required but was not found in PATH" >&2
        exit 1
    fi

    if [[ -z "${version}" ]]; then
        curl -fsSL "{{_claude_usage_repo_raw}}/main/install.sh" | bash
        exit 0
    fi

    # Normalize to the v-prefixed tag form used by upstream releases.
    [[ "${version}" == v* ]] || version="v${version}"
    if [[ ! "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid version: '${version}'. Expected a semver tag like v0.5.0" >&2
        exit 1
    fi

    # Fetch the installer from the tagged ref AND pin the binary, so the installer
    # logic and the installed release are both reproducible.
    curl -fsSL "{{_claude_usage_repo_raw}}/${version}/install.sh" | CLAUDE_USAGE_VERSION="${version}" bash

# Uninstall claude-usage.
[group('claude')]
claude-usage-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required but was not found in PATH" >&2
        exit 1
    fi

    curl -fsSL "{{_claude_usage_repo_raw}}/main/install.sh" | bash -s -- --uninstall
