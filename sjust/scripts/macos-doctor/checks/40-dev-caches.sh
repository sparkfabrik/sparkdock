#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/40-dev-caches.sh — developer caches and build artifacts by size.
#
# Every managed entry carries the method that clears it, because one `rm -rf` loop
# is wrong for this set. The Go module cache is stored read-only on purpose, so
# deleting it with `rm` fails partway through with permission errors; `go clean
# -modcache` is the tool that exists for it.
#
# One path is reported but never cleared: ~/Library/Caches. It is not a cache in
# any useful sense, it is a mixed bag of live application state, and there is no
# safe blanket operation on it. Everything else here re-downloads or rebuilds.
#
# Not cheap: measuring means walking large trees with du.

# Report anything at or above this many kilobytes (about 1 GB).
_DC_WARN_KB=1048576

# Managed entries the fix can clear: path, method, consequence.
#
#   contents  remove everything inside, keep the directory (tools expect it)
#   modcache  go clean -modcache, which handles the read-only module store
_dc_managed() {
    cat <<ENTRIES
${HOME}/Library/Developer/Xcode/DerivedData	contents	rebuilds on next Xcode build
${HOME}/Library/Developer/CoreSimulator/Caches	contents	regenerates on next simulator run
${HOME}/Library/Developer/Xcode/iOS DeviceSupport	contents	regenerates when you next attach a device
${HOME}/.npm/_cacache	contents	re-downloads on next npm install
${HOME}/Library/Caches/Yarn	contents	re-downloads on next yarn install
${HOME}/.cache/yarn	contents	re-downloads on next yarn install
${HOME}/Library/pnpm/store	contents	re-downloads on next pnpm install
${HOME}/Library/Caches/pnpm	contents	re-downloads on next pnpm install
${HOME}/.gradle/caches	contents	re-downloads on next gradle build
${HOME}/.m2/repository	contents	re-downloads on next maven build
${HOME}/.composer/cache	contents	re-downloads on next composer install
${HOME}/Library/Caches/composer	contents	re-downloads on next composer install
${HOME}/Library/Caches/pip	contents	re-downloads on next pip install
${HOME}/.cache/uv	contents	re-downloads on next uv sync
${HOME}/go/pkg/mod	modcache	re-downloads on next go build
ENTRIES
}

# Reported for size, never cleared by the fix.
_dc_reported_only() {
    cat <<ENTRIES
${HOME}/Library/Caches	holds live application state, clear per-app instead
ENTRIES
}

doctor_meta() {
    printf 'dev-caches\tDeveloper caches\tcache and build-artifact directories over 1 GB\tno\tyes\tno\n'
}

