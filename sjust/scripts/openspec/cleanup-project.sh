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

if [[ -n "${mode}" && "${mode}" != "dry-run" ]]; then
    log_error "Unknown argument '${mode}'. Usage: cleanup-project.sh [dry-run]"
    exit 1
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || root="${PWD}"

# OpenSpec only writes into these subdirectories of the tool config folders.
# Constraining the search here keeps unrelated files that merely share the
# name prefix (e.g. .github/workflows/openspec-review.yml) out of reach.
search_dirs=()
for base in .claude .opencode .github; do
    for sub in skills commands command prompts; do
        if [[ -d "${root}/${base}/${sub}" ]]; then
            search_dirs+=("${root}/${base}/${sub}")
        fi
    done
done

targets=()
if [[ ${#search_dirs[@]} -gt 0 ]]; then
    mapfile -d '' -t targets < <(find "${search_dirs[@]}" \
        -mindepth 1 \( -iname 'openspec*' -o -iname 'opsx*' \) -prune -print0 2>/dev/null || true)
fi

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

# Prune only the directories the removal touched, so pre-existing empty
# folders elsewhere are left alone.
declare -A pruned
for target in "${targets[@]}"; do
    parent="$(dirname "${target}")"
    if [[ -z "${pruned[${parent}]:-}" ]]; then
        pruned[${parent}]=1
        find "${parent}" -depth -type d -empty -delete 2>/dev/null || true
    fi
done

log_success "Removed ${#targets[@]} OpenSpec component(s)."
