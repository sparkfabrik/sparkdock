#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2030,SC2031
# (SC2034 = "appears unused": this file is sourced by run.sh / info.sh / fix.sh /
# undo.sh and by every check under checks/. The MDOC_* variables below ARE used,
# but only in those sourcing scripts, which shellcheck cannot see across files.
# Disabling at the file level keeps the variable declarations clean.
#
# SC2030/SC2031 = "modified in a subshell, that change might be lost": that is
# the design. mdoc_run_detect exports MDOC_CURRENT_CHECK inside the subshell that
# also sources the check and calls doctor_finding, so writer and reader are the
# same subshell. shellcheck cannot follow that across the source boundary.)
#
# sjust/scripts/macos-doctor/lib.sh — shared helpers for the macos-doctor scripts.
#
# Sourced by run.sh, info.sh, fix.sh, undo.sh. Provides:
#   mdoc_require_macos      — bail out cleanly on non-macOS hosts
#   mdoc_check_files        — the registry: checks/*.sh sorted by NN- prefix
#   mdoc_meta               — read one check's doctor_meta TSV line
#   mdoc_run_detect         — run one check's doctor_detect in an isolated subshell
#   mdoc_findings_init      — create the findings collector file
#   doctor_finding          — record a finding (called from inside a check)
#   mdoc_findings_for       — findings belonging to one check
#   mdoc_severity_count     — count findings, optionally by severity
#   mdoc_render_findings    — render a check's findings as a table
#   mdoc_label_excluded     — hard label exclusions (Apple, MDM)
#   mdoc_path_excluded      — hard path exclusions (/System, privileged helpers)
#   mdoc_confirm            — TTY-gated yes/no prompt, declines when not a TTY
#   mdoc_quarantine_new     — create a quarantine snapshot dir (printed on stdout)
#   mdoc_quarantine_store   — move one path into quarantine and record it
#   mdoc_quarantine_publish_latest — update the relative "latest" symlink
#   mdoc_quarantine_restore — move everything in a snapshot back to its origin
#   mdoc_prune_quarantine   — keep only the N newest snapshot directories
#
# Checks are code, not data. A check registers itself by existing in checks/;
# there is no catalog file and no yq dependency. Each check file defines
# doctor_meta, doctor_detect, doctor_explain and (when fixable) doctor_fix, and
# is always sourced inside a subshell so that several checks defining the same
# function names cannot collide with each other.
#
# Findings live in a file rather than a shell array precisely because checks run
# in subshells: a child cannot write back into the parent's memory, but it can
# append to a file whose path it inherited through the environment.
#
# Findings TSV (no header), one line per finding:
#
#   check_id<TAB>severity<TAB>subject<TAB>detail<TAB>remedy
#
# Quarantine manifest TSV (no header), one line per moved path:
#
#   check_id<TAB>label<TAB>original_abs_path<TAB>needed_sudo
#
# The moved file itself is stored under <snapshot>/files/<original path without
# the leading slash>, so a restore is a plain move back and needs no guessing.

