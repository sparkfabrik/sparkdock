#!/usr/bin/env bash
set -euo pipefail
#
# sjust/scripts/macos-doctor/info.sh — document every registered check.
#
# Usage: info.sh [<mode>]
#   pretty  render markdown through gum and page it (default)
#   raw     print the markdown to stdout, no pager
#
# The document is generated from the checks themselves, so a new file under
# checks/ shows up here with no edit to this script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
mdoc_require_macos

mode="${1:-pretty}"
case "${mode}" in
    pretty | raw) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: pretty, raw."
        exit 2
        ;;
esac

render_markdown() {
    mapfile -t check_files < <(mdoc_check_files)

    cat <<MD
# Sparkdock macOS doctor

Diagnostics for a provisioned Mac. \`sjust macos-doctor\` runs every check and
reports; it never changes anything. Fixes are opt-in, one check at a time.

## Commands

\`\`\`bash
sjust macos-doctor                      # report everything
sjust macos-doctor <check-id>           # report one check
sjust macos-doctor-fix <check-id>       # fix one check (confirmation required)
sjust macos-doctor-fix <check-id> system # also act on root-owned paths
sjust macos-doctor-undo                 # list quarantine snapshots
sjust macos-doctor-undo restore         # restore the newest snapshot
\`\`\`

## Severities

- \`cruft\`: dead weight that can be removed
- \`warn\`: needs a human decision
- \`info\`: context worth printing

## Flags in the table below

- **cheap** means safe to run on every sparkdock-tui dashboard refresh. Checks that
  sample over time or walk large directory trees are not cheap, and only run on
  an explicit \`sjust macos-doctor\`.
- **fixable** means an automated fix exists.
- **reversible** means the fix moves things into a quarantine snapshot that
  \`sjust macos-doctor-undo\` can restore. When this is \`no\`, the fix deletes
  something that cannot be recreated, and asks twice before doing it.

## Checks

| id | cheap | fixable | reversible | summary |
| --- | --- | --- | --- | --- |
MD

    local file id title summary cheap fixable reversible
    for file in "${check_files[@]}"; do
        IFS=$'\t' read -r id title summary cheap fixable reversible < <(mdoc_meta "${file}")
        # shellcheck disable=SC2016  # literal backticks for markdown, not expansion
        printf '| `%s` | %s | %s | %s | %s |\n' \
            "${id}" "${cheap}" "${fixable}" "${reversible}" "${summary}"
    done

    for file in "${check_files[@]}"; do
        IFS=$'\t' read -r id title _summary _cheap _fixable _reversible < <(mdoc_meta "${file}")
        # shellcheck disable=SC2016  # literal backticks for markdown, not expansion
        printf '\n### %s (`%s`)\n\n' "${title}" "${id}"
        mdoc_explain "${file}"
    done

    cat <<'MD'

## State on disk

Quarantined paths live under `~/.local/spark/macos-doctor/quarantine/<UTC-timestamp>/`,
with the original absolute path preserved under `files/` and a `manifest.tsv`
recording where each one came from. The ten newest snapshots are kept.

## Adding a check

Drop a `checks/NN-<name>.sh` file defining `doctor_meta`, `doctor_detect`,
`doctor_explain` and, when it can fix something, `doctor_fix`. There is no
catalog to edit: the file being there is the registration.

A `doctor_detect` must be read-only and must never call `sudo`. Report findings
with `doctor_finding <severity> <subject> <detail> [remedy]`.
MD
}

if [[ "${mode}" == "raw" ]]; then
    render_markdown
    exit 0
fi

md_output="$(render_markdown)"

if command -v gum >/dev/null 2>&1; then
    if [[ -t 1 ]]; then
        printf '%s' "${md_output}" | gum format -t markdown | gum pager
    else
        printf '%s' "${md_output}" | gum format -t markdown
    fi
else
    printf '%s' "${md_output}"
fi
