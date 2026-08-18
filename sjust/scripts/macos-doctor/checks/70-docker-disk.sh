#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/70-docker-disk.sh — reclaimable Docker disk space, broken down by type.
#
# The breakdown is the whole point. `docker system df` reports one Reclaimable
# figure per type, and the command that reclaims each one is different:
#
#   Images        `docker system prune -f` removes only DANGLING images. Unused
#                 but tagged images, which is usually the bulk of it, need
#                 `docker image prune -a`.
#   Build Cache   removed by `docker system prune -f`.
#   Containers    stopped containers are removed by `docker system prune -f`.
#   Local Volumes NOT touched by `docker system prune -f` at all. Needs
#                 `--volumes`, and that deletes data, not cache.
#
# An earlier version of this check summed all four and pointed at
# `sjust system-cleanup`, which runs `docker system prune -f`. On a real machine
# that reported 40 GB reclaimable and recovered almost none of it, because the
# bulk sat in unused-but-tagged images and in volumes. Reporting a number next to
# a command that does not reclaim it is worse than reporting nothing.

# Report a type once its reclaimable size reaches this many bytes (about 1 GB).
_DD_WARN_BYTES=1073741824

doctor_meta() {
    printf 'docker-disk\tDocker disk usage\treclaimable space per type, with the command that reclaims each\tno\tno\tno\n'
}

doctor_detect() {
    command -v docker >/dev/null 2>&1 || return 0

    # A stopped daemon is not a finding: Docker Desktop is often deliberately off.
    if ! docker system df --format '{{json .}}' >/dev/null 2>&1; then
        return 0
    fi

    local reported=0 volumes_seen=0
    local kind human bytes total active

    while IFS=$'\t' read -r kind human bytes total active; do
        [[ -n "${kind}" ]] || continue
        [[ "${bytes}" -ge "${_DD_WARN_BYTES}" ]] || continue
        reported=$((reported + 1))

        case "${kind}" in
            Images)
                doctor_finding info "images" \
                    "${human} reclaimable (${active} of ${total} in use)" \
                    "docker image prune -a"
                ;;
            "Build Cache")
                doctor_finding info "build cache" \
                    "${human} reclaimable (${total} entries)" \
                    "docker builder prune"
                ;;
            Containers)
                doctor_finding info "stopped containers" \
                    "${human} reclaimable (${active} of ${total} running)" \
                    "docker container prune"
                ;;
            "Local Volumes")
                volumes_seen=1
                doctor_finding warn "volumes" \
                    "${human} in ${total} volume(s), ${active} in use, holds DATA not cache" \
                    "inspect first: docker volume ls"
                ;;
            *)
                doctor_finding info "${kind}" "${human} reclaimable" ""
                ;;
        esac
    done < <(
        docker system df --format '{{json .}}' 2>/dev/null | python3 -c '
import json, re, sys

UNITS = {"B": 1, "KB": 10**3, "MB": 10**6, "GB": 10**9, "TB": 10**12,
         "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}

def to_bytes(text):
    # Reclaimable looks like "27.52GB (58%)" or "0B".
    m = re.match(r"\s*([0-9.]+)\s*([A-Za-z]+)", text or "")
    if not m:
        return 0
    try:
        return int(float(m.group(1)) * UNITS.get(m.group(2).upper(), 1))
    except ValueError:
        return 0

def human(text):
    # Keep the size docker printed, minus its percentage suffix.
    return re.sub(r"\s*\(.*\)\s*$", "", (text or "").strip()) or "0B"

for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        row = json.loads(raw)
    except Exception:
        continue
    rec = row.get("Reclaimable")
    print("\t".join([
        str(row.get("Type") or "?"),
        human(rec),
        str(to_bytes(rec)),
        str(row.get("TotalCount") or "?"),
        str(row.get("Active") or "?"),
    ]))
'
    )

    [[ "${reported}" -gt 0 ]] || return 0

    doctor_note "Each row above names the command that actually reclaims it."
    doctor_note "\`sjust system-cleanup\` runs \`docker system prune -f\`, which removes only"
    doctor_note "dangling images, stopped containers and unused build cache. It does not"
    doctor_note "remove unused-but-tagged images, and it never removes volumes."
    if [[ "${volumes_seen}" -eq 1 ]]; then
        doctor_note ""
        doctor_note "Volumes hold application data (databases, uploads). Removing one is not a"
        doctor_note "cache eviction, so list them and decide per volume rather than pruning."
    fi
}

doctor_explain() {
    cat <<'MD'
Reports reclaimable Docker space **per type**, because the command that reclaims
each type is different and conflating them is misleading.

| type | reclaimed by |
| --- | --- |
| Images (dangling only) | `docker system prune -f` |
| Images (unused but tagged) | `docker image prune -a` |
| Stopped containers | `docker system prune -f` |
| Build cache | `docker system prune -f` or `docker builder prune` |
| Local volumes | nothing above; needs `--volumes`, and that deletes data |

An earlier version summed all four into one figure and pointed at
`sjust system-cleanup`. On a real machine that read 40 GB while the cleanup
recovered almost none of it, because the bulk sat in unused-but-tagged images and
in volumes. That is why the breakdown exists.

Volumes are reported as `warn` rather than `info`, and with no prune command
attached. A volume holds application data such as a database or uploaded files.
Removing one is not a cache eviction, so the remedy is to list them and decide
per volume.

A stopped Docker daemon produces no findings: Docker Desktop being off is a
normal state, not a fault.

Report-only. Every command it names is destructive to some degree, and which
images or volumes you still want is a judgement this check cannot make.
MD
}
