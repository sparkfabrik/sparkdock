#!/usr/bin/env bash
set -euo pipefail

# Script to list installed sparkdock packages with category and description

# Paths
SPARKDOCK_PATH="${SPARKDOCK_PATH:-/opt/sparkdock}"
PACKAGES_YML="${SPARKDOCK_PATH}/config/packages/all-packages.yml"
METADATA_YML="${SPARKDOCK_PATH}/config/packages/package-metadata.yml"

# Parse YAML to get package lists and metadata
get_yaml_packages() {
    local file="$1"
    local key="$2"
    # Use awk to extract package list from YAML
    awk -v key="${key}:" '
        $0 ~ key {in_section=1; next}
        in_section && /^[a-z_]+:/ {exit}
        in_section && /^  - / {gsub(/^  - /, ""); gsub(/"/, ""); print}
    ' "${file}"
}

# Get package metadata from YAML
get_package_metadata() {
    local package="$1"
    local field="$2"
    # Normalize package name (remove quotes for lookup, keep version numbers)
    local normalized_package="${package//\"/}"
    normalized_package="${normalized_package##*/}"  # Remove tap prefix if present
    
    awk -v pkg="${normalized_package}" -v field="${field}" '
        $0 ~ "^" pkg ":" {in_package=1; next}
        in_package && $0 ~ "^[a-z]" {exit}
        in_package && $0 ~ field ":" {
            gsub(/^[[:space:]]+/, "")
            gsub(field ": \"", "")
            gsub("\"", "")
            print
            exit
        }
    ' "${METADATA_YML}" | head -1
}

# Check if package is installed
is_package_installed() {
    local package="$1"
    local type="$2"
    
    # Normalize package name
    local normalized_package="${package//\"/}"
    normalized_package="${normalized_package##*/}"  # Remove tap prefix
    
    if [[ "${type}" == "cask" ]]; then
        brew list --cask "${normalized_package}" &>/dev/null
    else
        brew list --formula "${normalized_package}" &>/dev/null
    fi
}

# Format package info for table
format_package_row() {
    local package="$1"
    local type="$2"
    
    # Get metadata
    local category
    local description
    category=$(get_package_metadata "${package}" "category")
    description=$(get_package_metadata "${package}" "description")
    
    # Default values if metadata not found
    if [[ -z "${category}" ]]; then
        category="Uncategorized"
    fi
    if [[ -z "${description}" ]]; then
        # Try to get description from brew
        if [[ "${type}" == "cask" ]]; then
            description=$(brew info --cask "${package//\"/}" 2>/dev/null | head -1 || echo "No description")
        else
            description=$(brew info "${package//\"/}" 2>/dev/null | head -1 || echo "No description")
        fi
    fi
    
    # Check if installed
    local installed="No"
    if is_package_installed "${package}" "${type}"; then
        installed="Yes"
    fi
    
    # Normalize package name for display
    local display_name="${package//\"/}"
    
    echo "${display_name}|${category}|${description}|${installed}"
}

# Main function
main() {
    local filter_package="${1:-}"
    
    # Collect all packages
    declare -a all_rows=()
    
    # Process cask packages
    while IFS= read -r package; do
        [[ -z "${package}" ]] && continue
        
        # Skip if filter is set and doesn't match
        if [[ -n "${filter_package}" ]] && [[ ! "${package}" =~ ${filter_package} ]]; then
            continue
        fi
        
        all_rows+=("$(format_package_row "${package}" "cask")")
    done < <(get_yaml_packages "${PACKAGES_YML}" "cask_packages")
    
    # Process homebrew packages
    while IFS= read -r package; do
        [[ -z "${package}" ]] && continue
        
        # Skip if filter is set and doesn't match
        if [[ -n "${filter_package}" ]] && [[ ! "${package}" =~ ${filter_package} ]]; then
            continue
        fi
        
        all_rows+=("$(format_package_row "${package}" "formula")")
    done < <(get_yaml_packages "${PACKAGES_YML}" "homebrew_packages")
    
    # Print table header
    printf "%-35s | %-25s | %-60s | %-10s\n" "Package" "Category" "Description" "Installed"
    printf "%-35s-+-%-25s-+-%-60s-+-%-10s\n" \
        "-----------------------------------" \
        "-------------------------" \
        "------------------------------------------------------------" \
        "----------"
    
    # Sort by category, then by package name
    printf "%s\n" "${all_rows[@]}" | sort -t'|' -k2,2 -k1,1 | while IFS='|' read -r pkg cat desc inst; do
        # Truncate long descriptions
        local short_desc="${desc}"
        if [[ ${#desc} -gt 60 ]]; then
            short_desc="${desc:0:57}..."
        fi
        printf "%-35s | %-25s | %-60s | %-10s\n" "${pkg}" "${cat}" "${short_desc}" "${inst}"
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
