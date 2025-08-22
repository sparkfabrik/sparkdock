#!/usr/bin/env bash
set -euo pipefail

# LaunchAgent helper script for sparkdock
# Handles loading/unloading LaunchAgents with modern and fallback approaches

SCRIPT_NAME="$(basename "${0}")"

show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} <command> <plist_path>

Commands:
  load        Load a LaunchAgent plist
  unload      Unload a LaunchAgent plist
  reload      Unload then load a LaunchAgent plist

Arguments:
  plist_path  Path to the .plist file

Examples:
  ${SCRIPT_NAME} load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
  ${SCRIPT_NAME} unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist
  ${SCRIPT_NAME} reload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist

This script uses modern 'launchctl bootstrap' command with fallback to legacy 'launchctl load'
for backward compatibility with older macOS versions.
EOF
}

log_info() {
    echo "ℹ️  ${*}"
}

log_success() {
    echo "✅ ${*}"
}

log_warning() {
    echo "⚠️  ${*}"
}

log_error() {
    echo "❌ ${*}" >&2
}

# Get the current user's UID for bootstrap domain
get_user_domain() {
    echo "gui/$(id -u)"
}

# Check if a LaunchAgent is currently loaded
is_loaded() {
    local plist_path="${1}"
    local label
    
    # Extract label from plist file
    if ! label=$(plutil -extract Label raw "${plist_path}" 2>/dev/null); then
        log_warning "Could not extract label from ${plist_path}"
        return 1
    fi
    
    # Check if service is loaded using launchctl list
    if launchctl list "${label}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Unload a LaunchAgent using modern or fallback approach
unload_launchagent() {
    local plist_path="${1}"
    local label
    local domain
    
    if [[ ! -f "${plist_path}" ]]; then
        log_warning "Plist file not found: ${plist_path}"
        return 0  # Not an error if file doesn't exist
    fi
    
    # Extract label from plist file
    if ! label=$(plutil -extract Label raw "${plist_path}" 2>/dev/null); then
        log_error "Could not extract label from ${plist_path}"
        return 1
    fi
    
    # Check if it's loaded first
    if ! is_loaded "${plist_path}"; then
        log_info "LaunchAgent ${label} is not currently loaded"
        return 0
    fi
    
    log_info "Unloading LaunchAgent: ${label}"
    
    # Try modern approach first (bootout)
    domain=$(get_user_domain)
    if launchctl bootout "${domain}" "${plist_path}" 2>/dev/null; then
        log_success "LaunchAgent unloaded using modern bootout command"
        return 0
    fi
    
    # Fallback to legacy approach
    if launchctl unload "${plist_path}" 2>/dev/null; then
        log_success "LaunchAgent unloaded using legacy unload command"
        return 0
    fi
    
    log_error "Failed to unload LaunchAgent using both modern and legacy approaches"
    return 1
}

# Load a LaunchAgent using modern or fallback approach
load_launchagent() {
    local plist_path="${1}"
    local label
    local domain
    
    if [[ ! -f "${plist_path}" ]]; then
        log_error "Plist file not found: ${plist_path}"
        return 1
    fi
    
    # Validate plist file format
    if ! plutil -lint "${plist_path}" >/dev/null 2>&1; then
        log_error "Invalid plist format: ${plist_path}"
        return 1
    fi
    
    # Extract label from plist file
    if ! label=$(plutil -extract Label raw "${plist_path}" 2>/dev/null); then
        log_error "Could not extract label from ${plist_path}"
        return 1
    fi
    
    # Check if already loaded
    if is_loaded "${plist_path}"; then
        log_info "LaunchAgent ${label} is already loaded"
        return 0
    fi
    
    log_info "Loading LaunchAgent: ${label}"
    
    # Try modern approach first (bootstrap)
    domain=$(get_user_domain)
    if launchctl bootstrap "${domain}" "${plist_path}" 2>/dev/null; then
        log_success "LaunchAgent loaded using modern bootstrap command"
        return 0
    fi
    
    # Fallback to legacy approach
    if launchctl load "${plist_path}" 2>/dev/null; then
        log_success "LaunchAgent loaded using legacy load command"
        return 0
    fi
    
    # If both fail, provide detailed error information
    log_error "Failed to load LaunchAgent using both modern and legacy approaches"
    log_error "This may indicate:"
    log_error "  1. Permission issues with the plist file"
    log_error "  2. Invalid executable path in the plist"
    log_error "  3. System security restrictions"
    log_error "  4. LaunchAgent daemon issues"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  1. Check plist file permissions: ls -la ${plist_path}"
    log_error "  2. Validate executable exists and is executable"
    log_error "  3. Try running the command manually: launchctl bootstrap ${domain} ${plist_path}"
    log_error "  4. Check system logs: log show --predicate 'subsystem == \"com.apple.launchd\"' --last 5m"
    
    return 1
}

# Main command processing
main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    local command="${1}"
    
    case "${command}" in
        -h|--help)
            show_help
            exit 0
            ;;
        load|unload|reload)
            if [[ $# -ne 2 ]]; then
                log_error "Command '${command}' requires a plist path argument"
                show_help
                exit 1
            fi
            local plist_path="${2}"
            ;;
        *)
            log_error "Unknown command: ${command}"
            show_help
            exit 1
            ;;
    esac
    
    case "${command}" in
        load)
            load_launchagent "${plist_path}"
            ;;
        unload)
            unload_launchagent "${plist_path}"
            ;;
        reload)
            unload_launchagent "${plist_path}"
            load_launchagent "${plist_path}"
            ;;
    esac
}

# Run main function with all arguments
main "${@}"