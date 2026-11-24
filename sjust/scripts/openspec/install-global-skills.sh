#!/usr/bin/env bash
set -euo pipefail

# Install or update the OpenSpec skills globally for the requested AI coding
# tools.
#
# OpenSpec 2.1 and later install global skills themselves with
# `openspec init --scope global`, which must run inside a project folder: it
# refuses the home folder and scaffolds `openspec/` where it runs. A dedicated
# folder under the sparkdock data directory holds that scaffold, so the home
# folder stays clean and OpenSpec registers one stable project.
#
# Older releases have no global scope: they install relative to a project root,
# so ${HOME} is used as the root, with the home project in ~/openspec.
#
# Usage: install-global-skills.sh [tools]
#   tools  — comma-separated tool list (default: claude); OpenSpec identifiers,
#            e.g. claude, opencode, github-copilot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../libs/libshell.sh"

tools="${1:-claude}"

if ! command -v openspec >/dev/null 2>&1; then
    log_error "openspec CLI not found. Install it first (brew install openspec)."
    exit 1
fi

# OpenSpec 1.x treated the home folder as a project and wrote skills, commands
# and prompts there for each configured tool. 2.1 installs the skills once in
# ~/.agents/skills and links them, so those copies are stale. Only files whose
# name and frontmatter match what 1.x generated are removed; anything else,
# including links, is kept and reported.

# Description 1.x wrote in the frontmatter of each workflow's command.
legacy_description() {
    case "$1" in
        apply) echo "Implement tasks from an OpenSpec change (Experimental)" ;;
        archive) echo "Archive a completed change in the experimental workflow" ;;
        bulk-archive) echo "Archive multiple completed changes at once" ;;
        continue) echo "Continue working on a change - create the next artifact (Experimental)" ;;
        explore) echo "Enter explore mode - think through ideas, investigate problems, clarify requirements" ;;
        ff) echo "Create a change and generate all artifacts needed for implementation in one go" ;;
        new) echo "Start a new change using the experimental artifact workflow (OPSX)" ;;
        onboard) echo "Guided onboarding - walk through a complete OpenSpec workflow cycle with narration" ;;
        propose) echo "Propose a new change - create it and generate all artifacts in one step" ;;
        sync) echo "Sync delta specs from a change to main specs" ;;
        update) echo "Update a change - revise existing planning artifacts and keep them coherent (Experimental)" ;;
        verify) echo "Verify implementation matches change artifacts before archiving" ;;
        *) return 1 ;;
    esac
}

# Print the frontmatter lines of a file, without the --- delimiters.
frontmatter() {
    awk 'NR == 1 { if ($0 != "---") exit; next } /^---$/ { exit } { print }' "$1"
}

# Value of a frontmatter key, without surrounding quotes.
frontmatter_value() {
    printf '%s\n' "$1" | sed -n "s/^$2: *//p" | head -1 | sed 's/^"\(.*\)"$/\1/'
}

# True when a command or prompt file is the one 1.x generated for a workflow.
# tool: claude, cursor or plain (OpenCode and Copilot write only a description).
is_legacy_command() {
    local file="$1" workflow="$2" tool="$3" fm expected
    [[ -f "${file}" && ! -L "${file}" ]] || return 1
    expected="$(legacy_description "${workflow}")" || return 1
    fm="$(frontmatter "${file}")"
    [[ "$(frontmatter_value "${fm}" description)" == "${expected}" ]] || return 1
    case "${tool}" in
        claude)
            [[ "$(frontmatter_value "${fm}" name)" == "OPSX: "* ]] &&
                [[ "$(frontmatter_value "${fm}" category)" == "Workflow" ]]
            ;;
        cursor)
            [[ "$(frontmatter_value "${fm}" id)" == "opsx-${workflow}" ]]
            ;;
        *)
            [[ "$(printf '%s\n' "${fm}" | wc -l)" -eq 1 ]]
            ;;
    esac
}

