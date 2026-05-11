#!/usr/bin/env bash
set -euo pipefail

# Initialize RTK hooks for the current project (Copilot).
# Creates .github/hooks/ and .github/copilot-instructions.md.
# Must be run from the root of a git repository.
#
# Note: Claude Code does not need per-project init — the global hook
# installed by setup.sh applies to all projects automatically.
#
# Usage: project-init.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../libs/libshell.sh"

if [[ ! -d .git ]]; then
    log_error "Not a git repository. Run this from a project root."
    exit 1
fi

if ! command -v rtk &> /dev/null; then
    log_error "rtk is not installed. Run 'brew install rtk' first."
    exit 1
fi

log_info "Installing RTK Copilot hooks for this project..."

rtk init --copilot --auto-patch > /dev/null 2>&1
log_success "Copilot: .github/hooks/ + .github/copilot-instructions.md"

log_info ""
log_info "Add .github/hooks/ to version control for team-wide RTK."
log_info "Note: Copilot hooks require Copilot CLI >= 1.0.24 for transparent rewrite."
