# vim: set ft=make :

# Restart the Docker daemon to resolve common issues.
[group('docker-desktop')]
docker-desktop-restart: _docker_desktop_check_cli
    @docker desktop restart

# Use a more efficient kernel networking path for UDP. This may not be compatible with your VPN software
[group('docker-desktop')]
docker-desktop-enable-kernel-udp: _docker_desktop_check_cli
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Enabling Docker Desktop kernel networking for UDP..."

    # Ensure Docker Desktop is running.
    just _docker_desktop_ensure_running

    # Update Docker Desktop kernel networking setting for UDP (with automatic backup)
    just _docker_desktop_update_setting "KernelForUDP" "true" "kernel networking for UDP"

# Disable docker desktop kernel networking for UDP.
[group('docker-desktop')]
docker-desktop-disable-kernel-udp: _docker_desktop_check_cli
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Disabling Docker Desktop kernel networking for UDP..."

    # Ensure Docker Desktop is running.
    just _docker_desktop_ensure_running

    # Update Docker Desktop kernel networking setting for UDP (with automatic backup)
    just _docker_desktop_update_setting "KernelForUDP" "false" "kernel networking for UDP"

# Host networking allows containers that are started with --net=host use localhost to connect to TCP and UDP services on the host.
[group('docker-desktop')]
docker-desktop-enable-host-networking: _docker_desktop_check_cli
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Enabling Docker Desktop host networking..."

    # Ensure Docker Desktop is running.
    just _docker_desktop_ensure_running

    # Update Docker Desktop host networking setting (with automatic backup)
    just _docker_desktop_update_setting "EnableHostNetworking" "true" "host networking"

# Disable host networking for Docker Desktop.
[group('docker-desktop')]
docker-desktop-disable-host-networking: _docker_desktop_check_cli
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Disabling Docker Desktop host networking..."

    # Ensure Docker Desktop is running.
    just _docker_desktop_ensure_running

    # Update Docker Desktop host networking setting (with automatic backup)
    just _docker_desktop_update_setting "EnableHostNetworking" "false" "host networking"

# Run Docker Desktop diagnostics
[group('docker-desktop')]
docker-desktop-diagnose upload="false": _docker_desktop_check_cli
    #!/usr/bin/env bash
    set -euo pipefail
    
    DIAGNOSE_PATH="/Applications/Docker.app/Contents/MacOS/com.docker.diagnose"
    UPLOAD="{{ upload }}"
    
    if [[ ! -f "${DIAGNOSE_PATH}" ]]; then
        echo "❌ Docker Desktop diagnose tool not found at ${DIAGNOSE_PATH}"
        echo "💡 Make sure Docker Desktop is installed properly."
        exit 1
    fi
    
    if [[ "${UPLOAD}" == "true" ]]; then
        echo "🔍 Running Docker Desktop diagnostics with upload..."
        "${DIAGNOSE_PATH}" gather -upload
        echo "✅ Diagnostics completed and uploaded to Docker support."
    else
        echo "🔍 Running Docker Desktop diagnostics..."
        "${DIAGNOSE_PATH}"
        echo "✅ Diagnostics completed. Results saved locally."
        echo "💡 To upload diagnostics to Docker support, run: sjust docker-desktop-diagnose upload=true"
    fi

# Install specific version of Docker Desktop (4.41.2) to work around network issues
[group('docker-desktop')]
docker-desktop-install-version-4412:
    #!/usr/bin/env bash
    set -euo pipefail
    
    DMG_URL="https://desktop.docker.com/mac/main/arm64/191736/Docker.dmg"
    
    echo "🐳 Downloading and opening Docker Desktop 4.41.2..."
    curl -L -o /tmp/Docker.dmg "${DMG_URL}"
    open /tmp/Docker.dmg
    echo "✅ Docker Desktop DMG downloaded and opened. Please complete the installation manually."