# True when a folder is a skill 1.x generated: a real folder that holds only a
# regular SKILL.md naming the folder, written by OpenSpec.
is_legacy_skill() {
    local dir="$1" fm
    [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
    [[ "$(find "${dir}" -mindepth 1 | wc -l)" -eq 1 ]] || return 1
    [[ -f "${dir}/SKILL.md" && ! -L "${dir}/SKILL.md" ]] || return 1
    fm="$(frontmatter "${dir}/SKILL.md")"
    [[ "$(frontmatter_value "${fm}" name)" == "$(basename "${dir}")" ]] &&
        printf '%s\n' "${fm}" | grep -q '^ *author: openspec$' &&
        printf '%s\n' "${fm}" | grep -q '^ *generatedBy:'
}

remove_legacy() {
    rm -rf -- "$1"
    log_info "Removed ${1/#${HOME}/\~}, left by OpenSpec 1.x"
}

keep_legacy() {
    log_warn "Kept ${1/#${HOME}/\~}: it does not match what OpenSpec 1.x generated."
}

# Remove the generated commands in a folder. pattern is the file name with
# WORKFLOW in place of the workflow name.
remove_legacy_commands() {
    local dir="$1" pattern="$2" tool="$3" file name prefix suffix workflow
    [[ -d "${dir}" && ! -L "${dir}" ]] || return 0
    prefix="${pattern%%WORKFLOW*}"
    suffix="${pattern#*WORKFLOW}"
    for file in "${dir}/${prefix}"*"${suffix}"; do
        [[ -e "${file}" || -L "${file}" ]] || continue
        name="$(basename "${file}")"
        workflow="${name#"${prefix}"}"
        workflow="${workflow%"${suffix}"}"
        if is_legacy_command "${file}" "${workflow}" "${tool}"; then
            remove_legacy "${file}"
        else
            keep_legacy "${file}"
        fi
    done
    rmdir "${dir}" 2>/dev/null || true
}

remove_legacy_skills() {
    local dir="$1" skill
    [[ -d "${dir}" && ! -L "${dir}" ]] || return 0
    for skill in "${dir}"/openspec-*; do
        [[ -e "${skill}" || -L "${skill}" ]] || continue
        # Links are how 2.1 itself exposes the global skills.
        [[ -L "${skill}" ]] && continue
        if is_legacy_skill "${skill}"; then
            remove_legacy "${skill}"
        else
            keep_legacy "${skill}"
        fi
    done
}

# Clean up only the tools this run configured, so other tools keep their files.
remove_legacy_home_files() {
    local tool
    local -a selected
    IFS=',' read -r -a selected <<<"$1"
    if [[ " ${selected[*]} " == *" all "* ]]; then
        selected=(claude cursor github-copilot opencode)
    fi
    for tool in "${selected[@]}"; do
        case "${tool}" in
            claude)
                remove_legacy_skills "${HOME}/.claude/skills"
                remove_legacy_commands "${HOME}/.claude/commands/opsx" "WORKFLOW.md" claude
                ;;
            cursor)
                remove_legacy_skills "${HOME}/.cursor/skills"
                remove_legacy_commands "${HOME}/.cursor/commands" "opsx-WORKFLOW.md" cursor
                ;;
            github-copilot)
                remove_legacy_skills "${HOME}/.github/skills"
                remove_legacy_commands "${HOME}/.github/prompts" "opsx-WORKFLOW.prompt.md" plain
                ;;
            opencode)
                remove_legacy_skills "${HOME}/.opencode/skills"
                remove_legacy_commands "${HOME}/.opencode/commands" "opsx-WORKFLOW.md" plain
                remove_legacy_commands "${HOME}/.opencode/command" "opsx-WORKFLOW.md" plain
                ;;
        esac
    done
}

init_help="$(openspec init --help 2>/dev/null || true)"
if [[ "${init_help}" == *"--scope"* ]]; then
    # A fixed path, so every caller (shell, Ansible) uses the same project.
    global_dir="${HOME}/.local/share/sparkdock/openspec-global"
    mkdir -p "${global_dir}"
    log_info "Configuring global OpenSpec skills (tools: ${tools})"
    # Additive and idempotent: tools configured earlier are kept.
    (cd "${global_dir}" && openspec init --scope global --tools "${tools}" --force --no-animation </dev/null)
    remove_legacy_home_files "${tools}"
    # Refresh the skills for the workflow profile in the global config. It
    # needs GitHub; the skills installed above stay usable when it fails.
    if ! (cd "${global_dir}" && openspec update --force </dev/null); then
        log_warn "Could not refresh the OpenSpec skills; the installed ones stay in place."
    fi
    log_success "Global OpenSpec skills installed for: ${tools}"
    exit 0
fi

# Ensure the requested tools are configured. Re-running init is additive and
# idempotent: it preserves openspec/changes, config.yaml edits, and any tools
# configured previously (a narrower list never removes tools).
log_info "Configuring global OpenSpec skills under ${HOME} (tools: ${tools})"
openspec init "${HOME}" --tools "${tools}" --force

# Refresh instruction files for every configured tool.
openspec update "${HOME}" --force
log_success "Global OpenSpec skills and prompts installed for: ${tools}"
