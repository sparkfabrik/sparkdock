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

# Remove a marker-delimited block from a file (no-op if file or block missing).
# Usage: _remove_block <file> <begin_marker> <end_marker>
_remove_block() {
    local file="$1"
    local begin="$2"
    local end="$3"

    [[ -f "${file}" ]] || return 0
    grep -q "${begin}" "${file}" 2>/dev/null || return 0

    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/caveman-cleanup.XXXXXX")"
    awk -v b="${begin}" -v e="${end}" '
        $0 ~ b { skip=1; next }
        $0 ~ e { skip=0; next }
        !skip
    ' "${file}" > "${tmpfile}"
    mv "${tmpfile}" "${file}"
    log_info "Removed stale block from ${file}"
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
    # The native installer copies agents/cavecrew-*.md into
    # ~/.config/opencode/agents/.  Those files use a `tools` YAML array
    # that OpenCode rejects ("Expected object | undefined"), breaking
    # startup entirely.  Remove them until upstream fixes the schema.
    # Tracked: https://github.com/JuliusBrussee/caveman/issues/386
    local opencode_agents_dir="${HOME}/.config/opencode/agents"
    local -a bad_agents=(cavecrew-investigator.md cavecrew-builder.md cavecrew-reviewer.md)
    for f in "${bad_agents[@]}"; do
        if [[ -f "${opencode_agents_dir}/${f}" ]]; then
            rm -f "${opencode_agents_dir}/${f}"
            log_warn "Removed incompatible agent file: ${opencode_agents_dir}/${f}"
        fi
    done

    # Patch: upstream plugin.js uses non-existent opencode hooks
    # (session.created, tui.prompt.append). Replace with our fixed version
    # that uses chat.message + experimental.chat.system.transform.
    # Tracked: https://github.com/JuliusBrussee/caveman/issues/418
    local plugin_patch
    plugin_patch="$(dirname "${BASH_SOURCE[0]}")/patches/opencode-plugin.js"
    local plugin_dest="${HOME}/.config/opencode/plugins/caveman/plugin.js"
    if [[ -f "${plugin_patch}" ]]; then
        if [[ -f "${plugin_dest}" ]]; then
            cp "${plugin_patch}" "${plugin_dest}"
            log_success "Applied opencode plugin.js patch (issue #418)"
        else
            log_warn "Cannot apply plugin.js patch: destination not found (${plugin_dest})"
        fi
    fi

    log_success "Caveman configured for OpenCode (plugin + skills + commands)"
}

# --- GitHub Copilot ---

