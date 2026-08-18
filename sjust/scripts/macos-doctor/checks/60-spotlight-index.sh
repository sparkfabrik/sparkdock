#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/60-spotlight-index.sh — Spotlight indexing scope and footprint.
#
# Two things go wrong with Spotlight on a development machine. It indexes
# container and VM directories, which churn constantly and produce millions of
# pointless index updates. And mds_stores holds on to a large resident footprint
# after a heavy indexing run without releasing it.
#
# Report-only: changing indexing scope with mdutil needs sudo and is a policy
# decision about what you want searchable.

# mds_stores resident size worth mentioning, in kilobytes (about 1.5 GB).
_SI_WARN_KB=1572864

# Path fragments that should not normally be indexed on a dev machine.
_SI_SUSPECT_FRAGMENTS=(
    'Library/Containers'
    'Docker'
    'containers'
    '.docker'
    'colima'
    'lima'
    'OrbStack'
)

doctor_meta() {
    printf 'spotlight-index\tSpotlight index\tindexing scope and mds_stores footprint\tyes\tno\tno\n'
}

doctor_detect() {
    command -v mdutil >/dev/null 2>&1 || return 0

    # --- Volumes with indexing enabled ---------------------------------------
    local volumes
    volumes="$(mdutil -sa 2>/dev/null || true)"
    if [[ -n "${volumes}" ]]; then
        local vol frag
        # mdutil -sa prints a volume path line, then an indented state line.
        while IFS= read -r vol; do
            [[ "${vol}" == /* ]] || continue
            vol="${vol%:}"
            for frag in "${_SI_SUSPECT_FRAGMENTS[@]}"; do
                if [[ "${vol}" == *"${frag}"* ]]; then
                    doctor_finding warn "${vol}" \
                        "indexed volume looks like a container or VM store" \
                        "sudo mdutil -i off '${vol}'"
                    break
                fi
            done
        done <<<"${volumes}"
    fi

    # --- mds_stores footprint ------------------------------------------------
    local pid kb
    pid="$(pgrep -x mds_stores | head -1 || true)"
    [[ -n "${pid}" ]] || return 0

    kb="$(ps -o rss= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    [[ -n "${kb}" ]] || return 0

    if [[ "${kb}" -ge "${_SI_WARN_KB}" ]]; then
        doctor_finding info "mds_stores" \
            "$(python3 -c 'import sys; print("%.1f GB" % (float(sys.argv[1]) / 1048576))' "${kb}") resident" \
            "harmless if CPU is idle; sudo mdutil -E / rebuilds the index"
    fi
}

doctor_explain() {
    cat <<'MD'
Two Spotlight facts.

**Indexing scope.** Reads `mdutil -sa` and flags any indexed volume whose path
looks like a container or VM store (`Library/Containers`, Docker, colima, lima,
OrbStack). Those directories churn constantly, so indexing them produces a large
volume of pointless index updates and I/O for search results nobody wants.

**mds_stores footprint.** Reports the resident size when it is at or above roughly
1.5 GB. This is `info`, not a fault: after a heavy indexing run mds_stores can
hold a large footprint while sitting at 0% CPU, and that memory is reclaimable
under pressure. It is worth knowing when you are accounting for where RAM went.

Report-only. Changing indexing scope needs sudo and is a policy decision about
what you want searchable, not something a diagnostic should decide. If the index
is genuinely corrupt, `sudo mdutil -E /` erases and rebuilds it.
MD
}
