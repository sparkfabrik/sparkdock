#!/usr/bin/env bash
set -euo pipefail

# Remove OpenSpec-managed tool components (skills, commands, prompts) from
# .claude, .opencode and .github in the current repository. The openspec/
# folder at the repository root is never touched.
# Covers current layouts (skills/openspec-*, commands/opsx, prompts/opsx-*)
# and legacy ones (commands/openspec, command/opsx-*, prompts/openspec-*).
# Usage: cleanup-project.sh [dry-run]
#   dry-run  — only list what would be removed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

mode="${1:-}"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="${PWD}"

mapfile -d '' -t targets < <(find "${root}/.claude" "${root}/.opencode" "${root}/.github" \
    -mindepth 2 \( -iname 'openspec*' -o -iname 'opsx*' \) -prune -print0 2>/dev/null || true)

if [[ ${#targets[@]} -eq 0 ]]; then
    log_info "No OpenSpec components found in .claude, .opencode or .github."
    exit 0
fi

printf '%s\n' "${targets[@]}"

if [[ "${mode}" == "dry-run" ]]; then
    log_info "Dry run: nothing removed."
    exit 0
fi

rm -rf -- "${targets[@]}"
find "${root}/.claude" "${root}/.opencode" "${root}/.github" \
    -depth -mindepth 1 -type d -empty -delete 2>/dev/null || true
log_success "Removed ${#targets[@]} OpenSpec component(s)."
