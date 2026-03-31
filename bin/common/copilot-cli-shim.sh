# shellcheck shell=bash
# bin/common/copilot-cli-shim.sh — Temporary skill symlink shim for Copilot CLI and Claude Code
#
# Neither Copilot CLI nor Claude Code reads skills from ~/.agents/skills/ natively.
# This shim bridges the gap with per-skill symlinks for managed skills.
#
# Copilot CLI track: https://github.com/github/copilot-cli/issues/1744
#                    https://github.com/github/copilot-cli/issues/1846
#
# REMOVAL (Copilot CLI): When Copilot CLI adds native ~/.agents/skills/ support:
#   1. Remove ensure_copilot_cli_symlinks() and related counters/helpers below
#   2. In sparkdock-agents-sync: remove the call to ensure_copilot_cli_symlinks() and
#      the Copilot CLI counters from print_summary()
#   3. In sparkdock-agents-status: remove the COPILOT column from the skills table,
#      remove the call to check_copilot_cli_availability(), and remove print_copilot_cli_issues()
#   4. Optionally remove the ~/.copilot/skills/ directory-ensure task from ansible/macos/macos/base.yml
#   5. If Claude Code support has also been removed, delete this file entirely
#
# REMOVAL (Claude Code): When Claude Code adds native ~/.agents/skills/ support:
#   1. Remove ensure_claude_code_symlinks() and related counters/helpers below
#   2. In sparkdock-agents-sync: remove the call to ensure_claude_code_symlinks() and
#      the Claude Code counters from print_summary()
#   3. In sparkdock-agents-status: remove the CLAUDE column from the skills table,
#      remove the call to check_claude_code_availability(), and remove print_claude_code_issues()
#   4. Optionally remove the ~/.claude/skills/ directory-ensure task from ansible/macos/macos/base.yml
#   5. If Copilot CLI support has also been removed, delete this file entirely

