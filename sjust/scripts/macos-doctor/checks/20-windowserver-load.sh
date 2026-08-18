#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/20-windowserver-load.sh — WindowServer burning CPU while the screen is idle.
#
# WindowServer serialises input-event dispatch and frame compositing on one
# thread, so anything that makes that thread slow shows up as laggy scrolling and
# stuttering animations even when nothing looks busy.
#
# The measurement matters as much as the threshold. `ps` reports %CPU as an
# average decayed over the whole process lifetime, so for a process that has been
# alive for days it says almost nothing about right now. A real delta of the
# cumulative CPU time over a wall-clock window is the only honest reading, and it
# is what this check does.
#
# Above the threshold, the remedy is the stack-sampling recipe that finds the
# actual cause. The event-tap variant of that recipe found a real bug: an input
# remapper was re-injecting events through a virtual HID device, building a tap
# chain roughly 500 hops deep that the main thread walked for every event, idle
# or not.

# Seconds to measure over. Long enough to be meaningful, short enough to tolerate
# in an interactive run. This is why the check is not cheap.
_WS_WINDOW=10

# Percent of one core. An idle WindowServer normally sits between 1 and 5.
_WS_WARN_PCT=15

doctor_meta() {
    printf 'windowserver-load\tWindowServer CPU\tWindowServer CPU measured as a real delta, not ps %%CPU\tno\tno\tno\n'
}

# Print WindowServer's CPU percentage over _WS_WINDOW seconds, or nothing.
_ws_measure() {
    local pid t0 t1
    pid="$(pgrep -x WindowServer | head -1 || true)"
    [[ -n "${pid}" ]] || return 0

    t0="$(ps -o time= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "${t0}" ]] || return 0
    sleep "${_WS_WINDOW}"
    t1="$(ps -o time= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "${t1}" ]] || return 0

    python3 -c '
import sys

def secs(t):
    parts = t.split(":")
    out = float(parts[-1]) + 60 * int(parts[-2])
    if len(parts) > 2:
        out += 3600 * int(parts[-3])
    return out

a, b, window = sys.argv[1], sys.argv[2], float(sys.argv[3])
print("%.1f" % ((secs(b) - secs(a)) / window * 100))
' "${t0}" "${t1}" "${_WS_WINDOW}"
}

doctor_detect() {
    local pct
    pct="$(_ws_measure)"

    if [[ -z "${pct}" ]]; then
        doctor_finding info "WindowServer" "not running or not measurable" ""
        return 0
    fi

    # Integer comparison: bash has no floats.
    if [[ "${pct%.*}" -lt "${_WS_WARN_PCT}" ]]; then
        return 0
    fi

    doctor_finding warn "WindowServer" \
        "${pct}% of one core while idle (normal is 1-5%), causes scroll and animation lag" \
        "sjust macos-doctor-info windowserver-load"

    # Say what this means and what the next step is, in prose. The sampling recipe
    # itself lives in doctor_explain: it is five lines of shell that nobody can
    # read from a report, and printing it here buried the actual finding.
    doctor_note "This is felt as jerky scrolling, because WindowServer dispatches input"
    doctor_note "events and composites frames on the same thread."
    doctor_note ""
    doctor_note "The cause is a third-party program, and identifying which one needs a"
    doctor_note "stack sample. The command above prints the recipe plus how to read it."
    doctor_note "It is read-only and needs sudo."
}

doctor_explain() {
    cat <<'MD'
Measures WindowServer's CPU as a real delta over a 10 second wall-clock window.

This check exists because `ps` reports `%CPU` as an average decayed over the
process lifetime. On a WindowServer that has been alive for a week it can read
under 1% while the process is actually burning 50%, which sends you looking in
the wrong place.

Above 15% of one core with an idle screen it reports a `warn` and sends you here.
The cause is always a third-party program, and identifying which one needs a
stack sample. This is read-only and needs sudo:

```bash
sudo sample WindowServer 5 -file /tmp/ws.txt
R=$(grep -nE '^ +[0-9]+ Thread_' /tmp/ws.txt | sed -n '1p;2p' | cut -d: -f1 | paste -sd' ' -)
set -- $R
awk -v a="$1" -v b="$2" 'NR>a && NR<b' /tmp/ws.txt | grep -c add_event_vector_to_tap
```

Note the line range comes from the sample file itself. Thread boundaries move
between captures, so a range copied from an earlier sample silently reports zero.

Reading the result:

- **Hundreds of `add_event_vector_to_tap` frames** means an input event tap chain.
  Every input event walks it on the same thread that composites frames, which is
  why the symptom is jerky scrolling. Suspect input remappers that re-inject
  events through a virtual HID device, since those re-enter the chain instead of
  adding one hop.
- **Time in `CGXUpdateDisplay` with deep `CA::OGL::ImagingNode::render` nesting**
  means compositing, typically nested backdrop blur. Check for terminal or editor
  windows configured with a background blur.
- **Mostly `mach_msg2_trap`** means the main thread is idle and the cost is on
  another thread.

There is no automated fix: the cause is always a third-party program, and which
one is a judgement call.
MD
}
