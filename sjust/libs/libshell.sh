#!/usr/bin/env bash
# Sparkdock Shell Utilities
# Shared functions for shell configuration management

# Check if a user file is symlinked to Sparkdock's default
# Usage: check_sparkdock_symlink <user_file> <sparkdock_file>
# Returns:
#   0 - Managed by Sparkdock (symlinked to our file)
#   1 - Custom configuration (user's file or external symlink)
#   2 - Does not exist (needs setup)
check_sparkdock_symlink() {
    local user_file="$1"
    local sparkdock_file="$2"

    if [[ ! -e "${user_file}" ]]; then
        return 2
    fi

    if [[ -L "${user_file}" ]]; then
        local link_target
        link_target="$(readlink "${user_file}")"
        if [[ "${link_target}" == "${sparkdock_file}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Print configuration status message
# Args: program_name, status (0=managed, 1=custom, 2=not exists), user_file, sparkdock_file, config_name
print_config_status() {
    local program_name="${1}"
    local status="${2}"
    local user_file="${3}"
    local sparkdock_file="${4}"
    local config_name="${5}"
    local prefix=""

    if [[ -n "${program_name}" ]]; then
        prefix="${program_name}: "
    fi

    if [[ ${status} -eq 0 ]]; then
        echo "ℹ️ ${prefix}managed ${config_name} (auto-updates with Sparkdock)"
    else
        echo "ℹ️ ${prefix}custom ${config_name} detected, this file cannot be managed, skipping."
        echo "💡 To use Sparkdock defaults: rm ${user_file} && ln -s ${sparkdock_file} ${user_file}"
    fi
}

# Print setup completion message for newly created config files
# Usage: print_setup_complete <user_file> <sparkdock_file> <extra_info>
# extra_info: Optional additional info (e.g., "Based on Catppuccin color scheme")
print_setup_complete() {
    local user_file="$1"
    local sparkdock_file="$2"
    local extra_info="${3:-}"

    echo ""
    echo "💡 This uses Sparkdock's default (auto-updates with Sparkdock)"
    echo "💡 To customize: rm ${user_file} && cp ${sparkdock_file} ${user_file}"
    if [[ -n "${extra_info}" ]]; then
        echo "💡 ${extra_info}"
    fi
}
