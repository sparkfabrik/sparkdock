#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/25-memory-pressure.sh — memory pressure and the processes holding memory.
#
# "Used memory" on macOS is close to meaningless on its own. The kernel fills all
# available RAM with file cache and compressed pages by design, so a healthy
# machine reports almost no free memory and that is correct. Reading `top` and
# concluding you are out of RAM is one of the easiest mistakes to make.
#
# The signals that do mean something:
#
#   swap used       the kernel ran out of options and went to disk. This is the
#                   one that correlates with the machine feeling slow.
#   swapins/outs    whether swap is being actively churned rather than just
#                   allocated once and left alone.
#   free percentage what memory_pressure reports, which accounts for reclaimable
#                   pages instead of counting them as used.
#
# Cheap: every reading here is instantaneous.

# Swap in use worth reporting, in megabytes.
_MEM_SWAP_WARN_MB=1024

# memory_pressure free percentage at or below this is a warn.
_MEM_FREE_WARN_PCT=15

doctor_meta() {
    printf 'memory-pressure\tMemory pressure\tswap use and free percentage, not the misleading "used" figure\tyes\tno\tno\n'
}

doctor_detect() {
    # --- Swap ----------------------------------------------------------------
    local swap used_mb total_mb
    swap="$(sysctl -n vm.swapusage 2>/dev/null || true)"
    if [[ -n "${swap}" ]]; then
        # "total = 2048.00M  used = 512.00M  free = 1536.00M"
        total_mb="$(printf '%s' "${swap}" | sed -nE 's/.*total = ([0-9.]+)M.*/\1/p')"
        used_mb="$(printf '%s' "${swap}" | sed -nE 's/.*used = ([0-9.]+)M.*/\1/p')"

        if [[ -n "${used_mb}" ]]; then
            if [[ "${used_mb%.*}" -ge "${_MEM_SWAP_WARN_MB}" ]]; then
                doctor_finding warn "swap" \
                    "${used_mb}M in use of ${total_mb:-?}M, the machine has run out of RAM headroom" \
                    "sjust macos-doctor cpu-load   # see what is holding it"
            elif [[ "${used_mb%.*}" -gt 0 ]]; then
                doctor_finding info "swap" "${used_mb}M in use of ${total_mb:-?}M" ""
            fi
        fi
    fi

    # --- Free percentage, as the kernel accounts it --------------------------
    local free_pct
    free_pct="$(memory_pressure 2>/dev/null |
        sed -nE 's/.*free percentage: ([0-9]+)%.*/\1/p' | tail -1 || true)"

    if [[ -n "${free_pct}" ]]; then
        if [[ "${free_pct}" -le "${_MEM_FREE_WARN_PCT}" ]]; then
            doctor_finding warn "memory pressure" \
                "${free_pct}% free system-wide, under real pressure" ""
        else
            doctor_finding info "memory pressure" "${free_pct}% free system-wide" ""
        fi
    fi

    # --- Top holders ---------------------------------------------------------
    #
    # RSS double-counts shared memory across the processes of one app, so these
    # figures are an upper bound rather than a footprint. Said plainly in a note
    # below rather than silently overstating.
    local gb comm
    while IFS=$'\t' read -r gb comm; do
        [[ -n "${gb}" ]] || continue
        doctor_finding info "${comm}" "${gb} GB resident" ""
    done < <(
        ps -axo rss=,comm= 2>/dev/null | awk '
            {
                name = $2
                sub(/.*\//, "", name)
                total[name] += $1
            }
            END {
                for (n in total) if (total[n] > 1048576) printf "%.1f\t%s\n", total[n] / 1048576, n
            }
        ' | sort -rn | head -5
    )

    doctor_note "macOS fills spare RAM with cache by design, so a low free figure is"
    doctor_note "normal and \"used memory\" on its own says little. Swap in use is the"
    doctor_note "signal that actually correlates with the machine feeling slow."
    doctor_note "Resident sizes are summed per app name and count shared memory once"
    doctor_note "per process, so treat them as an upper bound, not a footprint."
}

doctor_explain() {
    cat <<'MD'
Reports swap use, the free percentage as the kernel accounts it, and the apps
holding the most resident memory.

**Why not just report used memory.** macOS deliberately fills spare RAM with file
cache and compressed pages, so a healthy machine shows almost no free memory. On
one real machine `top` showed 47 GB of 48 GB used while `memory_pressure` reported
89% free and swap was completely untouched, because roughly 20 GB of that was
reclaimable cache. Reading the first number and concluding the machine is out of
RAM is the easy mistake this check exists to avoid.

What it reports instead:

- **Swap in use.** This is the signal that correlates with the machine feeling
  slow, because it means the kernel ran out of options and went to disk. Over
  1 GB is a `warn`, any non-zero amount is `info`.
- **Free percentage from `memory_pressure`**, which accounts for reclaimable pages
  rather than counting them as used. At or below 15% is a `warn`.
- **The five largest resident apps**, summed per app name.

Resident size double-counts memory shared between the processes of one
application, so a browser with many renderers reads high. Treat those figures as
an upper bound rather than a true footprint.

Cheap, so it runs on every `sparkdock tui` dashboard refresh: every reading here
is instantaneous.
MD
}
