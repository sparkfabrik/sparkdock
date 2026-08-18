#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/20-cpu-load.sh — sustained CPU load and the processes causing it.
#
# The measurement method matters more than the thresholds. `ps` and `top` report
# %CPU as an average decayed over each process's lifetime, so a process alive for
# a week can read near zero while it is in fact saturating a core, and a process
# that started a second ago can read absurdly high. Neither tells you what is
# happening now.
#
# This check instead samples cumulative CPU time twice and divides the difference
# by elapsed wall-clock time. That is the only reading that answers "what is
# eating the CPU right now", which is why it is worth the sampling window.
#
# Not cheap, for exactly that reason: it has to wait.

# Seconds to sample over. Long enough to be meaningful, short enough to tolerate.
_CPU_WINDOW=5

# Load average per core. Above 1.0 the machine has more runnable work than cores.
_CPU_LOAD_WARN=2.0

# A single process above this percentage of one core is worth naming.
_CPU_PROC_WARN=50

# Processes expected to be busy, which are not findings in themselves. A build or
# a container runtime using CPU is the machine doing its job.
_CPU_EXPECTED='^(kernel_task|WindowServer|Xcode|clang|swift|go|node|java|docker|com\.docker\..*|qemu.*|rustc|cargo|ld|python3\.[0-9]+)$'

doctor_meta() {
    printf 'cpu-load\tCPU load\tsustained load average and the processes actually using CPU\tno\tno\tno\n'
}

# Print "<percent>\t<command>" for the busiest processes, measured as a real delta.
_cpu_top() {
    python3 - "${_CPU_WINDOW}" <<'PY'
import subprocess, sys, time


def snapshot():
    out = subprocess.run(
        ["ps", "-axo", "pid=,time=,comm="],
        capture_output=True, text=True,
    ).stdout
    seen = {}
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        pid, cputime, comm = parts
        bits = cputime.split(":")
        try:
            secs = float(bits[-1]) + 60 * int(bits[-2])
            if len(bits) > 2:
                secs += 3600 * int(bits[-3])
        except (ValueError, IndexError):
            continue
        seen[pid] = (secs, comm.split("/")[-1])
    return seen


window = float(sys.argv[1])
first = snapshot()
started = time.monotonic()
time.sleep(window)
second = snapshot()
elapsed = time.monotonic() - started

rows = []
for pid, (secs, comm) in second.items():
    if pid not in first:
        continue
    pct = (secs - first[pid][0]) / elapsed * 100
    if pct >= 1.0:
        rows.append((pct, comm))

# Collapse the multi-process apps (browser and Electron helpers) so one app does
# not fill the table with a dozen near-identical rows.
totals = {}
for pct, comm in rows:
    totals[comm] = totals.get(comm, 0.0) + pct

for comm, pct in sorted(totals.items(), key=lambda kv: -kv[1])[:8]:
    print("%.1f\t%s" % (pct, comm))
PY
}

doctor_detect() {
    # --- Load average --------------------------------------------------------
    local cores loadavg one
    cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
    loadavg="$(sysctl -n vm.loadavg 2>/dev/null || true)"
    # vm.loadavg looks like "{ 5.32 3.53 2.87 }".
    one="$(printf '%s' "${loadavg}" | awk '{ print $2 }')"

    if [[ -n "${one}" ]]; then
        local per_core
        per_core="$(python3 -c '
import sys
load, cores = float(sys.argv[1]), max(int(sys.argv[2]), 1)
print("%.2f" % (load / cores))
' "${one}" "${cores}" 2>/dev/null || true)"

        if [[ -n "${per_core}" ]]; then
            # Integer compare: bash has no floats, and the fraction does not matter
            # for a threshold this coarse.
            if [[ "${per_core%.*}" -ge "${_CPU_LOAD_WARN%.*}" ]]; then
                doctor_finding warn "load average" \
                    "${one} across ${cores} cores (${per_core} per core), machine is oversubscribed" \
                    ""
            else
                doctor_finding info "load average" \
                    "${one} across ${cores} cores (${per_core} per core)" ""
            fi
        fi
    fi

    # --- Who is actually using CPU -------------------------------------------
    local pct comm shown=0
    while IFS=$'\t' read -r pct comm; do
        [[ -n "${pct}" ]] || continue
        shown=$((shown + 1))

        if [[ "${pct%.*}" -ge "${_CPU_PROC_WARN}" ]] && ! [[ "${comm}" =~ ${_CPU_EXPECTED} ]]; then
            doctor_finding warn "${comm}" "${pct}% of one core over ${_CPU_WINDOW}s" ""
        else
            doctor_finding info "${comm}" "${pct}% of one core over ${_CPU_WINDOW}s" ""
        fi
    done < <(_cpu_top)

    [[ "${shown}" -gt 0 ]] || return 0

    doctor_note "Percentages are a real delta over ${_CPU_WINDOW}s, not the lifetime average"
    doctor_note "that ps and top report, so they reflect the last ${_CPU_WINDOW} seconds only."
    doctor_note "Multi-process apps are summed, so one browser can exceed 100%."
}

doctor_explain() {
    cat <<'MD'
Reports the one-minute load average per core, and the processes actually using CPU
right now.

**How it measures, and why that matters.** `ps` and `top` report `%CPU` as an
average decayed over each process's whole lifetime. A process alive for a week can
read under 1% while saturating a core, and one that started a second ago can read
several hundred percent. This check samples cumulative CPU time twice, 5 seconds
apart, and divides by elapsed wall-clock time. That is the only reading that
answers what is busy now, and it is why the check is not cheap: it has to wait.

Percentages are per core, so 100% means one core fully used. Multi-process
applications are summed under one name, so a browser with a dozen renderers
appears once and can legitimately exceed 100%.

Thresholds:

- Load average at or above 2.0 per core is a `warn`: there is more runnable work
  than cores, so everything is waiting.
- A single process at or above 50% of one core is a `warn`, unless it is something
  expected to be busy (compilers, container runtimes, `kernel_task`,
  `WindowServer`). A build using CPU is the machine doing its job.

Report-only. What to do about a busy process depends entirely on what it is.
MD
}
