#!/usr/bin/env bash
set -euo pipefail

# Install the herdr agent skill for the AI coding tools.
#
# herdr ships its own skill: `herdr --skill` prints the SKILL.md on stdout, so
# the skill is generated from the installed binary instead of being synced from
# the upstream harness repo. Both provisioners call this script (sparkdock on
# macOS, sf-toolbox on Linux), so it sticks to bash plus tools that behave the
# same on BSD and GNU userlands.
#
# Usage: setup.sh [install|uninstall]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"
# Tool registry: TOOL_SKILLS_DIR, TOOL_LABEL, TOOLS_NATIVE_DISCOVERY.
# Sourced instead of duplicated so a new tool in the registry is picked up here too.
# shellcheck source=../../../bin/common/skills-symlink-shim.sh
source "${SPARKDOCK_ROOT}/bin/common/skills-symlink-shim.sh"

SKILL_NAME="herdr"
SKILL_DIR="${HOME}/.agents/skills/${SKILL_NAME}"
SKILL_FILE="${SKILL_DIR}/SKILL.md"

# --- Helpers ---

is_native_discovery() {
    local tool_id="$1"
    local native
    for native in "${TOOLS_NATIVE_DISCOVERY[@]}"; do
        if [[ "${tool_id}" == "${native}" ]]; then
            return 0
        fi
    done
    return 1
}

# --- Install ---

write_skill() {
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/herdr-skill.XXXXXX")"

    if ! herdr --skill > "${tmpfile}"; then
        rm -f "${tmpfile}"
        log_error "herdr --skill failed"
        return 1
    fi

    # An empty or truncated file would break tool discovery without any visible
    # error, so require the YAML front matter herdr always emits.
    if [[ ! -s "${tmpfile}" ]] || [[ "$(head -n 1 "${tmpfile}")" != "---" ]]; then
        rm -f "${tmpfile}"
        log_error "herdr --skill produced no usable skill file"
        return 1
    fi

    mkdir -p "${SKILL_DIR}"

    if [[ -f "${SKILL_FILE}" ]] && cmp -s "${tmpfile}" "${SKILL_FILE}"; then
        rm -f "${tmpfile}"
        log_info "herdr skill already up to date: ${SKILL_FILE}"
        return 0
    fi

    mv "${tmpfile}" "${SKILL_FILE}"
    chmod 0644 "${SKILL_FILE}"
    log_success "herdr skill installed: ${SKILL_FILE}"
}

link_skill() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        if is_native_discovery "${tool_id}"; then
            continue
        fi

        local tool_dir="${TOOL_SKILLS_DIR[${tool_id}]}"
        local link="${tool_dir}/${SKILL_NAME}"
        mkdir -p "${tool_dir}"

        if [[ -L "${link}" ]]; then
            local link_target
            link_target="$(readlink "${link}")"
            if [[ "${link_target}" != "${SKILL_DIR}" ]]; then
                log_warn "${TOOL_LABEL[${tool_id}]}: skipped ${SKILL_NAME} (symlink points to ${link_target})"
                continue
            fi
        elif [[ -e "${link}" ]]; then
            log_warn "${TOOL_LABEL[${tool_id}]}: skipped ${SKILL_NAME} (user content exists at ${link})"
            continue
        fi

        ln -sfn "${SKILL_DIR}" "${link}"
        log_success "${TOOL_LABEL[${tool_id}]}: symlinked ${SKILL_NAME}"
    done
}

# herdr also installs per-tool integrations (hooks or plugins that report the
# agent state to the herdr pane). They are opt-in, so nothing is installed here;
# but an installed integration that herdr reports as outdated is refreshed,
# because a stale one can stop loading after the tool updates (the OpenCode 1.x
# plugin no longer loads on OpenCode 2.x, for example).
# Print the name of every integration that `herdr integration status` (read
# from stdin) reports as outdated, one per line. Lines look like
# "opencode: outdated (v11 < v12) (/path/to/plugin)"; an experimental one is
# "letta (experimental): outdated (...)". Only the text before the first colon
# is inspected, so "outdated" inside a path never matches.
outdated_integrations() {
    local line name
    while IFS= read -r line; do
        if [[ "${line}" != *": outdated"* ]]; then
            continue
        fi
        name="${line%%:*}"
        name="${name% (experimental)}"
        echo "${name}"
    done
}

update_integrations() {
    local status_output
    if ! status_output="$(herdr integration status 2> /dev/null)"; then
        log_warn "herdr integration status failed, skipping integration refresh"
        return 0
    fi

    local outdated=()
    local name
    while IFS= read -r name; do
        outdated+=("${name}")
    done < <(outdated_integrations <<< "${status_output}")

    if (( ${#outdated[@]} == 0 )); then
        log_info "herdr integrations are up to date"
        return 0
    fi

    for name in "${outdated[@]}"; do
        if herdr integration install "${name}" > /dev/null 2>&1; then
            log_success "herdr integration refreshed: ${name}"
        else
            log_warn "herdr integration install ${name} failed"
        fi
    done
}

# --- Uninstall ---

uninstall() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        local link="${TOOL_SKILLS_DIR[${tool_id}]}/${SKILL_NAME}"
        if [[ -L "${link}" ]] && [[ "$(readlink "${link}")" == "${SKILL_DIR}" ]]; then
            rm -f "${link}"
            log_success "${TOOL_LABEL[${tool_id}]}: removed ${SKILL_NAME} symlink"
        fi
    done

    if [[ -L "${SKILL_DIR}" ]]; then
        log_warn "herdr skill is managed elsewhere (${SKILL_DIR} -> $(readlink "${SKILL_DIR}")), leaving it in place"
        return 0
    fi

    if [[ -d "${SKILL_DIR}" ]]; then
        rm -rf "${SKILL_DIR}"
        log_success "Removed herdr skill: ${SKILL_DIR}"
    fi
}

# --- Main ---

main() {
    local action="${1:-install}"

    case "${action}" in
        install)
            if ! command -v herdr &> /dev/null; then
                log_warn "herdr is not installed, skipping herdr skill setup"
                return 0
            fi
            # A symlinked skill directory means the skill is managed elsewhere (a
            # checkout, a dotfiles repo). Writing through the link would overwrite
            # content this script does not own, so leave the whole thing alone.
            # Not an error: provisioning must not fail over a deliberate local setup.
            if [[ -L "${SKILL_DIR}" ]]; then
                log_warn "herdr skill is managed elsewhere (${SKILL_DIR} -> $(readlink "${SKILL_DIR}")), skipping"
                return 0
            fi
            write_skill
            link_skill
            update_integrations
            log_success "herdr skill setup complete. Restart your AI coding tools to pick it up."
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
