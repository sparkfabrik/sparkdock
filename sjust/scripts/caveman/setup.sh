#!/usr/bin/env bash
set -euo pipefail

# Setup caveman output compression for AI coding tools.
# Clones the caveman repo, writes default config, then delegates to the
# native installer for Claude Code and OpenCode.  Copilot is handled
# directly (skill copy + always-on instruction injection).
#
# Each agent is behind a guard clause; adding or removing an agent means
# adding or removing one function and one call in main().
#
# Usage: setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

# --- Constants ---

CAVEMAN_REPO_URL="https://github.com/JuliusBrussee/caveman.git"
CAVEMAN_CACHE_DIR="${HOME}/.cache/sparkdock/caveman"
CAVEMAN_CONFIG_DIR="${HOME}/.config/caveman"
CAVEMAN_CONFIG_FILE="${CAVEMAN_CONFIG_DIR}/config.json"
CAVEMAN_DEFAULT_MODE="full"

# Shared skills directory (used by the symlink shim for tool discovery)
SKILLS_DIR="${HOME}/.agents/skills"

# --- Helpers ---

# Inject content between markers into a file, replacing any existing block.
# Creates the file (and parent dirs) if it doesn't exist.
# Usage: inject_with_markers <file> <begin_marker> <end_marker> <content>
inject_with_markers() {
    local file="$1"
    local marker_begin="$2"
    local marker_end="$3"
    local content="$4"

    if [[ ! -f "${file}" ]]; then
        mkdir -p "$(dirname "${file}")"
        touch "${file}"
    fi

    # Remove existing block if present
    if grep -q "${marker_begin}" "${file}" 2>/dev/null; then
        local tmpfile
        tmpfile="$(mktemp "${TMPDIR:-/tmp}/caveman-setup.XXXXXX")"
        if [[ -z "${tmpfile}" || ! -f "${tmpfile}" ]]; then
            log_error "Failed to create temporary file"
            return 1
        fi
        awk -v begin="${marker_begin}" -v end="${marker_end}" '
            $0 ~ begin { skip=1; next }
            $0 ~ end   { skip=0; next }
            !skip
        ' "${file}" > "${tmpfile}"
        mv "${tmpfile}" "${file}"
    fi

    printf '\n%s\n%s\n%s\n' "${marker_begin}" "${content}" "${marker_end}" >> "${file}"
}

# --- Repository ---

ensure_caveman_repo() {
    log_info "Ensuring caveman repo is up to date..."
    mkdir -p "$(dirname "${CAVEMAN_CACHE_DIR}")"

    if [[ ! -d "${CAVEMAN_CACHE_DIR}/.git" ]]; then
        git clone --depth=1 "${CAVEMAN_REPO_URL}" "${CAVEMAN_CACHE_DIR}"
        log_success "Caveman repo cloned: ${CAVEMAN_CACHE_DIR}"
    else
        git -C "${CAVEMAN_CACHE_DIR}" fetch --depth=1 origin main
        git -C "${CAVEMAN_CACHE_DIR}" reset --hard origin/main
        log_success "Caveman repo updated: ${CAVEMAN_CACHE_DIR}"
    fi

    # Workaround: upstream installer references caveman-compress.md command
    # but the file is missing from the repo (as of 2026-05-13).  Create a
    # minimal stub so the OpenCode install doesn't bail mid-way.
    # Remove this block once upstream ships the file.
    local compress_cmd="${CAVEMAN_CACHE_DIR}/src/plugins/opencode/commands/caveman-compress.md"
    if [[ ! -f "${compress_cmd}" ]]; then
        cat > "${compress_cmd}" << 'STUB'
---
description: Compress a memory file into caveman format to save input tokens
---
Compress the following file into caveman format: $ARGUMENTS

Preserve all technical substance, code, URLs, and structure.
Save a human-readable backup as FILE.original.md before overwriting.
STUB
        log_warn "Created stub for missing upstream file: caveman-compress.md"
    fi
}

# --- Config ---

write_default_config() {
    log_info "Writing caveman config..."
    mkdir -p "${CAVEMAN_CONFIG_DIR}"
    printf '{"defaultMode": "%s"}\n' "${CAVEMAN_DEFAULT_MODE}" > "${CAVEMAN_CONFIG_FILE}"
    log_success "Caveman config written: ${CAVEMAN_CONFIG_FILE} (mode: ${CAVEMAN_DEFAULT_MODE})"
}

# --- Claude Code ---

setup_claude() {
    if ! command -v claude &> /dev/null; then
        log_info "Claude Code not found, skipping caveman setup for Claude Code"
        return 0
    fi

    log_info "Setting up caveman for Claude Code..."
    if ! node "${CAVEMAN_CACHE_DIR}/bin/install.js" \
        --only claude --force --non-interactive --no-mcp-shrink; then
        log_error "Caveman installer failed for Claude Code"
        return 1
    fi
    log_success "Caveman configured for Claude Code (plugin + hooks)"
}

# --- OpenCode ---

