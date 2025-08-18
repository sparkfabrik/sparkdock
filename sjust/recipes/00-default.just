# vim: set ft=make :

uid := `id -u`
shell := `grep :$(id -u): /etc/passwd | cut -d: -f7`
sparkdock_path := "/opt/sparkdock"
default_branch := "master"

# Print system information.
[group('system')]
device-info:
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
clear-dns-cache:
    @sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
    @echo "DNS cache cleared successfully!"

# Install and update http-proxy to latest version.
[group('http-proxy')]
install-update-http-proxy:
    #!/usr/bin/env bash
    set -e
    echo "Installing/updating http-proxy system to latest version..."
    cd {{ sparkdock_path }}

    # Update http-proxy repository if it exists
    if [ -d "http-proxy" ]; then
        echo "🔄 Updating existing http-proxy repository..."
        cd http-proxy

        # Fix git ownership issues
        echo "🔧 Configuring git safe directory..."
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
    # Check if running in CI/non-interactive mode (detect based on common CI environment variables)
    if [[ -n "$CI" || -n "$GITHUB_ACTIONS" || -n "$NON_INTERACTIVE" ]]; then
        echo "🤖 Detected non-interactive environment, running without password prompt..."
        ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "http-proxy" -e "ansible_become_password=" --become
    else
        ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "http-proxy" --ask-become-pass
    fi

    # Clean up and restart
    echo "🔄 Restarting http-proxy services..."
    docker rm -vf http-proxy || true
    spark-http-proxy start
    echo "✅ Http-proxy installation/update completed!"

# Update system packages via Homebrew.
[group('system')]
upgrade-system:
    #!/usr/bin/env bash
    echo "Updating system packages..."
    brew update && brew upgrade && brew cleanup
    echo "System packages updated successfully!"

# Install mkcert for local SSL certificate generation.
[group('system')]
install-mkcert:
    #!/usr/bin/env bash
    echo "Installing mkcert..."
    brew install mkcert nss
    mkcert -install
    echo "mkcert installed successfully!"

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

# Restart the Docker daemon to resolve common issues.
[group('docker')]
docker-restart:
    @osascript -e 'quit app "Docker"' && open -a Docker

# Install sparkdock ansible tag.
[group('sparkdock')]
install-tags tags:
    #!/usr/bin/env bash
    echo "Running ansible with following tags: {{tags}}"
    cd {{ sparkdock_path }}
    ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "{{tags}}" --ask-become-pass

# Update Sparkdock git repository to latest version, it doesn't run any ansible task.
[group('sparkdock')]
update-sparkdock-repository:
    #!/usr/bin/env bash
    set -e
    echo "Updating Sparkdock repository to latest version..."
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

    echo "✅ Sparkdock updated successfully!"
    echo "📝 You now have access to the latest sjust commands and configurations."
    echo "💡 Run 'sjust --list' to see available commands."

# Run sparkdock system configuration and updates.
[group('sparkdock')]
upgrade:
    #!/usr/bin/env bash
    {{ sparkdock_path }}/bin/sparkdock.macos
    echo "System configuration and updates completed!"

# Rebuild and install the latest Sparkdock menu bar application.
[group('sparkdock')]
menubar-install:
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

# Helper functions for menubar management
_menubar_plist_path := "${HOME}/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist"
_menubar_process_name := "sparkdock-manager"

# Check if menubar app process is running
_menubar_is_running:
    #!/usr/bin/env bash
    pgrep -f "{{_menubar_process_name}}" > /dev/null

# Stop any running menubar processes
_menubar_kill_processes:
    #!/usr/bin/env bash
    if pgrep -f "{{_menubar_process_name}}" > /dev/null; then
        echo "🔄 Terminating any running {{_menubar_process_name}} processes..."
        pkill -f "{{_menubar_process_name}}"
        sleep 1
        if pgrep -f "{{_menubar_process_name}}" > /dev/null; then
            echo "⚠️  Some processes may still be running"
        else
            echo "✅ All {{_menubar_process_name}} processes stopped"
        fi
    else
        echo "✅ No {{_menubar_process_name}} processes found"
    fi

# Start/restart the Sparkdock menu bar application using LaunchAgent.
[group('sparkdock')]
menubar-start:
    #!/usr/bin/env bash
    echo "Starting Sparkdock menu bar application via LaunchAgent..."
    
    PLIST_PATH="{{_menubar_plist_path}}"
    
    if [[ ! -f "${PLIST_PATH}" ]]; then
        echo "❌ LaunchAgent plist not found at ${PLIST_PATH}"
        echo "💡 Run 'sjust menubar-install' first to install the menu bar app"
        exit 1
    fi
    
    # Unload the service if it's currently loaded (ignore errors)
    launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    
    # Load the service
    if launchctl load "${PLIST_PATH}"; then
        echo "✅ Sparkdock menu bar app started successfully via LaunchAgent!"
        echo "💡 Look for the Sparkdock icon in your menu bar"
        
        # Give it a moment to start and then check if it's running
        sleep 2
        if just _menubar_is_running; then
            echo "✅ Menu bar app is now running"
        else
            echo "⚠️  Menu bar app may still be starting up"
        fi
    else
        echo "❌ Failed to start menu bar app via LaunchAgent"
        echo "💡 Check if the app is installed: ls -la ${PLIST_PATH}"
        echo "💡 Try running 'sjust menubar-install' to reinstall"
        exit 1
    fi

# Stop the Sparkdock menu bar application using LaunchAgent.
[group('sparkdock')]
menubar-stop:
    #!/usr/bin/env bash
    echo "Stopping Sparkdock menu bar application..."
    
    PLIST_PATH="{{_menubar_plist_path}}"
    
    if [[ ! -f "${PLIST_PATH}" ]]; then
        echo "❌ LaunchAgent plist not found at ${PLIST_PATH}"
        echo "💡 Menu bar app may not be installed via LaunchAgent"
    else
        # Unload the service
        if launchctl unload "${PLIST_PATH}" 2>/dev/null; then
            echo "✅ Menu bar app LaunchAgent unloaded"
        else
            echo "⚠️  LaunchAgent was not loaded or failed to unload"
        fi
    fi
    
    # Also kill any running processes
    just _menubar_kill_processes
