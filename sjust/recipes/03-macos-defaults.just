# vim: set ft=make :

# macOS System Defaults Configuration
# Apply developer-optimized macOS system defaults using YAML configuration

sparkdock_path := "/opt/sparkdock"
config_file := sparkdock_path + "/config/macos/defaults.yml"
user_overrides := "${HOME}/.local/spark/macos-defaults/overrides.yml"

# Apply macOS system defaults for developers
[group('macos')]
macos-defaults:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        echo "${red}Error: yq is required but not installed.${normal}"
        echo "Please install it with: brew install yq"
        exit 1
    fi
    
    config_file="{{config_file}}"
    user_overrides="{{user_overrides}}"
    
    echo "${bold}${cyan}Applying macOS System Defaults for Developers${normal}"
    echo
    echo "Configuration file: ${config_file}"
    if [[ -f "${user_overrides}" ]]; then
        echo "User overrides: ${user_overrides}"
    fi
    echo
    
    # Create temporary merged config if user overrides exist
    temp_config="/tmp/macos-defaults-merged.yml"
    if [[ -f "${user_overrides}" ]]; then
        echo "${green}Merging user overrides...${normal}"
        yq eval-all '. as $item ireduce ({}; . * $item)' "${config_file}" "${user_overrides}" > "${temp_config}"
        config_to_use="${temp_config}"
    else
        config_to_use="${config_file}"
    fi
    
    # Function to apply defaults from YAML
    apply_defaults_category() {
        local category="$1"
        local description="$2"
        
        echo "• Configuring ${description}..."
        
        # Get all items in this category
        yq eval ".${category}[]" "${config_to_use}" -o json | while IFS= read -r item; do
            if [[ -n "${item}" && "${item}" != "null" ]]; then
                domain=$(echo "${item}" | yq eval '.domain' -)
                key=$(echo "${item}" | yq eval '.key' -)
                type=$(echo "${item}" | yq eval '.type' -)
                value=$(echo "${item}" | yq eval '.value' -)
                description=$(echo "${item}" | yq eval '.description' -)
                
                # Handle different value types
                case "${type}" in
                    "bool")
                        if [[ "${value}" == "true" ]]; then
                            defaults write "${domain}" "${key}" -bool true
                        else
                            defaults write "${domain}" "${key}" -bool false
                        fi
                        ;;
                    "int")
                        defaults write "${domain}" "${key}" -int "${value}"
                        ;;
                    "float")
                        defaults write "${domain}" "${key}" -float "${value}"
                        ;;
                    "string")
                        # Handle environment variable expansion
                        expanded_value=$(eval echo "${value}")
                        defaults write "${domain}" "${key}" -string "${expanded_value}"
                        ;;
                    "array")
                        # Handle arrays (like [4] for encoding)
                        array_values=$(echo "${item}" | yq eval '.value[]' - | tr '\n' ' ')
                        defaults write "${domain}" "${key}" -array ${array_values}
                        ;;
                    *)
                        echo "${yellow}Warning: Unknown type '${type}' for ${domain}.${key}${normal}"
                        ;;
                esac
            fi
        done
    }
    
    echo "This will configure macOS system defaults optimized for developer productivity."
    echo "Settings are defined in: ${config_file}"
    echo
    echo "${yellow}Note: Some settings require applications to be restarted to take effect.${normal}"
    echo
    echo "${green}Applying macOS defaults...${normal}"
    
    # Apply all categories
    apply_defaults_category "ui_ux" "UI/UX settings"
    apply_defaults_category "keyboard" "keyboard settings"
    apply_defaults_category "accessibility" "accessibility settings"
    apply_defaults_category "trackpad" "trackpad settings"
    apply_defaults_category "finder" "Finder settings"
    apply_defaults_category "dock" "Dock settings"
    apply_defaults_category "safari" "Safari developer settings"
    apply_defaults_category "terminal" "Terminal settings"
    apply_defaults_category "textedit" "TextEdit settings"
    apply_defaults_category "activity_monitor" "Activity Monitor settings"
    apply_defaults_category "screenshots" "screenshot settings"
    apply_defaults_category "time_machine" "Time Machine settings"
    apply_defaults_category "disk_utility" "Disk Utility settings"
    
    echo
    echo "${green}Restarting affected applications...${normal}"
    
    # Get applications to restart from config
    restart_apps=$(yq eval '.restart_applications[]' "${config_to_use}")
    for app in ${restart_apps}; do
        # Remove quotes if present
        app_clean=$(echo "${app}" | tr -d '"')
        killall "${app_clean}" 2>/dev/null || true
    done
    
    # Clean up temporary file
    if [[ -f "${temp_config}" ]]; then
        rm -f "${temp_config}"
    fi
    
    echo
    echo "${bold}${green}✅ macOS system defaults applied successfully!${normal}"
    echo
    echo "Applications restarted:"
    echo "${restart_apps}" | while read app; do
        echo "  • ${app}"
    done
    echo
    echo "Some changes may require a logout/login or system restart to fully take effect."

