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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
mdoc_require_macos

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
trap 'rm -f "${MDOC_FINDINGS_FILE}"' EXIT

[[ "${mode}" == "report" ]] && log_section "macOS doctor"

ran=0
skipped=0
failed=0
clean_ids=()
found_ids=()

for file in "${check_files[@]}"; do
    IFS=$'\t' read -r id title _summary cheap _fixable _reversible < <(mdoc_meta "${file}")

    if [[ "${mode}" == "count" && "${cheap}" != "yes" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    before="$(mdoc_severity_count)"

    if ! mdoc_run_detect "${file}" "${id}"; then
        log_warn "${id}: check failed to complete"
        failed=$((failed + 1))
        continue
    fi
    ran=$((ran + 1))

    after="$(mdoc_severity_count)"
    if [[ "${after}" -gt "${before}" ]]; then
        found_ids+=("${id}")
        if [[ "${mode}" == "report" ]]; then
            printf '\n'
            mdoc_section_label "${title}"
            mdoc_render_findings "${id}"
        fi
    else
        clean_ids+=("${id}")
    fi
done

total="$(mdoc_severity_count)"

if [[ "${mode}" == "report" ]]; then
    if [[ "${#clean_ids[@]}" -gt 0 ]]; then
        printf '\n'
        mdoc_faint "Clean: ${clean_ids[*]}"
    fi

    printf '\n'
    if [[ "${total}" -eq 0 ]]; then
        log_success "No findings across ${ran} check(s)."
    else
        log_info "${total} finding(s) across ${#found_ids[@]} of ${ran} check(s): ${found_ids[*]}"
        log_info "Fix one with: sjust macos-doctor-fix <check-id>"
    fi
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
