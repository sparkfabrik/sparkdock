#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/macos-doctor/undo.sh — list or restore quarantine snapshots.
#
# Usage: undo.sh [<action>]
#   (no argument)  list available snapshots (the safe default, mutates nothing)
#   list           same as no argument
#   restore        restore the newest snapshot
#   <timestamp>    restore that specific snapshot directory
#
# Only fixes from checks declaring reversible=yes produce a snapshot. An
# irreversible fix has nothing to restore, by construction.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
mdoc_require_macos

action="${1:-}"

if [[ ! -d "${MDOC_QUARANTINE_ROOT}" ]]; then
    log_error "No quarantine directory at ${MDOC_QUARANTINE_ROOT}"
    log_info "Nothing has been quarantined on this machine yet."
    exit 1
fi

# Ascending (oldest first) so "${snapshots[-1]}" is the newest.
mapfile -t snapshots < <(find "${MDOC_QUARANTINE_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "${#snapshots[@]}" -eq 0 ]]; then
    log_error "No snapshots available."
    exit 1
fi

# --- List (default) ----------------------------------------------------------

if [[ -z "${action}" || "${action}" == "list" ]]; then
    log_section "Quarantine snapshots (oldest to newest)"

    tsv="SNAPSHOT"$'\t'"PATHS"$'\t'"CHECKS"$'\n'
    for snapshot in "${snapshots[@]}"; do
        manifest="${snapshot}/manifest.tsv"
        if [[ -f "${manifest}" ]]; then
            count="$(awk 'END { print NR + 0 }' "${manifest}")"
            checks="$(cut -f1 "${manifest}" | sort -u | paste -sd, -)"
        else
            count="?"
            checks="?"
        fi
        tsv+="${snapshot##*/}"$'\t'"${count}"$'\t'"${checks}"$'\n'
    done
    render_table <<<"${tsv%$'\n'}"

    if [[ -L "${MDOC_QUARANTINE_ROOT}/latest" ]]; then
        mdoc_faint "latest -> $(readlink "${MDOC_QUARANTINE_ROOT}/latest")"
    fi

    printf '\n'
    log_info "To restore, run one of:"
    log_info "  sjust macos-doctor-undo restore"
    log_info "  sjust macos-doctor-undo ${snapshots[-1]##*/}"
    exit 0
fi

# --- Restore -----------------------------------------------------------------

if [[ "${action}" == "restore" ]]; then
    target="${snapshots[-1]}"
else
    target="${MDOC_QUARANTINE_ROOT}/${action}"
    if [[ ! -d "${target}" ]]; then
        log_error "No snapshot named '${action}' under ${MDOC_QUARANTINE_ROOT}"
        exit 1
    fi
fi

target_name="${target##*/}"
log_section "Restoring quarantine snapshot ${target_name}"

if [[ -f "${target}/manifest.tsv" ]]; then
    tsv="CHECK"$'\t'"PATH"$'\n'
    while IFS=$'\t' read -r check_id _label path _needed_sudo; do
        [[ -n "${path}" ]] || continue
        tsv+="${check_id}"$'\t'"${path}"$'\n'
    done <"${target}/manifest.tsv"
    render_table <<<"${tsv%$'\n'}"
    printf '\n'
fi

if ! mdoc_confirm "Restore these paths?"; then
    log_info "Cancelled."
    exit 0
fi

mdoc_quarantine_restore "${target}"

# An emptied snapshot has nothing left to restore; drop it so the listing stays
# meaningful. A partial restore keeps its snapshot and its manifest.
if [[ -d "${target}/files" ]] && [[ -z "$(find "${target}/files" -type f -print -quit)" ]]; then
    rm -rf "${target}"
    if [[ "$(readlink "${MDOC_QUARANTINE_ROOT}/latest" 2>/dev/null)" == "${target_name}" ]]; then
        rm -f "${MDOC_QUARANTINE_ROOT}/latest"
    fi
    log_info "Snapshot ${target_name} is empty and was removed."
fi

log_success "Restored snapshot ${target_name}."
printf 'MACOS_DOCTOR_STATUS: undo=restored snapshot=%s\n' "${target_name}"
