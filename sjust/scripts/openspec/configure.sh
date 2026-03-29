#!/usr/bin/env bash
set -euo pipefail

# Configure OpenSpec with custom profile and all workflows.
# Usage: configure.sh [force]
#   force  — overwrite existing config without prompting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPARKDOCK_ROOT="${SCRIPT_DIR}/../../.."

source "${SCRIPT_DIR}/../../libs/libshell.sh"

force="${1:-}"

CONFIG_DIR="${HOME}/.config/openspec"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SOURCE_FILE="${SPARKDOCK_ROOT}/config/macos/openspec.json"

if [[ ! -f "${SOURCE_FILE}" ]]; then
    log_error "Source config not found at ${SOURCE_FILE}"
    exit 1
fi

if [[ -f "${CONFIG_FILE}" ]]; then
    if [[ "${force}" == "force" ]]; then
        log_info "Overwriting existing OpenSpec config (force mode)"
    else
        log_warn "OpenSpec config already exists at ${CONFIG_FILE}"
        read -p "Overwrite with Sparkdock defaults? (y/N): " -n 1 -r
        echo
        if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
            log_info "Keeping existing configuration."
            exit 0
        fi
    fi
fi

mkdir -p "${CONFIG_DIR}"
rm -f "${CONFIG_FILE}"
cp "${SOURCE_FILE}" "${CONFIG_FILE}"
chmod 644 "${CONFIG_FILE}"
log_success "OpenSpec configured with custom profile (all 11 workflows enabled)"
