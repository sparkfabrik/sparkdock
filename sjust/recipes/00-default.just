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

# Launch the Sparkdock menu bar application.
[group('sparkdock')]
menubar:
    #!/usr/bin/env bash
    echo "Launching Sparkdock menu bar application..."
    if pgrep -f "sparkdock-manager" > /dev/null; then
        echo "⚠️  Sparkdock menu bar app is already running"
        echo "💡 If you need to restart it, quit the app first from the menu bar"
        echo "💡 If the app is stuck or not visible, use: pkill -f sparkdock-manager"
    else
        nohup /usr/local/bin/sparkdock-manager > /dev/null &
        echo "✅ Sparkdock menu bar app launched successfully!"
        echo "💡 Look for the Sparkdock icon in your menu bar"
    fi