if [[ "${_SPARKDOCK_MACOS_DOCTOR_LIB_LOADED:-}" = "1" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || true
fi
_SPARKDOCK_MACOS_DOCTOR_LIB_LOADED=1

# shellcheck source=../../libs/libshell.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/sjust/libs/libshell.sh"

# --- Canonical paths and tunables -------------------------------------------

MDOC_CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/checks"
MDOC_STATE_ROOT="${HOME}/.local/spark/macos-doctor"
MDOC_QUARANTINE_ROOT="${MDOC_STATE_ROOT}/quarantine"
MDOC_QUARANTINE_RETENTION=10
MDOC_LOCK_FILE="${MDOC_STATE_ROOT}/.lock"

# Valid severities, most to least serious. "cruft" is dead weight that can go,
# "warn" needs a human decision, "info" is context worth printing.
MDOC_SEVERITIES=(cruft warn info)

# --- Hard exclusions ---------------------------------------------------------
#
# These are deliberately not configurable. Apple's own agents are managed by the
# OS and protected by SIP. Mosyle and Jamf push managed items on this fleet, so
# removing one either gets re-pushed on the next check-in or breaks compliance
# reporting. A check that wants to report on them may do so; none may offer to
# remove them.

MDOC_EXCLUDED_LABEL_GLOBS=(
    'com.apple.*'
    'com.mosyle.*'
    'com.jamf.*'
)

# Paths that must never be moved or deleted. /System is SIP-protected.
# PrivilegedHelperTools holds root helpers whose absence breaks a later reinstall
# of the owning app, and a present-but-unused helper costs nothing.
MDOC_EXCLUDED_PATH_GLOBS=(
    '/System/*'
    '/usr/bin/*'
    '/usr/sbin/*'
    '/Library/PrivilegedHelperTools/*'
)

# --- Platform guard ----------------------------------------------------------

# Exit 0 rather than failing: a non-macOS host is a skip, not an error, so CI and
# Ansible treat it the same way md_require_macos_version does for old macOS.
mdoc_require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_warn "macos-doctor only runs on macOS (detected: $(uname -s)). Skipping."
        exit 0
    fi
}

# --- Check registry ----------------------------------------------------------

# Print every check file path, ordered by the NN- prefix.
mdoc_check_files() {
    [[ -d "${MDOC_CHECKS_DIR}" ]] || return 0
    find "${MDOC_CHECKS_DIR}" -mindepth 1 -maxdepth 1 -name '[0-9][0-9]-*.sh' -type f | sort
}

# Print one check's doctor_meta line. Sourced in a subshell so the check's
# function definitions never leak into the caller.
# Usage: IFS=$'\t' read -r id title summary cheap fixable reversible < <(mdoc_meta "${file}")
mdoc_meta() {
    local file="$1"
    (
        # shellcheck source=/dev/null
        source "${file}"
        doctor_meta
    )
}

# Resolve a check id to its file path, or return 1 when unknown.
mdoc_file_for_id() {
    local want="$1" file id
    while IFS= read -r file; do
        [[ -n "${file}" ]] || continue
        id="$(mdoc_meta "${file}" | cut -f1)"
        if [[ "${id}" == "${want}" ]]; then
            printf '%s' "${file}"
            return 0
        fi
    done < <(mdoc_check_files)
    return 1
}

# Run one check's doctor_detect. The check appends to MDOC_FINDINGS_FILE, which
# it inherits from the environment. A check that fails must not abort the run, so
# the subshell's exit status is swallowed and reported by the caller instead.
mdoc_run_detect() {
    local file="$1" id="$2"
    (
        export MDOC_CURRENT_CHECK="${id}"
        # shellcheck source=/dev/null
        source "${file}"
        doctor_detect
    ) || return 1
}

# Print what a check's fix manages, one "<subject>\t<detail>\t<actionable>" row
# each, where actionable is yes or no.
#
# Rows with actionable=no are things the fix knows about but will not touch on this
# run: an already-empty cache, or a root-owned plist without the system scope.
# Listing them is what makes "nothing to do" comprehensible instead of mysterious,
# and it is where the user learns the command that would widen the scope.
#
# An omitted third column is treated as actionable, so the findings fallback below
# keeps working for checks whose fix acts on everything they report.
#
# This exists because a check's findings and its fix targets are not the same set.
# dev-caches reports every cache directory but only deletes the regenerable
# subset; launchd-orphans reports root-owned plists but skips them without the
# system scope. Confirming an irreversible action against the wrong list is how a
# prompt becomes a rubber stamp, so fix.sh asks about these rows, not the findings.
#
# A check without the hook falls back to its findings, which is correct for checks
# whose fix acts on everything it reports.
mdoc_fix_targets() {
    local file="$1" id="$2" scope="${3:-}"
    (
        export MDOC_CURRENT_CHECK="${id}"
        export MDOC_SCOPE="${scope}"
        # shellcheck source=/dev/null
        source "${file}"
        if declare -F doctor_fix_targets >/dev/null 2>&1; then
            doctor_fix_targets
        else
            mdoc_findings_for "${id}" | cut -f3,4
        fi
    ) | awk -F'\t' 'NF > 0 { if ($3 == "") $3 = "yes"; print $1 "\t" $2 "\t" $3 }' OFS='\t'
}

# Keep only the rows a fix will actually act on.
mdoc_fix_actionable() {
    awk -F'\t' '$3 == "yes"'
}

# Print a check's doctor_explain markdown body.
mdoc_explain() {
    local file="$1"
    (
        # shellcheck source=/dev/null
        source "${file}"
        if declare -F doctor_explain >/dev/null 2>&1; then
            doctor_explain
        fi
    )
}

# --- Findings collector ------------------------------------------------------

# Create the collectors and export their paths so checks running in subshells can
# append to them. Caller owns cleanup via
# `trap 'rm -f "${MDOC_FINDINGS_FILE}" "${MDOC_NOTES_FILE}"' EXIT`.
mdoc_findings_init() {
    MDOC_FINDINGS_FILE="$(mktemp -t macos-doctor.XXXXXX)"
    MDOC_NOTES_FILE="$(mktemp -t macos-doctor-notes.XXXXXX)"
    export MDOC_FINDINGS_FILE MDOC_NOTES_FILE
}

# Record a line of guidance for the current check, rendered underneath its table.
#
# A check must never print to stdout itself. Detection and rendering are separate
# phases, so anything a check writes directly lands before its own section header
# and reads as though it belonged to the previous check.
doctor_note() {
    local text="$*"
    text="${text//$'\t'/ }"
    printf '%s\t%s\n' "${MDOC_CURRENT_CHECK:-unknown}" "${text}" >>"${MDOC_NOTES_FILE}"
}

# Print the notes belonging to one check.
mdoc_notes_for() {
    local id="$1"
    [[ -f "${MDOC_NOTES_FILE:-}" ]] || return 0
    awk -F'\t' -v id="${id}" '$1 == id { sub(/^[^\t]*\t/, ""); print }' "${MDOC_NOTES_FILE}"
}

# Record a finding. Called from inside a check's doctor_detect.
# Usage: doctor_finding <severity> <subject> <detail> [remedy]
doctor_finding() {
    local severity="$1" subject="$2" detail="$3" remedy="${4:-}"

    case "${severity}" in
        cruft | warn | info) ;;
        *)
            log_warn "${MDOC_CURRENT_CHECK:-?}: invalid severity '${severity}', recording as info"
            severity="info"
            ;;
    esac

    # Tabs and newlines would corrupt the TSV; collapse them.
    subject="${subject//$'\t'/ }"
    subject="${subject//$'\n'/ }"
    detail="${detail//$'\t'/ }"
    detail="${detail//$'\n'/ }"
    remedy="${remedy//$'\t'/ }"
    remedy="${remedy//$'\n'/ }"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${MDOC_CURRENT_CHECK:-unknown}" "${severity}" "${subject}" "${detail}" "${remedy}" \
        >>"${MDOC_FINDINGS_FILE}"
}

