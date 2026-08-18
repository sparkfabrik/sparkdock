#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/macos-doctor/run.sh — run the macOS health checks and report.
#
# This path never mutates anything. Every check's doctor_detect is read-only and
# must never call sudo; fixes live behind fix.sh.
#
# Usage: run.sh [<check-id>|count]
#   (no argument)  run every check and print a report
#   <check-id>     run a single check (exit 2 if the id is unknown)
#   count          run only the cheap checks and print nothing but the status line
#
# "count" exists for the sparkdock-tui status row, which refreshes on every
# dashboard load and on 'r'. Restricting it to cheap=yes checks is what keeps
# that cheap: no time-based sampling, no walking large directory trees.
#
# There is also an internal mode, --detect-one, used only so the spinner can run
# a check as a child process. It is not part of the public interface.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
mdoc_require_macos

# --- Internal: run one check as a child so gum spin has something to wrap -----
#
# The findings and notes collectors are files inherited through the environment,
# so a child process contributes to the same report as an in-process run.
if [[ "${1:-}" == "--detect-one" ]]; then
    mdoc_run_detect "$2" "$3"
    exit $?
fi

target="${1:-}"
mode="report"
if [[ "${target}" == "count" ]]; then
    mode="count"
    target=""
fi

mapfile -t check_files < <(mdoc_check_files)
if [[ "${#check_files[@]}" -eq 0 ]]; then
    log_error "No checks found under ${MDOC_CHECKS_DIR}"
    exit 1
fi

# A single named check narrows the list; an unknown name is a usage error.
if [[ -n "${target}" ]]; then
    single=""
    if single="$(mdoc_file_for_id "${target}")"; then
        check_files=("${single}")
    else
        log_error "unknown check '${target}'. Run 'sjust macos-doctor-info' to list them."
        exit 2
    fi
fi

mdoc_findings_init
trap 'rm -f "${MDOC_FINDINGS_FILE}" "${MDOC_NOTES_FILE}"' EXIT

# Interactive runs get a spinner on the slow checks. Without a TTY (CI, a pipe,
# the TUI's structured renderer) the spinner is pointless and its escape codes
# are noise, so a plain progress line is used instead.
spinning=false
if [[ "${mode}" == "report" && "${HAS_GUM}" = true && -t 1 && -z "${NO_COLOR:-}" ]]; then
    spinning=true
fi

run_check() {
    local file="$1" id="$2" title="$3" cheap="$4"

    # Cheap checks finish fast enough that a spinner would only flicker.
    if [[ "${cheap}" == "yes" || "${spinning}" == false ]]; then
        [[ "${mode}" == "report" && "${cheap}" != "yes" ]] && log_info "checking ${title}…"
        mdoc_run_detect "${file}" "${id}"
        return $?
    fi

    gum spin --spinner dot --title "checking ${title}…" -- \
        "${SCRIPT_DIR}/run.sh" --detect-one "${file}" "${id}"
}

[[ "${mode}" == "report" ]] && log_section "Sparkdock macOS doctor"

ran=0
skipped=0
failed=0
clean_ids=()
found_ids=()
declare -a report_order=()
declare -A report_title=()

for file in "${check_files[@]}"; do
    IFS=$'\t' read -r id title _summary cheap _fixable _reversible < <(mdoc_meta "${file}")

    if [[ "${mode}" == "count" && "${cheap}" != "yes" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    before="$(mdoc_severity_count)"

    if ! run_check "${file}" "${id}" "${title}" "${cheap}"; then
        log_warn "${id}: check failed to complete"
        failed=$((failed + 1))
        continue
    fi
    ran=$((ran + 1))

    after="$(mdoc_severity_count)"
    if [[ "${after}" -gt "${before}" ]]; then
        found_ids+=("${id}")
        report_order+=("${id}")
        report_title["${id}"]="${title}"
    else
        clean_ids+=("${id}")
    fi
done

total="$(mdoc_severity_count)"

# --- Report ------------------------------------------------------------------
#
# Rendering happens after every check has finished, never interleaved with
# detection. A check that printed while running would land above its own heading.

if [[ "${mode}" == "report" ]]; then
    for id in "${report_order[@]}"; do
        printf '\n'
        mdoc_section_label "${report_title[${id}]}"
        mdoc_render_findings "${id}"
    done

    printf '\n'
    mdoc_section_label "Summary"
    printf '\n'

    if [[ "${total}" -eq 0 ]]; then
        log_success "Nothing to report across ${ran} check(s)."
    else
        # Counts by severity, so the shape of the report is readable at a glance.
        n_cruft="$(mdoc_severity_count cruft)"
        n_warn="$(mdoc_severity_count warn)"
        n_info="$(mdoc_severity_count info)"

        tsv="SEVERITY"$'\t'"COUNT"$'\t'"MEANING"$'\n'
        [[ "${n_cruft}" -gt 0 ]] && tsv+="cruft"$'\t'"${n_cruft}"$'\t'"dead weight, safe to remove"$'\n'
        [[ "${n_warn}" -gt 0 ]] && tsv+="warn"$'\t'"${n_warn}"$'\t'"needs a decision from you"$'\n'
        [[ "${n_info}" -gt 0 ]] && tsv+="info"$'\t'"${n_info}"$'\t'"context, no action required"$'\n'
        render_table <<<"${tsv%$'\n'}"

        printf '\n'

        # Only checks that can actually act on their findings get a fix command.
        # Offering one for a report-only check sends you to an exit 2.
        next=()
        for id in "${report_order[@]}"; do
            file="$(mdoc_file_for_id "${id}")" || continue
            IFS=$'\t' read -r _ _ _ _ fixable reversible < <(mdoc_meta "${file}")
            [[ "${fixable}" == "yes" ]] || continue
            if [[ "${reversible}" == "yes" ]]; then
                next+=("sjust macos-doctor-fix ${id}   (reversible, undo with macos-doctor-undo)")
            else
                next+=("sjust macos-doctor-fix ${id}   (NOT reversible, asks twice)")
            fi
        done

        if [[ "${#next[@]}" -gt 0 ]]; then
            mdoc_section_label "What you can fix from here"
            printf '\n'
            for line in "${next[@]}"; do
                mdoc_faint "    ${line}"
            done
            printf '\n'
            mdoc_faint "    Preview any of them first with: sjust macos-doctor-fix <check-id> dry-run"
            printf '\n'
        fi

        log_info "The remaining findings print their own commands above."
    fi

    if [[ "${#clean_ids[@]}" -gt 0 ]]; then
        mdoc_faint "Clean: ${clean_ids[*]}"
    fi
    if [[ "${failed}" -gt 0 ]]; then
        log_warn "${failed} check(s) failed to complete."
    fi
    mdoc_faint "Details for every check: sjust macos-doctor-info"
    printf '\n'
fi

# Machine-readable summary on stdout. Logging goes to stderr, so this line stays
# parseable by Ansible changed_when, CI greps and the sparkdock-tui status row.
printf 'MACOS_DOCTOR_STATUS: findings=%d cruft=%d warn=%d info=%d checks=%d skipped=%d failed=%d ids=%s\n' \
    "${total}" \
    "$(mdoc_severity_count cruft)" \
    "$(mdoc_severity_count warn)" \
    "$(mdoc_severity_count info)" \
    "${ran}" \
    "${skipped}" \
    "${failed}" \
    "$(
        IFS=,
        printf '%s' "${found_ids[*]:-}"
    )"
