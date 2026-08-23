#!/usr/bin/env bash
set -euo pipefail

# Install the herdr agent skill for the AI coding tools.
#
# herdr ships its own skill: `herdr --skill` prints the SKILL.md on stdout, so
# the skill is generated from the installed binary instead of being synced from
# the upstream harness repo. Both provisioners call this script (sparkdock on
# macOS, sf-toolbox on Linux), which is why it must stay POSIX-portable.
#
# Usage: setup.sh [install|uninstall]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"
# Tool registry: TOOL_SKILLS_DIR, TOOL_LABEL, TOOLS_NATIVE_DISCOVERY, tool_is_enabled.
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
        if ! tool_is_enabled "${tool_id}"; then
            continue
        fi
        if is_native_discovery "${tool_id}"; then
            continue
        fi

        local tool_dir="${TOOL_SKILLS_DIR[${tool_id}]}"
        local link="${tool_dir}/${SKILL_NAME}"
        mkdir -p "${tool_dir}"

        if [[ -e "${link}" && ! -L "${link}" ]]; then
            log_warn "${TOOL_LABEL[${tool_id}]}: skipped ${SKILL_NAME} (user content exists at ${link})"
            continue
        fi

        ln -sfn "${SKILL_DIR}" "${link}"
        log_success "${TOOL_LABEL[${tool_id}]}: symlinked ${SKILL_NAME}"
    done
}

# --- Uninstall ---

uninstall() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        local link="${TOOL_SKILLS_DIR[${tool_id}]}/${SKILL_NAME}"
        if [[ -L "${link}" ]]; then
            rm -f "${link}"
            log_success "${TOOL_LABEL[${tool_id}]}: removed ${SKILL_NAME} symlink"
        fi
    done

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
            write_skill
            link_skill
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

main "$@"