# Show current macOS defaults status (dry-run)
[group('macos')]
macos-defaults-check:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        echo "${red}Error: yq is required but not installed.${normal}"
        echo "Please install it with: brew install yq"
        exit 1
    fi
    
    config_file="{{config_file}}"
    user_overrides="{{user_overrides}}"
    
    echo "${bold}${cyan}Checking macOS System Defaults Status${normal}"
    echo
    echo "Configuration file: ${config_file}"
    if [[ -f "${user_overrides}" ]]; then
        echo "User overrides: ${user_overrides}"
    fi
    echo
    
    # Create temporary merged config if user overrides exist
    temp_config="/tmp/macos-defaults-check.yml"
    if [[ -f "${user_overrides}" ]]; then
        echo "${green}Using merged configuration with user overrides...${normal}"
        yq eval-all '. as $item ireduce ({}; . * $item)' "${config_file}" "${user_overrides}" > "${temp_config}"
        config_to_use="${temp_config}"
    else
        config_to_use="${config_file}"
    fi
    
    # Function to check defaults from a category
    check_defaults_category() {
        local category="$1"
        local display_name="$2"
        
        echo "${bold}${display_name}:${normal}"
        
        # Get all items in this category
        yq eval ".${category}[]" "${config_to_use}" -o json | while IFS= read -r item; do
            if [[ -n "${item}" && "${item}" != "null" ]]; then
                domain=$(echo "${item}" | yq eval '.domain' -)
                key=$(echo "${item}" | yq eval '.key' -)
                type=$(echo "${item}" | yq eval '.type' -)
                expected=$(echo "${item}" | yq eval '.value' -)
                description=$(echo "${item}" | yq eval '.description' -)
                
                # Get current value
                current=$(defaults read "${domain}" "${key}" 2>/dev/null || echo "not set")
                
                # Handle different expected value types for comparison
                case "${type}" in
                    "bool")
                        if [[ "${expected}" == "true" ]]; then
                            expected_display="1"
                        else
                            expected_display="0"
                        fi
                        ;;
                    "string")
                        # Handle environment variable expansion
                        expected_display=$(eval echo "${expected}")
                        ;;
                    "array")
                        # Format array for display
                        expected_display="(${expected})"
                        current=$(defaults read "${domain}" "${key}" 2>/dev/null | tr '\n' ' ' | xargs || echo "not set")
                        ;;
                    *)
                        expected_display="${expected}"
                        ;;
                esac
                
                # Compare and display result
                if [[ "${current}" == "${expected_display}" ]] || [[ "${current}" == "${expected}" ]]; then
                    echo "  ${green}✓${normal} ${description}: ${green}${current}${normal}"
                else
                    echo "  ${red}✗${normal} ${description}: ${red}${current}${normal} (expected: ${yellow}${expected_display}${normal})"
                fi
            fi
        done
        echo
    }
    
    # Check all categories
    check_defaults_category "ui_ux" "UI/UX Settings"
    check_defaults_category "keyboard" "Keyboard Settings"
    check_defaults_category "accessibility" "Accessibility Settings"
    check_defaults_category "trackpad" "Trackpad Settings"
    check_defaults_category "finder" "Finder Settings"
    check_defaults_category "dock" "Dock Settings"
    check_defaults_category "safari" "Safari Developer Settings"
    check_defaults_category "terminal" "Terminal Settings"
    check_defaults_category "textedit" "TextEdit Settings"
    check_defaults_category "activity_monitor" "Activity Monitor Settings"
    check_defaults_category "screenshots" "Screenshot Settings"
    check_defaults_category "time_machine" "Time Machine Settings"
    check_defaults_category "disk_utility" "Disk Utility Settings"
    
    # Clean up temporary file
    if [[ -f "${temp_config}" ]]; then
        rm -f "${temp_config}"
    fi

