#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/40-dev-caches.sh — developer caches and build artifacts by size.
#
# Reports every known cache location over the threshold. The fix deletes only the
# subset that regenerates from a network-free local rebuild or a cheap refetch,
# and never touches a dependency store whose loss means a long reinstall.
#
# Not cheap: measuring means walking large trees with du.

# Report anything at or above this many kilobytes (about 1 GB).
_DC_WARN_KB=1048576

# Every path considered, reported by size. Missing paths are skipped silently.
_dc_paths() {
    cat <<PATHS
${HOME}/Library/Caches
${HOME}/Library/Developer/Xcode/DerivedData
${HOME}/Library/Developer/CoreSimulator/Caches
${HOME}/Library/Developer/Xcode/iOS DeviceSupport
${HOME}/.npm/_cacache
${HOME}/Library/pnpm/store
${HOME}/Library/Caches/pnpm
${HOME}/Library/Caches/Yarn
${HOME}/.cache/yarn
${HOME}/go/pkg/mod
${HOME}/.gradle/caches
${HOME}/.m2/repository
${HOME}/.composer/cache
${HOME}/Library/Caches/composer
${HOME}/Library/Caches/pip
${HOME}/.cache/uv
PATHS
}

# The subset the fix may delete. Everything here is a pure cache or a build
# product: it rebuilds locally, or refetches on the next install.
#
# Deliberately absent: go/pkg/mod, .m2/repository, composer caches and the whole
# of ~/Library/Caches. The module stores are slow and bandwidth-heavy to rebuild,
# and ~/Library/Caches holds live application state, not just caches.
_dc_safe_paths() {
    cat <<PATHS
${HOME}/Library/Developer/Xcode/DerivedData
${HOME}/Library/Developer/CoreSimulator/Caches
${HOME}/.npm/_cacache
${HOME}/Library/Caches/Yarn
${HOME}/.cache/yarn
PATHS
}

doctor_meta() {
    printf 'dev-caches\tDeveloper caches\tcache and build-artifact directories over 1 GB\tno\tyes\tno\n'
}

# Print "<kb>\t<path>" for existing paths, largest first.
_dc_measure() {
    local path kb
    while IFS= read -r path; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        kb="$(du -sk "${path}" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
        [[ -n "${kb}" ]] || continue
        printf '%s\t%s\n' "${kb}" "${path}"
    done < <(_dc_paths) | sort -rn
}

_dc_human() {
    python3 -c '
import sys
kb = float(sys.argv[1])
for unit in ("KB", "MB", "GB", "TB"):
    if kb < 1024 or unit == "TB":
        print("%.1f %s" % (kb, unit))
        break
    kb /= 1024
' "$1"
}

doctor_detect() {
    local kb path total_kb=0 shown=0 safe_list
    safe_list="$(_dc_safe_paths)"

    while IFS=$'\t' read -r kb path; do
        [[ -n "${kb}" ]] || continue
        total_kb=$((total_kb + kb))
        [[ "${kb}" -ge "${_DC_WARN_KB}" ]] || continue

        local remedy=""
        if printf '%s\n' "${safe_list}" | grep -qxF "${path}"; then
            remedy="sjust macos-doctor-fix dev-caches"
        fi

        doctor_finding info "${path/#"${HOME}"/\~}" "$(_dc_human "${kb}")" "${remedy}"
        shown=$((shown + 1))
    done < <(_dc_measure)

    [[ "${shown}" -gt 0 ]] || return 0
    doctor_finding info "total" "$(_dc_human "${total_kb}") across all known cache paths" ""
}

doctor_fix() {
    local path kb freed_kb=0 rc=0

    while IFS= read -r path; do
        [[ -n "${path}" && -d "${path}" ]] || continue

        # Never step outside the home directory, whatever the list says.
        if [[ "${path}" != "${HOME}/"* ]]; then
            log_warn "refusing to delete outside \$HOME: ${path}"
            continue
        fi

        kb="$(du -sk "${path}" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"

        # Remove the contents, keep the directory: some tools expect it to exist.
        if find "${path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
            freed_kb=$((freed_kb + ${kb:-0}))
            log_success "cleared ${path/#"${HOME}"/\~} ($(_dc_human "${kb:-0}"))"
        else
            log_warn "failed to clear ${path}"
            rc=1
        fi
    done < <(_dc_safe_paths)

    log_info "Freed roughly $(_dc_human "${freed_kb}")."
    return "${rc}"
}

doctor_explain() {
    cat <<'MD'
Reports developer cache and build-artifact directories at or above 1 GB, plus the
combined total. Findings are `info`: a large cache is not a fault, it is a
disk-space fact you may want to act on.

The fix deletes the contents of only these, keeping the directories themselves:

- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/CoreSimulator/Caches`
- `~/.npm/_cacache`
- `~/Library/Caches/Yarn` and `~/.cache/yarn`

Everything in that list is a build product or a pure cache: it rebuilds locally or
refetches on the next install.

Deliberately excluded from the fix, though still reported: `~/go/pkg/mod`,
`~/.m2/repository`, the Composer caches, and `~/Library/Caches` as a whole. The
module stores are slow and bandwidth-heavy to rebuild, and `~/Library/Caches`
holds live application state rather than only caches.

The fix is `reversible=no`. Caches are far too large to copy into quarantine, so
deletion is real and the confirmation is asked twice. Nothing outside `$HOME` is
ever touched.
MD
}
