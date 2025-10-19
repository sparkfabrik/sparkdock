#!/usr/bin/env bash
set -euo pipefail

# Script to list sparkdock packages with category and description

# Paths
SPARKDOCK_PATH="${SPARKDOCK_PATH:-/opt/sparkdock}"
PACKAGES_YML="${SPARKDOCK_PATH}/config/packages/all-packages.yml"

# Parse YAML to get package entries with metadata
get_yaml_package_entries() {
    local file="$1"
    local key="$2"
    # Use awk to extract package entries with metadata from YAML
    awk -v key="${key}:" '
        $0 ~ key {in_section=1; next}
        in_section && /^[a-z_]+:/ {exit}
        in_section && /^  - name:/ {
            gsub(/^  - name: /, "")
            gsub(/"/, "")
            package=$0
            getline
            gsub(/^[[:space:]]+category: /, "")
            gsub(/"/, "")
            category=$0
            getline
            gsub(/^[[:space:]]+description: /, "")
            gsub(/"/, "")
            description=$0
            # Check if next line has URL
            url=""
            if (getline > 0 && $0 ~ /^[[:space:]]+url:/) {
                gsub(/^[[:space:]]+url: /, "")
                gsub(/"/, "")
                url=$0
            }
            print package "|" category "|" description "|" url
        }
    ' "${file}"
}

# Main function
main() {
    local filter_package="${1:-}"

    # Collect all packages
    declare -a all_rows=()

    # Process cask packages
    while IFS='|' read -r package category description url; do
        [[ -z "${package}" ]] && continue

        # Skip if filter is set and doesn't match
        if [[ -n "${filter_package}" ]] && [[ ! "${package}" =~ ${filter_package} ]]; then
            continue
        fi

        all_rows+=("${package}|${category}|${description}|${url}")
    done < <(get_yaml_package_entries "${PACKAGES_YML}" "cask_packages")

    # Process homebrew packages
    while IFS='|' read -r package category description url; do
        [[ -z "${package}" ]] && continue

        # Skip if filter is set and doesn't match
        if [[ -n "${filter_package}" ]] && [[ ! "${package}" =~ ${filter_package} ]]; then
            continue
        fi

        all_rows+=("${package}|${category}|${description}|${url}")
    done < <(get_yaml_package_entries "${PACKAGES_YML}" "homebrew_packages")

    # Print table header
    printf "%-35s | %-25s | %-45s | %-50s\n" "Package" "Category" "Description" "URL"
    printf "%-35s-+-%-25s-+-%-45s-+-%-50s\n" \
        "-----------------------------------" \
        "-------------------------" \
        "---------------------------------------------" \
        "--------------------------------------------------"

    # Sort by category, then by package name
    printf "%s\n" "${all_rows[@]}" | sort -t'|' -k2,2 -k1,1 | while IFS='|' read -r pkg cat desc url; do
        # Truncate long descriptions
        local short_desc="${desc}"
        if [[ ${#desc} -gt 45 ]]; then
            short_desc="${desc:0:42}..."
        fi

        # Truncate long URLs
        local short_url="${url}"
        if [[ ${#url} -gt 50 ]]; then
            short_url="${url:0:47}..."
        fi

        printf "%-35s | %-25s | %-45s | %-50s\n" "${pkg}" "${cat}" "${short_desc}" "${short_url}"
    done

    # Print summary
    echo ""
    echo "Total packages: ${#all_rows[@]}"

    if [[ -n "${filter_package}" ]]; then
        echo "Filtered by: ${filter_package}"
    fi
}

# Run main function
main "$@"
