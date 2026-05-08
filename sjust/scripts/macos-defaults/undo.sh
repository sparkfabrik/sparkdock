#!/usr/bin/env bash
set -euo pipefail
#
# Restore a snapshot taken by a previous `sjust macos-defaults` apply.
# Usage: undo.sh [<action>]
#   (none)             restore the latest snapshot
#   list               print available snapshots, no mutation
#   <timestamp>        restore the snapshot directory matching this name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

action="${1:-}"

if [[ ! -d "${MD_SNAPSHOTS_ROOT}" ]]; then
    log_error "No snapshots directory at ${MD_SNAPSHOTS_ROOT}"
    exit 1
fi

mapfile -t snapshots < <(
    find "${MD_SNAPSHOTS_ROOT}" -mindepth 1 -maxdepth 1 -type d -not -name "latest" \
        | sort
)

if [[ ${#snapshots[@]} -eq 0 ]]; then
    log_error "No snapshots available."
    exit 1
fi

if [[ "${action}" == "list" ]]; then
    log_section "Available snapshots (oldest → newest)"
    for s in "${snapshots[@]}"; do
        ts="$(basename "${s}")"
        domains_count="$(wc -l < "${s}/manifest.txt" 2>/dev/null | tr -d ' ' || printf '?')"
        printf '  %s  (%s domain(s))\n' "${ts}" "${domains_count}"
    done
    if [[ -L "${MD_SNAPSHOTS_ROOT}/latest" ]]; then
        latest="$(readlink "${MD_SNAPSHOTS_ROOT}/latest" 2>/dev/null || true)"
        [[ -n "${latest}" ]] && printf '\nlatest → %s\n' "${latest}"
    fi
    exit 0
fi

if [[ -n "${action}" ]]; then
    target="${MD_SNAPSHOTS_ROOT}/${action}"
    if [[ ! -d "${target}" ]]; then
        log_error "No snapshot directory named '${action}' under ${MD_SNAPSHOTS_ROOT}"
        exit 1
    fi
else
    target="${snapshots[-1]}"
fi

target_name="$(basename "${target}")"
log_info "Restoring snapshot: ${target_name}"
md_restore "${target}"

echo
log_success "Restored snapshot ${target_name}."
