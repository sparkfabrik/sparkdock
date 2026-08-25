#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/system-cleanup/run.sh — survey what can be reclaimed, then reclaim it.
#
# Usage: run.sh [apply|dry-run]
#   apply    survey, show, confirm, clean (default)
#   dry-run  survey and show only, change nothing
#
# Three sections: Homebrew, Docker, developer caches. Each one surveys first, and
# nothing is removed that was not listed with its size beforehand.
#
# Two things this deliberately does NOT do, because both delete data rather than
# cache, and which of it you still want is not a decision a cleanup script should
# make. Each is reported with the command that would do it:
#
#   docker image prune -a   removes unused but TAGGED images, usually the bulk of
#                           Docker's reclaimable figure
#   docker ... --volumes    removes named volumes, which hold databases and uploads
#
# The Go module cache is cleared with `go clean -modcache`, not rm: the module
# store is written read-only on purpose, so rm fails partway through with
# permission errors.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
sc_require_macos

mode="${1:-apply}"
case "${mode}" in
    apply | dry-run) ;;
    "") mode="apply" ;;
    *)
        log_error "unknown mode '${mode}'. Valid: apply (default), dry-run."
        exit 2
        ;;
esac

export SC_DRY_RUN=0
[[ "${mode}" == "dry-run" ]] && export SC_DRY_RUN=1

# Managed developer caches: path, method, consequence.
#
#   contents  remove everything inside, keep the directory (tools expect it)
#   modcache  go clean -modcache, which handles the read-only module store
_sc_caches() {
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

log_section "Sparkdock system cleanup"
[[ "${mode}" == "dry-run" ]] && log_info "Dry run: nothing will be changed."

# =============================================================================
# Survey
# =============================================================================

targets=""  # SECTION \t ITEM \t SIZE \t CONSEQUENCE
advisories="" # ITEM \t SIZE \t WHY NOT AUTOMATIC \t COMMAND
total_kb=0

# --- Homebrew ----------------------------------------------------------------

brew_present=false
brew_free_bytes=0
if command -v brew >/dev/null 2>&1; then
    brew_present=true

    # The size is an estimate for display only. `brew cleanup -n` output has
    # changed shape across versions, so a failed parse must never stop the cleanup
    # from running: the survey informs, it does not gate.
    brew_dry="$(brew cleanup -n 2>/dev/null || true)"
    brew_free_human="$(printf '%s' "${brew_dry}" |
        sed -nE 's/.*would free (approximately )?([0-9.]+[A-Za-z]+).*/\2/p' | tail -1)"
    if [[ -n "${brew_free_human}" ]]; then
        brew_free_bytes="$(sc_docker_bytes "${brew_free_human}")"
        total_kb=$((total_kb + brew_free_bytes / 1024))
    else
        brew_free_human="nothing measurable"
    fi
    targets+="Homebrew"$'\t'"stale downloads and old versions"$'\t'"${brew_free_human}"$'\t'"re-downloads if needed"$'\n'

    # Advisories: real findings that cleanup does not and should not act on.
    outdated="$(brew outdated --quiet 2>/dev/null || true)"
    n_outdated="$(printf '%s' "${outdated}" | grep -c . || true)"
    if [[ "${n_outdated}" -gt 0 ]]; then
        advisories+="outdated packages"$'\t'"${n_outdated} behind"$'\t'"upgrading changes software versions, not disk use"$'\t'"brew upgrade"$'\n'
    fi

    # A cask whose .app is gone from /Applications: brew still believes it is
    # installed. The Homebrew analogue of an orphaned install.
    brew_json="$(brew info --json=v2 --installed 2>/dev/null || true)"
    if [[ -n "${brew_json}" ]]; then
        while IFS=$'\t' read -r kind value; do
            [[ -n "${kind}" ]] || continue
            case "${kind}" in
                missing_app)
                    advisories+="${value%%|*}"$'\t'"app missing"$'\t'"reinstall or uninstall is your call, ${value#*|} is gone"$'\t'"brew reinstall --cask ${value%%|*}"$'\n'
                    ;;
                unused_tap)
                    advisories+="${value}"$'\t'"unused tap"$'\t'"you may still want it for future installs"$'\t'"brew untap ${value}"$'\n'
                    ;;
            esac
        done < <(
            printf '%s' "${brew_json}" | python3 -c '
import json, os, subprocess, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

used = set()
for kind in ("formulae", "casks"):
    for pkg in d.get(kind) or []:
        if pkg.get("tap"):
            used.add(pkg["tap"])

for cask in d.get("casks") or []:
    token = cask.get("token") or ""
    for artifact in cask.get("artifacts") or []:
        if not isinstance(artifact, dict):
            continue
        for app in artifact.get("app") or []:
            if isinstance(app, str) and app.endswith(".app"):
                if not os.path.exists(os.path.join("/Applications", app)):
                    print("missing_app\t%s|%s" % (token, app))

# Default taps are always present and hold the bulk of the catalog.
DEFAULT = {"homebrew/core", "homebrew/cask", "homebrew/services"}
try:
    taps = subprocess.run(["brew", "tap"], capture_output=True, text=True).stdout.split()
except Exception:
    taps = []
for tap in sorted(set(taps) - used - DEFAULT):
    print("unused_tap\t%s" % tap)
'
        )
    fi