_dc_size_kb() {
    du -sk "$1" 2>/dev/null | awk 'NR == 1 { print $1 }' || true
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

_dc_is_empty() {
    [[ -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

doctor_detect() {
    local path method note kb total_kb=0 shown=0

    # Managed entries: reported with the fix command attached.
    while IFS=$'\t' read -r path method note; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        kb="$(_dc_size_kb "${path}")"
        [[ -n "${kb}" ]] || continue
        total_kb=$((total_kb + kb))
        [[ "${kb}" -ge "${_DC_WARN_KB}" ]] || continue

        doctor_finding info "${path/#"${HOME}"/\~}" \
            "$(_dc_human "${kb}"), ${note}" \
            "sjust macos-doctor-fix dev-caches"
        shown=$((shown + 1))
    done < <(_dc_managed)

    # Reported only, with the reason it is not cleared, so a large number is not
    # mistaken for something this fix will handle.
    while IFS=$'\t' read -r path note; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        kb="$(_dc_size_kb "${path}")"
        [[ -n "${kb}" ]] || continue
        total_kb=$((total_kb + kb))
        [[ "${kb}" -ge "${_DC_WARN_KB}" ]] || continue

        doctor_finding info "${path/#"${HOME}"/\~}" \
            "$(_dc_human "${kb}"), not cleared: ${note}" ""
        shown=$((shown + 1))
    done < <(_dc_reported_only)

    [[ "${shown}" -gt 0 ]] || return 0
    doctor_finding info "total" "$(_dc_human "${total_kb}") across all known cache paths" ""
}

# Every managed entry, actionable only when it holds something. Listing the empty
# ones is what makes "nothing to remove" legible rather than mysterious.
doctor_fix_targets() {
    local path method note kb
    while IFS=$'\t' read -r path method note; do
        [[ -n "${path}" ]] || continue

        if [[ ! -d "${path}" ]]; then
            printf '%s\t%s\tno\n' "${path/#"${HOME}"/\~}" "does not exist"
            continue
        fi
        if _dc_is_empty "${path}"; then
            printf '%s\t%s\tno\n' "${path/#"${HOME}"/\~}" "already empty"
            continue
        fi

        kb="$(_dc_size_kb "${path}")"
        printf '%s\t%s\tyes\n' "${path/#"${HOME}"/\~}" "$(_dc_human "${kb:-0}"), ${note}"
    done < <(_dc_managed)
}

doctor_fix() {
    local path method note kb freed_kb=0 rc=0

    while IFS=$'\t' read -r path method note; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        _dc_is_empty "${path}" && continue

        # Never step outside the home directory, whatever the table says.
        if [[ "${path}" != "${HOME}/"* ]]; then
            log_warn "refusing to clear outside \$HOME: ${path}"
            continue
        fi

        kb="$(_dc_size_kb "${path}")"
        freed_kb=$((freed_kb + ${kb:-0}))

        mdoc_would "clear ${path/#"${HOME}"/\~} ($(_dc_human "${kb:-0}") via ${method}, permanent)" && continue

        case "${method}" in
            modcache)
                # The module cache is written read-only, so rm fails partway
                # through. This is what `go clean -modcache` is for.
                if command -v go >/dev/null 2>&1; then
                    if go clean -modcache 2>/dev/null; then
                        log_success "cleared ${path/#"${HOME}"/\~} ($(_dc_human "${kb:-0}"), go clean -modcache)"
                    else
                        log_warn "go clean -modcache failed for ${path}"
                        freed_kb=$((freed_kb - ${kb:-0}))
                        rc=1
                    fi
                else
                    log_warn "go is not installed, skipping ${path/#"${HOME}"/\~}"
                    freed_kb=$((freed_kb - ${kb:-0}))
                fi
                ;;
            contents)
                # Remove the contents, keep the directory: some tools expect it.
                if find "${path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
                    log_success "cleared ${path/#"${HOME}"/\~} ($(_dc_human "${kb:-0}"))"
                else
                    log_warn "failed to clear ${path}"
                    freed_kb=$((freed_kb - ${kb:-0}))
                    rc=1
                fi
                ;;
            *)
                log_warn "${path}: unknown method '${method}', skipping"
                freed_kb=$((freed_kb - ${kb:-0}))
                ;;
        esac
    done < <(_dc_managed)

    if mdoc_is_dry_run; then
        log_info "Would free roughly $(_dc_human "${freed_kb}")."
    else
        log_info "Freed roughly $(_dc_human "${freed_kb}")."
    fi
    return "${rc}"
}

doctor_explain() {
    cat <<'MD'
Reports cache and build-artifact directories at or above 1 GB, plus the combined
total. Findings are `info`: a large cache is not a fault, it is a disk-space fact
you may want to act on.

Every managed entry carries the method that clears it, because a single `rm -rf`
loop is wrong for this set.

| entry | cleared by | consequence |
| --- | --- | --- |
| Xcode `DerivedData` | contents removed | rebuilds on next build |
| `CoreSimulator/Caches` | contents removed | regenerates |
| Xcode `iOS DeviceSupport` | contents removed | regenerates when you attach a device |
| npm, yarn, pnpm caches | contents removed | re-download on next install |
| gradle, maven, composer, pip, uv caches | contents removed | re-download on next build |
| `~/go/pkg/mod` | `go clean -modcache` | re-downloads on next build |

The Go module cache is stored **read-only** on purpose, so deleting it with `rm`
fails partway through with permission errors. `go clean -modcache` is the tool
that exists for it, and the fix uses that rather than pretending one method fits
every path.

**One path is reported but never cleared:** `~/Library/Caches`. Despite the name it
is a mixed bag of live application state, not a cache, and there is no safe blanket
operation on it. It shows up in the report with that reason attached so a large
number there is not mistaken for something this fix will handle. Clear it per
application instead.

The fix is `reversible=no`: caches are far too large to copy into quarantine, so
deletion is real and the confirmation is asked twice. It lists every managed entry
with its size and consequence before asking, and skips anything already empty.
Nothing outside `$HOME` is ever touched.
MD
}
