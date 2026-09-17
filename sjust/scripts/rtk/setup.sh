#!/usr/bin/env bash
set -euo pipefail

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, helper scripts, instructions, and rewrites exclude_commands.
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

install_rtk_run() {
    local source_file="${SCRIPT_DIR}/rtk-run"
    local target_dir="${HOME}/.local/bin"
    local target_file="${target_dir}/rtk-run"

    if [[ ! -f "${source_file}" ]]; then
        log_error "rtk-run helper not found: ${source_file}"
        return 1
    fi

    mkdir -p "${target_dir}"
    cp "${source_file}" "${target_file}"
    chmod 0755 "${target_file}"

    log_success "RTK helper installed: ${target_file}"
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
# .github/hooks/. The global setup is helper + instructions only.
#
# Upstream issue for proper hook support: rtk-ai/rtk#1839
setup_copilot() {
    log_info "Setting up RTK for GitHub Copilot (helper + instructions only)..."

    local instructions_content
    read -r -d '' instructions_content <<'EOF' || true
Use `rtk-run` for high-output local shell commands such as build, test, lint, search, status, diff, log, and package manager commands.

For commands with pipes, chains, or redirects, pass the whole command as one quoted string to `rtk-run`.

If unsure, run the raw command.
EOF

    # Copilot CLI — official user-level instructions path per GitHub docs.
    local copilot_file="${HOME}/.copilot/copilot-instructions.md"

    if [[ -L "${copilot_file}" ]]; then
        log_info "Copilot instructions is a symlink ($(readlink "${copilot_file}")) — skipping (managed externally)"
    else
        inject_with_markers "${copilot_file}" "${instructions_content}"
    fi

    # Clean up orphaned ~/.github/copilot-instructions.md from previous runs
    # (that path was never documented by GitHub; only ~/.copilot/ is official).
    local orphan="${HOME}/.github/copilot-instructions.md"
    if [[ -f "${orphan}" && ! -L "${orphan}" ]]; then
        local marker_begin="<!-- BEGIN RTK MANAGED BLOCK -->"
        local marker_end="<!-- END RTK MANAGED BLOCK -->"
        if grep -q "${marker_begin}" "${orphan}" 2>/dev/null; then
            local tmpfile
            tmpfile="$(mktemp "${TMPDIR:-/tmp}/rtk-cleanup.XXXXXX")"
            awk -v begin="${marker_begin}" -v end="${marker_end}" '
                $0 ~ begin { skip=1; next }
                $0 ~ end   { skip=0; next }
                !skip
            ' "${orphan}" > "${tmpfile}"
            mv "${tmpfile}" "${orphan}"
            log_info "Removed RTK block from orphaned ${orphan}"
        fi
    fi

    log_success "RTK configured for GitHub Copilot (helper + instructions only, no global hooks)"
}

# --- OpenCode ---

# Major version of the installed OpenCode binary, or 0 when it is missing or
# does not report one (`opencode --version` prints "opencode v2.0.5").
opencode_major_version() {
    local version
    if ! command -v opencode > /dev/null 2>&1; then
        echo 0
        return 0
    fi
    version="$(opencode --version 2> /dev/null | sed -E 's/^[^0-9]*([0-9]+).*$/\1/' | head -n 1)"
    if [[ "${version}" =~ ^[0-9]+$ ]]; then
        echo "${version}"
        return 0
    fi
    echo 0
}

# `rtk init --opencode` still writes an OpenCode 1.x plugin that OpenCode 2.x
# refuses to load ("Plugin must export a default definition with an id and an
# effect or setup function"). Replace it with the 2.x version shipped in
# patches/ when the installed OpenCode is 2.x or newer.
# Tracked: https://github.com/rtk-ai/rtk/issues/3898
patch_opencode_plugin() {
    local plugin_patch="${SCRIPT_DIR}/patches/opencode-plugin.ts"
    local plugin_dest="${HOME}/.config/opencode/plugins/rtk.ts"
    local major

    major="$(opencode_major_version)"
    if (( major < 2 )); then
        return 0
    fi
    if [[ ! -f "${plugin_patch}" ]]; then
        log_warn "Cannot apply OpenCode 2.x plugin patch: ${plugin_patch} not found"
        return 0
    fi
    if [[ ! -f "${plugin_dest}" ]]; then
        log_warn "Cannot apply OpenCode 2.x plugin patch: ${plugin_dest} not found"
        return 0
    fi
    if cmp -s "${plugin_patch}" "${plugin_dest}"; then
        return 0
    fi
    cp "${plugin_patch}" "${plugin_dest}"
    log_success "Applied OpenCode 2.x plugin patch to ${plugin_dest} (rtk#3898)"
}

setup_opencode() {
    log_info "Setting up RTK for OpenCode..."
    if ! rtk init -g --opencode --auto-patch > /dev/null; then
        log_error "rtk init -g --opencode --auto-patch failed"
        return 1
    fi
    patch_opencode_plugin
    log_success "RTK configured for OpenCode (global plugin)"
}

# --- Main ---

if ! command -v rtk &> /dev/null; then
    log_error "rtk is not installed. Run 'brew install rtk' first."
    exit 1
fi

generate_config
install_rtk_run
setup_claude
setup_copilot
setup_opencode

log_success "RTK setup complete. Restart your AI coding tools to activate."
