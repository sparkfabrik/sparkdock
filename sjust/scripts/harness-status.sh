#!/usr/bin/env bash
set -euo pipefail

# sjust/scripts/harness-status.sh — Show status of AI agent token harness tools.
#
# Displays a unified dashboard of installed harness tools (RTK, caveman, etc.),
# their per-agent integration status, and token savings metrics.
#
# Extensible: to add a new tool, define _<tool>_type, _<tool>_version,
# _<tool>_active, _<tool>_gain, _<tool>_agents functions and append to HARNESS_TOOLS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../libs/libshell.sh
source "${SCRIPT_DIR}/../libs/libshell.sh"

# --- Registry ---

HARNESS_TOOLS=(rtk caveman)
AGENTS=(claude copilot opencode)

# --- RTK functions ---

_rtk_type() { echo "input"; }

_rtk_version() {
    if command -v rtk &>/dev/null; then
        rtk --version 2>/dev/null | awk '{print $2}'
    else
        echo ""
    fi
}

_rtk_active() {
    command -v rtk &>/dev/null
}

_rtk_gain() {
    if ! command -v rtk &>/dev/null; then
        echo "not installed"
        return
    fi

    local json
    json="$(rtk gain --format json 2>/dev/null)" || { echo "gain data unavailable"; return; }

    if ! command -v python3 &>/dev/null; then
        echo "gain data unavailable (python3 not found)"
        return
    fi

    local tokens_saved reduction_pct commands_count
    tokens_saved="$(printf '%s' "${json}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tokens_saved', d.get('total_tokens_saved', 0)))" 2>/dev/null)" || tokens_saved="0"
    reduction_pct="$(printf '%s' "${json}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reduction_pct', d.get('total_reduction_pct', 0)))" 2>/dev/null)" || reduction_pct="0"
    commands_count="$(printf '%s' "${json}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('commands_count', d.get('total_commands', 0)))" 2>/dev/null)" || commands_count="0"

    if [[ "${tokens_saved}" == "0" || -z "${tokens_saved}" ]]; then
        echo "No data yet — run some rtk commands to start tracking"
        return
    fi

    printf "Tokens saved: %s  │  Reduction: %s%%  │  Commands: %s" \
        "${tokens_saved}" "${reduction_pct}" "${commands_count}"
}

_rtk_agents() {
    local -A result=()
    result[claude]="—"
    result[copilot]="—"
    result[opencode]="—"

    # Claude: check for rtk hook in settings.json
    local claude_settings="${HOME}/.claude/settings.json"
    if [[ -f "${claude_settings}" ]] && grep -q "rtk" "${claude_settings}" 2>/dev/null; then
        result[claude]="ok"
    fi

    # Copilot: check for RTK MANAGED BLOCK in instructions
    local copilot_instructions="${HOME}/.copilot/copilot-instructions.md"
    if [[ -f "${copilot_instructions}" ]] && grep -q "RTK MANAGED BLOCK" "${copilot_instructions}" 2>/dev/null; then
        result[copilot]="ok"
    fi

    # OpenCode: check for rtk plugin or RTK MANAGED BLOCK in AGENTS.md
    local opencode_plugin="${HOME}/.config/opencode/plugins/rtk.ts"
    local opencode_agents="${HOME}/.config/opencode/AGENTS.md"
    if [[ -f "${opencode_plugin}" ]] || \
       { [[ -f "${opencode_agents}" ]] && grep -q "RTK MANAGED BLOCK" "${opencode_agents}" 2>/dev/null; }; then
        result[opencode]="ok"
    fi

    # Print space-separated values in AGENTS order
    local out=""
    for agent in "${AGENTS[@]}"; do
        out+="${result[${agent}]} "
    done
    echo "${out% }"
}

# --- Caveman functions ---

_caveman_type() { echo "output"; }

_caveman_version() {
    local caveman_dir="${HOME}/.cache/sparkdock/caveman"
    if [[ -d "${caveman_dir}/.git" ]]; then
        git -C "${caveman_dir}" log -1 --format="%h" 2>/dev/null || echo "unknown"
        return
    fi
    # Caveman may be configured without the git cache present
    if [[ -f "${HOME}/.config/caveman/config.json" ]]; then
        echo "unknown"
        return
    fi
    echo ""
}

_caveman_active() {
    [[ -f "${HOME}/.config/caveman/config.json" ]]
}

