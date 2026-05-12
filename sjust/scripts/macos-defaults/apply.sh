#!/usr/bin/env bash
set -euo pipefail
#
# Apply or preview the curated macOS defaults.
# Usage: apply.sh <mode> [<strict>] [<verbose>]
#   mode    apply | dry-run     (default: apply)
#   strict  pass "strict" with mode=dry-run → exit 2 if drift exists
#   verbose pass "verbose" → also print "=" lines for unchanged settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
md_require_macos_version

mode="${1:-apply}"
strict="${2:-}"
verbose="${3:-}"

case "${mode}" in
    apply|dry-run) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: apply, dry-run."
        exit 2
        ;;
esac

md_check_yq

# --- Color (honour NO_COLOR https://no-color.org) ----------------------------
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    c_reset="" c_dim="" c_red="" c_green="" c_yellow=""
else
    c_reset=$'\033[0m'; c_dim=$'\033[2m'; c_red=$'\033[31m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'
fi

# --- Concurrency lock --------------------------------------------------------
# Apply mutates user state; coordinate with any concurrent run on the same
# machine via a flock on a sentinel file. Skipped in dry-run.
if [[ "${mode}" == "apply" ]] && command -v flock >/dev/null 2>&1; then
    mkdir -p "$(dirname "${MD_LOCK_FILE}")"
    exec 9>"${MD_LOCK_FILE}"
    if ! flock -n 9; then
        log_error "Another macos-defaults run is in progress (lock: ${MD_LOCK_FILE})."
        exit 1
    fi
fi

merged="$(md_load_config)"
trap 'rm -f "${merged}"' EXIT

# Render every entry as one TSV row: id\tdomain\tkey\ttype\tvalue\trequires_csv
mapfile -t rows < <(yq eval '
    . | to_entries | .[] |
    [.key, .value.domain, .value.key, .value.type, .value.value, ((.value.requires // []) | join(","))]
    | @tsv
' "${merged}")

declare -a to_write
drift_count=0
skipped_count=0

for row in "${rows[@]}"; do
    IFS=$'\t' read -r id domain key type desired_raw _requires_csv <<<"${row}"

    if [[ "${type}" == "string" ]]; then
        desired="$(md_expand_home "${desired_raw}")"
    else
        desired="${desired_raw}"
    fi
    desired_norm="$(md_normalize "${type}" "${desired}")"

    # Refuse to overwrite a non-scalar existing value. If the user already has
    # this key set as an array / dictionary / data blob, we cannot represent it
    # in the snapshot's per-key TSV (which only handles scalars), and clobbering
    # it with a bool/int/float/string would lose the original data without a
    # sound undo path. Skip with a clear warning instead.
    existing_type="$(md_read_type "${domain}" "${key}")"
    case "${existing_type}" in
        bool|int|float|string|__UNSET__)
            ;;  # supported; fall through to drift detection
        array|dict|data|unknown)
            log_warn "${id}: existing value has type '${existing_type}'; skipping (would clobber non-scalar user data)"
            skipped_count=$((skipped_count + 1))
            continue
            ;;
    esac

    current="$(md_read_current "${domain}" "${key}")"

    if [[ "${current}" == "__UNSET__" ]]; then
        relation="+"
        drift_count=$((drift_count + 1))
        to_write+=("${id}")
    elif [[ "${current}" == "${desired_norm}" || "${current}" == "${desired}" ]]; then
        relation="="
    else
        relation="±"
        drift_count=$((drift_count + 1))
        to_write+=("${id}")
    fi

    case "${relation}" in
        "=")
            if [[ "${verbose}" == "verbose" ]]; then
                printf '%s=%s  %s: %s\n' "${c_dim}" "${c_reset}" "${id}" "${current}"
            fi
            ;;
        "+")
            printf '%s+%s  %s: %s<unset>%s → %s%s%s\n' \
                "${c_green}" "${c_reset}" "${id}" \
                "${c_dim}" "${c_reset}" \
                "${c_green}" "${desired_norm}" "${c_reset}"
            ;;
        "±")
            printf '%s±%s  %s: %s%s%s → %s%s%s\n' \
                "${c_yellow}" "${c_reset}" "${id}" \
                "${c_red}" "${current}" "${c_reset}" \
                "${c_green}" "${desired_norm}" "${c_reset}"
            ;;
    esac
