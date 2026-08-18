#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/10-launchd-orphans.sh — launchd jobs whose target program is gone.
#
# Detection requires TWO independent signals, because either one alone is wrong.
#
# Signal 1: launchctl reports the job as not running with a non-zero last exit
# status. On its own this catches every job that merely failed once, including
# jobs killed by jetsam or by the user.
#
# Signal 2: the program the plist points at does not exist on disk. On its own
# this is defeated by a shell wrapper. A real example: Podman Desktop's agent had
# ProgramArguments[0] = /bin/bash, which exists, with the actual binary buried in
# the -c string. A check keying on ProgramArguments[0] calls that healthy.
#
# When the first array element is an interpreter, the job is NOT classified. It
# goes to a review bucket with the absolute paths found inside the command
# string, for a human to judge. Guessing here is how you delete something that
# was working.
#
# Only the caller's GUI domain is inspected, because reading the system domain
# needs sudo and a detect pass must never elevate. System daemons under
# /Library/LaunchDaemons are therefore out of scope for detection.

_LO_INTERPRETERS=(sh bash zsh dash ksh csh tcsh env python python2 python3 ruby perl php node osascript open login)

# Emit one TSV row per candidate: label, plist path, classification, target.
# Classification is "orphan" (both signals, safe to act on) or "review" (an
# interpreter wrapper, needs a human).
_lo_scan() {
    local uid label plist target kind
    uid="$(id -u)"

    # Not running ("-" in the PID column) with a non-zero last exit status.
    while read -r label; do
        [[ -n "${label}" ]] || continue
        mdoc_label_excluded "${label}" && continue

        plist="$(launchctl print "gui/${uid}/${label}" 2>/dev/null |
            awk -F' = ' '/^[[:space:]]*path = / && !seen { print $2; seen = 1 }' || true)"
        [[ -n "${plist}" && -f "${plist}" ]] || continue
        mdoc_path_excluded "${plist}" && continue

        IFS=$'\t' read -r kind target < <(_lo_classify "${plist}")
        [[ -n "${kind}" ]] || continue

        printf '%s\t%s\t%s\t%s\n' "${label}" "${plist}" "${kind}" "${target}"
    done < <(launchctl list 2>/dev/null |
        awk -F'\t' 'NR > 1 && $1 == "-" && $2 != "0" && $2 != "-" { print $3 }')
}

# Print "<kind>\t<target>" for one plist, or nothing when the job looks healthy.
_lo_classify() {
    local plist="$1"
    local json first rest candidate

    json="$(plutil -convert json -o - "${plist}" 2>/dev/null)" || return 0
    [[ -n "${json}" ]] || return 0

    # Program wins when present. Otherwise ProgramArguments[0], with the rest of
    # the arguments kept so an interpreter's command string can be mined for
    # absolute paths. BundleProgram is bundle-relative and never auto-classified.
    IFS=$'\t' read -r first rest < <(
        printf '%s' "${json}" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
prog = d.get("Program")
args = d.get("ProgramArguments") or []
if isinstance(prog, str) and prog:
    print(prog + "\t")
elif isinstance(args, list) and args and isinstance(args[0], str):
    rest = " ".join(a for a in args[1:] if isinstance(a, str))
    print(args[0] + "\t" + rest.replace("\t", " ").replace("\n", " "))
elif isinstance(d.get("BundleProgram"), str):
    print("__BUNDLE__\t" + d["BundleProgram"])
'
    )

    [[ -n "${first}" ]] || return 0

    if [[ "${first}" == "__BUNDLE__" ]]; then
        printf 'review\tBundleProgram %s\n' "${rest}"
        return 0
    fi

    # An interpreter at position 0 tells us nothing about the real target.
    local base interp
    base="${first##*/}"
    for interp in "${_LO_INTERPRETERS[@]}"; do
        if [[ "${base}" == "${interp}" ]]; then
            # Mine the command string for absolute paths and report which of
            # them are missing, without deciding anything.
            candidate="$(_lo_missing_paths "${rest}")"
            if [[ -n "${candidate}" ]]; then
                printf 'review\t%s\n' "${candidate}"
            else
                printf 'review\t%s wrapper, no absolute path resolved\n' "${base}"
            fi
            return 0
        fi
    done

    # A plain program path: the second signal is simply whether it exists.
    if [[ ! -e "${first}" ]]; then
        printf 'orphan\t%s\n' "${first}"
    fi
}

