#!/usr/bin/env bash
set -euo pipefail
#
# Pretty-print the curated macOS defaults profile, grouped by category.
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

mode="${1:-pretty}"

case "${mode}" in
    pretty|raw) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: pretty, raw."
        exit 2
        ;;
esac

md_check_yq

render_markdown() {
    local total cats
    total="$(yq eval '. | length' "${MD_CONFIG_FILE}")"
    cats="$(yq eval '. | to_entries | map(.value.category) | unique | length' "${MD_CONFIG_FILE}")"

    cat <<MD
# Sparkdock — curated macOS defaults

**${total} settings** across **${cats} categories**, applied by \`sjust macos-defaults\`.

## What this command applies

- Every setting below is written via \`defaults write\` only when the current value differs from the desired one — second runs are no-ops.
- Before any change, the affected preference domains are exported to \`~/.local/spark/macos-defaults/snapshots/<UTC-timestamp>/\`. Run \`sjust macos-defaults-undo\` to roll back.
- Apps in the **Restarts** column are \`killall\`-ed only when one of their settings actually changed.

## How to customise

Sparkdock applies an opinionated-but-conservative default set. Anything you disagree with goes in your personal overrides file (same shape as \`config/macos/defaults.yml\`):

\`\`\`yaml
# ~/.local/spark/macos-defaults/overrides.yml
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
sjust macos-defaults-undo            # roll back the latest snapshot
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
        printf '| Setting | Default | Description |\n'
        printf '| --- | --- | --- |\n'
        yq eval "
            . | to_entries
            | map(select(.value.category == \"${cat}\"))
            | sort_by(.value.key) | .[]
            | [
                (.value.domain + \".\" + .value.key),
                (.value.value | tostring),
                .value.description
              ]
            | @tsv
        " "${MD_CONFIG_FILE}" | while IFS=$'\t' read -r setting value description; do
            # shellcheck disable=SC2016 # backticks are literal Markdown
            printf '| `%s` | `%s` | %s |\n' "${setting}" "${value}" "${description}"
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