# Print the findings belonging to one check.
mdoc_findings_for() {
    local id="$1"
    [[ -f "${MDOC_FINDINGS_FILE:-}" ]] || return 0
    awk -F'\t' -v id="${id}" '$1 == id' "${MDOC_FINDINGS_FILE}"
}

# Count findings. With no argument, counts them all; with one, counts a severity.
mdoc_severity_count() {
    local severity="${1:-}"
    [[ -f "${MDOC_FINDINGS_FILE:-}" ]] || {
        printf '0'
        return 0
    }
    if [[ -z "${severity}" ]]; then
        awk 'END { print NR + 0 }' "${MDOC_FINDINGS_FILE}"
        return 0
    fi
    awk -F'\t' -v s="${severity}" '$2 == s { n++ } END { print n + 0 }' "${MDOC_FINDINGS_FILE}"
}

# --- Rendering ---------------------------------------------------------------

# Section heading, matching bin/sparkdock-agents-status.
mdoc_section_label() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum style --bold --foreground 99 "$*"
    else
        printf '\n%b%s%b\n' "${BOLD}" "$*" "${NC}"
    fi
}

# Faint trailing note.
mdoc_faint() {
    if [[ "${HAS_GUM}" = true ]]; then
        gum style --faint "$*"
    else
        printf '%s\n' "$*"
    fi
}

