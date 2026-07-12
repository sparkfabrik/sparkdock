#!/usr/bin/env bash
set -euo pipefail

# Install or update OpenSpec skills and prompt commands in the home directory
# for the requested AI coding tools.
#
# OpenSpec installs skills to ~/.claude/skills/openspec-* and prompt commands to
# ~/.claude/commands/opsx/* relative to a project root. Using ${HOME} as the
# root makes them global for the user. The home project lives at ~/openspec.
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

# Ensure the requested tools are configured. Re-running init is additive and
# idempotent: it preserves openspec/changes, config.yaml edits, and any tools
# configured previously (a narrower list never removes tools).
log_info "Configuring global OpenSpec skills under ${HOME} (tools: ${tools})"
openspec init "${HOME}" --tools "${tools}" --force

# Refresh instruction files for every configured tool.
openspec update "${HOME}" --force
log_success "Global OpenSpec skills and prompts installed for: ${tools}"
