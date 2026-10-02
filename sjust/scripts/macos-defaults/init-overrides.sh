#!/usr/bin/env bash
set -euo pipefail
#
# Drop a commented overrides template at ~/.local/spark/macos-defaults/overrides.yml
# so the user can edit a real file with example shapes for the most common
# personal-preference toggles. Idempotent: refuses to clobber an existing file.
#
# Usage: init-overrides.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [[ -f "${MD_USER_OVERRIDES}" ]]; then
    log_info "Overrides file already exists at ${MD_USER_OVERRIDES} — leaving it alone."
    exit 0
fi

mkdir -p "$(dirname "${MD_USER_OVERRIDES}")"

cat > "${MD_USER_OVERRIDES}" <<'YML'
# Personal macOS-defaults overrides for sparkdock.
#
# Same shape as /opt/sparkdock/config/macos/defaults.yml. Top-level keys are
# merged into the curated set by name, so an override on
# "com.apple.dock.autohide" replaces only that one entry.
#
# Below are the most commonly customised settings, all commented out. Uncomment
# (and tweak) the ones you want, then run `sjust macos-defaults`.

# --- Dock --------------------------------------------------------------------

# "com.apple.dock.autohide":
#   domain: com.apple.dock
#   key: autohide
#   type: bool
#   value: true
#   description: Auto-hide dock
#   category: dock
#   requires: [Dock]

# "com.apple.dock.tilesize":
#   domain: com.apple.dock
#   key: tilesize
#   type: float
#   value: 48
#   description: Dock tile size (px)
#   category: dock
#   requires: [Dock]

# "com.apple.dock.show-recents":
#   domain: com.apple.dock
#   key: show-recents
#   type: bool
#   value: false
#   description: Hide recent applications in dock
#   category: dock
#   requires: [Dock]

# --- Finder ------------------------------------------------------------------

# "com.apple.finder.AppleShowAllFiles":
#   domain: com.apple.finder
#   key: AppleShowAllFiles
#   type: bool
#   value: true
#   description: Show hidden files
#   category: finder
#   requires: [Finder]

# "NSGlobalDomain.AppleShowAllExtensions":
#   domain: NSGlobalDomain
#   key: AppleShowAllExtensions
#   type: bool
#   value: true
#   description: Show all filename extensions
#   category: finder
#   requires: [Finder]

# "com.apple.finder.ShowPathbar":
#   domain: com.apple.finder
#   key: ShowPathbar
#   type: bool
#   value: true
#   description: Show path bar
#   category: finder
#   requires: [Finder]

# --- Keyboard ----------------------------------------------------------------

# "NSGlobalDomain.KeyRepeat":
#   domain: NSGlobalDomain
#   key: KeyRepeat
#   type: int
#   value: 1
#   description: Fastest key repeat rate
#   category: keyboard
#   requires: []

# "NSGlobalDomain.InitialKeyRepeat":
#   domain: NSGlobalDomain
#   key: InitialKeyRepeat
#   type: int
#   value: 10
#   description: Shortest practical initial key-repeat delay
#   category: keyboard
#   requires: []

# --- Accessibility -----------------------------------------------------------

# "com.apple.universalaccess.reduceMotion":
#   domain: com.apple.universalaccess
#   key: reduceMotion
#   type: int
#   value: 1
#   description: Reduce motion (animations)
#   category: accessibility
#   requires: []

# --- Add your own below ------------------------------------------------------
YML

log_success "Wrote overrides template at ${MD_USER_OVERRIDES}"
log_info "Edit it, then run: sjust macos-defaults dry-run"
