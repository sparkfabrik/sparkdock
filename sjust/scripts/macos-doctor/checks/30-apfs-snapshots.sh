#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/30-apfs-snapshots.sh — local APFS (Time Machine) snapshots eating disk.
#
# Time Machine keeps local snapshots on the boot volume so you can restore
# without the backup drive attached. They are useful, and they are also a common
# silent consumer of tens of gigabytes, because the space they hold does not show
# up as any file you can find.
#
# Deleting a snapshot cannot be undone, so this check declares reversible=no and
# fix.sh asks twice.

# Snapshots kept without comment. macOS keeps roughly one per hour for 24 hours,
# so a handful is normal and a large pile means Time Machine has not thinned them.
_TM_WARN_COUNT=8

doctor_meta() {
    printf 'apfs-snapshots\tLocal APFS snapshots\tlocal Time Machine snapshots holding disk space\tyes\tyes\tno\n'
}

# Print one snapshot name per line.
_tm_list() {
    command -v tmutil >/dev/null 2>&1 || return 0
    tmutil listlocalsnapshots / 2>/dev/null | grep -E '^com\.apple\.TimeMachine\.' || true
}

doctor_detect() {
    local -a snaps
    mapfile -t snaps < <(_tm_list)

    local count="${#snaps[@]}"
    [[ "${count}" -gt 0 ]] || return 0

    # Names embed the creation date: com.apple.TimeMachine.2026-08-18-120000.local
    local oldest newest
    oldest="$(printf '%s\n' "${snaps[@]}" | sort | head -1)"
    newest="$(printf '%s\n' "${snaps[@]}" | sort | tail -1)"
    oldest="${oldest#com.apple.TimeMachine.}"
    oldest="${oldest%.local}"
    newest="${newest#com.apple.TimeMachine.}"
    newest="${newest%.local}"

    if [[ "${count}" -lt "${_TM_WARN_COUNT}" ]]; then
        doctor_finding info "local snapshots" \
            "${count} snapshot(s), oldest ${oldest}" ""
        return 0
    fi

    doctor_finding cruft "local snapshots" \
        "${count} snapshot(s), ${oldest} to ${newest}" \
        "sjust macos-doctor-fix apfs-snapshots"
}

doctor_fix() {
    local -a snaps
    mapfile -t snaps < <(_tm_list)
    [[ "${#snaps[@]}" -gt 0 ]] || {
        log_info "No local snapshots to delete."
        return 0
    }

    local snap name rc=0
    for snap in "${snaps[@]}"; do
        name="${snap#com.apple.TimeMachine.}"
        name="${name%.local}"
        mdoc_would "delete local snapshot ${name} (permanent)" && continue
        if sudo tmutil deletelocalsnapshots "${name}" >/dev/null 2>&1; then
            log_success "deleted snapshot ${name}"
        else
            log_warn "failed to delete snapshot ${name}"
            rc=1
        fi
    done
    return "${rc}"
}

doctor_explain() {
    cat <<'MD'
Counts local APFS snapshots on the boot volume via `tmutil listlocalsnapshots /`.

Time Machine keeps these so you can restore without the backup drive attached.
They are genuinely useful, and they are also a common silent consumer of disk
space, because the bytes they hold belong to no file you can locate.

Fewer than 8 is reported as `info` only, since macOS normally keeps roughly one
per hour for a day. More than that means thinning has not been keeping up.

The fix deletes every listed snapshot with `sudo tmutil deletelocalsnapshots`.
This **cannot be undone**: a deleted snapshot is not recoverable, and quarantine
does not apply to it. That is why the check declares `reversible=no` and the fix
asks for confirmation twice.

Deleting local snapshots does not affect backups already written to a Time
Machine destination.
MD
}