fi

# --- Docker ------------------------------------------------------------------

docker_running=false
docker_safe_bytes=0
docker_stopped=0
docker_cache_human=""
if command -v docker >/dev/null 2>&1 && docker system df --format '{{json .}}' >/dev/null 2>&1; then
    docker_running=true
    while IFS=$'\t' read -r kind human bytes total active; do
        [[ -n "${kind}" ]] || continue

        # A stopped container can hold zero reclaimable bytes and still exist, so
        # count them before the byte filter below discards the row. Gating the
        # prune on bytes alone would leave stopped containers behind.
        if [[ "${kind}" == "Containers" && "${total}" =~ ^[0-9]+$ && "${active}" =~ ^[0-9]+$ ]]; then
            docker_stopped=$((total - active))
        fi

        [[ "${bytes}" -gt 0 ]] || continue

        case "${kind}" in
            "Build Cache")
                docker_safe_bytes=$((docker_safe_bytes + bytes))
                docker_cache_human="${human}"
                ;;
            Containers)
                # Already listed above by count; only add its bytes to the total.
                docker_safe_bytes=$((docker_safe_bytes + bytes))
                ;;
            Images)
                # prune -f removes only DANGLING images. The rest, usually the bulk,
                # needs -a, which is a re-pull rather than a cache eviction.
                advisories+="docker images"$'\t'"${human}"$'\t'"unused but tagged (${active} of ${total} in use), removing means re-pulling"$'\t'"docker image prune -a"$'\n'
                ;;
            "Local Volumes")
                advisories+="docker volumes"$'\t'"${human}"$'\t'"holds DATA not cache (${total} volumes), never safe in bulk"$'\t'"docker volume ls"$'\n'
                ;;
        esac
    done < <(
        docker system df --format '{{json .}}' 2>/dev/null | python3 -c '
import json, re, sys

UNITS = {"B": 1, "KB": 10**3, "MB": 10**6, "GB": 10**9, "TB": 10**12,
         "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}

def to_bytes(text):
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
    rec = row.get("Reclaimable")
    print("\t".join([
        str(row.get("Type") or "?"),
        re.sub(r"\s*\(.*\)\s*$", "", (rec or "").strip()) or "0B",
        str(to_bytes(rec)),
        str(row.get("TotalCount") or "?"),
        str(row.get("Active") or "?"),
    ]))
'
    )
    total_kb=$((total_kb + docker_safe_bytes / 1024))

    docker_detail="stopped containers, dangling images, unused networks, build cache"
    docker_size="${docker_cache_human:-nothing measurable}"
    [[ "${docker_stopped}" -gt 0 ]] && docker_detail="${docker_stopped} stopped container(s), ${docker_detail}"
    targets+="Docker"$'\t'"${docker_detail}"$'\t'"${docker_size}"$'\t'"rebuilt or re-pulled on next use"$'\n'
fi

# --- Developer caches --------------------------------------------------------

cache_kb=0
while IFS=$'\t' read -r path method note; do
    [[ -n "${path}" && -d "${path}" ]] || continue
    sc_is_empty_dir "${path}" && continue
    kb="$(sc_size_kb "${path}")"
    [[ -n "${kb}" && "${kb}" -gt 0 ]] || continue
    cache_kb=$((cache_kb + kb))
    targets+="Dev caches"$'\t'"$(sc_tilde "${path}")"$'\t'"$(sc_human_kb "${kb}")"$'\t'"${note}"$'\n'
done < <(_sc_caches)
total_kb=$((total_kb + cache_kb))

# ~/Library/Caches is reported, never cleared: despite the name it is live
# application state, and there is no safe blanket operation on it.
if [[ -d "${HOME}/Library/Caches" ]]; then
    lc_kb="$(sc_size_kb "${HOME}/Library/Caches")"
    if [[ -n "${lc_kb}" && "${lc_kb}" -gt 1048576 ]]; then
        # The Homebrew download cache sits inside this tree and IS managed by brew,
        # so calling the whole figure "live app state" overstates it.
        brew_cache_kb=0
        bc="$(brew --cache 2>/dev/null || true)"
        [[ -n "${bc}" && -d "${bc}" ]] && brew_cache_kb="$(sc_size_kb "${bc}")"
        if [[ "${brew_cache_kb:-0}" -gt 1048576 ]]; then
            # shellcheck disable=SC2088  # a literal tilde for display, not a path to expand
            advisories+="~/Library/Caches/Homebrew"$'\t'"$(sc_human_kb "${brew_cache_kb}")"$'\t'"downloads for versions you still have installed"$'\t'"brew cleanup --prune=all"$'\n'
        fi
        # shellcheck disable=SC2088  # a literal tilde for display, not a path to expand
        advisories+="~/Library/Caches"$'\t'"$(sc_human_kb "${lc_kb}") total"$'\t'"mostly live app state, no safe bulk operation exists"$'\t'"clear it per application"$'\n'
    fi
fi

# =============================================================================
# Show
# =============================================================================

if [[ -z "${targets}" ]]; then
    log_success "Nothing to reclaim."
else
    sc_section "This will be removed"
    printf '\n'
    render_table <<<"SECTION"$'\t'"ITEM"$'\t'"SIZE"$'\t'"AFTERWARDS"$'\n'"${targets%$'\n'}"
    printf '\n'
    log_info "Total to reclaim: roughly $(sc_human_kb "${total_kb}")"
fi

if [[ -n "${advisories}" ]]; then
    sc_section "Not touched: each needs a decision this command should not make"
    printf '\n'
    render_table <<<"ITEM"$'\t'"SIZE"$'\t'"WHY NOT AUTOMATIC"$'\t'"COMMAND"$'\n'"${advisories%$'\n'}"
    printf '\n'
fi

if [[ -z "${targets}" ]]; then
    exit 0
fi

if [[ "${mode}" == "dry-run" ]]; then
    log_info "Apply it with: sjust system-cleanup"
    exit 0
fi

# =============================================================================
# Confirm and clean
# =============================================================================

log_warn "This cannot be undone. Everything above re-downloads or rebuilds when next needed."
if ! sc_confirm "Reclaim roughly $(sc_human_kb "${total_kb}")?"; then
    log_info "Cancelled."
    exit 0
fi

printf '\n'
freed_kb=0
rc=0

if [[ "${brew_present}" == true ]]; then
    sc_section "Homebrew"

    # Measured, not estimated: brew's own dry-run figure is advisory and its output
    # shape has changed across versions, so the cache directory is sized before and
    # after instead.
    brew_cache_dir="$(brew --cache 2>/dev/null || true)"
    brew_before_kb=0
    [[ -n "${brew_cache_dir}" && -d "${brew_cache_dir}" ]] && brew_before_kb="$(sc_size_kb "${brew_cache_dir}")"

    if brew cleanup 2>&1 | tail -3; then
        brew_after_kb="${brew_before_kb}"
        [[ -n "${brew_cache_dir}" && -d "${brew_cache_dir}" ]] && brew_after_kb="$(sc_size_kb "${brew_cache_dir}")"
        brew_delta_kb=$(( ${brew_before_kb:-0} - ${brew_after_kb:-0} ))
        [[ "${brew_delta_kb}" -lt 0 ]] && brew_delta_kb=0
        freed_kb=$((freed_kb + brew_delta_kb))
        log_success "brew cleanup done, reclaimed $(sc_human_kb "${brew_delta_kb}")"
    else
        log_warn "brew cleanup reported errors"
        rc=1
    fi
fi

if [[ "${docker_running}" == true ]]; then
    sc_section "Docker"

    # Two commands, because they cover different things. `system prune` takes
    # stopped containers, dangling images and unused networks. It removes only
    # DANGLING build cache, so the reclaimable build-cache figure `docker system
    # df` reports survives it: that needs `builder prune`. Reporting the figure
    # and then not reclaiming it is how this looked broken.
    docker_freed_bytes=0
    for docker_cmd in "system prune -f" "builder prune -f"; do
        # shellcheck disable=SC2086  # deliberate word splitting of the subcommand
        if out="$(docker ${docker_cmd} 2>&1)"; then
            printf '%s\n' "${out}" | tail -2
            reclaimed="$(printf '%s\n' "${out}" |
                sed -nE 's/.*Total reclaimed space: *([0-9.]+[A-Za-z]+).*/\1/p' | tail -1)"
            if [[ -n "${reclaimed}" ]]; then
                docker_freed_bytes=$((docker_freed_bytes + $(sc_docker_bytes "${reclaimed}")))
            fi
        else
            log_warn "docker ${docker_cmd} reported errors"
            rc=1
        fi
    done

    # The real figure from docker itself, not the pre-run estimate.
    freed_kb=$((freed_kb + docker_freed_bytes / 1024))
    log_success "docker prune done, reclaimed $(sc_human_bytes "${docker_freed_bytes}")"
