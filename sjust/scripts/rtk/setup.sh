#!/usr/bin/env bash
set -euo pipefail

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, instructions, and generates config.toml with exclude_commands.
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
    if [[ ! -f "${file}" ]]; then
        mkdir -p "$(dirname "${file}")"
        touch "${file}"
    fi

    # Remove existing block if present (portable sed: no -i flag differences)
    if grep -q "${marker_begin}" "${file}" 2>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        awk -v begin="${marker_begin}" -v end="${marker_end}" '
            $0 ~ begin { skip=1; next }
            $0 ~ end   { skip=0; next }
            !skip
        ' "${file}" > "${tmpfile}"
        mv "${tmpfile}" "${file}"
    fi

    # Append new block
    printf '\n%s\n%s\n%s\n' "${marker_begin}" "${content}" "${marker_end}" >> "${file}"
}

# Detect RTK config directory (XDG on Linux, Application Support on macOS)
rtk_config_dir() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "${HOME}/Library/Application Support/rtk"
    else
        echo "${XDG_CONFIG_HOME:-${HOME}/.config}/rtk"
    fi
}

# --- Config Generation ---

# Generate config.toml with exclude_commands to prevent RTK from rewriting
# dangerous commands. This is the mechanical safety gate for tools that use
# hooks (OpenCode, Claude Code). When RTK receives one of these commands via
# rtk rewrite or a hook, it returns "no rewrite" so the raw command goes
# through the tool's own safety system (deny/ask patterns, permission prompts).
#
# Pass "force" as first argument to overwrite existing exclude_commands.
generate_config() {
    local force="${1:-}"
    log_info "Generating RTK config with exclude_commands..."

    local config_dir
    config_dir="$(rtk_config_dir)"
    local config_file="${config_dir}/config.toml"
    local exclude_src="${SPARKDOCK_ROOT}/config/rtk/exclude-commands.toml"

    if [[ ! -f "${exclude_src}" ]]; then
        log_error "exclude-commands.toml not found: ${exclude_src}"
        return 1
    fi

    mkdir -p "${config_dir}"

    # Create default config if it doesn't exist
    if [[ ! -f "${config_file}" ]]; then
        rtk config --create > /dev/null 2>&1 || true
        if [[ ! -f "${config_file}" ]]; then
            log_error "rtk config --create did not produce ${config_file}"
            return 1
        fi
    fi

    # Skip if exclude_commands is already configured (non-empty), unless forced
    if [[ "${force}" != "force" ]] \
       && grep -q 'exclude_commands' "${config_file}" 2>/dev/null \
       && ! grep -q 'exclude_commands = \[\]' "${config_file}" 2>/dev/null; then
        log_info "RTK config.toml already has exclude_commands, skipping (use --force to overwrite)"
        return 0
    fi

    # Replace only the exclude_commands value under [hooks], preserving other keys.
    # Reads the desired value from exclude_src and splices it into config_file.
    local tmpfile
    tmpfile=$(mktemp)
    local exclude_value
    exclude_value=$(awk '/^exclude_commands/ { found=1 } found { print } /\]/ && found { exit }' "${exclude_src}")

    awk -v replacement="${exclude_value}" '
        /^exclude_commands/ { replacing=1 }
        replacing && /\]/ { print replacement; replacing=0; next }
        replacing { next }
        { print }
    ' "${config_file}" > "${tmpfile}"

    # If exclude_commands didn't exist yet, append it under [hooks]
    if ! grep -q 'exclude_commands' "${tmpfile}"; then
        awk -v insertion="${exclude_value}" '
            { print }
            /^\[hooks\]/ { print insertion }
        ' "${tmpfile}" > "${tmpfile}.2"
        mv "${tmpfile}.2" "${tmpfile}"
    fi

    mv "${tmpfile}" "${config_file}"

    log_success "RTK config generated: ${config_file}"
}

# --- Claude Code ---

setup_claude() {
    log_info "Setting up RTK for Claude Code..."
    if ! rtk init -g --auto-patch > /dev/null; then
        log_error "rtk init -g --auto-patch failed"
        return 1
    fi
    log_success "RTK configured for Claude Code (global hook + RTK.md)"
}

# --- GitHub Copilot ---

# Copilot CLI does not support global hooks — only project-scoped hooks in
# .github/hooks/. The global setup is instructions-only. Keep the policy small:
# use rtk broadly for high-output local dev commands, but do not manually prefix
# destructive, infra, or remote-state commands. This is a prompt-based safety
# measure, not a mechanical one.
#
# Upstream issue for proper hook support: rtk-ai/rtk#1839
setup_copilot() {
    log_info "Setting up RTK for GitHub Copilot (instructions only)..."

    local instructions_content
    read -r -d '' instructions_content <<'EOF' || true
Use `rtk` for high-output local development commands such as build, test, lint, search, status, diff, log, list/get/show, and package manager operations.

Do not manually prefix destructive commands or commands that change infrastructure, cloud, cluster, or remote repository state with `rtk` (for example: `rm -rf`, `git push`, `kubectl apply`, `helm upgrade`, `terraform apply`, `gh pr merge`).

If a project contains `.github/hooks/rtk-rewrite.json`, use normal shell commands and let the hook rewrite safe ones automatically. If unsure, use the raw command.
EOF

    # VS Code Copilot Chat — writes to ~/.github/
    local vscode_dest="${HOME}/.github/copilot-instructions.md"
    inject_with_markers "${vscode_dest}" "${instructions_content}"

    # Copilot CLI — writes to ~/.copilot/
    local cli_dest="${HOME}/.copilot/copilot-instructions.md"
    inject_with_markers "${cli_dest}" "${instructions_content}"

    log_success "RTK configured for GitHub Copilot (instructions only, no global hooks)"
}

# --- OpenCode ---

setup_opencode() {
    log_info "Setting up RTK for OpenCode..."
    if ! rtk init -g --opencode --auto-patch > /dev/null; then
        log_error "rtk init -g --opencode --auto-patch failed"
        return 1
    fi
    log_success "RTK configured for OpenCode (global plugin)"
}

# --- Main ---

FORCE=""
if [[ "${1:-}" == "--force" || "${1:-}" == "force" ]]; then
    FORCE="force"
fi

if ! command -v rtk &> /dev/null; then
    log_error "rtk is not installed. Run 'brew install rtk' first."
    exit 1
fi

generate_config "${FORCE}"
setup_claude
setup_copilot
setup_opencode

log_success "RTK setup complete. Restart your AI coding tools to activate."
