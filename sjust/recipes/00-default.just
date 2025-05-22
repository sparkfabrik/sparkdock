# vim: set ft=make :

uid := `id -u`
shell := `grep :$(id -u): /etc/passwd | cut -d: -f7`

# Print system information.
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
start-http-proxy:
    #!/usr/bin/env bash

    # The certs are only red by dinghy on startup.
    # Rerun the script to update the certs.
    mkdir -p ~/.dinghy/certs

    echo "Starting a dinghy-http-proxy container..."
    IMAGE=codekitchen/dinghy-http-proxy:2.7.1
    docker pull ${IMAGE}
    docker rm -vf http-proxy || true
    docker run -d --restart=always \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    -v ~/.dinghy/certs:/etc/nginx/certs \
    -p 80:80 -p 443:443 -p 19322:19322/udp \
    -e DNS_IP=127.0.0.1 -e CONTAINER_NAME=http-proxy -e DOMAIN_TLD=loc \
    --name http-proxy \
     ${IMAGE}

# Update Sparkdock to the latest version.
[group('maintenance')]
upgrade-sparkdock:
    #!/usr/bin/env bash
    echo "Upgrading Sparkdock environment..."
    cd /opt/sparkdock && git pull
    # Reload sjust recipes if needed
    echo "Sparkdock updated successfully!"

# Update system packages via Homebrew.
[group('system')]
upgrade-system:
    #!/usr/bin/env bash
    echo "Updating system packages..."
    brew update && brew upgrade && brew cleanup
    echo "System packages updated successfully!"

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

