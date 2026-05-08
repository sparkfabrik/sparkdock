#!/usr/bin/env bash
set -euo pipefail
#
# Generate, verify, or write the macOS-defaults Markdown table embedded in
# README.md.
#
# Usage: docs.sh [<mode>]
#   print  (default)  emit the rendered block to stdout
#   check             exit non-zero if the README block differs from a fresh render
#   write             rewrite the README block from the curated YAML

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

mode="${1:-print}"

case "${mode}" in
    print|check|write) ;;
    *)
        log_error "unknown mode '${mode}'. Valid: print, check, write."
        exit 2
        ;;
esac

md_check_yq

readme="${SPARKDOCK_ROOT}/README.md"
start_marker="<!-- macos-defaults:start -->"
end_marker="<!-- macos-defaults:end -->"

render_table() {
    printf '%s\n' "${start_marker}"
    printf '\n<!-- prettier-ignore-start -->\n\n'
    # shellcheck disable=SC2016 # backticks are literal Markdown
    printf '_This table is generated from `config/macos/defaults.yml` by `sjust macos-defaults-docs write`. Do not edit by hand._\n\n'
    printf '| Category | Domain | Key | Type | Default | Description | Restarts |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    yq eval '
        . | to_entries
        | sort_by(.value.category, .value.key) | .[]
        | [
            .value.category,
            .value.domain,
            .value.key,
            .value.type,
            (.value.value | tostring),
            .value.description,
            ((.value.requires // []) | join(", "))
          ]
        | @tsv
    ' "${MD_CONFIG_FILE}" | while IFS=$'\t' read -r category domain key type value description requires; do
        # shellcheck disable=SC2016 # backticks are literal Markdown
        printf '| %s | `%s` | `%s` | %s | `%s` | %s | %s |\n' \
            "${category}" "${domain}" "${key}" "${type}" "${value}" "${description}" "${requires}"
    done
    printf '\n<!-- prettier-ignore-end -->\n\n%s\n' "${end_marker}"
}

fresh="$(mktemp -t macos-defaults-docs.XXXXXX)"
trap 'rm -f "${fresh}"' EXIT
render_table > "${fresh}"

if [[ "${mode}" == "print" ]]; then
    cat "${fresh}"
    exit 0
fi

if [[ ! -f "${readme}" ]]; then
    log_error "${readme} not found"
    exit 1
fi

if ! grep -qF "${start_marker}" "${readme}" || ! grep -qF "${end_marker}" "${readme}"; then
    log_error "README is missing the macos-defaults markers (${start_marker} … ${end_marker})"
    exit 1
fi

current="$(awk -v start="${start_marker}" -v end="${end_marker}" '
    $0 == start { in_block = 1; print; next }
    $0 == end   { in_block = 0; print; next }
    in_block    { print }
' "${readme}")"
fresh_content="$(cat "${fresh}")"

if [[ "${current}" == "${fresh_content}" ]]; then
    if [[ "${mode}" == "check" ]]; then
        log_success "README macos-defaults block is up to date."
    else
        log_info "(no change)"
    fi
    exit 0
fi

if [[ "${mode}" == "check" ]]; then
    log_error "README macos-defaults block is stale. Run: sjust macos-defaults-docs write"
    exit 1
fi

# write
out="$(mktemp -t macos-defaults-readme.XXXXXX)"
awk -v start="${start_marker}" -v end="${end_marker}" -v fresh="${fresh}" '
    $0 == start { in_block = 1; while ((getline line < fresh) > 0) print line; close(fresh); next }
    $0 == end   { in_block = 0; next }
    !in_block   { print }
' "${readme}" > "${out}"
mv "${out}" "${readme}"
log_success "README macos-defaults block updated."
