#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/macos-doctor/fix.sh — apply one check's fix, with confirmation.
#
# Usage: fix.sh <check-id> [system]
#   <check-id>  the single check to fix. There is deliberately no fix-all.
#   system      also act on root-owned paths under /Library. Without it, only
#               user-owned paths are touched and root-owned findings are listed
#               for a second, explicit run.
#
# Two safety properties are worth stating plainly.
#
# A check declaring reversible=yes moves things into a quarantine snapshot that
# `sjust macos-doctor-undo` can restore. A check declaring reversible=no deletes
# something that cannot be recreated, so it asks a second time and says so.
#
# The detect pass runs first and its findings are what gets fixed. Nothing is
# fixed that was not just shown to the user.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
mdoc_require_macos

check_id="${1:-}"
scope="${2:-}"

if [[ -z "${check_id}" ]]; then
    log_error "a check id is required. Usage: sjust macos-doctor-fix <check-id> [system]"
    exit 2
fi

case "${scope}" in
    "" | system) ;;
    *)
        log_error "unknown scope '${scope}'. Valid: system (or omit)."
        exit 2
        ;;
esac

check_file=""
if ! check_file="$(mdoc_file_for_id "${check_id}")"; then
    log_error "unknown check '${check_id}'. Run 'sjust macos-doctor-info' to list them."
    exit 2
fi

IFS=$'\t' read -r id title _summary _cheap fixable reversible < <(mdoc_meta "${check_file}")

if [[ "${fixable}" != "yes" ]]; then
    log_error "${id} has no automated fix."
    log_info "Run 'sjust macos-doctor ${id}' and follow the commands it prints."
    exit 2
fi

# --- Detect first: the fix only ever acts on findings just shown -------------

mdoc_findings_init
trap 'rm -f "${MDOC_FINDINGS_FILE}"' EXIT

log_section "macOS doctor · fix · ${title}"

if ! mdoc_run_detect "${check_file}" "${id}"; then
    log_error "${id}: detect failed, refusing to fix."
    exit 1
fi

if [[ "$(mdoc_severity_count)" -eq 0 ]]; then
    log_success "Nothing to fix: ${id} reports no findings."
    exit 0
fi

mdoc_render_findings "${id}"
printf '\n'

# --- Confirm -----------------------------------------------------------------

if [[ "${reversible}" == "yes" ]]; then
    log_info "Affected paths are moved to ${MDOC_QUARANTINE_ROOT} and can be restored with 'sjust macos-doctor-undo restore'."
    if ! mdoc_confirm "Apply the fix for ${id}?"; then
        log_info "Cancelled."
        exit 0
    fi
else
    log_warn "This fix is NOT reversible. What it removes cannot be recovered by 'sjust macos-doctor-undo'."
    if ! mdoc_confirm "Apply the irreversible fix for ${id}?"; then
        log_info "Cancelled."
        exit 0
    fi
    if ! mdoc_confirm "Confirm again: permanently remove what was listed above?"; then
        log_info "Cancelled."
        exit 0
    fi
fi

# --- Lock --------------------------------------------------------------------
#
# flock is not present on every supported host, so its absence is tolerated
# rather than fatal (it is in config/packages/all-packages.yml, but a machine may
# predate that).

if command -v flock >/dev/null 2>&1; then
    mkdir -p "$(dirname "${MDOC_LOCK_FILE}")"
    exec 9>"${MDOC_LOCK_FILE}"
    if ! flock -n 9; then
        log_error "Another macos-doctor fix is in progress (lock: ${MDOC_LOCK_FILE})."
        exit 1
    fi
fi

# --- Apply -------------------------------------------------------------------

quarantine_dir=""
if [[ "${reversible}" == "yes" ]]; then
    quarantine_dir="$(mdoc_quarantine_new)"
    log_info "Quarantine: ${quarantine_dir}"
fi

rc=0
(
    export MDOC_CURRENT_CHECK="${id}"
    export MDOC_QUARANTINE_DIR="${quarantine_dir}"
    export MDOC_SCOPE="${scope}"
    # shellcheck source=/dev/null
    source "${check_file}"
    doctor_fix
) || rc=$?

if [[ -n "${quarantine_dir}" ]]; then
    if [[ -s "${quarantine_dir}/manifest.tsv" ]]; then
        mdoc_quarantine_publish_latest "${quarantine_dir}"
        mdoc_prune_quarantine
    else
        # Nothing was moved, so an empty snapshot would just be noise in the
        # undo listing.
        rm -rf "${quarantine_dir}"
        log_info "Nothing was quarantined."
    fi
fi

if [[ "${rc}" -ne 0 ]]; then
    log_error "${id}: fix reported errors (exit ${rc})."
    printf 'MACOS_DOCTOR_STATUS: fix=failed check=%s\n' "${id}"
    exit "${rc}"
fi

log_success "Applied the fix for ${id}."
log_info "Re-run 'sjust macos-doctor ${id}' to confirm."
printf 'MACOS_DOCTOR_STATUS: fix=applied check=%s reversible=%s\n' "${id}" "${reversible}"
