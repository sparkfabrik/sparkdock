#!/usr/bin/env bash
# shellcheck shell=bash
# sjust/scripts/macos-defaults/lib.sh — shared helpers for the macos-defaults scripts.
#
# Sourced by apply.sh, undo.sh, docs.sh, info.sh. Provides:
#   md_check_yq        — verify yq v4 (mikefarah) is installed
#   md_load_config     — merge curated YAML + user overrides into a temp file (printed on stdout)
#   md_expand_home     — bash parameter expansion for ${HOME} in string values
#   md_normalize       — type-aware normalization for current-vs-desired comparison
#   md_read_current    — defaults read with __UNSET__ sentinel
#   md_write           — type-aware defaults write
#   md_snapshot        — defaults export per touched domain + manifest
#   md_restore         — defaults import each plist + restart apps from manifest
#   md_prune_snapshots — keep only the N newest snapshot directories

# Guard against double-sourcing.
if [[ "${_SPARKDOCK_MACOS_DEFAULTS_LIB_LOADED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi
_SPARKDOCK_MACOS_DEFAULTS_LIB_LOADED=1

# Resolve sparkdock root from this script's location.
# lib.sh lives at <root>/sjust/scripts/macos-defaults/lib.sh.
_md_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPARKDOCK_ROOT="${SPARKDOCK_ROOT:-$(cd "${_md_lib_dir}/../../.." && pwd)}"
export SPARKDOCK_ROOT

# shellcheck source=../../libs/libshell.sh
source "${SPARKDOCK_ROOT}/sjust/libs/libshell.sh"

# Canonical paths used by all scripts.
MD_CONFIG_FILE="${SPARKDOCK_ROOT}/config/macos/defaults.yml"
MD_USER_OVERRIDES="${HOME}/.local/spark/macos-defaults/overrides.yml"
MD_SNAPSHOTS_ROOT="${HOME}/.local/spark/macos-defaults/snapshots"
MD_SNAPSHOT_RETENTION=10

# Verify mikefarah/yq v4 is installed.
md_check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq is required. Install with: brew install yq"
        return 1
    fi
    # mikefarah/yq prints "yq (https://github.com/mikefarah/yq/) version v4.x.x"
    if ! yq --version 2>&1 | grep -q "mikefarah\|version v4"; then
        log_error "yq v4 (mikefarah) required. Found: $(yq --version 2>&1)"
        return 1
    fi
}

# Merge curated YAML with optional user overrides into a temp file.
# Echoes the temp-file path on stdout. Caller is responsible for cleanup
# (typical pattern: trap 'rm -f "$merged"' EXIT).
md_load_config() {
    if [[ ! -f "${MD_CONFIG_FILE}" ]]; then
        log_error "Curated defaults missing at ${MD_CONFIG_FILE}"
        return 1
    fi

    local merged
    merged="$(mktemp -t macos-defaults.XXXXXX)"

    if [[ -f "${MD_USER_OVERRIDES}" ]]; then
        if ! yq eval '.' "${MD_USER_OVERRIDES}" >/dev/null 2>&1; then
            log_error "Invalid YAML in ${MD_USER_OVERRIDES}"
            yq eval '.' "${MD_USER_OVERRIDES}" 2>&1 | head -n 5 >&2 || true
            rm -f "${merged}"
            return 1
        fi
        # shellcheck disable=SC2016 # $i is a yq variable, not bash
        yq eval-all '. as $i ireduce ({}; . *+ $i)' "${MD_CONFIG_FILE}" "${MD_USER_OVERRIDES}" > "${merged}"
    else
        cp "${MD_CONFIG_FILE}" "${merged}"
    fi

    printf '%s\n' "${merged}"
}

# Expand ${HOME} / $HOME in a string value. No other expansion is performed.
md_expand_home() {
    local v="$1"
    v="${v//\$\{HOME\}/${HOME}}"
    v="${v//\$HOME/${HOME}}"
    printf '%s' "${v}"
}

# Normalize a desired value for comparison against `defaults read` output.
# Booleans → 1/0 to match macOS's textual representation.
md_normalize() {
    local type="$1" value="$2"
    case "${type}" in
        bool) [[ "${value}" == "true" ]] && printf '1' || printf '0' ;;
        *)    printf '%s' "${value}" ;;
    esac
}

