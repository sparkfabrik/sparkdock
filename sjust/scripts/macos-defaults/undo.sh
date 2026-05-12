#!/usr/bin/env bash
set -euo pipefail
#
# Restore a per-key snapshot taken by a previous `sjust macos-defaults` apply.
# Only the keys sparkdock managed are touched — unrelated user changes in the
# same preference domain are NOT rolled back.
#
# Usage: undo.sh [<action>]
#   (none)             list available snapshots (safe, no mutation)
#   restore            restore the latest snapshot
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

if [[ -z "${action}" || "${action}" == "list" ]]; then
    log_section "Available snapshots (oldest → newest)"
    for s in "${snapshots[@]}"; do
        ts="$(basename "${s}")"
        if [[ -f "${s}/snapshot.tsv" ]]; then
            keys_count="$(wc -l < "${s}/snapshot.tsv" | tr -d ' ')"
        else
            keys_count="?"
        fi
        printf '  %s  (%s key(s))  %s\n' "${ts}" "${keys_count}" "${s}"
    done
    if [[ -L "${MD_SNAPSHOTS_ROOT}/latest" ]]; then
        latest="$(readlink "${MD_SNAPSHOTS_ROOT}/latest" 2>/dev/null || true)"
        [[ -n "${latest}" ]] && printf '\nlatest → %s\n' "${latest}"
    fi
    echo
    log_info "To restore a snapshot run:"
    echo "  sjust macos-defaults-undo restore            # restore latest"
    echo "  sjust macos-defaults-undo <timestamp>         # restore a specific one"
    exit 0
fi

if [[ "${action}" == "restore" ]]; then
    target="${snapshots[-1]}"
else
    target="${MD_SNAPSHOTS_ROOT}/${action}"
    if [[ ! -d "${target}" ]]; then
        log_error "No snapshot directory named '${action}' under ${MD_SNAPSHOTS_ROOT}"
        exit 1
    fi
fi

target_name="$(basename "${target}")"
log_info "Restoring snapshot: ${target_name}"
md_restore "${target}"

echo
log_success "Restored snapshot ${target_name}."
