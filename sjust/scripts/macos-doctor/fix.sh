#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/macos-doctor/fix.sh — apply one check's fix, with confirmation.
#
# Usage: fix.sh <check-id> [mode] [scope]
#   <check-id>  the single check to fix. There is deliberately no fix-all.
#   mode        apply (default) or dry-run. A dry run prints every mutation it
#               would make and changes nothing, so a destructive fix can always
#               be previewed before it is trusted.
#   scope       system, to also act on root-owned paths under /Library. Without
#               it only user-owned paths are touched and root-owned findings are
#               listed for a second, explicit run.
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
mode="${2:-apply}"
scope="${3:-}"

if [[ -z "${check_id}" ]]; then
    log_error "a check id is required. Usage: sjust macos-doctor-fix <check-id> [dry-run] [system]"
    exit 2
fi

# "system" in the mode slot is a natural mistake, so accept it there rather than
# rejecting a command that clearly means what it says.
if [[ "${mode}" == "system" && -z "${scope}" ]]; then
    scope="system"
    mode="apply"
fi

case "${mode}" in
    apply | dry-run) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: apply (default), dry-run."
        exit 2
        ;;
esac

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
trap 'rm -f "${MDOC_FINDINGS_FILE}" "${MDOC_NOTES_FILE}"' EXIT

if [[ "${mode}" == "dry-run" ]]; then
    log_section "Sparkdock macOS doctor · dry run · ${title}"
else
    log_section "Sparkdock macOS doctor · fix · ${title}"
fi

# Every terminal path below prints a MACOS_DOCTOR_STATUS line on stdout. Logging
# goes to stderr, so stdout is all a caller can parse: a path that exits without
# one leaves a script with nothing to key on, which is exactly how the CI check
# for this script first broke.

if ! mdoc_run_detect "${check_file}" "${id}"; then
    log_error "${id}: detect failed, refusing to fix."
    printf 'MACOS_DOCTOR_STATUS: fix=detect-failed check=%s mode=%s\n' "${id}" "${mode}"
    exit 1
fi

if [[ "$(mdoc_severity_count)" -eq 0 ]]; then
    log_success "Nothing to fix: ${id} reports no findings."
    printf 'MACOS_DOCTOR_STATUS: fix=nothing check=%s mode=%s\n' "${id}" "${mode}"
    exit 0
fi

# --- Show what the fix will actually touch ------------------------------------
#
# Not the findings. A check's findings and its fix targets differ: dev-caches
# reports every cache directory but deletes only the regenerable subset, and
# launchd-orphans reports root-owned plists but skips them without the system
# scope. Confirming against the wrong list makes the prompt a rubber stamp.

targets="$(mdoc_fix_targets "${check_file}" "${id}" "${scope}")"

if [[ -z "${targets}" ]]; then
    log_success "Nothing for ${id} to act on."
    log_info "It reports findings, but none of them are things this fix removes."
    log_info "See what it does and does not touch: sjust macos-doctor-info ${id}"
    printf 'MACOS_DOCTOR_STATUS: fix=nothing check=%s mode=%s\n' "${id}" "${mode}"
    exit 0
fi

if [[ "${mode}" == "dry-run" ]]; then
    log_info "These are the only things this fix acts on:"
else
    log_warn "These will be removed:"
fi
printf '\n'
render_table <<<"TARGET"$'\t'"DETAIL"$'\n'"${targets}"
printf '\n'

# --- Confirm -----------------------------------------------------------------
#
# A dry run mutates nothing, so it asks nothing. Skipping straight to the apply
# block with MDOC_DRY_RUN set means the preview walks exactly the same code path
# the real run would, which is the only way a preview is worth trusting.

if [[ "${mode}" == "dry-run" ]]; then
    log_info "Dry run: nothing will be changed."
elif [[ "${reversible}" == "yes" ]]; then
    log_info "Affected paths are moved to ${MDOC_QUARANTINE_ROOT} and can be restored with 'sjust macos-doctor-undo restore'."
    if ! mdoc_confirm "Apply the fix for ${id}?"; then
        log_info "Cancelled."
        printf 'MACOS_DOCTOR_STATUS: fix=cancelled check=%s mode=%s\n' "${id}" "${mode}"
        exit 0
    fi
else
    log_warn "This fix is NOT reversible. What it removes cannot be recovered by 'sjust macos-doctor-undo'."
    if ! mdoc_confirm "Apply the irreversible fix for ${id}?"; then
        log_info "Cancelled."
        printf 'MACOS_DOCTOR_STATUS: fix=cancelled check=%s mode=%s\n' "${id}" "${mode}"
        exit 0
    fi
    if ! mdoc_confirm "Confirm again: permanently remove what was listed above?"; then
        log_info "Cancelled."
        printf 'MACOS_DOCTOR_STATUS: fix=cancelled check=%s mode=%s\n' "${id}" "${mode}"
        exit 0
    fi
fi

# --- Lock --------------------------------------------------------------------
#
# flock is not present on every supported host, so its absence is tolerated
# rather than fatal (it is in config/packages/all-packages.yml, but a machine may
# predate that).

if [[ "${mode}" == "apply" ]] && command -v flock >/dev/null 2>&1; then
    mkdir -p "$(dirname "${MDOC_LOCK_FILE}")"
    exec 9>"${MDOC_LOCK_FILE}"
    if ! flock -n 9; then
        log_error "Another macos-doctor fix is in progress (lock: ${MDOC_LOCK_FILE})."
        printf 'MACOS_DOCTOR_STATUS: fix=locked check=%s mode=%s\n' "${id}" "${mode}"
        exit 1
    fi
fi

# --- Apply -------------------------------------------------------------------

quarantine_dir=""
if [[ "${reversible}" == "yes" && "${mode}" == "apply" ]]; then
    quarantine_dir="$(mdoc_quarantine_new)"
    log_info "Quarantine: ${quarantine_dir}"
fi

printf '\n'

dry_run=0
[[ "${mode}" == "dry-run" ]] && dry_run=1

rc=0
(
    export MDOC_CURRENT_CHECK="${id}"
    export MDOC_QUARANTINE_DIR="${quarantine_dir}"
    export MDOC_DRY_RUN="${dry_run}"
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
    log_error "${id}: ${mode} reported errors (exit ${rc})."
    printf 'MACOS_DOCTOR_STATUS: fix=failed check=%s mode=%s\n' "${id}" "${mode}"
    exit "${rc}"
fi

printf '\n'

if [[ "${mode}" == "dry-run" ]]; then
    log_success "Dry run complete. Nothing was changed."
    log_info "Apply it with: sjust macos-doctor-fix ${id}$([[ "${scope}" == "system" ]] && printf ' apply system')"
    printf 'MACOS_DOCTOR_STATUS: fix=dry-run check=%s\n' "${id}"
    exit 0
fi

log_success "Applied the fix for ${id}."
if [[ "${reversible}" == "yes" ]]; then
    log_info "Undo it with: sjust macos-doctor-undo restore"
fi
log_info "Re-run 'sjust macos-doctor ${id}' to confirm."
printf 'MACOS_DOCTOR_STATUS: fix=applied check=%s reversible=%s\n' "${id}" "${reversible}"