fi

if [[ "${cache_kb}" -gt 0 ]]; then
    sc_section "Developer caches"
    while IFS=$'\t' read -r path method note; do
        [[ -n "${path}" && -d "${path}" ]] || continue
        sc_is_empty_dir "${path}" && continue

        # Never step outside the home directory, whatever the table says.
        if [[ "${path}" != "${HOME}/"* ]]; then
            log_warn "refusing to clear outside \$HOME: ${path}"
            continue
        fi

        kb="$(sc_size_kb "${path}")"
        case "${method}" in
            modcache)
                if ! command -v go >/dev/null 2>&1; then
                    log_warn "go is not installed, skipping $(sc_tilde "${path}")"
                    continue
                fi
                if go clean -modcache 2>/dev/null; then
                    freed_kb=$((freed_kb + ${kb:-0}))
                    log_success "cleared $(sc_tilde "${path}") ($(sc_human_kb "${kb}"), go clean -modcache)"
                else
                    log_warn "go clean -modcache failed"
                    rc=1
                fi
                ;;
            contents)
                if find "${path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null; then
                    freed_kb=$((freed_kb + ${kb:-0}))
                    log_success "cleared $(sc_tilde "${path}") ($(sc_human_kb "${kb}"))"
                else
                    log_warn "failed to clear ${path}"
                    rc=1
                fi
                ;;
            *)
                log_warn "${path}: unknown method '${method}', skipping"
                ;;
        esac
    done < <(_sc_caches)
fi

printf '\n'
if [[ "${rc}" -ne 0 ]]; then
    log_warn "Reclaimed roughly $(sc_human_kb "${freed_kb}"), with errors above."
    exit "${rc}"
fi

log_success "Reclaimed roughly $(sc_human_kb "${freed_kb}")."
