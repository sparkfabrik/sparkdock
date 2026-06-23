#!/usr/bin/env bash
set -euo pipefail

# Install or update OpenSpec skills and prompt commands in the home directory
# for Claude Code (and any other already-configured tools).
#
# OpenSpec installs skills to ~/.claude/skills/openspec-* and prompt commands to
# ~/.claude/commands/opsx/* relative to a project root. Using ${HOME} as the
# root makes them global for the user. The home project lives at ~/openspec.
#
# Usage: install-global-skills.sh [tools]
#   tools  — comma-separated tool list for first-time init (default: claude)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../libs/libshell.sh"

tools="${1:-claude}"

if ! command -v openspec >/dev/null 2>&1; then
    log_error "openspec CLI not found. Install it first (brew install openspec)."
    exit 1
fi

# Already initialized: refresh skills + commands for every configured tool.
if [[ -d "${HOME}/openspec" ]]; then
    log_info "Updating global OpenSpec skills and prompts under ${HOME} (all configured tools)"
    openspec update "${HOME}" --force
    log_success "Global OpenSpec skills and prompts updated"
    exit 0
fi

# First run: scaffold the home project and install the requested tools.
log_info "Initializing global OpenSpec project at ${HOME}/openspec (tools: ${tools})"
openspec init "${HOME}" --tools "${tools}" --force
log_success "Global OpenSpec skills and prompts installed for: ${tools}"