# Render one check's findings as a table. Severity is colorized after rendering
# so the escape sequences cannot break gum's column alignment.
mdoc_render_findings() {
    local id="$1"
    local rows table
    rows="$(mdoc_findings_for "${id}")"
    [[ -n "${rows}" ]] || return 0

    local tsv
    tsv="SEVERITY"$'\t'"SUBJECT"$'\t'"DETAIL"$'\n'
    tsv+="$(printf '%s\n' "${rows}" | cut -f2,3,4)"

    table="$(render_table <<<"${tsv}")"

    if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]] || ! command -v perl >/dev/null 2>&1; then
        printf '%s\n' "${table}"
    else
        printf '%s\n' "${table}" | perl -pe '
            s/\bcruft\b/\e[38;5;220mcruft\e[0m/g;
            s/\bwarn\b/\e[38;5;214mwarn\e[0m/g;
            s/\binfo\b/\e[2minfo\e[0m/g;
        '
    fi

    # Remedies are printed under the table: they are commands, and a command in a
    # table cell either wraps badly or blows the column width out. Identical
    # remedies are collapsed, because repeating the same command once per row is
    # noise rather than information.
    local remedies
    remedies="$(printf '%s\n' "${rows}" | cut -f5 | grep -v '^$' | sort -u || true)"
    if [[ -n "${remedies}" ]]; then
        printf '\n'
        local remedy
        while IFS= read -r remedy; do
            [[ -n "${remedy}" ]] || continue
            mdoc_faint "    ${remedy}"
        done <<<"${remedies}"
    fi

    # Then any longer-form guidance the check recorded with doctor_note.
    local notes
    notes="$(mdoc_notes_for "${id}")"
    if [[ -n "${notes}" ]]; then
        printf '\n'
        local note
        while IFS= read -r note; do
            mdoc_faint "    ${note}"
        done <<<"${notes}"
    fi
}

# --- Dry run -----------------------------------------------------------------

# Report whether the current fix run is a dry run.
mdoc_is_dry_run() {
    [[ "${MDOC_DRY_RUN:-0}" == "1" ]]
}

# In a dry run, describe the mutation and return 0 so the caller skips it. In a
# real run, return 1 so the caller proceeds.
#
# Usage:
#   mdoc_would "delete snapshot ${name}" && continue
#   sudo tmutil deletelocalsnapshots "${name}"
mdoc_would() {
    mdoc_is_dry_run || return 1
    log_info "would ${*}"
    return 0
}

# --- Exclusions --------------------------------------------------------------

# Return 0 when a launchd label must never be touched.
mdoc_label_excluded() {
    local label="$1" glob
    for glob in "${MDOC_EXCLUDED_LABEL_GLOBS[@]}"; do
        # shellcheck disable=SC2053
        [[ "${label}" == ${glob} ]] && return 0
    done
    return 1
}

# Return 0 when a path must never be moved or deleted.
mdoc_path_excluded() {
    local path="$1" glob
    for glob in "${MDOC_EXCLUDED_PATH_GLOBS[@]}"; do
        # shellcheck disable=SC2053
        [[ "${path}" == ${glob} ]] && return 0
    done
    return 1
}

# --- Confirmation ------------------------------------------------------------

# Ask a yes/no question. Declines when there is no TTY, so an unattended caller
# can never accidentally consent to a mutation.
mdoc_confirm() {
    local prompt="$1" reply
    if [[ ! -t 0 ]]; then
        log_warn "Not a TTY, declining: ${prompt}"
        return 1
    fi
    read -r -p "${prompt} (y/n) " -n 1 reply
    printf '\n'
    [[ "${reply}" =~ ^[Yy]$ ]]
}

# --- Quarantine --------------------------------------------------------------

# Create a new snapshot directory and print its path. The timestamp format
# matches macos-defaults: UTC, filesystem-safe, and lexicographically sortable,
# which is what listing, "restore latest" and pruning all rely on.
mdoc_quarantine_new() {
    local ts dir
    ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    dir="${MDOC_QUARANTINE_ROOT}/${ts}"
    mkdir -p "${dir}/files"
    : >"${dir}/manifest.tsv"
    printf '%s' "${dir}"
}

# Move one path into a snapshot and record it in the manifest.
# Usage: mdoc_quarantine_store <snapshot_dir> <check_id> <label> <abs_path>
mdoc_quarantine_store() {
    local dir="$1" check_id="$2" label="$3" path="$4"

    if mdoc_path_excluded "${path}"; then
        log_error "refusing to quarantine an excluded path: ${path}"
        return 1
    fi
    if [[ ! -e "${path}" ]]; then
        log_warn "nothing to quarantine at ${path}"
        return 1
    fi

    mdoc_would "move ${path} into quarantine" && return 0

    # Preserve the original absolute path inside files/ so restore is a plain
    # move back with no path reconstruction.
    local dest="${dir}/files${path}"
    mkdir -p "$(dirname "${dest}")"

    local needed_sudo="no"
    if mv "${path}" "${dest}" 2>/dev/null; then
        :
    elif sudo mv "${path}" "${dest}"; then
        needed_sudo="yes"
    else
        log_error "failed to quarantine ${path}"
        return 1
    fi

    printf '%s\t%s\t%s\t%s\n' "${check_id}" "${label}" "${path}" "${needed_sudo}" \
        >>"${dir}/manifest.tsv"
    log_success "quarantined ${path}"
}

# Update the relative "latest" symlink next to the snapshot directories.
mdoc_quarantine_publish_latest() {
    local dir="$1"
    ln -sfn "$(basename "${dir}")" "$(dirname "${dir}")/latest"
}

# Move every path in a snapshot back where it came from.
mdoc_quarantine_restore() {
    local dir="$1"
    local manifest="${dir}/manifest.tsv"

    if [[ ! -f "${manifest}" ]]; then
        log_error "No manifest at ${manifest}"
        return 1
    fi

    local check_id label path needed_sudo src restored=0
    while IFS=$'\t' read -r check_id label path needed_sudo; do
        [[ -n "${path}" ]] || continue
        src="${dir}/files${path}"
        if [[ ! -e "${src}" ]]; then
            log_warn "missing from quarantine, skipping: ${path}"
            continue
        fi
        if [[ -e "${path}" ]]; then
            log_warn "already exists, skipping: ${path}"
            continue
        fi

        if [[ "${needed_sudo}" == "yes" ]]; then
            sudo mkdir -p "$(dirname "${path}")" && sudo mv "${src}" "${path}"
        else
            mkdir -p "$(dirname "${path}")" && mv "${src}" "${path}"
        fi || {
            log_error "failed to restore ${path}"
            continue
        }

        log_success "restored ${path}"
        restored=$((restored + 1))

        # A launchd plist is inert until it is loaded again.
        if [[ "${check_id}" == "launchd-orphans" && "${path}" == *.plist ]]; then
            case "${path}" in
                /Library/LaunchDaemons/*)
                    sudo launchctl bootstrap system "${path}" 2>/dev/null || true
                    ;;
                *)
                    launchctl bootstrap "gui/$(id -u)" "${path}" 2>/dev/null || true
                    ;;
            esac
        fi
    done <"${manifest}"

    log_info "Restored ${restored} path(s) from ${dir##*/}."
}

# Keep only the N newest snapshot directories. -type d excludes the "latest"
# symlink from both the count and the deletion.
mdoc_prune_quarantine() {
    local keep="${1:-${MDOC_QUARANTINE_RETENTION}}"
    [[ -d "${MDOC_QUARANTINE_ROOT}" ]] || return 0
    local skip=$((keep + 1))
    local old
    while IFS= read -r old; do
        [[ -n "${old}" ]] && rm -rf "${old}"
    done < <(
        find "${MDOC_QUARANTINE_ROOT}" -mindepth 1 -maxdepth 1 -type d \
            | sort -r | tail -n "+${skip}"
    )
}
