#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/70-docker-disk.sh — reclaimable Docker disk space.
#
# Report-only by design. `sjust system-cleanup` already owns the prune, and
# duplicating a destructive operation in two places is how the two drift apart.
# This check surfaces the number and names the command that acts on it.

# Reclaimable bytes worth reporting (about 5 GB).
_DD_WARN_BYTES=5368709120

doctor_meta() {
    printf 'docker-disk\tDocker disk usage\treclaimable space held by images, containers and build cache\tno\tno\tno\n'
}

doctor_detect() {
    command -v docker >/dev/null 2>&1 || return 0

    # A stopped daemon is not a finding: Docker Desktop is often deliberately off.
    if ! docker system df --format '{{json .}}' >/dev/null 2>&1; then
        return 0
    fi

    local total_reclaimable=0 line
    while IFS=$'\t' read -r line; do
        [[ -n "${line}" ]] || continue
        total_reclaimable=$((total_reclaimable + line))
    done < <(
        docker system df --format '{{json .}}' 2>/dev/null | python3 -c '
import json, re, sys

UNITS = {"B": 1, "KB": 10**3, "MB": 10**6, "GB": 10**9, "TB": 10**12,
         "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}

def to_bytes(text):
    # Reclaimable looks like "8.104GB (94%)" or "0B".
    m = re.match(r"\s*([0-9.]+)\s*([A-Za-z]+)", text or "")
    if not m:
        return 0
    try:
        return int(float(m.group(1)) * UNITS.get(m.group(2).upper(), 1))
    except ValueError:
        return 0

for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        row = json.loads(raw)
    except Exception:
        continue
    print(to_bytes(row.get("Reclaimable")))
'
    )

    [[ "${total_reclaimable}" -ge "${_DD_WARN_BYTES}" ]] || return 0

    doctor_finding info "docker" \
        "$(python3 -c 'import sys; print("%.1f GB" % (float(sys.argv[1]) / 1e9))' "${total_reclaimable}") reclaimable" \
        "sjust system-cleanup"
}

doctor_explain() {
    cat <<'MD'
Sums the `RECLAIMABLE` column from `docker system df` across images, containers,
volumes and build cache, and reports it once the total is at or above roughly
5 GB.

A stopped Docker daemon is not reported. Docker Desktop being off is a normal
state, not a fault.

Report-only on purpose. `sjust system-cleanup` already runs `brew cleanup` and
`docker system prune -f` behind its own confirmation, and duplicating a
destructive operation in two places is how the two versions drift apart. This
check gives you the number and points at the command that acts on it.

Note that `docker system prune` removes stopped containers, dangling images,
unused networks and unused build cache. It does not remove named volumes unless
you ask it to, but it is still not reversible.
MD
}
