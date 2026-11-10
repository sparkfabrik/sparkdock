#!/usr/bin/env bash
set -euo pipefail

# Install the herdr agent skill for the AI coding tools.
#
# Two Herdr runtimes exist: the Herdr TUI (`herdr`) and herdr-core (`hc`),
# which runs the terminals of the Herdr desktop app (`herdr-app`). Each binary
# ships its own manual (`<binary> --skill`), so the skill is generated from the
# installed binaries instead of being synced from the upstream harness repo.
# SKILL.md is a static router (skill-router.md next to this script) that
# detects the runtime the agent runs in and loads the matching manual from
# references/. Both provisioners call this script (sparkdock on macOS,
# sf-toolbox on Linux), so it sticks to bash plus tools that behave the same on
# BSD and GNU userlands.
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
REFERENCES_DIR="${SKILL_DIR}/references"
ROUTER_SOURCE="${SCRIPT_DIR}/skill-router.md"

# --- Helpers ---

# Print the path of a usable herdr-core CLI, or nothing. The Herdr app installs
# it as `herdr-core` (with an `hc` name next to it) in ~/.local/bin by default,
# and the app looks in its own data directory too. Provisioning runs can have a
# PATH without ~/.local/bin, so those locations are checked explicitly. The
# `--version` check rejects an unrelated `hc` on PATH: herdr-core answers
# `hc <version>`.
find_hc() {
    local candidate
    for candidate in \
        "$(command -v hc 2> /dev/null || true)" \
        "$(command -v herdr-core 2> /dev/null || true)" \
        "${HOME}/.local/bin/hc" \
        "${HOME}/.local/bin/herdr-core" \
        "${HOME}/.local/share/herdr-core/current/Contents/MacOS/herdr-core" \
        "${HOME}/.local/share/herdr-core/Herdr Core.app/Contents/MacOS/herdr-core"; do
        if [[ -n "${candidate}" && -x "${candidate}" ]] \
            && [[ "$("${candidate}" --version 2> /dev/null || true)" == "hc "* ]]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 0
}

