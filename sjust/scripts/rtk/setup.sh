#!/usr/bin/env bash
set -euo pipefail

# Setup RTK (Rust Token Killer) for GitHub Copilot and OpenCode.
# Handles the temp-dir workaround for Copilot (upstream bug rtk-ai/rtk#1512)
# and direct init for OpenCode.
#
# Usage: setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../libs/libshell.sh"

# --- Helpers ---

# Inject content between markers into a file, replacing any existing block.
# Creates the file if it doesn't exist.
# Usage: inject_with_markers <file> <content>
inject_with_markers() {
    local file="$1"
    local content="$2"
    local marker_begin="<!-- BEGIN RTK MANAGED BLOCK -->"
    local marker_end="<!-- END RTK MANAGED BLOCK -->"

    # Create file if it doesn't exist
    if [[ ! -f "$file" ]]; then
        mkdir -p "$(dirname "$file")"
        touch "$file"
    fi

    # Remove existing block if present
    if grep -q "$marker_begin" "$file" 2>/dev/null; then
        sed -i '' "/$marker_begin/,/$marker_end/d" "$file"
    fi

    # Append new block
    printf '\n%s\n%s\n%s\n' "$marker_begin" "$content" "$marker_end" >> "$file"
}

# --- GitHub Copilot ---

setup_copilot() {
    log_info "Setting up RTK for GitHub Copilot..."

    # Run rtk init in a temp directory to avoid overwriting user files
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && rtk init --copilot --auto-patch > /dev/null 2>&1)

    local instructions_src="${tmpdir}/.github/copilot-instructions.md"

    if [[ ! -f "$instructions_src" ]]; then
        log_error "RTK did not generate instructions in temp directory"
        rm -rf "$tmpdir"
        return 1
    fi

    local instructions_content
    instructions_content=$(cat "$instructions_src")

    # Append safety clause to prevent rtk from bypassing destructive command checks
    local safety_clause="

Only use the rtk prefix for read-only and build/test/lint commands. Any command that modifies, creates, or deletes files or remote state must run WITHOUT the rtk prefix to preserve safety checks. Examples of commands that must NOT be prefixed: rm, mv, cp, chmod, chown, git push, git commit, git reset, kubectl delete, docker rm. When in doubt, do not use the rtk prefix."
    instructions_content="${instructions_content}${safety_clause}"

    # VS Code Copilot Chat — writes to ~/.github/
    local vscode_instructions_dest="${HOME}/.github/copilot-instructions.md"
    mkdir -p "$(dirname "$vscode_instructions_dest")"
    inject_with_markers "$vscode_instructions_dest" "$instructions_content"

    # Copilot CLI — writes to ~/.copilot/
    local cli_instructions_dest="${HOME}/.copilot/copilot-instructions.md"
    mkdir -p "$(dirname "$cli_instructions_dest")"
    inject_with_markers "$cli_instructions_dest" "$instructions_content"

    # Cleanup
    rm -rf "$tmpdir"

    log_success "RTK configured for GitHub Copilot (VS Code + CLI)"
}

# --- OpenCode ---

setup_opencode() {
    log_info "Setting up RTK for OpenCode..."
    rtk init -g --opencode --auto-patch > /dev/null 2>&1
    log_success "RTK configured for OpenCode"
}

# --- Main ---

if ! command -v rtk &> /dev/null; then
    log_error "rtk is not installed. Run 'brew install rtk' first."
    exit 1
fi

setup_copilot
setup_opencode

log_success "RTK setup complete. Restart your AI coding tools to activate."
