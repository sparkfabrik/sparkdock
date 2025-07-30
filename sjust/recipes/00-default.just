# vim: set ft=make :

uid := `id -u`
shell := `grep :$(id -u): /etc/passwd | cut -d: -f7`
sparkdock_path := "/opt/sparkdock"

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

# Run default docker http proxy.
[group('http-proxy')]
start-http-proxy:
    #!/usr/bin/env bash

    # The certs directory for the new http-proxy
    # Rerun the script to update the certs.
    mkdir -p ~/.local/spark/http-proxy/certs

    echo "Starting http-proxy container using spark-http-proxy..."
    if ! command -v spark-http-proxy &> /dev/null; then
        echo "Error: spark-http-proxy is not installed or not in PATH. Please install it and try again."
        exit 1
    fi
    spark-http-proxy start

# Start http-proxy with monitoring (Grafana + Prometheus).
[group('http-proxy')]
start-http-proxy-with-metrics:
    #!/usr/bin/env bash
    echo "Starting http-proxy with monitoring services..."
    spark-http-proxy start-with-metrics

# Show http-proxy status and dashboard links.
[group('http-proxy')]
http-proxy-status:
    #!/usr/bin/env bash
    echo "Checking http-proxy status..."
    spark-http-proxy status

# Open http-proxy dashboard in browser.
[group('http-proxy')]
http-proxy-dashboard:
    #!/usr/bin/env bash
    echo "Opening http-proxy dashboard..."
    spark-http-proxy dashboard

# Generate SSL certificates for a domain.
[group('http-proxy')]
generate-ssl-cert domain:
    #!/usr/bin/env bash
    echo "Generating SSL certificate for {{ domain }}..."
    spark-http-proxy generate-mkcert "{{ domain }}"

# Configure system DNS to resolve proxy domains.
[group('http-proxy')]
configure-dns:
    #!/usr/bin/env bash
    echo "Configuring system DNS for proxy domains..."
    spark-http-proxy configure-dns

# Show http-proxy configuration and file locations.
[group('http-proxy')]
http-proxy-config:
    #!/usr/bin/env bash
    echo "Showing http-proxy configuration..."
    spark-http-proxy show-config

# Install http-proxy without full system update (faster, targeted).
[group('http-proxy')]
install-http-proxy:
    #!/usr/bin/env bash
    echo "Configuring http-proxy system (targeted update)..."
    cd {{ sparkdock_path }}
    ansible-playbook -i ansible/inventory.ini ansible/macos.yml -v --tags "http-proxy" --ask-become-pass
    docker rm -vf http-proxy || true
    spark-http-proxy start
    echo "Http-proxy configuration completed!"

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

# System cleanup to free up disk space.
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

# Run sparkdock system configuration and updates.
[group('sparkdock')]
upgrade:
    #!/usr/bin/env bash
    {{ sparkdock_path }}/bin/sparkdock.macos
    echo "System configuration and updates completed!"