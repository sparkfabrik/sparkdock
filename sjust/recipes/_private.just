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