# Read the current value of a defaults pair. Prints __UNSET__ if missing.
md_read_current() {
    defaults read "$1" "$2" 2>/dev/null || printf '__UNSET__'
}

# Write a defaults pair with the appropriate type flag.
# Args: domain, key, type (bool|int|float|string), value
md_write() {
    local domain="$1" key="$2" type="$3" value="$4"
    case "${type}" in
        bool)
            if [[ "${value}" == "true" ]]; then
                defaults write "${domain}" "${key}" -bool true
            else
                defaults write "${domain}" "${key}" -bool false
            fi
            ;;
        int)    defaults write "${domain}" "${key}" -int "${value}" ;;
        float)  defaults write "${domain}" "${key}" -float "${value}" ;;
        string) defaults write "${domain}" "${key}" -string "${value}" ;;
        *)
            log_warn "skipping ${domain}.${key}: unknown type '${type}'"
            return 1
            ;;
    esac
}

# Snapshot a list of preference domains into <snapshots_root>/<UTC-timestamp>/.
# Args: snapshot_dir, then one or more domain names.
# Writes manifest.txt with one domain per line, and updates the `latest` symlink.
md_snapshot() {
    local snapshot_dir="$1"
    shift
    mkdir -p "${snapshot_dir}"
    : > "${snapshot_dir}/manifest.txt"
    local d
    for d in "$@"; do
        defaults export "${d}" "${snapshot_dir}/${d}.plist" 2>/dev/null || true
        printf '%s\n' "${d}" >> "${snapshot_dir}/manifest.txt"
    done
    ln -sfn "$(basename "${snapshot_dir}")" "$(dirname "${snapshot_dir}")/latest"
}

# Restore a snapshot directory. Reads manifest.txt, runs `defaults import` for
# each plist, then restarts any apps the curated YAML associates with the
# restored domains.
# Args: snapshot_dir
md_restore() {
    local snapshot_dir="$1"
    if [[ ! -f "${snapshot_dir}/manifest.txt" ]]; then
        log_error "Snapshot $(basename "${snapshot_dir}") is missing manifest.txt"
        return 1
    fi

    local -A restart_apps=()
    local domain plist
    while IFS= read -r domain; do
        [[ -z "${domain}" ]] && continue
        plist="${snapshot_dir}/${domain}.plist"
        if [[ ! -f "${plist}" ]]; then
            log_warn "domain ${domain} listed in manifest but plist missing; skipping"
            continue
        fi
        if defaults import "${domain}" "${plist}" 2>/dev/null; then
            log_success "restored ${domain}"
        else
            log_error "failed to restore ${domain}"
            continue
        fi
        # Collect requires: from any curated entry on this domain
        if [[ -f "${MD_CONFIG_FILE}" ]] && command -v yq >/dev/null 2>&1; then
            local app
            while IFS= read -r app; do
                [[ -z "${app}" || "${app}" == "null" ]] && continue
                restart_apps["${app}"]=1
            done < <(
                yq eval ". | to_entries | .[] | select(.value.domain == \"${domain}\") | .value.requires // [] | .[]" \
                    "${MD_CONFIG_FILE}" 2>/dev/null
            )
        fi
    done < "${snapshot_dir}/manifest.txt"

    if [[ ${#restart_apps[@]} -gt 0 ]]; then
        log_section "Restarting affected applications"
        for app in "${!restart_apps[@]}"; do
            if pgrep -x "${app}" >/dev/null 2>&1; then
                printf '  • %s\n' "${app}"
                killall "${app}" 2>/dev/null || true
            fi
        done
    fi
}

# Keep only the N most recent timestamp directories under MD_SNAPSHOTS_ROOT.
# Args: keep_n (default: MD_SNAPSHOT_RETENTION)
md_prune_snapshots() {
    local keep="${1:-${MD_SNAPSHOT_RETENTION}}"
    [[ -d "${MD_SNAPSHOTS_ROOT}" ]] || return 0
    local skip=$((keep + 1))
    local old
    while IFS= read -r old; do
        [[ -n "${old}" ]] && rm -rf "${old}"
    done < <(
        find "${MD_SNAPSHOTS_ROOT}" -mindepth 1 -maxdepth 1 -type d -not -name "latest" \
            | sort -r | tail -n "+${skip}"
    )
}
