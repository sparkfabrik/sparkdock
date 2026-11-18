#!/usr/bin/env bash
set -euo pipefail

# Install or update the OpenSpec skills globally for the requested AI coding
# tools.
#
# OpenSpec 2.1 and later install global skills themselves with
# `openspec init --scope global`, which must run inside a project folder: it
# refuses the home folder and scaffolds `openspec/` where it runs. A dedicated
# folder under the sparkdock data directory holds that scaffold, so the home
# folder stays clean and OpenSpec registers one stable project.
#
# Older releases have no global scope: they install relative to a project root,
# so ${HOME} is used as the root, with the home project in ~/openspec.
#
# Usage: install-global-skills.sh [tools]
#   tools  — comma-separated tool list (default: claude); OpenSpec identifiers,
#            e.g. claude, opencode, github-copilot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../libs/libshell.sh"

tools="${1:-claude}"

if ! command -v openspec >/dev/null 2>&1; then
    log_error "openspec CLI not found. Install it first (brew install openspec)."
    exit 1
fi

if openspec init --help 2>/dev/null | grep -q -- '--scope'; then
    global_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/sparkdock/openspec-global"
    mkdir -p "${global_dir}"
    log_info "Configuring global OpenSpec skills (tools: ${tools})"
    # Additive and idempotent: tools configured earlier are kept.
    (cd "${global_dir}" && openspec init --scope global --tools "${tools}" --force --no-animation </dev/null)
    # Refresh the skills for the workflow profile in the global config.
    (cd "${global_dir}" && openspec update --force </dev/null)
    log_success "Global OpenSpec skills installed for: ${tools}"
    exit 0
fi

# Ensure the requested tools are configured. Re-running init is additive and
# idempotent: it preserves openspec/changes, config.yaml edits, and any tools
# configured previously (a narrower list never removes tools).
log_info "Configuring global OpenSpec skills under ${HOME} (tools: ${tools})"
openspec init "${HOME}" --tools "${tools}" --force

# Refresh instruction files for every configured tool.
openspec update "${HOME}" --force
log_success "Global OpenSpec skills and prompts installed for: ${tools}"