_caveman_gain() {
    local config="${HOME}/.config/caveman/config.json"
    if [[ ! -f "${config}" ]]; then
        echo "not configured"
        return
    fi

    local mode
    if command -v python3 &>/dev/null; then
        mode="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('defaultMode', 'unknown'))" < "${config}" 2>/dev/null)" || mode="unknown"
    else
        mode="unknown"
    fi

    local estimate=""
    case "${mode}" in
        lite)  estimate="~25%" ;;
        full)  estimate="~50%" ;;
        ultra) estimate="~75%" ;;
        *)     estimate="unknown" ;;
    esac

    printf "Mode: %s  │  Est. output reduction: %s  │  (session-level only)" \
        "${mode}" "${estimate}"
}

_caveman_agents() {
    local -A result=()
    result[claude]="—"
    result[copilot]="—"
    result[opencode]="—"

    # Claude: check for caveman hook in settings.json
    local claude_settings="${HOME}/.claude/settings.json"
    if [[ -f "${claude_settings}" ]] && grep -q "caveman" "${claude_settings}" 2>/dev/null; then
        result[claude]="ok"
    fi

    # Copilot: check for CAVEMAN MANAGED BLOCK or caveman-begin in instructions
    local copilot_instructions="${HOME}/.copilot/copilot-instructions.md"
    if [[ -f "${copilot_instructions}" ]] && \
       grep -q "CAVEMAN MANAGED BLOCK\|caveman-begin" "${copilot_instructions}" 2>/dev/null; then
        result[copilot]="ok"
    fi

    # OpenCode: check for caveman plugin directory
    local opencode_plugin_dir="${HOME}/.config/opencode/plugins/caveman"
    if [[ -d "${opencode_plugin_dir}" ]]; then
        result[opencode]="ok"
    fi

    # Print space-separated values in AGENTS order
    local out=""
    for agent in "${AGENTS[@]}"; do
        out+="${result[${agent}]} "
    done
    echo "${out% }"
}

# --- OpenSpec functions ---

# Per-tool skills directories (mirrors bin/common/skills-symlink-shim.sh).
declare -A OPENSPEC_TOOL_SKILLS_DIR=(
    [claude]="${HOME}/.claude/skills"
    [copilot]="${HOME}/.copilot/skills"
    [opencode]="${HOME}/.config/opencode/skills"
)

# Per-tool prompt/command directories where OpenSpec installs opsx prompts.
declare -A OPENSPEC_TOOL_CMD_DIR=(
    [claude]="${HOME}/.claude/commands/opsx"
    [copilot]="${HOME}/.copilot/prompts/opsx"
    [opencode]="${HOME}/.config/opencode/command/opsx"
)

_openspec_version() {
    if command -v openspec &>/dev/null; then
        openspec --version 2>&1 | head -1
    else
        echo ""
    fi
}

# Count openspec-* skill directories installed under a tool's skills dir.
_openspec_skill_count() {
    local dir="$1"
    local count=0 d
    for d in "${dir}"/openspec-*/; do
        [[ -d "${d}" ]] && count=$((count + 1))
    done
    echo "${count}"
}