setup_copilot() {
    log_info "Setting up caveman for GitHub Copilot..."

    local skill_src="${CAVEMAN_CACHE_DIR}/skills/caveman"
    local skill_dest="${SKILLS_DIR}/caveman"

    # 1. Copy skill files to shared skills directory (clean copy to remove stale files)
    if [[ -d "${skill_src}" ]]; then
        rm -rf "${skill_dest}"
        mkdir -p "${skill_dest}"
        cp -r "${skill_src}/." "${skill_dest}/"
        log_success "Caveman skill installed: ${skill_dest}"
    else
        log_warn "Caveman skill source not found: ${skill_src} — skipping Copilot setup"
        return 0
    fi

    # 2. Create symlinks for tool discovery (same pattern as skills-symlink-shim)
    local -A tool_skills_dirs=(
        [copilot]="${HOME}/.copilot/skills"
        [claude]="${HOME}/.claude/skills"
    )

    for tool_id in "${!tool_skills_dirs[@]}"; do
        local tool_dir="${tool_skills_dirs[${tool_id}]}"
        local link="${tool_dir}/caveman"
        mkdir -p "${tool_dir}"
        # Remove existing real directory before symlinking
        if [[ -d "${link}" && ! -L "${link}" ]]; then
            rm -rf "${link}"
        fi
        ln -sfn "${skill_dest}" "${link}"
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

    # Copilot CLI (official user-level instructions path per GitHub docs).
    local copilot_file="${HOME}/.copilot/copilot-instructions.md"

    if [[ -L "${copilot_file}" ]]; then
        local symlink_target
        symlink_target="$(readlink -f "${copilot_file}")"
        if [[ -f "${symlink_target}" ]] && grep -q "caveman" "${symlink_target}" 2>/dev/null; then
            log_info "Copilot instructions is a symlink ($(readlink "${copilot_file}")) — target already contains caveman rules"
        else
            log_warn "Copilot instructions is a symlink ($(readlink "${copilot_file}")) — target does NOT contain caveman rules; inject manually or remove the symlink"
        fi
    else
        inject_with_markers "${copilot_file}" \
            "${marker_begin}" "${marker_end}" "${rule_content}"
        # Remove stale native-installer block from this file (we own it)
        _remove_block "${copilot_file}" "<!-- caveman-begin -->" "<!-- caveman-end -->"
    fi

    # Clean up stale managed blocks from files we don't own (non-symlink only)
    if [[ ! -L "${HOME}/.config/opencode/AGENTS.md" ]]; then
        _remove_block "${HOME}/.config/opencode/AGENTS.md" "${marker_begin}" "${marker_end}"
    fi
    if [[ ! -L "${HOME}/.github/copilot-instructions.md" ]]; then
        _remove_block "${HOME}/.github/copilot-instructions.md" "${marker_begin}" "${marker_end}"
    fi

    log_success "Caveman configured for GitHub Copilot (skill + always-on instructions)"

    # Mirror the native installer's "done" banner (same orange/green/dim
    # palette) so the Copilot section has the same visual weight as the
    # Claude/OpenCode output above.
    local orange='' green='' dim='' reset=''
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        orange=$'\033[38;5;172m'
        green=$'\033[32m'
        dim=$'\033[2m'
        reset=$'\033[0m'
    fi
    printf '\n%s🪨 done%s\n%s  installed:%s\n    • copilot\n\n%s  start any Copilot session and say '\''caveman mode'\'', or run /caveman%s\n%s  uninstall: sjust sf-caveman-uninstall%s\n\n' \
        "${orange}" "${reset}" \
        "${green}" "${reset}" \
        "${dim}" "${reset}" \
        "${dim}" "${reset}"
}

# --- Claude settings repair ---

# Normalize sparkdock-managed Claude Code hooks after the native installer runs.
# The caveman installer bakes a version-pinned node path into the hook commands
# (breaks on node upgrades); the shared fixer rewrites it to a stable Homebrew
# symlink. Runs on macOS and Linux, since both provisioners invoke this script.
# Note: claude-usage hook removal is intentionally NOT requested here — that is
# opt-in via `sjust claude-fix-settings`, so we never strip hooks a user added
# deliberately during automatic provisioning.
normalize_claude_settings() {
    local fixer="${SCRIPT_DIR}/../claude-fix-settings.sh"
    if [[ ! -f "${fixer}" ]]; then
        log_warn "Claude settings fixer not found: ${fixer} — skipping"
        return 0
    fi
    log_info "Normalizing Claude Code hook settings..."
    # Best-effort: this is a self-healing repair, so a failure here (missing
    # python3, transient IO error, ...) must not abort the whole provisioning
    # run under the caller's `set -euo pipefail`.
    bash "${fixer}" fix || log_warn "Claude Code hook normalization failed (non-fatal); continuing"
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
            # Claude Code's official installer lives in <user>/.local/bin, which
            # is not always on PATH during non-interactive provisioning. Without
            # it, setup_claude's `command -v claude` guard fails and the Claude
            # plugin + hooks are silently skipped. Under sudo/become (the Linux
            # sf-toolbox run) $HOME may not be the invoking user's home, so
            # resolve the home of the *effective* user (the account this process
            # actually runs as) via getent when available, falling back to $HOME.
            local user_home="${HOME}"
            if command -v getent &> /dev/null; then
                local resolved_home
                resolved_home="$(getent passwd "$(id -un)" 2> /dev/null | cut -d: -f6 || true)"
                [[ -n "${resolved_home}" ]] && user_home="${resolved_home}"
            fi
            export PATH="${user_home}/.local/bin:${PATH}"
            ensure_caveman_repo
            write_default_config
            setup_claude
            setup_opencode
            setup_copilot
            normalize_claude_settings
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