done

echo
if [[ ${drift_count} -eq 0 ]]; then
    log_success "No drift — nothing to do."
    # Machine-readable status on stdout so Ansible's `changed_when` can see it
    # regardless of whether logs are routed to stdout or stderr.
    printf 'MACOS_DEFAULTS_STATUS: aligned (skipped=%d)\n' "${skipped_count}"
    exit 0
fi
log_info "${drift_count} setting(s) drifted from desired."

if [[ "${mode}" == "dry-run" ]]; then
    printf 'MACOS_DEFAULTS_STATUS: drift drift=%d skipped=%d\n' "${drift_count}" "${skipped_count}"
    [[ "${strict}" == "strict" ]] && exit 2
    exit 0
fi

# --- Confirmation prompt (skip when non-interactive, e.g. CI / Ansible) ------
if [[ -t 0 ]]; then
    echo
    echo -n "Apply these changes? [y/N]: "
    read -r response
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# --- Apply path: per-key snapshot, write, restart, prune ---------------------

ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
snapshot_dir="${MD_SNAPSHOTS_ROOT}/${ts}"
mkdir -p "${MD_SNAPSHOTS_ROOT}"
md_snapshot_init "${snapshot_dir}"

# Index rows by id for the second pass without re-running yq.
declare -A row_lookup
for row in "${rows[@]}"; do
    IFS=$'\t' read -r id _rest <<<"${row}"
    row_lookup["${id}"]="${row}"
done

# Capture per-key snapshot of every key we're about to touch — value AND type.
for id in "${to_write[@]}"; do
    IFS=$'\t' read -r _id domain key _type _desired_raw requires_csv <<<"${row_lookup[${id}]}"
    md_snapshot_key "${snapshot_dir}" "${id}" "${domain}" "${key}" "${requires_csv}"
done
md_snapshot_publish_latest "${snapshot_dir}"
log_info "Snapshot: ${snapshot_dir}"

declare -A restart_apps=()
declare -a no_restart_keys=()
for id in "${to_write[@]}"; do
    IFS=$'\t' read -r _id domain key type desired_raw requires_csv <<<"${row_lookup[${id}]}"
    if [[ "${type}" == "string" ]]; then
        desired="$(md_expand_home "${desired_raw}")"
    else
        desired="${desired_raw}"
    fi
    md_write "${domain}" "${key}" "${type}" "${desired}" || continue

    # Sanity-check the write actually landed. defaults silently accepts writes
    # to nonexistent or sandboxed domains (Safari, etc.) without taking effect.
    readback="$(md_read_current "${domain}" "${key}")"
    expected_norm="$(md_normalize "${type}" "${desired}")"
    if [[ "${readback}" != "${expected_norm}" && "${readback}" != "${desired}" ]]; then
        log_warn "${id}: write succeeded but readback returned '${readback}' (sandbox / TCC / wrong domain?)"
    fi
    if [[ -n "${requires_csv}" ]]; then
        IFS=',' read -ra apps <<<"${requires_csv}"
        for app in "${apps[@]}"; do
            [[ -n "${app}" ]] && restart_apps["${app}"]=1
        done
    else
        no_restart_keys+=("${id}")
    fi
done

if [[ ${#restart_apps[@]} -gt 0 ]]; then
    log_section "Restarting affected applications"
    for app in "${!restart_apps[@]}"; do
        # pgrep -x matches the exact process name including spaces.
        if pgrep -x "${app}" >/dev/null 2>&1; then
            printf '  • %s\n' "${app}"
            killall "${app}" 2>/dev/null || true
        fi
    done
fi

md_prune_snapshots

echo
log_success "Applied ${drift_count} setting(s)."
if [[ ${#no_restart_keys[@]} -gt 0 ]]; then
    log_info "The following settings take effect at next use (no app restart needed):"
    printf '  • %s\n' "${no_restart_keys[@]}"
fi
printf 'MACOS_DEFAULTS_STATUS: applied applied=%d skipped=%d\n' "${drift_count}" "${skipped_count}"
