#!/usr/bin/env bash
set -euo pipefail
#
# Pretty-print the curated macOS defaults profile, grouped by category, with
# per-setting current-state markers (✓ aligned, ✗ drifted, +. unset).
# Pipes through `gum format` (and `gum pager` when stdout is a TTY) for color
# and pagination. Falls back to plain Markdown when gum is unavailable or the
# output is being captured.
#
# Usage: info.sh [<mode>]
#   pretty (default)   colored, paginated when interactive
#   raw                plain Markdown to stdout (suitable for piping)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
md_require_macos_version

mode="${1:-pretty}"

case "${mode}" in
    pretty|raw) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: pretty, raw."
        exit 2
        ;;
esac

md_check_yq

# Compute current-state marker for one entry.
state_marker() {
    local domain="$1" key="$2" type="$3" desired_raw="$4"
    local desired desired_norm current
    if [[ "${type}" == "string" ]]; then
        desired="$(md_expand_home "${desired_raw}")"
    else
        desired="${desired_raw}"
    fi
    desired_norm="$(md_normalize "${type}" "${desired}")"
    current="$(md_read_current "${domain}" "${key}")"
    if [[ "${current}" == "__UNSET__" ]]; then
        printf '+'
    elif [[ "${current}" == "${desired_norm}" || "${current}" == "${desired}" ]]; then
        printf '✓'
    else
        printf '✗'
    fi
}

render_markdown() {
    local total cats
    total="$(yq eval '. | length' "${MD_CONFIG_FILE}")"
    cats="$(yq eval '. | to_entries | map(.value.category) | unique | length' "${MD_CONFIG_FILE}")"

    cat <<MD
# Sparkdock — curated macOS defaults

**${total} settings** across **${cats} categories**.

This is a deliberately tiny set: filesystem hygiene (no \`.DS_Store\` on networks/USB), one annoying prompt suppressed (Time Machine), secure keyboard entry in Terminal, UTF-8 in TextEdit, and expanded save / print panels. Personal preferences (dock, Finder layout, smart-quotes, accent picker, trackpad, reduce-motion, etc.) live only in your overrides file.

## What this command applies

- Every setting below is written via \`defaults write\` only when the current value differs from the desired one — second runs are no-ops.
- Before any change, the keys sparkdock is about to touch are recorded per-key into a snapshot at \`~/.local/spark/macos-defaults/snapshots/<UTC-timestamp>/\`. \`sjust macos-defaults-undo\` rolls back **only those keys**, leaving any unrelated changes you made in the same preference domain intact.
- Apps in the **Restarts** column are \`killall\`-ed only when one of their settings actually changed.

## Status legend

- \`✓\` already at the desired value (idempotent — apply will skip)
- \`✗\` set to a different value (apply will overwrite, undoable)
- \`+\` not set yet (apply will create it, undoable as delete)

## How to customise

Sparkdock applies an opinionated-but-conservative default set. Anything you want differently goes in your personal overrides file (same shape as \`config/macos/defaults.yml\`). Bootstrap the file with:

\`\`\`bash
sjust macos-defaults-init-overrides     # creates ~/.local/spark/macos-defaults/overrides.yml
\`\`\`

then edit it, e.g. to enable dock auto-hide:

\`\`\`yaml
"com.apple.dock.autohide":
  domain: com.apple.dock
  key: autohide
  type: bool
  value: true
  description: Auto-hide my dock
  category: dock
  requires: [Dock]
\`\`\`

Overrides are merged by exact key, so you only touch what you care about.

## Useful commands

\`\`\`
sjust macos-defaults dry-run         # preview drift, no changes
sjust macos-defaults dry-run strict  # exit 2 on drift (CI)
sjust macos-defaults                 # apply
sjust macos-defaults-undo            # roll back the latest snapshot (per-key)
sjust macos-defaults-undo list       # list available snapshots
sjust macos-defaults-docs            # print the README table to stdout
\`\`\`

---

## Curated settings, by category

MD

    local -a cat_list
    mapfile -t cat_list < <(
        yq eval '. | to_entries | map(.value.category) | unique | .[]' "${MD_CONFIG_FILE}"
    )

    local cat
    for cat in "${cat_list[@]}"; do
        printf '\n### %s\n\n' "${cat}"
        printf '| State | Setting | Default | Description |\n'
        printf '| --- | --- | --- | --- |\n'
        # strenv binds $cat as a yq env-var (https://mikefarah.gitbook.io/yq/operators/env-variable-operators)
        # so a category name with quotes/backslashes wouldn't break the filter.
        local cat_yq="${cat}"
        export cat_yq
        yq eval '
            . | to_entries
            | map(select(.value.category == strenv(cat_yq)))
            | sort_by(.value.key) | .[]
            | [
                .value.domain,
                .value.key,
                .value.type,
                (.value.value | tostring),
                .value.description
              ]
            | @tsv
        ' "${MD_CONFIG_FILE}" | while IFS=$'\t' read -r domain key type value description; do
            local marker
            marker="$(state_marker "${domain}" "${key}" "${type}" "${value}")"
            # shellcheck disable=SC2016 # backticks are literal Markdown
            printf '| %s | `%s.%s` | `%s` | %s |\n' \
                "${marker}" "${domain}" "${key}" "${value}" "${description}"
        done
    done
}

if [[ "${mode}" == "raw" ]]; then
    render_markdown
    exit 0
fi

# pretty mode: prefer gum format + pager when interactive.
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
