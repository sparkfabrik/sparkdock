# shellcheck shell=bash
# bin/common/logging.sh — Shared logging helpers with optional gum integration
#
# Provides: log_info, log_success, log_warn, log_error, log_section,
#           run_with_spinner, print_summary_box
#
# When gum is available, uses it for styled output; falls back to plain ANSI.
# Compatible with both bash and zsh.
#
# Usage (from bin/ scripts):
#   source "$(dirname "${BASH_SOURCE[0]}")/common/logging.sh"
# Usage (from bin/common/ scripts like utils.sh):
#   source "$(dirname "${BASH_SOURCE[0]:-$0}")/logging.sh"

# Guard against double-sourcing
if [[ "${_SPARKDOCK_LOGGING_LOADED:-}" = "1" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
_SPARKDOCK_LOGGING_LOADED=1

# --- Colors and formatting ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Gum detection (once) ---

HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# --- Logging functions ---

log_info() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum log --level info "$1"
    else
        printf "${BOLD}${BLUE}[INFO]${NC} %s\n" "$1"
    fi
}

log_success() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum log --level info --prefix "  OK" "$1"
    else
        printf "${BOLD}${GREEN}[ OK ]${NC} %s\n" "$1"
    fi
}

log_warn() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum log --level warn "$1"
    else
        printf "${BOLD}${YELLOW}[WARN]${NC} %s\n" "$1"
    fi
}

log_error() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum log --level error "$1"
    else
        printf "${BOLD}${RED}[FAIL]${NC} %s\n" "$1"
    fi
}

log_section() {
    if [[ "${HAS_GUM}" = true ]]; then
        echo ""
        gum style --border double --border-foreground 99 --bold --padding "0 2" --margin "0 0 1 0" "$1"
    else
        echo ""
        printf "${BOLD}${BLUE}=== %s ===${NC}\n" "$1"
    fi
}

# --- Higher-level helpers ---

# Run a command with a gum spinner (falls back to plain log + execution)
run_with_spinner() {
    local title="$1"
    shift
    if [[ "${HAS_GUM}" = true ]]; then
        gum spin --spinner dot --title "${title}" -- "$@"
    else
        log_info "${title}"
        "$@"
    fi
}

# Display a styled summary box (single content argument)
print_summary_box() {
    local content="$1"
    if [[ "${HAS_GUM}" = true ]]; then
        echo ""
        echo "${content}" | gum style \
            --border normal \
            --border-foreground 99 \
            --padding "1 2" \
            --margin "0 1" \
            --bold
    else
        echo ""
        local first_line
        first_line="$(echo "${content}" | head -1)"
        printf "${BOLD}=== %s ===${NC}\n" "${first_line}"
        echo "${content}" | tail -n +2
    fi
}
