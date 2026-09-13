#!/usr/bin/env bash
# homebrew-app — opt-in installation of the official Homebrew desktop app
# (BrewUI). Runs the sparkdock `homebrew-app` Ansible tag, which installs the
# Homebrew `homebrew-app` cask. macOS only, and macOS 26 (Tahoe) or later.
# Invoked by sjust/recipes/shared/15-homebrew-app.just.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# scripts live at <sparkdock_root>/sjust/scripts/
SPARKDOCK_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

usage() {
    echo "Usage: homebrew-app.sh install" >&2
    exit 2
}

install_macos() {
    local version major
    version="$(sw_vers -productVersion)"
    major="${version%%.*}"
    if [[ "${major}" -lt 26 ]]; then
        echo "The Homebrew desktop app (BrewUI) requires macOS 26 (Tahoe) or later (detected: ${version}). Skipping." >&2
        exit 0
    fi
    cd "${SPARKDOCK_ROOT}"
    "${SPARKDOCK_ROOT}/bin/sparkdock.macos" ensure-python3
    # The homebrew-app cask is a plain app bundle, so no sudo password is needed.
    ansible-playbook -i ansible/inventory.ini ansible/macos.yml \
        --tags homebrew-app \
        -e sparkdock_homebrew_app=true \
        -e ansible_become_pass=
}

[[ $# -eq 1 && $1 == install ]] || usage

case "$(uname -s)" in
    Darwin) install_macos ;;
    *)
        echo "The Homebrew desktop app (BrewUI) is macOS only; nothing to do on $(uname -s)." >&2
        exit 1
        ;;
esac
