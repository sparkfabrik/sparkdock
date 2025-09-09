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

# Install specific version of Docker Desktop (4.41.2) to work around network issues
[group('docker-desktop')]
docker-desktop-install-specific-version:
    #!/usr/bin/env bash
    set -euo pipefail
    
    DOCKER_VERSION="4.41.2"
    DMG_URL="https://desktop.docker.com/mac/main/arm64/191736/Docker.dmg"
    DOCKER_APP_PATH="/Applications/Docker.app"
    TEMP_DIR="/tmp/docker-install-$$"
    
    echo "🐳 Installing Docker Desktop version ${DOCKER_VERSION}..."
    
    # Check if Docker Desktop is already installed with the target version
    if [[ -d "${DOCKER_APP_PATH}" ]]; then
        if command -v docker >/dev/null 2>&1; then
            CURRENT_VERSION=$(docker version --format '{{"{{"}}.Client.Version{{"}}"}}' 2>/dev/null || echo "unknown")
            if [[ "${CURRENT_VERSION}" == "${DOCKER_VERSION}" ]]; then
                echo "✅ Docker Desktop ${DOCKER_VERSION} is already installed!"
                exit 0
            fi
            echo "⚠️  Docker Desktop is installed but version is ${CURRENT_VERSION}, will install ${DOCKER_VERSION}"
        else
            echo "⚠️  Docker.app exists but Docker CLI not available, will reinstall"
        fi
    fi
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Cleanup function
    cleanup() {
        echo "🧹 Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
    }
    trap cleanup EXIT
    
    echo "⬇️  Downloading Docker Desktop ${DOCKER_VERSION} DMG..."
    if ! curl -L -o "${TEMP_DIR}/Docker.dmg" "${DMG_URL}"; then
        echo "❌ Failed to download Docker Desktop DMG"
        exit 1
    fi
    
    echo "📦 Mounting Docker Desktop DMG..."
    MOUNT_POINT="${TEMP_DIR}/docker-mount"
    if ! hdiutil attach "${TEMP_DIR}/Docker.dmg" -mountpoint "${MOUNT_POINT}" -quiet; then
        echo "❌ Failed to mount Docker Desktop DMG"
        exit 1
    fi
    
    # Cleanup function to unmount DMG
    cleanup_with_unmount() {
        echo "📤 Unmounting Docker Desktop DMG..."
        hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
        cleanup
    }
    trap cleanup_with_unmount EXIT
    
    echo "📋 Installing Docker Desktop to Applications..."
    if [[ -d "${DOCKER_APP_PATH}" ]]; then
        echo "🗑️  Removing existing Docker Desktop installation..."
        sudo rm -rf "${DOCKER_APP_PATH}"
    fi
    
    if ! sudo cp -R "${MOUNT_POINT}/Docker.app" /Applications/; then
        echo "❌ Failed to copy Docker Desktop to Applications"
        exit 1
    fi
    
    # Fix permissions
    sudo chown -R root:admin "${DOCKER_APP_PATH}"
    sudo chmod -R 755 "${DOCKER_APP_PATH}"
    
    echo "✅ Docker Desktop ${DOCKER_VERSION} installed successfully!"
    echo "💡 You can now start Docker Desktop from Applications or run 'open -a Docker'"
    echo "⚠️  Note: You may need to go through the initial setup when first launching Docker Desktop"
