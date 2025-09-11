# vim: set ft=make :

# macOS System Defaults Configuration
# Apply developer-optimized macOS system defaults without running full Ansible provisioner

sparkdock_path := "/opt/sparkdock"

# Apply macOS system defaults for developers
[group('macos')]
macos-defaults:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    echo "${bold}${cyan}Applying macOS System Defaults for Developers${normal}"
    echo
    echo "This will configure 40+ macOS system defaults optimized for developer productivity:"
    echo "  • UI/UX improvements (expand panels, disable smart quotes/dashes)"
    echo "  • Finder enhancements (show hidden files, extensions, status bar)"
    echo "  • Dock optimizations (auto-hide, faster animations, no recents)"
    echo "  • Keyboard/trackpad settings (faster key repeat, right-click enabled)"
    echo "  • Safari developer settings (enable dev menu, web inspector)"
    echo "  • Terminal and development tools (UTF-8, secure keyboard entry)"
    echo "  • Accessibility improvements (reduce motion for better focus)"
    echo
    echo "${yellow}Note: Some settings require applications to be restarted to take effect.${normal}"
    echo
    
    # Run Ansible with just the macos-defaults tag
    cd "{{ sparkdock_path }}"
    echo "${green}Running Ansible to apply macOS defaults...${normal}"
    ansible-playbook ansible/macos.yml --tags macos-defaults --ask-become-pass
    
    echo
    echo "${bold}${green}✅ macOS system defaults applied successfully!${normal}"
    echo
    echo "The following applications will be restarted automatically:"
    echo "  • Finder"
    echo "  • Dock" 
    echo "  • Safari (if running)"
    echo "  • Activity Monitor (if running)"
    echo
    echo "Some changes may require a logout/login or system restart to fully take effect."

# Show current macOS defaults status (dry-run)
[group('macos')]
macos-defaults-check:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    echo "${bold}${cyan}Checking macOS System Defaults Status${normal}"
    echo
    echo "This will show which defaults would be changed (dry-run mode):"
    echo
    
    # Run Ansible in check mode
    cd "{{ sparkdock_path }}"
    ansible-playbook ansible/macos.yml --tags macos-defaults --check --diff --ask-become-pass

# Reset macOS defaults to system defaults (use with caution)
[group('macos')]
macos-defaults-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libformatting.sh
    source /opt/sparkdock/sjust/libs/libcolors.sh
    
    echo "${bold}${red}⚠️  Reset macOS System Defaults${normal}"
    echo
    echo "${yellow}This will reset some of the developer-optimized defaults back to system defaults.${normal}"
    echo "${red}This action cannot be easily undone!${normal}"
    echo
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r response
    
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        echo
        echo "${green}Resetting selected macOS defaults...${normal}"
        
        # Reset key developer-affecting defaults
        echo "Resetting keyboard settings..."
        defaults delete NSGlobalDomain KeyRepeat 2>/dev/null || true
        defaults delete NSGlobalDomain InitialKeyRepeat 2>/dev/null || true
        defaults delete NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null || true
        
        echo "Resetting Finder settings..."
        defaults delete com.apple.finder AppleShowAllFiles 2>/dev/null || true
        defaults delete NSGlobalDomain AppleShowAllExtensions 2>/dev/null || true
        defaults delete com.apple.finder ShowStatusBar 2>/dev/null || true
        defaults delete com.apple.finder ShowPathbar 2>/dev/null || true
        
        echo "Resetting Dock settings..."
        defaults delete com.apple.dock autohide 2>/dev/null || true
        defaults delete com.apple.dock autohide-delay 2>/dev/null || true
        defaults delete com.apple.dock show-recents 2>/dev/null || true
        
        echo "Resetting accessibility settings..."
        defaults delete com.apple.universalaccess reduceMotion 2>/dev/null || true
        
        # Restart affected applications
        killall Finder 2>/dev/null || true
        killall Dock 2>/dev/null || true
        
        echo
        echo "${bold}${green}✅ Selected macOS defaults have been reset.${normal}"
        echo "${yellow}You may need to restart applications or reboot for all changes to take effect.${normal}"
    else
        echo "Reset cancelled."
    fi