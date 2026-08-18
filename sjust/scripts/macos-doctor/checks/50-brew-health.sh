#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/50-brew-health.sh — Homebrew state worth knowing about.
#
# Three things, all read from a single `brew info --json=v2 --installed` call plus
# `brew outdated`, because shelling out to brew per package is slow enough to be
# noticeable.
#
# The missing-cask-app case is the Homebrew analogue of an orphaned launchd job:
# brew still believes the cask is installed while the application bundle it placed
# in /Applications has been dragged to the trash.
#
# Report-only. Uninstalling a cask or untapping is a judgement call, and getting
# it wrong costs a large redownload.

doctor_meta() {
    printf 'brew-health\tHomebrew health\toutdated packages, casks with a missing app, unused taps\tno\tno\tno\n'
}

doctor_detect() {
    command -v brew >/dev/null 2>&1 || return 0

    # --- Outdated ------------------------------------------------------------
    local outdated count
    outdated="$(brew outdated --quiet 2>/dev/null || true)"
    count="$(printf '%s' "${outdated}" | grep -c . || true)"
    if [[ "${count}" -gt 0 ]]; then
        doctor_finding info "outdated packages" \
            "${count} to update: $(printf '%s' "${outdated}" | head -3 | paste -sd, - )$([[ "${count}" -gt 3 ]] && printf ', ...')" \
            "brew upgrade"
    fi

    # --- One JSON call, two answers -----------------------------------------
    local json
    json="$(brew info --json=v2 --installed 2>/dev/null || true)"
    [[ -n "${json}" ]] || return 0

    local -a used_taps=()
    local kind value
    while IFS=$'\t' read -r kind value; do
        [[ -n "${kind}" ]] || continue
        case "${kind}" in
            missing_app)
                doctor_finding warn "${value%%|*}" \
                    "cask installed but app missing: ${value#*|}" \
                    "brew reinstall --cask ${value%%|*} (or brew uninstall --cask ${value%%|*})"
                ;;
            tap)
                used_taps+=("${value}")
                ;;
        esac
    done < <(
        printf '%s' "${json}" | python3 -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

taps = set()
for kind in ("formulae", "casks"):
    for pkg in d.get(kind) or []:
        tap = pkg.get("tap")
        if tap:
            taps.add(tap)

# A cask whose .app artifact is gone from /Applications: brew thinks it is
# installed, the bundle has been removed by hand.
for cask in d.get("casks") or []:
    token = cask.get("token") or ""
    for artifact in cask.get("artifacts") or []:
        if not isinstance(artifact, dict):
            continue
        for app in artifact.get("app") or []:
            if not isinstance(app, str) or not app.endswith(".app"):
                continue
            if not os.path.exists(os.path.join("/Applications", app)):
                print("missing_app\t%s|%s" % (token, app))

for tap in sorted(taps):
    print("tap\t%s" % tap)
'
    )

    # --- Taps with nothing installed from them -------------------------------
    local tap
    while IFS= read -r tap; do
        [[ -n "${tap}" ]] || continue
        # The default taps are always present and hold the bulk of the catalog.
        case "${tap}" in
            homebrew/core | homebrew/cask | homebrew/services) continue ;;
        esac
        local in_use=false
        local used
        for used in "${used_taps[@]}"; do
            [[ "${used}" == "${tap}" ]] && {
                in_use=true
                break
            }
        done
        if [[ "${in_use}" == false ]]; then
            doctor_finding info "${tap}" "tap with nothing installed from it" "brew untap ${tap}"
        fi
    done < <(brew tap 2>/dev/null || true)
}

doctor_explain() {
    cat <<'MD'
Three Homebrew facts, read from one `brew info --json=v2 --installed` call plus
`brew outdated`.

- **Outdated packages**, with a count and the first few names. Remedy is
  `brew upgrade`, or `Upgrade Brew packages` in `sparkdock tui`.
- **Casks whose application bundle is missing from `/Applications`.** This is the
  Homebrew analogue of an orphaned launchd job: brew still believes the cask is
  installed while the app has been dragged to the trash. Reported as `warn`
  because the right answer depends on intent, either `brew reinstall --cask` or
  `brew uninstall --cask`.
- **Taps with nothing installed from them.** The default `homebrew/core`,
  `homebrew/cask` and `homebrew/services` are never reported. A leftover tap costs
  only `brew update` time, so this is `info`.

Report-only, on purpose. Uninstalling a cask or untapping is a judgement call and
getting it wrong costs a large redownload.
MD
}
