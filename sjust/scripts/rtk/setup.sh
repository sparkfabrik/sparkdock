#!/usr/bin/env bash
set -euo pipefail

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, instructions, and rewrites Sparkdock-managed exclude_commands.
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
        tmpfile="$(mktemp "${TMPDIR:-/tmp}/rtk-setup.XXXXXX")"
        if [[ -z "${tmpfile}" || ! -f "${tmpfile}" ]]; then
            echo "Failed to create temporary file" >&2
            return 1
        fi
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

# RTK owns config.toml defaults. Sparkdock only bootstraps the file when missing
# and always rewrites exclude_commands from config/rtk/exclude-commands.toml.
generate_config() {
    local config_dir
    config_dir="$(rtk_config_dir)"
    local config_file="${config_dir}/config.toml"
    local exclude_src="${SPARKDOCK_ROOT}/config/rtk/exclude-commands.toml"

    log_info "Ensuring RTK config exists and updating exclude_commands..."

    if [[ ! -f "${exclude_src}" ]]; then
        log_error "exclude-commands.toml not found: ${exclude_src}"
        return 1
    fi

    mkdir -p "${config_dir}"

    if [[ ! -f "${config_file}" ]]; then
        rtk config --create > /dev/null 2>&1 || true
        if [[ ! -f "${config_file}" ]]; then
            log_error "rtk config --create did not produce ${config_file}"
            return 1
        fi
    fi

    local tmpfile
    tmpfile=$(mktemp)
    local exclude_tmpfile
    exclude_tmpfile=$(mktemp)
    awk '/^exclude_commands/ { found=1 } found { print } /\]/ && found { exit }' "${exclude_src}" > "${exclude_tmpfile}"

    awk -v exclude_file="${exclude_tmpfile}" '
        BEGIN {
            while ((getline line < exclude_file) > 0) {
                replacement = replacement line "\n"
            }
            close(exclude_file)
        }
        /^exclude_commands/ { replacing=1; printf "%s", replacement; next }
        replacing && /\]/ { replacing=0; next }
        replacing { next }
        { print }
    ' "${config_file}" > "${tmpfile}"

    if ! grep -q '^exclude_commands' "${tmpfile}"; then
        if grep -q '^\[hooks\]' "${tmpfile}"; then
            awk -v exclude_file="${exclude_tmpfile}" '
                BEGIN {
                    while ((getline line < exclude_file) > 0) {
                        insertion = insertion line "\n"
                    }
                    close(exclude_file)
                }
                { print }
                /^\[hooks\]/ { printf "%s", insertion }
            ' "${tmpfile}" > "${tmpfile}.hooks"
            mv "${tmpfile}.hooks" "${tmpfile}"
        else
            {
                printf '\n'
                cat "${exclude_src}"
                printf '\n'
            } >> "${tmpfile}"
        fi
    fi

    rm -f "${exclude_tmpfile}"

    mv "${tmpfile}" "${config_file}"

    log_success "RTK config updated: ${config_file}"
}

# --- Claude Code ---

setup_claude() {
    log_info "Setting up RTK for Claude Code..."
    mkdir -p "${HOME}/.claude"
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

Do not manually prefix destructive commands or commands that change infrastructure, cloud, cluster, or remote repository state with `rtk` (for example: `rm -rf`, `git push --force`, `kubectl apply`, `terraform destroy`, `gcloud ... destroy`, `gh pr merge`).

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

if ! command -v rtk &> /dev/null; then
    log_error "rtk is not installed. Run 'brew install rtk' first."
    exit 1
fi

generate_config
setup_claude
setup_copilot
setup_opencode

log_success "RTK setup complete. Restart your AI coding tools to activate."
