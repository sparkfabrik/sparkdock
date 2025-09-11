# vim: set ft=make :

# macOS System Defaults Configuration
# Apply developer-optimized macOS system defaults

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
    
    echo "${green}Applying macOS defaults...${normal}"
    
    # General UI/UX improvements
    echo "• Configuring UI/UX settings..."
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
    defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    
    # Keyboard and input settings for developers
    echo "• Configuring keyboard settings..."
    defaults write NSGlobalDomain KeyRepeat -int 1
    defaults write NSGlobalDomain InitialKeyRepeat -int 10
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    
    # Accessibility improvements for developers
    echo "• Configuring accessibility settings..."
    defaults write com.apple.universalaccess reduceMotion -int 1
    
    # Trackpad settings
    echo "• Configuring trackpad settings..."
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
    
    # Finder improvements for developers
    echo "• Configuring Finder settings..."
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    defaults write com.apple.finder AppleShowAllFiles -bool true
    defaults write com.apple.finder ShowStatusBar -bool true
    defaults write com.apple.finder ShowPathbar -bool true
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
    defaults write com.apple.finder _FXSortFoldersFirst -bool true
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
    defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
    
    # Dock improvements
    echo "• Configuring Dock settings..."
    defaults write com.apple.dock tilesize -float 48
    defaults write com.apple.dock mineffect -string "scale"
    defaults write com.apple.dock minimize-to-application -bool true
    defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
    defaults write com.apple.dock show-process-indicators -bool true
    defaults write com.apple.dock launchanim -bool false
    defaults write com.apple.dock autohide -bool true
    defaults write com.apple.dock autohide-delay -float 0
    defaults write com.apple.dock autohide-time-modifier -float 0
    defaults write com.apple.dock show-recents -bool false
    
    # Safari developer settings
    echo "• Configuring Safari developer settings..."
    defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
    defaults write com.apple.Safari IncludeDevelopMenu -bool true
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
    defaults write com.apple.Safari WebKitDeveloperExtras -bool true
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
    defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
    defaults write com.apple.Safari ShowStatusBar -bool true
    
    # Terminal improvements
    echo "• Configuring Terminal settings..."
    defaults write com.apple.terminal StringEncodings -array 4
    defaults write com.apple.terminal SecureKeyboardEntry -bool true
    
    # TextEdit improvements for developers
    echo "• Configuring TextEdit settings..."
    defaults write com.apple.TextEdit RichText -int 0
    defaults write com.apple.TextEdit PlainTextEncoding -int 4
    defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
    
    # Activity Monitor improvements
    echo "• Configuring Activity Monitor settings..."
    defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
    defaults write com.apple.ActivityMonitor IconType -int 5
    defaults write com.apple.ActivityMonitor ShowCategory -int 0
    defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
    defaults write com.apple.ActivityMonitor SortDirection -int 0
    
    # Screenshots improvements
    echo "• Configuring screenshot settings..."
    defaults write com.apple.screencapture location -string "${HOME}/Desktop"
    defaults write com.apple.screencapture type -string "png"
    defaults write com.apple.screencapture disable-shadow -bool true
    
    # Time Machine improvements
    echo "• Configuring Time Machine settings..."
    defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
    
    # Disk Utility improvements
    echo "• Configuring Disk Utility settings..."
    defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
    defaults write com.apple.DiskUtility advanced-image-options -bool true
    
    echo
    echo "${green}Restarting affected applications...${normal}"
    
    # Restart affected applications to apply changes
    killall Finder 2>/dev/null || true
    killall Dock 2>/dev/null || true
    killall Safari 2>/dev/null || true
    killall "Activity Monitor" 2>/dev/null || true
    
    echo
    echo "${bold}${green}✅ macOS system defaults applied successfully!${normal}"
    echo
    echo "The following applications have been restarted:"
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
    echo "This will show the current state of key developer macOS defaults:"
    echo
    
    # Function to check a defaults setting
    check_default() {
        local domain="$1"
        local key="$2"
        local expected="$3"
        local description="$4"
        
        current=$(defaults read "$domain" "$key" 2>/dev/null || echo "not set")
        
        if [[ "$current" == "$expected" ]]; then
            echo "  ${green}✓${normal} $description: ${green}$current${normal}"
        else
            echo "  ${red}✗${normal} $description: ${red}$current${normal} (expected: ${yellow}$expected${normal})"
        fi
    }
    
    echo "${bold}UI/UX Settings:${normal}"
    check_default "NSGlobalDomain" "NSNavPanelExpandedStateForSaveMode" "1" "Expand save panel by default"
    check_default "NSGlobalDomain" "NSDocumentSaveNewDocumentsToCloud" "0" "Save to disk (not iCloud) by default"
    check_default "NSGlobalDomain" "NSAutomaticCapitalizationEnabled" "0" "Disable automatic capitalization"
    check_default "NSGlobalDomain" "NSAutomaticQuoteSubstitutionEnabled" "0" "Disable smart quotes"
    
    echo
    echo "${bold}Keyboard Settings:${normal}"
    check_default "NSGlobalDomain" "KeyRepeat" "1" "Key repeat rate"
    check_default "NSGlobalDomain" "InitialKeyRepeat" "10" "Initial key repeat delay"
    check_default "NSGlobalDomain" "ApplePressAndHoldEnabled" "0" "Disable press-and-hold for key repeat"
    
    echo
    echo "${bold}Accessibility Settings:${normal}"
    check_default "com.apple.universalaccess" "reduceMotion" "1" "Reduce motion for better focus"
    
    echo
    echo "${bold}Finder Settings:${normal}"
    check_default "NSGlobalDomain" "AppleShowAllExtensions" "1" "Show all filename extensions"
    check_default "com.apple.finder" "AppleShowAllFiles" "1" "Show hidden files"
    check_default "com.apple.finder" "ShowStatusBar" "1" "Show status bar"
    check_default "com.apple.finder" "ShowPathbar" "1" "Show path bar"
    
    echo
    echo "${bold}Dock Settings:${normal}"
    check_default "com.apple.dock" "autohide" "1" "Auto-hide dock"
    check_default "com.apple.dock" "show-recents" "0" "Hide recent applications"
    check_default "com.apple.dock" "launchanim" "0" "Disable launch animations"
    
    echo
    echo "${bold}Safari Developer Settings:${normal}"
    check_default "com.apple.Safari" "IncludeDevelopMenu" "1" "Enable developer menu"
    check_default "com.apple.Safari" "WebKitDeveloperExtras" "1" "Enable web inspector"
    
    echo

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