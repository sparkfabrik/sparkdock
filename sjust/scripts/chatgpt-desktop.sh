#!/usr/bin/env bash
# chatgpt-desktop — opt-in installation of the ChatGPT desktop app (the Codex
# desktop). macOS runs the sparkdock `chatgpt-desktop` Ansible tag, which
# installs the Homebrew `chatgpt` cask. Linux delegates to sf-toolbox, which
# owns the per-distribution paths. Invoked by
# sjust/recipes/shared/14-chatgpt-desktop.just.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# scripts live at <sparkdock_root>/sjust/scripts/
SPARKDOCK_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"

usage() {
    echo "Usage: chatgpt-desktop.sh install" >&2
    exit 2
}

install_macos() {
    cd "${SPARKDOCK_ROOT}"
    "${SPARKDOCK_ROOT}/bin/sparkdock.macos" ensure-python3
    # The chatgpt cask is a plain app bundle, so no sudo password is needed.
    ansible-playbook -i ansible/inventory.ini ansible/macos.yml \
        --tags chatgpt-desktop \
        -e sparkdock_chatgpt_desktop=true \
        -e ansible_become_pass=
}

install_linux() {
    if ! command -v sf-toolbox >/dev/null 2>&1; then
        echo "sf-toolbox is not installed; it owns the Linux desktop installation." >&2
        echo "Install it from https://github.com/sparkfabrik/archlinux-ansible-provisioner and rerun." >&2
        exit 127
    fi
    CHATGPT_DESKTOP=1 TAGS=chatgpt-desktop exec sf-toolbox
}

[[ $# -eq 1 && $1 == install ]] || usage

case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_linux ;;
    *)
        echo "Unsupported platform: $(uname -s)" >&2
        exit 1
        ;;
esac