# Reset macOS defaults to system defaults (use with caution)
[group('macos')]
macos-defaults-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        echo "${red}Error: yq is required but not installed.${normal}"
        echo "Please install it with: brew install yq"
        exit 1
    fi
    
    config_file="{{config_file}}"
    
    echo "${bold}${red}⚠️  Reset macOS System Defaults${normal}"
    echo
    echo "${yellow}This will reset the developer-optimized defaults back to system defaults.${normal}"
    echo "${red}This action cannot be easily undone!${normal}"
    echo
    echo "Settings to be reset are defined in: ${config_file}"
    echo
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r response
    
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        echo
        echo "${green}Resetting macOS defaults...${normal}"
        
        # Function to reset defaults from a category
        reset_defaults_category() {
            local category="$1"
            local description="$2"
            
            echo "Resetting ${description}..."
            
            # Get all items in this category
            yq eval ".${category}[]" "${config_file}" -o json | while IFS= read -r item; do
                if [[ -n "${item}" && "${item}" != "null" ]]; then
                    domain=$(echo "${item}" | yq eval '.domain' -)
                    key=$(echo "${item}" | yq eval '.key' -)
                    
                    # Delete the key to restore system default
                    defaults delete "${domain}" "${key}" 2>/dev/null || true
                fi
            done
        }
        
        # Reset selected categories (those that are commonly customized)
        reset_defaults_category "keyboard" "keyboard settings"
        reset_defaults_category "accessibility" "accessibility settings"
        reset_defaults_category "finder" "Finder settings"
        reset_defaults_category "dock" "Dock settings"
        
        echo
        echo "${green}Restarting affected applications...${normal}"
        
        # Get applications to restart from config
        restart_apps=$(yq eval '.restart_applications[]' "${config_file}")
        for app in ${restart_apps}; do
            # Remove quotes if present
            app_clean=$(echo "${app}" | tr -d '"')
            killall "${app_clean}" 2>/dev/null || true
        done
        
        echo
        echo "${bold}${green}✅ Selected macOS defaults have been reset.${normal}"
        echo "${yellow}You may need to restart applications or reboot for all changes to take effect.${normal}"
    else
        echo "Reset cancelled."
    fi

# Create user overrides directory and example file
[group('macos')]
macos-defaults-init-overrides:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    user_overrides="{{user_overrides}}"
    overrides_dir="$(dirname "${user_overrides}")"
    
    echo "${bold}${cyan}Initializing macOS Defaults User Overrides${normal}"
    echo
    echo "This will create a user overrides file at: ${user_overrides}"
    echo
    
    # Create directory if it doesn't exist
    if [[ ! -d "${overrides_dir}" ]]; then
        echo "Creating directory: ${overrides_dir}"
        mkdir -p "${overrides_dir}"
    fi
    
    # Create example overrides file if it doesn't exist
    if [[ ! -f "${user_overrides}" ]]; then
        echo "Creating example overrides file..."
        cat > "${user_overrides}" << 'EOF'
# macOS Defaults User Overrides
# This file allows you to override the default macOS settings.
# 
# Example: To disable dock auto-hide and keep recent applications visible:
#
# dock:
#   - domain: com.apple.dock
#     key: autohide
#     type: bool
#     value: false
#     description: "Don't auto-hide dock"
#   
#   - domain: com.apple.dock
#     key: show-recents
#     type: bool
#     value: true
#     description: "Show recent applications in dock"
#
# Example: To change key repeat settings:
#
# keyboard:
#   - domain: NSGlobalDomain
#     key: KeyRepeat
#     type: int
#     value: 2
#     description: "Slower key repeat rate"

# Add your custom overrides below:
EOF
        
        echo "${bold}${green}✅ User overrides file created successfully!${normal}"
        echo
        echo "Edit your overrides at: ${user_overrides}"
        echo "Then run 'sjust macos-defaults' to apply settings with your overrides."
    else
        echo "${yellow}User overrides file already exists: ${user_overrides}${normal}"
    fi
    
    echo
    echo "To view the default configuration structure, see:"
    echo "  {{config_file}}"