#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034
# (SC2034 = "appears unused": this file is sourced by apply.sh / undo.sh /
# info.sh / docs.sh / init-overrides.sh. The MD_* variables below ARE used —
# but only in those sourcing scripts, which shellcheck cannot see across files.
# Disabling at the file level keeps the variable declarations clean.)
#
# sjust/scripts/macos-defaults/lib.sh — shared helpers for the macos-defaults scripts.
#
# Sourced by apply.sh, undo.sh, docs.sh, info.sh. Provides:
#   md_check_yq         — verify yq v4 (mikefarah) is installed
#   md_load_config      — merge curated YAML + user overrides into a temp file (printed on stdout)
#   md_expand_home      — bash parameter expansion for ${HOME} in string values
#   md_normalize        — type-aware normalization for current-vs-desired comparison
#   md_read_current     — defaults read with __UNSET__ sentinel
#   md_read_type        — defaults read-type, returns one of bool/int/float/string/__UNSET__
#   md_write            — type-aware defaults write
#   md_snapshot_key     — record a single (domain, key) into a per-key snapshot TSV
#   md_snapshot_init    — initialize a snapshot directory + TSV
#   md_restore          — restore a per-key snapshot TSV (defaults write or delete per key)
#   md_prune_snapshots  — keep only the N newest snapshot directories
#
# Snapshot format (per-key, not whole-domain): a single TSV at
# <snapshot_dir>/snapshot.tsv with columns
#
#   id<TAB>domain<TAB>key<TAB>was_set<TAB>prev_type<TAB>prev_value<TAB>requires_csv
#
# was_set is "true" or "false". When false, the prev_type/prev_value columns
# are empty and the restore step issues `defaults delete`. When true, the
# restore step writes the original value back with the original type flag.
# This means undo only touches the keys sparkdock managed, not the whole
# domain plist (`defaults import` is intentionally NOT used).

if [[ "${_SPARKDOCK_MACOS_DEFAULTS_LIB_LOADED:-}" = "1" ]]; then
    return 0 2>/dev/null || true
fi
_SPARKDOCK_MACOS_DEFAULTS_LIB_LOADED=1

# Bash 4+ is required (associative arrays, mapfile). Apple ships /bin/bash 3.2;
# Sparkdock relies on Homebrew's bash being on PATH (installed by brew + sparkdock provisioning).
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: bash >= 4 required (you have ${BASH_VERSION}). Install with: brew install bash" >&2
    exit 1
fi

# shellcheck source=../../libs/libshell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/sjust/libs/libshell.sh"

# Canonical paths and tunables used by all scripts that source this lib.
MD_CONFIG_FILE="${SPARKDOCK_ROOT}/config/macos/defaults.yml"
MD_USER_OVERRIDES="${HOME}/.local/spark/macos-defaults/overrides.yml"
MD_SNAPSHOTS_ROOT="${HOME}/.local/spark/macos-defaults/snapshots"
MD_SNAPSHOT_RETENTION=10
MD_LOCK_FILE="${HOME}/.local/spark/macos-defaults/.lock"

# --- yq detection ------------------------------------------------------------

md_check_yq() {
    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq is required. Install with: brew install yq"
        return 1
    fi
    if ! yq --version 2>&1 | grep -q "mikefarah\|version v4"; then
        log_error "yq v4 (mikefarah) required. Found: $(yq --version 2>&1)"
        return 1
    fi
}

# --- Config merge ------------------------------------------------------------

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

# --- Value handling ----------------------------------------------------------

md_expand_home() {
    local v="$1"
    v="${v//\$\{HOME\}/${HOME}}"
    v="${v//\$HOME/${HOME}}"
    printf '%s' "${v}"
}

md_normalize() {
    local type="$1" value="$2"
    case "${type}" in
        bool) [[ "${value}" == "true" ]] && printf '1' || printf '0' ;;
        *)    printf '%s' "${value}" ;;
    esac
}

md_read_current() {
    defaults read "$1" "$2" 2>/dev/null || printf '__UNSET__'
}

# defaults read-type returns "Type is boolean|integer|float|string|array|dictionary|data".
# We map it to our own type vocabulary; unknown / unset returns __UNSET__.
md_read_type() {
    local out
    out="$(defaults read-type "$1" "$2" 2>/dev/null)" || { printf '__UNSET__'; return 0; }
    case "${out}" in
        *boolean*)    printf 'bool' ;;
        *integer*)    printf 'int' ;;
        *float*)      printf 'float' ;;
        *string*)     printf 'string' ;;
        *)            printf '__UNSET__' ;;
    esac
}

