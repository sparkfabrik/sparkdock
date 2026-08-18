#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034
# (SC2034 = "appears unused": this file is sourced by run.sh, which is where the
# SC_* variables below are read. shellcheck cannot see across the source boundary.)
#
# sjust/scripts/system-cleanup/lib.sh — shared helpers for system-cleanup.
#
# Sourced by run.sh. Provides size formatting, table rendering, a TTY-gated
# confirmation, and the dry-run guard.
#
# Two conventions carried through the whole script:
#
#   Logging goes to stderr (via logging.sh), so stdout stays parseable and the
#   SYSTEM_CLEANUP_STATUS line at the end is a usable contract for CI and Ansible.
#
#   Nothing is removed that was not listed first. Every section surveys, the
#   totals are shown, and only then is consent asked. A confirmation that does not
#   name what it is about to delete trains people to approve without reading.

if [[ "${_SPARKDOCK_SYSTEM_CLEANUP_LIB_LOADED:-}" = "1" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
_SPARKDOCK_SYSTEM_CLEANUP_LIB_LOADED=1

# shellcheck source=../../libs/libshell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/sjust/libs/libshell.sh"

# --- Platform guard ----------------------------------------------------------

# Exit 0 rather than failing: a non-macOS host is a skip, not an error.
sc_require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_warn "system-cleanup targets macOS (detected: $(uname -s)). Skipping."
        exit 0
    fi
}

# --- Sizes -------------------------------------------------------------------

# Kilobytes for a path, or 0. du exits non-zero on unreadable subdirectories,
# which is normal under ~/Library, so its status is deliberately ignored.
sc_size_kb() {
    du -sk "$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true
}

sc_human_kb() {
    python3 -c '
import sys
kb = float(sys.argv[1] or 0)
for unit in ("KB", "MB", "GB", "TB"):
    if kb < 1024 or unit == "TB":
        print("%.1f %s" % (kb, unit))
        break
    kb /= 1024
' "${1:-0}"
}

sc_human_bytes() {
    python3 -c '
import sys
b = float(sys.argv[1] or 0)
for unit in ("B", "KB", "MB", "GB", "TB"):
    if b < 1024 or unit == "TB":
        print("%.1f %s" % (b, unit))
        break
    b /= 1024
' "${1:-0}"
}

# Parse a docker-style size ("27.52GB", "0B", "8.1GiB") into bytes.
sc_docker_bytes() {
    python3 -c '
import re, sys

UNITS = {"B": 1, "KB": 10**3, "MB": 10**6, "GB": 10**9, "TB": 10**12,
         "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}

m = re.match(r"\s*([0-9.]+)\s*([A-Za-z]+)", sys.argv[1] if len(sys.argv) > 1 else "")
if not m:
    print(0)
else:
    try:
        print(int(float(m.group(1)) * UNITS.get(m.group(2).upper(), 1)))
    except ValueError:
        print(0)
' "${1:-}"
}

sc_is_empty_dir() {
    [[ -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

# Abbreviate $HOME to ~ for display. The tilde is escaped so it is not expanded
# straight back into $HOME by the replacement.
sc_tilde() {
    printf '%s' "${1/#"${HOME}"/\~}"
}

# --- Rendering ---------------------------------------------------------------

sc_section() {
    if [[ "${HAS_GUM}" = true ]]; then
        printf '\n'
        gum style --bold --foreground 99 "$*"
    else
        printf '\n%b%s%b\n' "${BOLD}" "$*" "${NC}"
    fi
}

sc_faint() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum style --faint "$*"
    else
        printf '%s\n' "$*"
    fi
}

# --- Dry run -----------------------------------------------------------------

sc_is_dry_run() {
    [[ "${SC_DRY_RUN:-0}" == "1" ]]
}

# In a dry run, describe the action and return 0 so the caller skips it. In a real
# run, return 1 so the caller proceeds. This keeps the preview on exactly the same
# code path as the real thing, which is the only way a preview is trustworthy.
sc_would() {
    sc_is_dry_run || return 1
    log_info "would ${*}"
    return 0
}

# --- Confirmation ------------------------------------------------------------

# Declines when there is no TTY, so an unattended caller can never consent to a
# destructive operation.
sc_confirm() {
    local prompt="$1" reply
    if [[ ! -t 0 ]]; then
        log_warn "Not a TTY, declining: ${prompt}"
        return 1
    fi
    read -r -p "${prompt} (y/n) " -n 1 reply
    printf '\n'
    [[ "${reply}" =~ ^[Yy]$ ]]
}