setup_opencode() {
    if ! command -v opencode &> /dev/null; then
        log_info "OpenCode not found, skipping caveman setup for OpenCode"
        return 0
    fi

    log_info "Setting up caveman for OpenCode..."
    if ! node "${CAVEMAN_CACHE_DIR}/bin/install.js" \
        --only opencode --force --non-interactive --no-mcp-shrink; then
        log_error "Caveman installer failed for OpenCode"
        return 1
    fi
    log_success "Caveman configured for OpenCode (plugin + skills + commands)"
}

# --- GitHub Copilot ---

setup_copilot() {
    log_info "Setting up caveman for GitHub Copilot..."

    local skill_src="${CAVEMAN_CACHE_DIR}/skills/caveman"
    local skill_dest="${SKILLS_DIR}/caveman"

    # 1. Copy skill files to shared skills directory
    if [[ -d "${skill_src}" ]]; then
        mkdir -p "${skill_dest}"
        cp -r "${skill_src}/." "${skill_dest}/"
        log_success "Caveman skill installed: ${skill_dest}"
    else
        log_warn "Caveman skill source not found: ${skill_src}"
    fi

    # 2. Create symlinks for tool discovery (same pattern as skills-symlink-shim)
    local -A tool_skills_dirs=(
        [copilot]="${HOME}/.copilot/skills"
        [claude]="${HOME}/.claude/skills"
    )

    for tool_id in "${!tool_skills_dirs[@]}"; do
        local tool_dir="${tool_skills_dirs[${tool_id}]}"
        mkdir -p "${tool_dir}"
        ln -sfn "${skill_dest}" "${tool_dir}/caveman"
    done

    # 3. Inject always-on caveman rules into Copilot instruction files
    local rule_file="${CAVEMAN_CACHE_DIR}/src/rules/caveman-activate.md"
    if [[ ! -f "${rule_file}" ]]; then
        log_error "Caveman activation rule not found: ${rule_file}"
        return 1
    fi

    local rule_content
    rule_content="$(cat "${rule_file}")"
    local marker_begin="<!-- BEGIN CAVEMAN MANAGED BLOCK -->"
    local marker_end="<!-- END CAVEMAN MANAGED BLOCK -->"

    # VS Code Copilot Chat
    inject_with_markers "${HOME}/.github/copilot-instructions.md" \
        "${marker_begin}" "${marker_end}" "${rule_content}"

    # Copilot CLI
    inject_with_markers "${HOME}/.copilot/copilot-instructions.md" \
        "${marker_begin}" "${marker_end}" "${rule_content}"

    log_success "Caveman configured for GitHub Copilot (skill + always-on instructions)"
}

# --- Uninstall ---

uninstall() {
    log_info "Removing caveman from all AI coding tools..."

    # Delegate to native uninstaller for Claude Code and OpenCode
    if [[ -f "${CAVEMAN_CACHE_DIR}/bin/install.js" ]]; then
        node "${CAVEMAN_CACHE_DIR}/bin/install.js" --uninstall --non-interactive || true
    fi

    # Clean up Copilot markers
    local marker_begin="<!-- BEGIN CAVEMAN MANAGED BLOCK -->"
    local marker_end="<!-- END CAVEMAN MANAGED BLOCK -->"
    local files=(
        "${HOME}/.github/copilot-instructions.md"
        "${HOME}/.copilot/copilot-instructions.md"
    )

    for file in "${files[@]}"; do
        if [[ -f "${file}" ]] && grep -q "${marker_begin}" "${file}" 2>/dev/null; then
            local tmpfile
            tmpfile="$(mktemp "${TMPDIR:-/tmp}/caveman-uninstall.XXXXXX")"
            awk -v begin="${marker_begin}" -v end="${marker_end}" '
                $0 ~ begin { skip=1; next }
                $0 ~ end   { skip=0; next }
                !skip
            ' "${file}" > "${tmpfile}"
            mv "${tmpfile}" "${file}"
            log_success "Removed caveman block from ${file}"
        fi
    done

    # Remove skill and symlinks
    local -A tool_skills_dirs=(
        [copilot]="${HOME}/.copilot/skills"
        [claude]="${HOME}/.claude/skills"
    )

    for tool_id in "${!tool_skills_dirs[@]}"; do
        local link="${tool_skills_dirs[${tool_id}]}/caveman"
        if [[ -L "${link}" ]]; then
            rm -f "${link}"
        fi
    done

    if [[ -d "${SKILLS_DIR}/caveman" ]]; then
        rm -rf "${SKILLS_DIR}/caveman"
        log_success "Removed caveman skill from ${SKILLS_DIR}"
    fi

    log_success "Caveman uninstall complete"
}

# --- Main ---

main() {
    local action="${1:-install}"

    case "${action}" in
        install)
            if ! command -v node &> /dev/null; then
                log_error "Node.js is required but not found"
                exit 1
            fi
            ensure_caveman_repo
            write_default_config
            setup_claude
            setup_opencode
            setup_copilot
            log_success "Caveman setup complete. Restart your AI coding tools to activate."
            ;;
        uninstall)
            uninstall
            ;;
        *)
            log_error "Unknown action: ${action}. Use install or uninstall."
            exit 1
            ;;
    esac
}

main "$@"