md_write() {
    local domain="$1" key="$2" type="$3" value="$4"
    case "${type}" in
        bool)
            if [[ "${value}" == "true" || "${value}" == "1" ]]; then
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

# --- Per-key snapshots -------------------------------------------------------

# Initialize a fresh snapshot directory and write a TSV header line.
# Args: snapshot_dir
md_snapshot_init() {
    local snapshot_dir="$1"
    mkdir -p "${snapshot_dir}"
    : > "${snapshot_dir}/snapshot.tsv"
}

# Record one (domain, key) pair into the snapshot TSV. Captures the CURRENT
# value of the key (or __UNSET__) so we can restore exactly what we replaced.
# Args: snapshot_dir id domain key requires_csv
md_snapshot_key() {
    local snapshot_dir="$1" id="$2" domain="$3" key="$4" requires_csv="${5:-}"
    local prev_type prev_value was_set
    prev_type="$(md_read_type "${domain}" "${key}")"
    if [[ "${prev_type}" == "__UNSET__" ]]; then
        was_set="false"
        prev_type=""
        prev_value=""
    else
        was_set="true"
        prev_value="$(md_read_current "${domain}" "${key}")"
        # Strip newlines just in case (defaults read of arrays/dicts inserts them);
        # we only handle scalar types in restore.
        prev_value="${prev_value//$'\n'/ }"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${id}" "${domain}" "${key}" "${was_set}" "${prev_type}" "${prev_value}" "${requires_csv}" \
        >> "${snapshot_dir}/snapshot.tsv"
}

# Update the `latest` symlink (relative) to the given snapshot dir name.
md_snapshot_publish_latest() {
    local snapshot_dir="$1"
    ln -sfn "$(basename "${snapshot_dir}")" "$(dirname "${snapshot_dir}")/latest"
}

# Restore a per-key snapshot TSV. For each line:
#   was_set=false → defaults delete <domain> <key>
#   was_set=true  → defaults write <domain> <key> with the recorded type/value
# After all keys are restored, killall the union of `requires:` apps that the
# curated YAML maps to the restored domains.
# Args: snapshot_dir
md_restore() {
    local snapshot_dir="$1"
    local tsv="${snapshot_dir}/snapshot.tsv"
    if [[ ! -f "${tsv}" ]]; then
        log_error "Snapshot $(basename "${snapshot_dir}") is missing snapshot.tsv"
        return 1
    fi

    local -A restart_apps=()
    local id domain key was_set prev_type prev_value requires_csv
    while IFS=$'\t' read -r id domain key was_set prev_type prev_value requires_csv; do
        [[ -z "${id}" || -z "${domain}" || -z "${key}" ]] && continue
        if [[ "${was_set}" == "false" ]]; then
            if defaults delete "${domain}" "${key}" 2>/dev/null; then
                log_success "deleted ${id} (was previously unset)"
            fi
        else
            if md_write "${domain}" "${key}" "${prev_type}" "${prev_value}"; then
                log_success "restored ${id} → ${prev_value}"
            else
                log_error "failed to restore ${id}"
                continue
            fi
        fi
        if [[ -n "${requires_csv}" ]]; then
            local app
            local -a apps_array
            IFS=',' read -ra apps_array <<<"${requires_csv}"
            for app in "${apps_array[@]}"; do
                [[ -n "${app}" ]] && restart_apps["${app}"]=1
            done
        fi
    done < "${tsv}"

    if [[ ${#restart_apps[@]} -gt 0 ]]; then
        log_section "Restarting affected applications"
        local app
        for app in "${!restart_apps[@]}"; do
            # pgrep -x matches the full process name including spaces (e.g. "Activity Monitor").
            if pgrep -x "${app}" >/dev/null 2>&1; then
                printf '  • %s\n' "${app}"
                killall "${app}" 2>/dev/null || true
            fi
        done
    fi
}

# --- Retention ---------------------------------------------------------------

md_prune_snapshots() {
    local keep="${1:-${MD_SNAPSHOT_RETENTION}}"
    [[ -d "${MD_SNAPSHOTS_ROOT}" ]] || return 0
    local skip=$((keep + 1))
    local old
    while IFS= read -r old; do
        [[ -n "${old}" ]] && rm -rf "${old}"
    done < <(
        find "${MD_SNAPSHOTS_ROOT}" -mindepth 1 -maxdepth 1 -type d \
            | sort -r | tail -n "+${skip}"
    )
}