# Print the path of the Herdr desktop app CLI, or nothing. The macOS cask links
# it into the Homebrew bin directory; sf-toolbox puts it in ~/.local/bin.
find_herdr_app() {
    local candidate
    for candidate in \
        "$(command -v herdr-app 2> /dev/null || true)" \
        "${HOME}/.local/bin/herdr-app"; do
        if [[ -n "${candidate}" && -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 0
}

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

# Move a generated file into place unless the destination already matches it.
install_file() {
    local tmpfile="$1"
    local dest="$2"

    mkdir -p "$(dirname "${dest}")"

    if [[ -f "${dest}" ]] && cmp -s "${tmpfile}" "${dest}"; then
        rm -f "${tmpfile}"
        log_info "herdr skill file already up to date: ${dest}"
        return 0
    fi

    mv "${tmpfile}" "${dest}"
    chmod 0644 "${dest}"
    log_success "herdr skill file installed: ${dest}"
}

# Write `<binary> --skill` to a reference file under references/.
# The TUI manual is a full skill with YAML front matter: it is required, so a
# truncated file is caught, then stripped, so the reference does not look like a
# second `herdr` skill. The herdr-core and herdr-app manuals are plain Markdown
# and must start with a heading. An empty or truncated file would leave the
# router pointing at nothing without any visible error.
write_reference() {
    local binary="$1"
    local name="$2"
    local has_frontmatter="$3"
    local dest="${REFERENCES_DIR}/${name}.md"
    local raw tmpfile
    raw="$(mktemp "${TMPDIR:-/tmp}/herdr-skill.XXXXXX")"
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/herdr-skill.XXXXXX")"

    if ! "${binary}" --skill > "${raw}"; then
        rm -f "${raw}" "${tmpfile}"
        log_error "${binary} --skill failed"
        return 1
    fi

    if [[ "${has_frontmatter}" == "yes" ]]; then
        if [[ ! -s "${raw}" ]] || [[ "$(head -n 1 "${raw}")" != "---" ]]; then
            rm -f "${raw}" "${tmpfile}"
            log_error "${binary} --skill produced no usable skill file"
            return 1
        fi
        # awk exits 1 when the front matter is never closed; an unclosed block
        # would otherwise strip the whole manual.
        if ! awk 'NR == 1 { inside = 1; next } inside && /^---$/ { inside = 0; next } !inside { print } END { exit inside }' "${raw}" > "${tmpfile}" \
            || ! grep -q '[^[:space:]]' "${tmpfile}"; then
            rm -f "${raw}" "${tmpfile}"
            log_error "${binary} --skill produced a skill file without a closed front matter or a body"
            return 1
        fi
    else
        if [[ ! -s "${raw}" ]] || [[ "$(head -n 1 "${raw}")" != "#"* ]]; then
            rm -f "${raw}" "${tmpfile}"
            log_error "${binary} --skill produced no usable manual"
            return 1
        fi
        cp "${raw}" "${tmpfile}"
    fi
    rm -f "${raw}"

    install_file "${tmpfile}" "${dest}"
}

# Remove the reference of a runtime that is no longer installed, so the router
# reports it as missing instead of serving a stale manual.
remove_reference() {
    local name="$1"
    local dest="${REFERENCES_DIR}/${name}.md"

    if [[ -f "${dest}" ]]; then
        rm -f "${dest}"
        log_info "Removed herdr skill reference for a runtime that is not installed: ${dest}"
    fi
}

# The Herdr app installs herdr-core only the first time it is opened, so a
# provisioning run before that cannot write the hc manual.
warn_missing_hc() {
    local runner="sjust"
    if ! command -v sjust &> /dev/null && command -v ajust &> /dev/null; then
        runner="ajust"
    fi
    log_warn "The Herdr app is installed but herdr-core (hc) is not, so the hc manual was not written."
    log_warn "Open the Herdr app once to install herdr-core, then run: ${runner} sf-herdr-skill-install"
}

write_router() {
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/herdr-skill.XXXXXX")"
    cp "${ROUTER_SOURCE}" "${tmpfile}"
    install_file "${tmpfile}" "${SKILL_FILE}"
}

write_skill() {
    local herdr_bin="$1"
    local hc_bin="$2"
    local herdr_app_bin="$3"

    if [[ -n "${herdr_bin}" ]]; then
        write_reference "${herdr_bin}" herdr-tui yes
    else
        remove_reference herdr-tui
    fi

    if [[ -n "${hc_bin}" ]]; then
        write_reference "${hc_bin}" hc no
    else
        remove_reference hc
    fi

    if [[ -n "${herdr_app_bin}" ]]; then
        write_reference "${herdr_app_bin}" herdr-app no
    else
        remove_reference herdr-app
    fi

    # The router goes last, so it never points at references still being written.
    write_router
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

# herdr can hook itself into each coding tool (a plugin for OpenCode, a hook for
# Claude Code, ...) so the pane shows whether the agent is working or idle. Those
# hooks are versioned. When herdr is updated, hooks already installed can fall
# behind and stop working, as happened with the OpenCode plugin on OpenCode 2.
# This function asks herdr which installed hooks are outdated and reinstalls
# only those. Missing hooks are installed only for DEFAULT_INTEGRATIONS below.
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

# Integrations installed by default when missing, so herdr can track and resume
# the agents the team uses. Every other integration stays opt-in.
DEFAULT_INTEGRATIONS=(claude codex)

# A tool counts as present when its binary is on PATH or its config directory
# exists. The directory check covers provisioning runs whose PATH lacks
# ~/.local/bin, where the native Claude Code installer puts its binary.
tool_present() {
    local name="$1"
    local config_dir
    case "${name}" in
        claude) config_dir="${HOME}/.claude" ;;
        codex) config_dir="${CODEX_HOME:-${HOME}/.codex}" ;;
        *) return 1 ;;
    esac
    command -v "${name}" &> /dev/null || [[ -d "${config_dir}" ]]
}

