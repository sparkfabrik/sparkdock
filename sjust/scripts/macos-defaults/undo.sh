#!/usr/bin/env bash
set -euo pipefail
#
# Restore a per-key snapshot taken by a previous `sjust macos-defaults` apply.
# Only the keys sparkdock managed are touched — unrelated user changes in the
# same preference domain are NOT rolled back.
#
# Usage: undo.sh [<action>]
#   (none)             restore the latest snapshot
#   list               print available snapshots, no mutation
#   <timestamp>        restore the snapshot directory matching this name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
md_require_macos_version

action="${1:-}"

if [[ ! -d "${MD_SNAPSHOTS_ROOT}" ]]; then
    log_error "No snapshots directory at ${MD_SNAPSHOTS_ROOT}"
    exit 1
fi

mapfile -t snapshots < <(
    find "${MD_SNAPSHOTS_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort
)

if [[ ${#snapshots[@]} -eq 0 ]]; then
    log_error "No snapshots available."
    exit 1
fi

if [[ "${action}" == "list" ]]; then
    log_section "Available snapshots (oldest → newest)"
    for s in "${snapshots[@]}"; do
        ts="$(basename "${s}")"
        if [[ -f "${s}/snapshot.tsv" ]]; then
            keys_count="$(wc -l < "${s}/snapshot.tsv" | tr -d ' ')"
        else
            keys_count="?"
        fi
        printf '  %s  (%s key(s))\n' "${ts}" "${keys_count}"
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
