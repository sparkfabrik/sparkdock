# vim: set ft=make :

# Path to the managed statusline script, resolved per-platform from this file's
# location: shared/07-claude-statusline.just lives at <sparkdock_root>/sjust/recipes/shared/
_statusline_script := clean(source_directory() / "../../..") / "config/bin/sparkfabrik-claude-statusline"

# Enable the SparkFabrik managed statusline in ~/.claude/settings.json (opt-in, idempotent, overridable).
[group('claude')]
claude-statusline-enable:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT="{{_statusline_script}}"
    SETTINGS="${HOME}/.claude/settings.json"
    COMMAND="bash ${SCRIPT}"

    if [[ ! -x "${SCRIPT}" ]]; then
        echo "❌ Statusline script not found or not executable: ${SCRIPT}"
        echo "💡 Update sparkdock (git pull) and try again."
        exit 1
    fi

    mkdir -p "${HOME}/.claude"
    [[ -f "${SETTINGS}" ]] || echo '{}' > "${SETTINGS}"

    # Already pointing at the managed script? Nothing to do.
    if command -v jq >/dev/null 2>&1 && \
       [[ "$(jq -r '.statusLine.command // empty' "${SETTINGS}" 2>/dev/null)" == "${COMMAND}" ]]; then
        echo "ℹ️  SparkFabrik statusline already enabled in ${SETTINGS}"
        exit 0
    fi

    # Back up before touching the user's settings.
    BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${SETTINGS}" "${BACKUP}"

    # Merge the statusLine block, preserving every other key. Warn (don't clobber
    # silently) if a different statusLine was already configured.
    python3 - "${SETTINGS}" "${COMMAND}" <<'PY'
    import json, sys
    path, command = sys.argv[1], sys.argv[2]
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    existing = data.get("statusLine")
    if isinstance(existing, dict) and existing.get("command") and existing.get("command") != command:
        print(f"⚠️  Replacing existing statusLine command: {existing.get('command')}")
    data["statusLine"] = {"type": "command", "command": command}
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    PY

    echo "✅ SparkFabrik statusline enabled in ${SETTINGS}"
    echo "💡 Backup saved to ${BACKUP}"
    echo "💡 Start a new Claude Code session (or it refreshes on next render)."
    echo "💡 Disable anytime with: claude-statusline-disable"

# Disable the SparkFabrik managed statusline (removes the statusLine key).
[group('claude')]
claude-statusline-disable:
    #!/usr/bin/env bash
    set -euo pipefail

    SETTINGS="${HOME}/.claude/settings.json"

    if [[ ! -f "${SETTINGS}" ]]; then
        echo "ℹ️  No ~/.claude/settings.json — nothing to disable."
        exit 0
    fi
    if ! command -v jq >/dev/null 2>&1 || \
       [[ "$(jq -r 'has("statusLine")' "${SETTINGS}" 2>/dev/null)" != "true" ]]; then
        echo "ℹ️  No statusLine configured in ${SETTINGS}."
        exit 0
    fi

    BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${SETTINGS}" "${BACKUP}"

    python3 - "${SETTINGS}" <<'PY'
    import json, sys
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)
    data.pop("statusLine", None)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    PY

    echo "✅ statusLine removed from ${SETTINGS}"
    echo "💡 Backup saved to ${BACKUP}"

# Show the current statusline configuration and the managed script path.
[group('claude')]
claude-statusline-info:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT="{{_statusline_script}}"
    SETTINGS="${HOME}/.claude/settings.json"
    COMMAND="bash ${SCRIPT}"

    echo "Managed script: ${SCRIPT}"
    [[ -x "${SCRIPT}" ]] && echo "  status: present (executable)" || echo "  status: MISSING — run 'git pull' in sparkdock"
    echo

    if [[ ! -f "${SETTINGS}" ]]; then
        echo "Configured: no (~/.claude/settings.json does not exist)"
        exit 0
    fi

    current="$(jq -r '.statusLine.command // empty' "${SETTINGS}" 2>/dev/null || true)"
    if [[ -z "${current}" ]]; then
        echo "Configured: no statusLine in ${SETTINGS}"
    elif [[ "${current}" == "${COMMAND}" ]]; then
        echo "Configured: ✅ SparkFabrik managed statusline"
    else
        echo "Configured: custom statusLine → ${current}"
    fi