# Print every default integration that `herdr integration status` (read from
# stdin) reports as not installed and whose tool is present, one per line.
# SPARKDOCK_HERDR_DEFAULT_INTEGRATIONS=0 turns this off, so an integration the
# user removed is not installed again on the next run.
missing_default_integrations() {
    local line name default
    if [[ "${SPARKDOCK_HERDR_DEFAULT_INTEGRATIONS:-1}" == "0" ]]; then
        return 0
    fi
    while IFS= read -r line; do
        if [[ "${line}" != *": not installed"* ]]; then
            continue
        fi
        name="${line%%:*}"
        for default in "${DEFAULT_INTEGRATIONS[@]}"; do
            if [[ "${name}" == "${default}" ]] && tool_present "${name}"; then
                echo "${name}"
            fi
        done
    done
}

update_integrations() {
    local status_output
    if ! status_output="$(herdr integration status 2> /dev/null)"; then
        log_warn "herdr integration status failed, skipping integration refresh"
        return 0
    fi

    local outdated=()
    local missing=()
    local name
    while IFS= read -r name; do
        outdated+=("${name}")
    done < <(outdated_integrations <<< "${status_output}")
    while IFS= read -r name; do
        missing+=("${name}")
    done < <(missing_default_integrations <<< "${status_output}")

    if (( ${#outdated[@]} == 0 && ${#missing[@]} == 0 )); then
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

    for name in "${missing[@]}"; do
        if herdr integration install "${name}" > /dev/null 2>&1; then
            log_success "herdr integration installed: ${name}"
        else
            log_warn "herdr integration install ${name} failed"
        fi
    done
}

# --- Uninstall ---

unlink_skill() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        local link="${TOOL_SKILLS_DIR[${tool_id}]}/${SKILL_NAME}"
        if [[ -L "${link}" ]] && [[ "$(readlink "${link}")" == "${SKILL_DIR}" ]]; then
            rm -f "${link}"
            log_success "${TOOL_LABEL[${tool_id}]}: removed ${SKILL_NAME} symlink"
        fi
    done
}

# Remove only the files install writes, for a run that finds no Herdr runtime.
# Unlike uninstall, which the user asks for, this runs during provisioning, so
# it must never delete files the user added to the skill directory. The
# directory and its per-tool links go only when nothing else is left in it.
remove_installed_skill() {
    if [[ -L "${SKILL_DIR}" ]]; then
        log_warn "herdr skill is managed elsewhere (${SKILL_DIR} -> $(readlink "${SKILL_DIR}")), leaving it in place"
        return 0
    fi

    if [[ -d "${SKILL_DIR}" ]]; then
        rm -f "${SKILL_FILE}" \
            "${REFERENCES_DIR}/herdr-tui.md" \
            "${REFERENCES_DIR}/hc.md" \
            "${REFERENCES_DIR}/herdr-app.md"
        rmdir "${REFERENCES_DIR}" 2> /dev/null || true
        rmdir "${SKILL_DIR}" 2> /dev/null || true
    fi

    if [[ -e "${SKILL_DIR}" ]]; then
        log_warn "Removed the generated herdr skill files; kept ${SKILL_DIR} because it holds other files"
        return 0
    fi

    unlink_skill
    log_success "Removed herdr skill: ${SKILL_DIR}"
}

uninstall() {
    unlink_skill

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
            local herdr_bin hc_bin herdr_app_bin
            herdr_bin="$(command -v herdr 2> /dev/null || true)"
            hc_bin="$(find_hc)"
            herdr_app_bin="$(find_herdr_app)"
            # With no Herdr runtime left, a skill from an earlier run would route
            # agents to stale manuals, so remove the files install wrote.
            if [[ -z "${herdr_bin}" && -z "${hc_bin}" && -z "${herdr_app_bin}" ]]; then
                log_warn "None of herdr, hc or herdr-app is installed, removing any herdr skill left by an earlier run"
                remove_installed_skill
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
            write_skill "${herdr_bin}" "${hc_bin}" "${herdr_app_bin}"
            if [[ -n "${herdr_app_bin}" && -z "${hc_bin}" ]]; then
                warn_missing_hc
            fi
            link_skill
            # The integrations belong to the Herdr TUI.
            if [[ -n "${herdr_bin}" ]]; then
                update_integrations
            fi
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
