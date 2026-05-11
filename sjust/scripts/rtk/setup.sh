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
generate_config() {
    log_info "Generating RTK config with exclude_commands..."

    local config_dir
    config_dir="$(rtk_config_dir)"
    local config_file="${config_dir}/config.toml"
    local exclude_src="${SPARKDOCK_ROOT}/config/rtk/exclude-commands.toml"

    mkdir -p "${config_dir}"

    # Create default config if it doesn't exist
    if [[ ! -f "${config_file}" ]]; then
        rtk config --create > /dev/null 2>&1 || true
    fi

    # Skip if exclude_commands is already configured (non-empty)
    if grep -q 'exclude_commands' "${config_file}" 2>/dev/null \
       && ! grep -q 'exclude_commands = \[\]' "${config_file}" 2>/dev/null; then
        log_info "RTK config.toml already has exclude_commands, skipping"
        return 0
    fi

    # Replace the [hooks] section with our managed exclude list
    local tmpfile
    tmpfile=$(mktemp)
    awk '
        /^\[hooks\]/ { skip=1; next }
        /^\[/        { if (skip) skip=0 }
        !skip
    ' "${config_file}" > "${tmpfile}"
    cat "${exclude_src}" >> "${tmpfile}"
    mv "${tmpfile}" "${config_file}"

    log_success "RTK config generated: ${config_file}"
}

# --- Claude Code ---

setup_claude() {
    log_info "Setting up RTK for Claude Code..."
    rtk init -g --auto-patch > /dev/null 2>&1
    log_success "RTK configured for Claude Code (global hook + RTK.md)"
}

# --- GitHub Copilot ---

# Copilot CLI does not support global hooks — only project-scoped hooks in
# .github/hooks/. The global setup is instructions-only, which tells Copilot
# to prefix read-only commands with rtk. This is a prompt-based safety measure,
# not a mechanical one. For per-project hooks, use the sf-rtk-project-init recipe.
#
# Upstream issue for proper hook support: rtk-ai/rtk#1839
setup_copilot() {
    log_info "Setting up RTK for GitHub Copilot (instructions only)..."

    local instructions_content
    read -r -d '' instructions_content << 'INSTRUCTIONS' || true
# RTK — Token-Optimized CLI

rtk is a CLI proxy that compresses command output, saving 60-90% tokens.

## Rule

Prefix read-only and build/test/lint commands with `rtk`:

```bash
rtk git status          rtk cargo test
rtk git log -10         rtk docker ps
rtk kubectl get pods    rtk ls -la
```

Never prefix commands that modify state (git push, rm, kubectl apply, helm install, etc).

## Meta commands

```bash
rtk gain              # Token savings dashboard
rtk discover          # Find missed rtk opportunities
```
INSTRUCTIONS

    # VS Code Copilot Chat — writes to ~/.github/
    local vscode_dest="${HOME}/.github/copilot-instructions.md"
    mkdir -p "$(dirname "${vscode_dest}")"
    inject_with_markers "${vscode_dest}" "${instructions_content}"

    # Copilot CLI — writes to ~/.copilot/
    local cli_dest="${HOME}/.copilot/copilot-instructions.md"
    mkdir -p "$(dirname "${cli_dest}")"
    inject_with_markers "${cli_dest}" "${instructions_content}"

    log_success "RTK configured for GitHub Copilot (instructions only, no global hooks)"
}

# --- OpenCode ---

setup_opencode() {
    log_info "Setting up RTK for OpenCode..."
    rtk init -g --opencode --auto-patch > /dev/null 2>&1
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
