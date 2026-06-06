# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/08-claude-usage.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_usage_sh := clean(source_directory() / "../../..") / "sjust/scripts/claude-usage.sh"

# Install or upgrade claude-usage (https://github.com/sparkfabrik/claude-usage).
# Cross-platform: the upstream installer auto-detects macOS/Linux, CPU arch, and
# desktop environment (GNOME extension, KDE plasmoid, Waybar module, or macOS tray).
# Prefers the release-published install.sh asset and verifies it against the release
# checksums.txt when available, falling back to the raw script for older releases.
# Pass a version tag to pin the install: sjust claude-usage-install v0.6.0
[group('claude')]
claude-usage-install version="":
    @bash "{{_claude_usage_sh}}" install "{{version}}"

# Uninstall claude-usage.
[group('claude')]
claude-usage-uninstall:
    @bash "{{_claude_usage_sh}}" uninstall
