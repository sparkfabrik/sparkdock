#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/28-disk-space.sh — free space on the boot volume.
#
# The headline number, plus a pointer at whichever other check can actually
# recover space. This check deliberately does not try to find what is using the
# disk: dev-caches, docker-disk and apfs-snapshots already do that, each with the
# right command for its own bucket.
#
# One macOS subtlety it does handle: `df` on an APFS volume reports space shared
# across the whole container, and local snapshots hold space that shows up as
# neither a file nor free space. Purgeable space is why df and Finder disagree.
#
# Cheap: df is instantaneous.

# Free space below these is worth reporting.
_DISK_WARN_PCT=10
_DISK_WARN_GB=25

doctor_meta() {
    printf 'disk-space\tDisk space\tfree space on the boot volume, and what can reclaim it\tyes\tno\tno\n'
}

# The data volume is what fills up on APFS; / is a read-only system snapshot.
_disk_target() {
    if [[ -d /System/Volumes/Data ]]; then
        printf '/System/Volumes/Data'
    else
        printf '/'
    fi
}

doctor_detect() {
    local target row total_kb avail_kb pct_used
    target="$(_disk_target)"

    # -k for 1024-byte blocks, so the arithmetic is portable across df variants.
    # Only total and available are needed: used percentage is derived from them.
    row="$(df -k "${target}" 2>/dev/null | awk 'NR == 2 { print $2, $4 }' || true)"
    [[ -n "${row}" ]] || return 0

    read -r total_kb avail_kb <<<"${row}"
    [[ -n "${avail_kb}" ]] || return 0

    local avail_gb total_gb pct_free
    avail_gb="$(python3 -c 'import sys; print("%.0f" % (float(sys.argv[1]) / 1048576))' "${avail_kb}")"
    total_gb="$(python3 -c 'import sys; print("%.0f" % (float(sys.argv[1]) / 1048576))' "${total_kb}")"
    pct_free="$(python3 -c '
import sys
total, avail = float(sys.argv[1]), float(sys.argv[2])
print("%.0f" % (avail / total * 100 if total else 0))
' "${total_kb}" "${avail_kb}")"
    pct_used=$((100 - pct_free))

    if [[ "${pct_free}" -le "${_DISK_WARN_PCT}" || "${avail_gb}" -le "${_DISK_WARN_GB}" ]]; then
        doctor_finding warn "boot volume" \
            "${avail_gb} GB free of ${total_gb} GB (${pct_used}% used)" \
            "sjust macos-doctor dev-caches docker-disk apfs-snapshots"
    else
        doctor_finding info "boot volume" \
            "${avail_gb} GB free of ${total_gb} GB (${pct_used}% used)" ""
    fi

    # Purgeable space is the usual reason df and Finder disagree, and local
    # snapshots are the usual reason purgeable space is large.
    local snaps
    snaps="$(tmutil listlocalsnapshots / 2>/dev/null | grep -c TimeMachine || true)"
    if [[ "${snaps:-0}" -gt 0 ]]; then
        doctor_note "${snaps} local snapshot(s) also hold space that df counts as neither"
        doctor_note "free nor a file. See: sjust macos-doctor apfs-snapshots"
    fi
    doctor_note "This check reports the total only. What is using the space is covered by"
    doctor_note "dev-caches, docker-disk and apfs-snapshots, each with its own command."
}

doctor_explain() {
    cat <<'MD'
Reports free space on the boot volume, and points at whichever other check can
recover some.

On APFS it measures `/System/Volumes/Data` rather than `/`, because `/` is a
read-only system snapshot and its figures are not what fills up.

A `warn` is raised below 10% free **or** below 25 GB free, whichever comes first.
Both matter: 10% of a 4 TB disk is still plenty, and 25 GB is tight regardless of
percentage because macOS needs headroom for updates and swap.

It deliberately does not try to work out what is using the disk. `dev-caches`,
`docker-disk` and `apfs-snapshots` already do that, each naming the command that
reclaims its own bucket, and duplicating that logic here would just mean two
places to keep in sync.

When local snapshots exist, the finding says so. They hold space that `df` counts
as neither a file nor free space, which is the usual reason `df` and Finder
disagree about how full a disk is.

Cheap, so it runs on every `sparkdock tui` dashboard refresh.
MD
}
