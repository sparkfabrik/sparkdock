# Just check if Docker CLI is installed.
_docker_desktop_check_cli:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker CLI not found. Please install Docker Desktop first."
        exit 1
    fi

_docker_desktop_ensure_running:
    #!/usr/bin/env bash
    set -euo pipefail

    DOCKER_SETTINGS_FILE="{{ docker_settings_file }}"

    if [[ ! -f "${DOCKER_SETTINGS_FILE}" ]]; then
        echo "❌ Docker Desktop settings file not found at ${DOCKER_SETTINGS_FILE}"
        echo "💡 Make sure Docker Desktop is installed and has been run at least once."
        exit 1
    fi


    if ! docker desktop status >/dev/null 2>&1; then
        echo "⚠️  Docker Desktop is not running. Starting Docker Desktop..."
        docker desktop start
        echo "⏳ Waiting for Docker Desktop to start..."

        # Wait up to 60 seconds for Docker to be ready
        timeout=60
        while ! docker desktop status >/dev/null 2>&1 && (( timeout > 0 )); do
            sleep 2
            ((timeout -= 2))
        done

        if ! docker desktop status >/dev/null 2>&1; then
            echo "❌ Docker Desktop failed to start within 60 seconds"
            echo "💡 Please start Docker Desktop manually and try again"
            exit 1
        fi
        echo "✅ Docker Desktop is now running"
    fi

_docker_desktop_ensure_backup_file:
    #!/usr/bin/env bash
    set -euo pipefail

    DOCKER_SETTINGS_FILE="{{ docker_settings_file }}"
    BACKUP_DIR="${HOME}/.local/spark/docker-desktop"

    mkdir -p "${BACKUP_DIR}"
    BACKUP_FILE="${BACKUP_DIR}/settings-store.json.backup.$(date +%Y%m%d_%H%M%S)"

    # Cleanup old backups, keep only last 50.
    ls -1t ${BACKUP_DIR}/settings-store.json.backup.* 2>/dev/null | tail -n +51 | xargs -r rm --

    cp "${DOCKER_SETTINGS_FILE}" "${BACKUP_FILE}"
    echo "${BACKUP_FILE}"

# Update Docker Desktop setting with atomic backup/restore and verification
_docker_desktop_update_setting parameter desired_value description:
    #!/usr/bin/env bash
    set -euo pipefail

    DOCKER_SETTINGS_FILE="{{ docker_settings_file }}"
    PARAMETER="{{ parameter }}"
    DESIRED_VALUE="{{ desired_value }}"
    DESCRIPTION="{{ description }}"

    # Create backup first
    BACKUP_FILE="$(just _docker_desktop_ensure_backup_file)"

    # Check current setting value
    CURRENT_VALUE=$(jq -r ".${PARAMETER}" "${DOCKER_SETTINGS_FILE}")
    echo "🔍 Current ${PARAMETER} setting: ${CURRENT_VALUE}"

    if [[ "${CURRENT_VALUE}" == "${DESIRED_VALUE}" ]]; then
        echo "✅ ${DESCRIPTION} is already enabled!"
        echo "💡 You can restart Docker Desktop to ensure settings are applied"
        exit 0
    fi

    # Update the setting
    echo "🔧 Updating ${PARAMETER} setting to ${DESIRED_VALUE}..."
    jq ".${PARAMETER} = ${DESIRED_VALUE}" "${DOCKER_SETTINGS_FILE}" > "${DOCKER_SETTINGS_FILE}.tmp"
    mv "${DOCKER_SETTINGS_FILE}.tmp" "${DOCKER_SETTINGS_FILE}"

    # Verify the change and restore backup on failure
    NEW_VALUE=$(jq -r ".${PARAMETER}" "${DOCKER_SETTINGS_FILE}")
    if [[ "${NEW_VALUE}" == "${DESIRED_VALUE}" ]]; then
        echo "✅ Successfully updated ${PARAMETER} to ${DESIRED_VALUE}"
        echo "⚠️  You need to restart Docker Desktop for the changes to take effect"
        echo "💡 Run 'sjust docker-desktop-restart' to restart Docker Desktop"
    else
        echo "❌ Failed to update ${PARAMETER} setting"
        echo "🔄 Restoring backup ${BACKUP_FILE}..."
        mv "${BACKUP_FILE}" "${DOCKER_SETTINGS_FILE}"
        exit 1
    fi

# Helper function to validate plist and unload service
_menubar_plist_unload:
    #!/usr/bin/env bash
    PLIST_PATH="{{sparkdock_menubar_plist_path}}"

    if [[ ! -f "${PLIST_PATH}" ]]; then
        echo "❌ LaunchAgent plist not found at ${PLIST_PATH}"
        exit 1
    fi

    # Bootout the service if it's currently loaded (ignore errors)
    launchctl bootout gui/$(id -u) "${PLIST_PATH}" 2>/dev/null || true
