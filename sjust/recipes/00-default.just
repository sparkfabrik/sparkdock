# vim: set ft=make :

uid := `id -u`
shell := `grep :$(id -u): /etc/passwd | cut -d: -f7`
sparkdock_path := "/opt/sparkdock"
default_branch := "master"
sparkdock_menubar_plist_path := "${HOME}/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist"
sparkdock_menubar_process_name := "sparkdock-manager"

# Print system information.
[group('system')]
system-device-info:
    #!/usr/bin/env bash

    read -r -d '' AYSE << EOM
    @@@@@@@@@@@@@@@@@@@@@@@@@*,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@(#,/#%%&&&&&&&%/,(,*////**@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@&&%&&&@@@@@@@@@@@@@@@@@@%&@&&#/***@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@##%@&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&(*,@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@//&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#%#,*@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@*&&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@@&&%&(/&@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@((&&&@@&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&&%#@&@@&%&@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@((%#&&#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&@&&&&&#%%@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@*/###%%&&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%%@#%&&@%(%@@@@@@@@@@@@@@@
    @@@@@@@@@@@@//&##(#&&&&&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&%&&(%/##@@##&@@@@@@@@@@@@@
    @@@@@@@@@@**#&&&%#%%%&&&&&@@&@@@@@@@@@&@@@@@@&@&@&@&&&&&%%#&%%&&@@%&@@@@@@@@@@@@
    @@@@@@@@@(*&&&&#(#%@####((#%%&&&&%&&%&&@@&@&%&@%#%####%%#%#%#@@@@@@@&@@@@@@@@@@@
    @@@@@@@*(#&%%&&@@&#%&&@&@&&&(##((#(###&%%##%#&%&&@&%%&&&&&@@@@@@@@@@@@&&@@@@@@@@
    @@@@/*//&&&%#&&&@@@@@@@@@@@@@@@@@@@@%###%#&@@@@@@@@@@@@@@@@@@@@@@@@@%@@&@@@@@@@@
    @@@(*(#&&@@@@@@@@@@@@@@@@@@@@@@@@@@&#&@@&&%&@@@@@@@@@@@@@@@@@@@@@@@@&@@@@@@@@@@@
    @@@*(%&@@@@@@@@@@@@@@&###%@@@@@@@&@@@&@@%***/&@@@@((&@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@*#%@@@@@@@@@@@@@%///(#(/((((#%#/,,,,,,,,,,*//(//*/*((%@@@@@@@@@@@@@@@@@@@@@@@
    @@@/#%&@@@@@@@@@@@@&//***/#*/&/&(*//*,,,,**///(%&&%#//(#%&&@@@@@@@@@@@@@@@@@@@@@
    @@@/##&@@@@@@@&@@&%#%/*,,,,,,*********,,,/(/*,,(%%%///**/(#&@@@&&&&@@@@@@@@@@@@@
    @@@*(#&@@@@@@@@@@&&%%/,,,...,,,,*,,**,,.,*//*********,***(#%@@@@&%##@@@@@@@@@@@@
    @@@,/%%&@@@&%@@@@&@&&/,,........,,,,,,,,,****,,,,,..,,,**(%&@@@@@@&@@@@@@@@@@@@@
    @@@*/,*(&@@@@@@@@@@@@*,,.......,,**,,,,,,***,,.....,,,***(&@@@@@@@@@@@@@@@@@@@@@
    @@@@.,#&&&&@@&%&@@@@#**,,,,,,,*,,,,*,..,,/*/*,,,,.,,,***/#@@@&@@@@@@@@@@@@@@@@@@
    @@@@@@@.,/%&&&&&&@@&//***,**/*,,,,,*/**/##/*,,,*,,,***//(#@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@.,,//*****((//*,,,,,,,,,****///***///(#&@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@,*(/***/***///*,**/****//#(*/****//(%@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@&(*,,,,,***/*,.,**//((//**,,*/(#&@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@%/*,,,,,,,,,**,,****,****((%%@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@../*,.,,....,,,,,*/(##//@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ ,/********/(%#(@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,.,/@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    EOM

    echo "$AYSE"
    system_profiler SPHardwareDataType

# Clear DNS cache on macOS.
[group('system')]
system-clear-dns-cache:
    @sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
    @echo "DNS cache cleared successfully!"

# Install and update http-proxy to latest version.
[group('http-proxy')]
http-proxy-install-update:
    #!/usr/bin/env bash
    set -e
    echo "Installing/updating http-proxy system to latest version..."
    cd {{ sparkdock_path }}

    # Update http-proxy repository if it exists
    if [ -d "http-proxy" ]; then
        echo "🔄 Updating existing http-proxy repository..."
        cd http-proxy

        echo "🔧 Configuring git permissions..."
        uid=$(id -u)
        gid=$(id -g)
        current_uid=$(stat -f "%u" .)
        current_gid=$(stat -f "%g" .)
        if [[ "$current_uid" != "$uid" || "$current_gid" != "$gid" ]]; then
            sudo chown -R "${uid}:${gid}" .
        fi

        git config --local --add safe.directory $PWD
        # Check if we're on main branch (http-proxy uses main, not master)
        current_branch=$(git branch --show-current)
        if [[ "${current_branch}" != "main" ]]; then
            echo "❌ Error: Not on main branch (currently on '${current_branch}')"
            echo "💡 Switch to main branch first: git checkout main"
            exit 1
        fi

        # Fetch latest changes to compare
        echo "🔄 Fetching latest changes..."
        git fetch origin

        # Check if we're already up to date
        if git diff --quiet HEAD origin/main; then
            echo "✅ Http-proxy repository already up to date!"
        else
            # Stash any local changes
            if ! git diff --quiet || ! git diff --cached --quiet; then
                echo "📦 Stashing local changes..."
                git stash -m "Auto-stash before update $(date)"
            fi

            echo "⬆️  Updating to latest main..."
            git reset --hard origin/main
            echo "✅ Http-proxy repository updated successfully!"
        fi

        cd {{ sparkdock_path }}
    fi

    # Run ansible installation/update
    echo "🔧 Running ansible configuration..."
    just -f /opt/sparkdock/Justfile run-ansible-playbook http-proxy

    # Clean up and restart
    echo "🔄 Restarting http-proxy services..."
    docker rm -vf http-proxy || true
    spark-http-proxy start
    echo "✅ Http-proxy installation/update completed!"

# Update system packages via Homebrew (not sparkdock)
[group('system')]
system-upgrade:
    #!/usr/bin/env bash
    echo "Updating system packages..."
    brew update && brew upgrade && brew cleanup
    echo "System packages updated successfully!"

# Install mkcert for local SSL certificate generation.
[group('system')]
system-install-mkcert:
    #!/usr/bin/env bash
    echo "Installing mkcert..."
    brew install mkcert nss
    mkcert -install
    echo "mkcert installed successfully!"

# Configure Google Cloud SDK and install required components.
[group('system')]
system-gcloud-reconfigure:
    #!/usr/bin/env zsh
    set -euo pipefail
    echo "Configuring Google Cloud SDK..."

    # Install gcloud-cli via Homebrew if not already installed
    if ! brew list --cask google-cloud-sdk >/dev/null 2>&1; then
        echo "Installing Google Cloud SDK via Homebrew..."
        brew install --cask google-cloud-sdk
    fi

    # Get the Homebrew prefix
    HOMEBREW_PREFIX=$(brew --prefix)

    # Source the gcloud environment
    if [[ -f "${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc" ]]; then
        echo "Sourcing Google Cloud SDK environment..."
        # shellcheck source=/dev/null
        source "${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc"
    else
        echo "❌ Google Cloud SDK path script not found at ${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc"
        exit 1
    fi

    # Install gke-gcloud-auth-plugin component
    echo "Installing gke-gcloud-auth-plugin component..."
    gcloud components install gke-gcloud-auth-plugin --quiet

    # Verify installation
    echo "Verifying gke-gcloud-auth-plugin installation..."
    if gke-gcloud-auth-plugin --version >/dev/null 2>&1; then
        echo "✅ gke-gcloud-auth-plugin installed successfully!"
        gke-gcloud-auth-plugin --version
    else
        echo "❌ Failed to verify gke-gcloud-auth-plugin installation"
        exit 1
    fi

    # Add Google Cloud SDK paths to zshrc if not already present
    ZSHRC_FILE="${HOME}/.zshrc"
    echo "Updating ${ZSHRC_FILE} with Google Cloud SDK configuration..."

    # Create zshrc if it doesn't exist
    touch "${ZSHRC_FILE}"

    # Check if Google Cloud SDK lines are already in zshrc
    if ! grep -q "google-cloud-sdk/path.zsh.inc" "${ZSHRC_FILE}"; then
        {
            echo ""
            echo "# The next line updates PATH for the Google Cloud SDK."
            echo "if [ -f '${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc' ]; then . '${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc'; fi"
            echo ""
            echo "# The next line enables shell command completion for gcloud."
            echo "if [ -f '${HOMEBREW_PREFIX}/share/google-cloud-sdk/completion.zsh.inc' ]; then . '${HOMEBREW_PREFIX}/share/google-cloud-sdk/completion.zsh.inc'; fi"
        } >> "${ZSHRC_FILE}"
        echo "✅ Added Google Cloud SDK configuration to ${ZSHRC_FILE}"
    else
        echo "✅ Google Cloud SDK configuration already present in ${ZSHRC_FILE}"
    fi

    echo "🎉 Google Cloud SDK reconfiguration completed successfully!"
    echo "💡 You may need to restart your terminal or run 'source ~/.zshrc' to use the updated PATH"

# System cleanup to free up disk space (Homebrew and Docker).
[group('system')]
system-cleanup:
    #!/usr/bin/env bash
    echo "========== System Cleanup Operations =========="
    echo "This command will perform the following actions:"
    echo "  1. Homebrew cleanup:"
    echo "     - Remove old versions of installed formulae"
    echo "     - Delete cached downloads and outdated packages"
    echo ""
    echo "  2. Docker cleanup:"
    echo "     - Remove all stopped containers"
    echo "     - Remove all dangling images"
    echo "     - Remove all unused networks"
    echo "     - Remove all build cache not being used"
    echo ""
    echo "This will free up disk space, but you won't be able to"
    echo "recover the removed data afterward."
    echo "=============================================="
    echo ""

    read -p "Do you want to continue with system cleanup? (y/n) " -n 1 -r
    echo    # Move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo "Running cleanup operations..."
        brew cleanup && docker system prune -f
        echo "✅ System cleanup completed successfully!"
    else
        echo "System cleanup cancelled."
    fi

# List all running Docker containers with formatted output.
[group('docker')]
docker-ps:
    @docker ps --format 'table {{"{{"}}.Names{{"}}"}}\t{{"{{"}}.Status{{"}}"}}\t{{"{{"}}.Ports{{"}}"}}'

# Clean up unused Docker resources to free disk space.
[group('docker')]
docker-prune:
    @docker system prune -f

# List all sparkdock-managed packages with their categories and descriptions.
[group('sparkdock')]
sparkdock-packages package_filter="":
    #!/usr/bin/env bash
    set -euo pipefail
    bash {{ sparkdock_path }}/sjust/libs/list-packages.sh "{{package_filter}}"

# Alias for sparkdock-packages (short form).
[group('sparkdock')]
packages package_filter="":
    @just sparkdock-packages "{{package_filter}}"

# Install sparkdock ansible tag.
[group('sparkdock')]
sparkdock-install-tags tags:
    #!/usr/bin/env bash
    echo "Running ansible with following tags: {{tags}}"
    cd {{ sparkdock_path }}
    
    # Ensure Python3 is installed and available at the expected location
    sparkdock ensure-python3
    
    ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "{{tags}}" --ask-become-pass

# Fetch latest Sparkdock updates from git repository without running system configuration. Useful for getting the newest sjust recipes and commands without triggering a full system update.
[group('sparkdock')]
sparkdock-fetch-updates:
    #!/usr/bin/env bash
    set -e
    echo "Fetching latest Sparkdock updates..."
    cd {{ sparkdock_path }}

    # Fix git ownership issues
    echo "🔧 Configuring git safe directory..."
    git config --local --add safe.directory $PWD

    # Check if we're on {{ default_branch }} branch.
    current_branch=$(git branch --show-current)
    if [[ "${current_branch}" != "{{ default_branch }}" ]]; then
        echo "❌ Error: Not on {{ default_branch }} branch (currently on '${current_branch}')"
        echo "💡 Switch to {{ default_branch }} branch first: git checkout {{ default_branch }}"
        exit 1
    fi

    # Fetch latest changes to compare
    echo "🔄 Fetching latest changes..."
    git fetch origin

    # Check if we're already up to date
    if git diff --quiet HEAD origin/{{ default_branch }}; then
        echo "✅ Already up to date!"
        echo "💡 Run 'sjust --list' to see available commands."
        exit 0
    fi

    # Stash any local changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "📦 Stashing local changes..."
        git stash -m "Auto-stash before update $(date)"
    fi

    echo "⬆️  Updating to latest {{ default_branch }}..."
    git reset --hard origin/{{ default_branch }}

    echo "✅ Sparkdock updates fetched successfully!"
    echo "📝 You now have access to the latest sjust commands and configurations."
    echo "💡 Run 'sjust --list' to see available commands."

# Run sparkdock system configuration and updates.
[group('sparkdock')]
sparkdock-upgrade:
    #!/usr/bin/env bash
    {{ sparkdock_path }}/bin/sparkdock.macos
    echo "System configuration and updates completed!"

# Rebuild and install the latest Sparkdock menu bar application.
[group('sparkdock')]
sparkdock-menubar-install:
    #!/usr/bin/env bash
    echo "Rebuilding and installing Sparkdock menu bar application..."
    cd {{ sparkdock_path }}
    echo "🔧 Running ansible with menubar tag to rebuild and install..."
    # Check if running in CI/non-interactive mode (detect based on common CI environment variables)
    if [[ -n "$CI" || -n "$GITHUB_ACTIONS" || -n "$NON_INTERACTIVE" ]]; then
        echo "🤖 Detected non-interactive environment, running without password prompt..."
        ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "menubar" -e "ansible_become_password=" --become
    else
        ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "menubar" --ask-become-pass
    fi
    echo "✅ Sparkdock menu bar app rebuilt and installed successfully!"
    echo "💡 The app should now be running via LaunchAgent"

# Fix Xcode command line tools and rebuild menubar application.
[group('sparkdock')]
sparkdock-menubar-reinstall:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔧 Fixing Xcode command line tools and rebuilding Sparkdock menu bar application..."
    echo ""
    echo "This will fix common Swift compilation issues by reinstalling Xcode command line tools."
    echo "You will be prompted for your password and may need to interact with the installer."
    echo ""

    # Check if we're in a CI environment
    if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${NON_INTERACTIVE:-}" ]]; then
        echo "❌ This task cannot run in CI/non-interactive environments"
        echo "💡 Run this task manually on your local machine if you encounter compilation issues"
        exit 1
    fi

    # Confirm with user
    read -p "🤔 Do you want to proceed with removing and reinstalling Xcode command line tools? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled"
        exit 1
    fi

    echo "🗑️  Removing existing Xcode command line tools..."
    if [[ -d "/Library/Developer/CommandLineTools" ]]; then
        sudo rm -rf /Library/Developer/CommandLineTools
        echo "✅ Existing command line tools removed"
    fi

    echo "📥 Installing Xcode command line tools..."
    echo "💡 A dialog will appear - please click 'Install' and wait for completion"
    xcode-select --install

    # Wait for installation to complete
    echo "⏳ Waiting for Xcode command line tools installation to complete..."
    echo "💡 This may take several minutes. Please be patient..."

    while ! xcode-select -p &> /dev/null; do
        echo "⏳ Still waiting for installation to complete..."
        sleep 10
    done

    echo "✅ Xcode command line tools installation completed!"
    echo ""
    echo "🔧 Now attempting to rebuild and install the menubar application..."
    cd {{ sparkdock_path }}

    # Try to build the menubar app
    if ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "menubar" --ask-become-pass; then
        echo ""
        echo "🎉 Success! Sparkdock menu bar app has been rebuilt and installed!"
        echo "💡 The app should now be running via LaunchAgent"
    else
        echo ""
        echo "❌ Menubar installation still failed after fixing command line tools"
        echo "💡 You may need to:"
        echo "   - Restart your terminal/shell session"
        echo "   - Check for other Swift/Xcode related issues"
        echo "   - Verify Xcode license acceptance: sudo xcodebuild -license accept"
        exit 1
    fi

# Start/restart the Sparkdock menu bar application using LaunchAgent.
[group('sparkdock')]
sparkdock-menubar-start:
    #!/usr/bin/env bash
    # Kill any running processes first
    pkill -f "{{sparkdock_menubar_process_name}}" 2>/dev/null || true

    just _menubar_plist_unload

    # Load and start the service
    PLIST_PATH="{{sparkdock_menubar_plist_path}}"
    if ! launchctl bootstrap gui/$(id -u) "${PLIST_PATH}"; then
        echo "❌ Failed to bootstrap menu bar app via LaunchAgent"
        exit 1
    fi

    if ! launchctl enable gui/$(id -u)/com.sparkfabrik.sparkdock.menubar; then
        echo "❌ Failed to enable menu bar app via LaunchAgent"
        exit 1
    fi

    if ! launchctl kickstart gui/$(id -u)/com.sparkfabrik.sparkdock.menubar; then
        echo "❌ Failed to kickstart menu bar app via LaunchAgent"
        exit 1
    fi

    echo "✅ Sparkdock menu bar app started successfully"

# Stop the Sparkdock menu bar application using LaunchAgent.
[group('sparkdock')]
sparkdock-menubar-stop:
    #!/usr/bin/env bash
    just _menubar_plist_unload

    # Kill any running processes
    pkill -f "{{sparkdock_menubar_process_name}}" 2>/dev/null || true

    echo "✅ Sparkdock menu bar app stopped successfully"