# Count opsx command/prompt files installed under a tool's command dir.
_openspec_cmd_count() {
    local dir="$1"
    local count=0 f
    for f in "${dir}"/*.md; do
        [[ -f "${f}" ]] && count=$((count + 1))
    done
    echo "${count}"
}

# --- Output formatting ---

_print_header() {
    local title="AI Agent Harness — Token Optimization Stack"
    if [[ "${HAS_GUM}" = true ]]; then
        echo ""
        gum style --border double --border-foreground 99 --bold --padding "0 2" --margin "0 0 1 0" "${title}"
    else
        echo ""
        printf "${BOLD}${BLUE}=== %s ===${NC}\n\n" "${title}"
    fi
}

_print_section() {
    local title="$1"
    if [[ "${HAS_GUM}" = true ]]; then
        gum style --bold --foreground 99 "${title}"
    else
        printf "\n${BOLD}%s${NC}\n" "${title}"
    fi
}

_render_tool_table() {
    local SEP=$'\t'
    local header="TOOL${SEP}TYPE${SEP}VERSION${SEP}STATUS"
    for agent in "${AGENTS[@]}"; do
        header+="${SEP}$(echo "${agent}" | tr '[:lower:]' '[:upper:]')"
    done

    local rows=""
    local any_present=false

    for tool in "${HARNESS_TOOLS[@]}"; do
        local version type status agent_cols

        version="$("_${tool}_version")"
        type="$("_${tool}_type")"

        if [[ -z "${version}" ]]; then
            status="✗ not installed"
            version="—"
            agent_cols=""
            for _ in "${AGENTS[@]}"; do
                agent_cols+="${SEP}—"
            done
        else
            any_present=true
            if "_${tool}_active"; then
                status="✓ active"
            else
                status="✗ inactive"
            fi

            local agent_values_str agent_arr
            agent_values_str="$("_${tool}_agents")"
            IFS=' ' read -ra agent_arr <<< "${agent_values_str}"
            agent_cols=""
            for val in "${agent_arr[@]}"; do
                agent_cols+="${SEP}${val}"
            done
        fi

        rows+="${tool}${SEP}${type}${SEP}${version}${SEP}${status}${agent_cols}"$'\n'
    done

    local csv_data="${header}"$'\n'"${rows%$'\n'}"

    local table_output
    table_output="$(render_table <<< "${csv_data}")"

    # Colorize status markers
    if command -v perl &>/dev/null; then
        printf '%s\n' "${table_output}" | perl -pe '
            s/✓ active/\e[38;5;40m✓ active\e[0m/g;
            s/✗ not installed/\e[2m✗ not installed\e[0m/g;
            s/✗ inactive/\e[38;5;220m✗ inactive\e[0m/g;
            s/\bok\b/\e[38;5;40mok\e[0m/g;
        '
    else
        printf '%s\n' "${table_output}"
    fi

    if [[ "${any_present}" = false ]]; then
        echo ""
        log_warn "No harness tools detected. Install with:"
        log_info "  RTK:     brew install rtk && sjust sf-rtk-setup"
        log_info "  Caveman: sjust sf-caveman-install"
        return 1
    fi
    return 0
}

_render_gain_section() {
    _print_section "Token Savings"
    echo ""

    for tool in "${HARNESS_TOOLS[@]}"; do
        local version
        version="$("_${tool}_version")"
        [[ -z "${version}" ]] && continue

        local gain
        gain="$("_${tool}_gain")"
        printf "  %s: %s\n" "${tool}" "${gain}"
    done
}

_render_commands_section() {
    _print_section "Deep Dive Commands"
    echo ""

    local dim='' reset=''
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        dim=$'\033[2m'
        reset=$'\033[0m'
    fi

    if command -v rtk &>/dev/null; then
        printf "  %srtk gain%s              Input savings breakdown\n" "${dim}" "${reset}"
        printf "  %srtk gain --graph%s      Daily savings chart\n" "${dim}" "${reset}"
    fi
    printf "  %s/caveman-stats%s        In-session output stats\n" "${dim}" "${reset}"
    echo ""
}

_render_openspec_section() {
    local version
    version="$(_openspec_version)"

    _print_section "OpenSpec — Spec-Driven Workflow"
    echo ""

    if [[ -z "${version}" ]]; then
        printf "  CLI: ✗ not installed  (brew install openspec)\n\n"
        return
    fi

    local project_state="✗ not initialized"
    [[ -d "${HOME}/openspec" ]] && project_state="✓ ~/openspec"
    printf "  CLI: ✓ %s  │  Global project: %s\n" "${version}" "${project_state}"

    local agent
    for agent in "${AGENTS[@]}"; do
        local count cmd_count
        count="$(_openspec_skill_count "${OPENSPEC_TOOL_SKILLS_DIR[${agent}]}")"
        cmd_count="$(_openspec_cmd_count "${OPENSPEC_TOOL_CMD_DIR[${agent}]}")"
        if [[ "${count}" -gt 0 || "${cmd_count}" -gt 0 ]]; then
            printf "    %-9s skills: %s  │  commands: %s\n" "${agent}" "${count}" "${cmd_count}"
        else
            printf "    %-9s —\n" "${agent}"
        fi
    done

    echo ""
    local dim='' reset=''
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        dim=$'\033[2m'
        reset=$'\033[0m'
    fi
    printf "  %sInstall/update: sjust sf-openspec-install-global [tools]%s\n\n" "${dim}" "${reset}"
}

# --- Main ---

main() {
    _print_header
    if _render_tool_table; then
        _render_gain_section
        echo ""
        _render_commands_section
    fi

    # Show skills + agent profiles (the other half of the harness)
    local agents_status="${SCRIPT_DIR}/../../bin/sparkdock-agents-status"
    if [[ -x "${agents_status}" ]]; then
        "${agents_status}"
    fi

    # Show OpenSpec spec-driven workflow status (CLI + global skills/prompts)
    _render_openspec_section
}

main "$@"