# Guard against double-sourcing
if [[ "${_SPARKDOCK_COPILOT_CLI_SHIM_LOADED:-}" = "1" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
_SPARKDOCK_COPILOT_CLI_SHIM_LOADED=1

COPILOT_SKILLS_DIR="${HOME}/.copilot/skills"

# ============================================================================
# Used by sparkdock-agents-sync
# Depends on globals: MANIFEST_PATH, SKILLS_TARGET_DIR, FORCE (from caller)
# ============================================================================

COPILOT_CLI_SYMLINKED=0
COPILOT_CLI_SKIPPED=0
COPILOT_CLI_CLEANED=0

# List all managed skill names from the manifest (one per line).
# Single python3 call — avoids per-skill overhead.
get_managed_skill_names() {
    if [[ ! -f "${MANIFEST_PATH}" ]]; then
        return
    fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for name in sorted(data.get('skills', {}).keys()):
        print(name)
except Exception:
    pass
" "${MANIFEST_PATH}" 2>/dev/null || true
}

# Create per-skill symlinks in ~/.copilot/skills/ for managed skills.
# Handles collisions (foreign symlinks, user content) with skip+warn.
# Cleans up stale symlinks that point into ~/.agents/skills/ but no longer exist.
ensure_copilot_cli_symlinks() {
    mkdir -p "${COPILOT_SKILLS_DIR}"

    # Fetch managed skill names once (single python3 call)
    local managed_names
    managed_names="$(get_managed_skill_names)"

    # Create symlinks for each managed skill in ~/.agents/skills/
    for skill_dir in "${SKILLS_TARGET_DIR}"/*/; do
        [[ -d "${skill_dir}" ]] || continue
        local skill_name
        skill_name="$(basename "${skill_dir}")"

        # Only symlink skills that sparkdock manages — skip user-created ones
        if [[ -z "${managed_names}" ]] || ! echo "${managed_names}" | grep -Fqx "${skill_name}"; then
            continue
        fi

        local target="${COPILOT_SKILLS_DIR}/${skill_name}"
        local source="${SKILLS_TARGET_DIR}/${skill_name}"

        if [[ -L "${target}" ]]; then
            local link_target
            # Note: readlink without -f returns the raw target. This works because
            # we always create absolute symlinks (ln -s "${source}" above).
            link_target="$(readlink "${target}")"
            if [[ "${link_target}" == "${source}" ]]; then
                # Already pointing to the right place
                continue
            fi
            if [[ "${FORCE}" = true ]]; then
                rm -f "${target}"
                log_warn "Copilot CLI: removed foreign symlink for ${skill_name} (was pointing to ${link_target})"
            else
                log_warn "Copilot CLI: skipped ${skill_name} (symlink points to ${link_target})"
                COPILOT_CLI_SKIPPED=$((COPILOT_CLI_SKIPPED + 1))
                continue
            fi
        elif [[ -e "${target}" ]]; then
            if [[ "${FORCE}" = true ]]; then
                [[ -n "${target}" && "${target}" != "/" ]] || { log_error "refusing to remove unsafe path"; continue; }
                rm -rf "${target}"
                log_warn "Copilot CLI: removed user content for ${skill_name} (was at ${target})"
            else
                log_warn "Copilot CLI: skipped ${skill_name} (user content exists at ${target})"
                COPILOT_CLI_SKIPPED=$((COPILOT_CLI_SKIPPED + 1))
                continue
            fi
        fi

        ln -s "${source}" "${target}"
        COPILOT_CLI_SYMLINKED=$((COPILOT_CLI_SYMLINKED + 1))
        log_success "Copilot CLI: symlinked ${skill_name}"
    done

    # Clean up stale symlinks (point into ~/.agents/skills/ but target no longer exists).
    # Guard: if directory is empty, the glob expands to a literal "*/"; -L catches it.
    for entry in "${COPILOT_SKILLS_DIR}"/*; do
        [[ -L "${entry}" ]] || continue
        local link_target
        link_target="$(readlink "${entry}")"
        # Only touch symlinks that point into our managed skills directory
        if [[ "${link_target}" == "${SKILLS_TARGET_DIR}/"* ]] && [[ ! -d "${link_target}" ]]; then
            rm -f "${entry}"
            COPILOT_CLI_CLEANED=$((COPILOT_CLI_CLEANED + 1))
            local stale_name
            stale_name="$(basename "${entry}")"
            log_info "Copilot CLI: removed stale symlink ${stale_name}"
        fi
    done
}

# ============================================================================
# Used by sparkdock-agents-status
# Depends on globals: SKILLS_DIR, HAS_GUM, YELLOW, NC (from caller)
# ============================================================================

copilot_cli_issues=()

# Check whether a managed skill is discoverable by Copilot CLI.
# Sets COPILOT_CLI_AVAILABLE to "ok" or "partial". Appends a descriptive
# string to copilot_cli_issues when the skill is not properly linked.
# IMPORTANT: Must be called directly (not inside $(...) or a pipeline)
# so that array side effects propagate to the caller.
# Args: <skill_name>
COPILOT_CLI_AVAILABLE=""
check_copilot_cli_availability() {
    local skill_name="$1"
    local copilot_target="${COPILOT_SKILLS_DIR}/${skill_name}"

    if [[ -L "${copilot_target}" ]]; then
        local link_dest
        # Note: readlink without -f returns the raw target. This works because
        # sparkdock-agents-sync always creates absolute symlinks.
        link_dest="$(readlink "${copilot_target}")"
        if [[ "${link_dest}" == "${SKILLS_DIR}/${skill_name}" ]]; then
            COPILOT_CLI_AVAILABLE="ok"
            return
        fi
        copilot_cli_issues+=("${skill_name}: blocked by foreign symlink at ${copilot_target}")
    elif [[ -e "${copilot_target}" ]]; then
        copilot_cli_issues+=("${skill_name}: blocked by user content at ${copilot_target}")
    else
        copilot_cli_issues+=("${skill_name}: symlink missing")
    fi
    COPILOT_CLI_AVAILABLE="partial"
}

# Print Copilot CLI diagnostic box when skills have issues.
# Silent when everything is fine.
print_copilot_cli_issues() {
    if [[ ${#copilot_cli_issues[@]} -eq 0 ]]; then
        return
    fi

    local lines=()
    lines+=("Copilot CLI can't discover these skills")
    lines+=("")
    for issue in "${copilot_cli_issues[@]}"; do
        lines+=("  • ${issue}")
    done
    lines+=("")
    lines+=("Run 'sjust sf-agents-refresh force' to fix.")

    local body
    body="$(printf '%s\n' "${lines[@]}")"

    echo ""
    if [[ "${HAS_GUM}" = true ]]; then
        echo "${body}" | gum style \
            --border rounded \
            --border-foreground 220 \
            --padding "1 2" \
            --margin "0 1" \
            --foreground 220
    else
        printf '%b%s%b\n' "${YELLOW}" "────────────────────────────────────────" "${NC}"
        printf '%s\n' "${lines[@]}"
        printf '%b%s%b\n' "${YELLOW}" "────────────────────────────────────────" "${NC}"
    fi
}

# ============================================================================
# Claude Code — symlink management (mirrors Copilot CLI section above)
# Claude Code only reads skills from ~/.claude/skills/, not ~/.agents/skills/.
# ============================================================================

CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"

CLAUDE_CODE_SYMLINKED=0
CLAUDE_CODE_SKIPPED=0
CLAUDE_CODE_CLEANED=0

# Create per-skill symlinks in ~/.claude/skills/ for managed skills.
# Handles collisions (foreign symlinks, user content) with skip+warn.
# Cleans up stale symlinks that point into ~/.agents/skills/ but no longer exist.
ensure_claude_code_symlinks() {
    mkdir -p "${CLAUDE_SKILLS_DIR}"

    # Fetch managed skill names once (single python3 call)
    local managed_names
    managed_names="$(get_managed_skill_names)"

    # Create symlinks for each managed skill in ~/.agents/skills/
    for skill_dir in "${SKILLS_TARGET_DIR}"/*/; do
        [[ -d "${skill_dir}" ]] || continue
        local skill_name
        skill_name="$(basename "${skill_dir}")"

        # Only symlink skills that sparkdock manages — skip user-created ones
        if [[ -z "${managed_names}" ]] || ! echo "${managed_names}" | grep -Fqx "${skill_name}"; then
            continue
        fi

        local target="${CLAUDE_SKILLS_DIR}/${skill_name}"
        local source="${SKILLS_TARGET_DIR}/${skill_name}"

        if [[ -L "${target}" ]]; then
            local link_target
            # Note: readlink without -f returns the raw target. This works because
            # we always create absolute symlinks (ln -s "${source}" above).
            link_target="$(readlink "${target}")"
            if [[ "${link_target}" == "${source}" ]]; then
                # Already pointing to the right place
                continue
            fi
            if [[ "${FORCE}" = true ]]; then
                rm -f "${target}"
                log_warn "Claude Code: removed foreign symlink for ${skill_name} (was pointing to ${link_target})"
            else
                log_warn "Claude Code: skipped ${skill_name} (symlink points to ${link_target})"
                CLAUDE_CODE_SKIPPED=$((CLAUDE_CODE_SKIPPED + 1))
                continue
            fi
        elif [[ -e "${target}" ]]; then
            if [[ "${FORCE}" = true ]]; then
                [[ -n "${target}" && "${target}" != "/" ]] || { log_error "refusing to remove unsafe path"; continue; }
                rm -rf "${target}"
                log_warn "Claude Code: removed user content for ${skill_name} (was at ${target})"
            else
                log_warn "Claude Code: skipped ${skill_name} (user content exists at ${target})"
                CLAUDE_CODE_SKIPPED=$((CLAUDE_CODE_SKIPPED + 1))
                continue
            fi
        fi

        ln -s "${source}" "${target}"
        CLAUDE_CODE_SYMLINKED=$((CLAUDE_CODE_SYMLINKED + 1))
        log_success "Claude Code: symlinked ${skill_name}"
    done

    # Clean up stale symlinks (point into ~/.agents/skills/ but target no longer exists).
    # Guard: if directory is empty, the glob expands to a literal "*/"; -L catches it.
    for entry in "${CLAUDE_SKILLS_DIR}"/*; do
        [[ -L "${entry}" ]] || continue
        local link_target
        link_target="$(readlink "${entry}")"
        # Only touch symlinks that point into our managed skills directory
        if [[ "${link_target}" == "${SKILLS_TARGET_DIR}/"* ]] && [[ ! -d "${link_target}" ]]; then
            rm -f "${entry}"
            CLAUDE_CODE_CLEANED=$((CLAUDE_CODE_CLEANED + 1))
            local stale_name
            stale_name="$(basename "${entry}")"
            log_info "Claude Code: removed stale symlink ${stale_name}"
        fi
    done
}

# ============================================================================
# Used by sparkdock-agents-status
# Depends on globals: SKILLS_DIR, HAS_GUM, YELLOW, NC (from caller)
# ============================================================================

claude_code_issues=()

# Check whether a managed skill is discoverable by Claude Code.
# Sets CLAUDE_CODE_AVAILABLE to "ok" or "partial". Appends a descriptive
# string to claude_code_issues when the skill is not properly linked.
# IMPORTANT: Must be called directly (not inside $(...) or a pipeline)
# so that array side effects propagate to the caller.
# Args: <skill_name>
CLAUDE_CODE_AVAILABLE=""
check_claude_code_availability() {
    local skill_name="$1"
    local claude_target="${CLAUDE_SKILLS_DIR}/${skill_name}"

    if [[ -L "${claude_target}" ]]; then
        local link_dest
        # Note: readlink without -f returns the raw target. This works because
        # sparkdock-agents-sync always creates absolute symlinks.
        link_dest="$(readlink "${claude_target}")"
        if [[ "${link_dest}" == "${SKILLS_DIR}/${skill_name}" ]]; then
            CLAUDE_CODE_AVAILABLE="ok"
            return
        fi
        claude_code_issues+=("${skill_name}: blocked by foreign symlink at ${claude_target}")
    elif [[ -e "${claude_target}" ]]; then
        claude_code_issues+=("${skill_name}: blocked by user content at ${claude_target}")
    else
        claude_code_issues+=("${skill_name}: symlink missing")
    fi
    CLAUDE_CODE_AVAILABLE="partial"
}

# Print Claude Code diagnostic box when skills have issues.
# Silent when everything is fine.
print_claude_code_issues() {
    if [[ ${#claude_code_issues[@]} -eq 0 ]]; then
        return
    fi

    local lines=()
    lines+=("Claude Code can't discover these skills")
    lines+=("")
    for issue in "${claude_code_issues[@]}"; do
        lines+=("  • ${issue}")
    done
    lines+=("")
    lines+=("Run 'sjust sf-agents-refresh force' to fix.")

    local body
    body="$(printf '%s\n' "${lines[@]}")"

    echo ""
    if [[ "${HAS_GUM}" = true ]]; then
        echo "${body}" | gum style \
            --border rounded \
            --border-foreground 220 \
            --padding "1 2" \
            --margin "0 1" \
            --foreground 220
    else
        printf '%b%s%b\n' "${YELLOW}" "────────────────────────────────────────" "${NC}"
        printf '%s\n' "${lines[@]}"
        printf '%b%s%b\n' "${YELLOW}" "────────────────────────────────────────" "${NC}"
    fi
}
