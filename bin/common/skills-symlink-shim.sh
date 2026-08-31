# shellcheck shell=bash
# bin/common/skills-symlink-shim.sh — Temporary skill symlink shim
#
# Tools like Copilot CLI and Claude Code don't read skills from
# ~/.agents/skills/ natively. This shim bridges the gap with per-skill
# symlinks in each tool's skills directory.
#
# Copilot CLI track: https://github.com/github/copilot-cli/issues/1744
#                    https://github.com/github/copilot-cli/issues/1846
#
# ADDING A NEW TOOL:
#   1. Add entries to TOOL_SKILLS_DIR and TOOL_LABEL below.
#   2. For a tool that is not installed on every machine, add an entry to
#      TOOL_REQUIRES_DIR so it is wired up only where that directory exists.
#   3. In ansible/macos/macos/base.yml, add a directory-ensure task for
#      the new tool's skills directory (guarded the same way if optional).
#
# REMOVING A TOOL:
#   1. Remove its entries from TOOL_SKILLS_DIR, TOOL_LABEL and TOOL_REQUIRES_DIR.
#   2. Optionally remove the directory-ensure task from base.yml.
#   3. If no tools remain, delete this file and remove the source lines
#      from sparkdock-agents-sync and sparkdock-agents-status.

# Guard against double-sourcing
if [[ "${_SPARKDOCK_SKILLS_SHIM_LOADED:-}" = "1" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
_SPARKDOCK_SKILLS_SHIM_LOADED=1

# ============================================================================
# Tool registry — add new tools here (2 lines per tool)
# ============================================================================

declare -A TOOL_SKILLS_DIR=(
    [copilot]="${HOME}/.copilot/skills"
    [claude]="${HOME}/.claude/skills"
    # Codex CLI ships its own bundled skills in ~/.codex/skills/.system/. The
    # loops below glob "${tool_skills_dir}"/* which never matches dotfiles, so
    # .system is left alone.
    [codex]="${HOME}/.codex/skills"
    [opencode]="${HOME}/.config/opencode/skills"
)

declare -A TOOL_LABEL=(
    [copilot]="Copilot CLI"
    [claude]="Claude Code"
    [codex]="Codex CLI"
    [opencode]="OpenCode"
)

# Tools that discover ~/.agents/skills/ natively (no symlinks needed).
TOOLS_NATIVE_DISCOVERY=(opencode)

# Optional tools: wired up only when this directory already exists, which acts as
# the "user has this tool" marker. Tools absent from this array are always wired
# up. The tool's own skills subdirectory is still created on demand.
declare -A TOOL_REQUIRES_DIR=(
    [codex]="${HOME}/.codex"
)

# Whether a tool should be wired up on this machine.
# Args: <tool_id>
tool_is_enabled() {
    local tool_id="$1"
    local required_dir="${TOOL_REQUIRES_DIR[${tool_id}]:-}"
    [[ -z "${required_dir}" ]] && return 0
    [[ -d "${required_dir}" ]]
}

# ============================================================================
# Used by sparkdock-agents-sync
# Depends on globals: MANIFEST_PATH, SKILLS_TARGET_DIR, FORCE (from caller)
# and SKILLS_DISABLED_NAMES (set here via load_disabled_skill_names)
# ============================================================================

# Per-tool counters (associative arrays, keyed by tool_id)
declare -A TOOL_SYMLINKED=()
declare -A TOOL_SKIPPED=()
declare -A TOOL_CLEANED=()

for _tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
    TOOL_SYMLINKED[${_tool_id}]=0
    TOOL_SKIPPED[${_tool_id}]=0
    TOOL_CLEANED[${_tool_id}]=0
done
unset _tool_id

# List all managed skill names from the manifest (one per line).
# Delegates to the shared manifest_list_keys() from utils.sh.
get_managed_skill_names() {
    {
        manifest_list_keys "skills"
        manifest_list_keys "optional_skills" | sed 's@.*/@@'
    } | sort -u
}

# User-disabled skills, newline separated. Populated by load_disabled_skill_names()
# and read by ensure_tool_symlinks() and check_tool_availability(). A disabled skill
# stays installed in ~/.agents/skills/ but gets no per-tool symlink.
SKILLS_DISABLED_NAMES=""

load_disabled_skill_names() {
    SKILLS_DISABLED_NAMES="$(list_disabled_skills)"
}

# Args: <skill_name>
skill_is_disabled() {
    [[ -n "${SKILLS_DISABLED_NAMES}" ]] || return 1
    echo "${SKILLS_DISABLED_NAMES}" | grep -Fqx "$1"
}

# Create per-skill symlinks in a tool's skills directory for managed skills.
# Handles collisions (foreign symlinks, user content) with skip+warn.
# Skips skills the user disabled, and removes symlinks that point into
# ~/.agents/skills/ but no longer exist or belong to a disabled skill.
# Args: <tool_id> [managed_names]
#   tool_id:       key from TOOL_SKILLS_DIR (e.g. "copilot", "claude")
#   managed_names: optional pre-fetched output of get_managed_skill_names()
#                  (avoids repeated python3 calls when syncing multiple tools)
ensure_tool_symlinks() {
    local tool_id="$1"
    local managed_names="${2:-}"
    local tool_label="${TOOL_LABEL[${tool_id}]}"
    local tool_skills_dir="${TOOL_SKILLS_DIR[${tool_id}]}"

    # Skip optional tools whose marker directory is absent — nothing is created.
    if ! tool_is_enabled "${tool_id}"; then
        return
    fi

    # Skip tools that discover ~/.agents/skills/ natively.
    local native
    for native in "${TOOLS_NATIVE_DISCOVERY[@]}"; do
        if [[ "${tool_id}" == "${native}" ]]; then
            return
        fi
    done

    mkdir -p "${tool_skills_dir}"

    # Fetch managed skill names if not passed by caller
    if [[ -z "${managed_names}" ]]; then
        managed_names="$(get_managed_skill_names)"
    fi

    # Create symlinks for each managed skill in ~/.agents/skills/
    for skill_dir in "${SKILLS_TARGET_DIR}"/*/; do
        [[ -d "${skill_dir}" ]] || continue
        local skill_name
        skill_name="$(basename "${skill_dir}")"

        # Only symlink skills that sparkdock manages — skip user-created ones
        if [[ -z "${managed_names}" ]] || ! echo "${managed_names}" | grep -Fqx "${skill_name}"; then
            continue
        fi

        # Skills the user disabled stay installed but are never linked.
        if skill_is_disabled "${skill_name}"; then
            continue
        fi

        local target="${tool_skills_dir}/${skill_name}"
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
                log_warn "${tool_label}: removed foreign symlink for ${skill_name} (was pointing to ${link_target})"
            else
                log_warn "${tool_label}: skipped ${skill_name} (symlink points to ${link_target})"
                TOOL_SKIPPED[${tool_id}]=$((TOOL_SKIPPED[${tool_id}] + 1))
                continue
            fi
        elif [[ -e "${target}" ]]; then
            if [[ "${FORCE}" = true ]]; then
                [[ -n "${target}" && "${target}" != "/" ]] || { log_error "refusing to remove unsafe path"; continue; }
                rm -rf "${target}"
                log_warn "${tool_label}: removed user content for ${skill_name} (was at ${target})"
            else
                log_warn "${tool_label}: skipped ${skill_name} (user content exists at ${target})"
                TOOL_SKIPPED[${tool_id}]=$((TOOL_SKIPPED[${tool_id}] + 1))
                continue
            fi
        fi

        ln -s "${source}" "${target}"
        TOOL_SYMLINKED[${tool_id}]=$((TOOL_SYMLINKED[${tool_id}] + 1))
        log_success "${tool_label}: symlinked ${skill_name}"
    done

    # Clean up symlinks that point into ~/.agents/skills/ but should no longer
    # exist: the target is gone, or the link is a disabled skill's own link.
    # The disabled case matches on name, so it also checks the target: a user
    # alias sharing the name but pointing elsewhere is not ours to remove.
    # Guard: if directory is empty, the glob expands to a literal "*"; -L catches it.
    for entry in "${tool_skills_dir}"/*; do
        [[ -L "${entry}" ]] || continue
        local link_target stale_name
        link_target="$(readlink "${entry}")"
        # Only touch symlinks that point into our managed skills directory
        [[ "${link_target}" == "${SKILLS_TARGET_DIR}/"* ]] || continue
        stale_name="$(basename "${entry}")"

        if [[ ! -d "${link_target}" ]]; then
            rm -f "${entry}"
            TOOL_CLEANED[${tool_id}]=$((TOOL_CLEANED[${tool_id}] + 1))
            log_info "${tool_label}: removed stale symlink ${stale_name}"
        elif skill_is_disabled "${stale_name}" && [[ "${link_target}" == "${SKILLS_TARGET_DIR}/${stale_name}" ]]; then
            rm -f "${entry}"
            TOOL_CLEANED[${tool_id}]=$((TOOL_CLEANED[${tool_id}] + 1))
            log_info "${tool_label}: unlinked ${stale_name} (disabled by user)"
        fi
    done
}

# ============================================================================
# Used by sparkdock-agents-status
# Depends on globals: SKILLS_DIR, HAS_GUM, YELLOW, NC (from caller)
# ============================================================================

# Per-tool issues (flat array with "tool_id|message" entries).
# Filtered by tool_id at print time.
tool_symlink_issues=()

# Check whether a managed skill is discoverable by a specific tool.
# Sets TOOL_AVAILABLE to "ok", "partial", "off" (disabled by the user),
# "native" (disabled but still discovered natively) or "-" (tool not here).
# Appends a descriptive entry to tool_symlink_issues when the skill is not
# properly linked; a disabled skill is never reported as an issue.
# IMPORTANT: Must be called directly (not inside $(...) or a pipeline)
# so that array side effects propagate to the caller.
# Args: <tool_id> <skill_name>
TOOL_AVAILABLE=""
check_tool_availability() {
    local tool_id="$1"
    local skill_name="$2"

    # A disabled optional tool is not a problem to report — callers normally filter
    # these out before building their table, so this is only a safety net.
    if ! tool_is_enabled "${tool_id}"; then
        TOOL_AVAILABLE="-"
        return
    fi

    # Tools with native discovery read ~/.agents/skills/ directly — no symlink needed.
    local native
    for native in "${TOOLS_NATIVE_DISCOVERY[@]}"; do
        if [[ "${tool_id}" == "${native}" ]]; then
            # A disabled skill is still discovered natively: there is no symlink
            # layer to remove, so report it honestly rather than as "off".
            if skill_is_disabled "${skill_name}"; then
                TOOL_AVAILABLE="native"
                return
            fi
            if [[ -f "${SKILLS_DIR}/${skill_name}/SKILL.md" ]]; then
                TOOL_AVAILABLE="ok"
            else
                TOOL_AVAILABLE="partial"
            fi
            return
        fi
    done

    # The user disabled this skill: no symlink is expected, so this is not an issue.
    if skill_is_disabled "${skill_name}"; then
        TOOL_AVAILABLE="off"
        return
    fi

    local tool_target="${TOOL_SKILLS_DIR[${tool_id}]}/${skill_name}"

    if [[ -L "${tool_target}" ]]; then
        local link_dest
        # Note: readlink without -f returns the raw target. This works because
        # sparkdock-agents-sync always creates absolute symlinks.
        link_dest="$(readlink "${tool_target}")"
        if [[ "${link_dest}" == "${SKILLS_DIR}/${skill_name}" ]]; then
            TOOL_AVAILABLE="ok"
            return
        fi
        tool_symlink_issues+=("${tool_id}|${skill_name}: blocked by foreign symlink at ${tool_target}")
    elif [[ -e "${tool_target}" ]]; then
        tool_symlink_issues+=("${tool_id}|${skill_name}: blocked by user content at ${tool_target}")
    else
        tool_symlink_issues+=("${tool_id}|${skill_name}: symlink missing")
    fi
    # shellcheck disable=SC2034
    TOOL_AVAILABLE="partial"
}

# Print diagnostic box for a specific tool when skills have issues.
# Silent when everything is fine.
# Args: <tool_id>
print_tool_issues() {
    local tool_id="$1"
    local tool_label="${TOOL_LABEL[${tool_id}]}"

    # Filter issues for this tool
    local filtered=()
    if [[ ${#tool_symlink_issues[@]} -gt 0 ]]; then
        for entry in "${tool_symlink_issues[@]}"; do
            if [[ "${entry}" == "${tool_id}|"* ]]; then
                filtered+=("${entry#"${tool_id}|"}")
            fi
        done
    fi

    if [[ ${#filtered[@]} -eq 0 ]]; then
        return
    fi

    local lines=()
    lines+=("${tool_label} can't discover these skills")
    lines+=("")
    for issue in "${filtered[@]}"; do
        lines+=("  • ${issue}")
    done
    lines+=("")
    lines+=("Run '$(get_harness_runner) sf-harness-sync force' to fix.")

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