# Print the absolute paths inside a command string that do not exist.
_lo_missing_paths() {
    local text="$1"
    printf '%s' "${text}" | python3 -c '
import os, re, sys
text = sys.stdin.read()
# Quoted absolute paths first, then bare ones. Bare paths stop at whitespace,
# which is why the quoted form is tried first: app bundles contain spaces.
seen, missing = set(), []
for m in re.findall(r"""["\x27](/[^"\x27]+)["\x27]""", text) + re.findall(r"(?<![\x27\"])(/[^\s\x27\";|&]+)", text):
    p = m.rstrip(";")
    if p in seen:
        continue
    seen.add(p)
    if not os.path.exists(p):
        missing.append(p)
print(", ".join(missing[:3]))
'
}

doctor_meta() {
    printf 'launchd-orphans\tOrphaned launchd jobs\tlaunchd agents whose target program no longer exists\tyes\tyes\tyes\n'
}

doctor_detect() {
    local label plist kind target owner
    while IFS=$'\t' read -r label plist kind target; do
        [[ -n "${label}" ]] || continue

        owner="user"
        [[ "${plist}" == /Library/* ]] && owner="root"

        if [[ "${kind}" == "orphan" ]]; then
            doctor_finding cruft "${label}" \
                "target missing: ${target} (${owner}-owned plist)" \
                "sjust macos-doctor-fix launchd-orphans$([[ "${owner}" == root ]] && printf ' system')"
        else
            doctor_finding warn "${label}" \
                "needs review: ${target}" \
                "inspect ${plist}"
        fi
    done < <(_lo_scan)
}

# Only the unambiguous orphans, and only those in scope. The report also lists the
# review bucket and root-owned plists, neither of which this fix touches without
# an explicit scope, so confirming against the findings would overstate it.
doctor_fix_targets() {
    local label plist kind target owner
    while IFS=$'\t' read -r label plist kind target; do
        [[ -n "${label}" ]] || continue

        # The review bucket is never touched automatically, and saying so is more
        # useful than omitting it: it is why a reported job was left alone.
        if [[ "${kind}" != "orphan" ]]; then
            printf '%s\t%s\tno\n' "${label}" "needs manual review, not auto-classified"
            continue
        fi

        owner="user"
        [[ "${plist}" == /Library/* ]] && owner="root"

        if [[ "${owner}" == "root" && "${MDOC_SCOPE:-}" != "system" ]]; then
            printf '%s\t%s\tno\n' "${label}" "root-owned, needs: macos-doctor-fix launchd-orphans apply system"
            continue
        fi

        printf '%s\t%s\tyes\n' "${label}" "${plist}"
    done < <(_lo_scan)
}

doctor_fix() {
    local label plist kind target owner uid rc=0
    uid="$(id -u)"

    while IFS=$'\t' read -r label plist kind target; do
        [[ -n "${label}" ]] || continue

        # Only the unambiguous ones. A review-bucket entry is never touched by
        # the automated path, by design.
        [[ "${kind}" == "orphan" ]] || continue

        owner="user"
        [[ "${plist}" == /Library/* ]] && owner="root"

        if [[ "${owner}" == "root" && "${MDOC_SCOPE:-}" != "system" ]]; then
            log_warn "${label}: root-owned plist, skipping. Re-run with: sjust macos-doctor-fix launchd-orphans system"
            continue
        fi

        # Boot out first so launchd stops retrying a plist that is about to move.
        # A dead job may already be gone from the domain, so failure is fine.
        if [[ "${owner}" == "root" ]]; then
            sudo launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
        else
            launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
        fi

        if ! mdoc_quarantine_store "${MDOC_QUARANTINE_DIR}" "launchd-orphans" "${label}" "${plist}"; then
            rc=1
        fi
    done < <(_lo_scan)

    return "${rc}"
}

doctor_explain() {
    cat <<'MD'
Finds launchd jobs that can never succeed because the program they point at was
uninstalled. They cost no measurable CPU, but launchd keeps retrying them and
nothing else surfaces them.

A job is reported as `cruft` only when two independent signals agree: `launchctl
list` shows it not running with a non-zero last exit status, **and** the resolved
program does not exist on disk.

When `ProgramArguments[0]` is an interpreter (`/bin/bash -c "..."`), the real
target is inside the command string and cannot be resolved reliably. Those go to
a `warn` review bucket listing the absolute paths that are missing, and the
automated fix never touches them.

The fix runs `launchctl bootout` and then moves the plist into quarantine, so
`sjust macos-doctor-undo restore` puts it back and bootstraps it again.

Only the caller's GUI domain is inspected: reading the system domain needs sudo,
and a detect pass never elevates. Root-owned plists under `/Library` are detected
(they load into the GUI domain) but only fixed when you pass `system`.

Apple, Mosyle and Jamf labels are excluded, and so is
`/Library/PrivilegedHelperTools`. A privileged helper with no installed app costs
nothing and its absence breaks a later reinstall.
MD
}
