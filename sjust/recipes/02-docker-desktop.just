# vim: set ft=make :

# Run Docker Desktop diagnostics
[group('docker-desktop')]
docker-desktop-diagnose upload="false":
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
        exit 0
    fi

    echo "🔍 Running Docker Desktop diagnostics..."
    "${DIAGNOSE_PATH}"
    echo "✅ Diagnostics completed. Results saved locally."
    echo "💡 To upload diagnostics to Docker support, run: sjust docker-desktop-diagnose true"
