#!/usr/bin/env bash
# claude-statusline — enable/disable/show the SparkFabrik managed statusline in
# the user's ~/.claude/settings.json. Invoked by the shared sjust/ajust recipes
# (sjust/recipes/shared/07-claude-statusline.just); see those for usage.
#
# All JSON work is done in python3 (always present per the sparkdock toolchain)
# so there is no jq dependency, writes are atomic (temp file + os.replace), and
# corrupt/non-object settings files are handled gracefully. The script path is
# quoted inside the settings command so paths containing spaces work.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# scripts live at <sparkdock_root>/sjust/scripts/
SPARKDOCK_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
STATUSLINE_SCRIPT="${SPARKDOCK_ROOT}/config/bin/sparkfabrik-claude-statusline"
COMMAND="bash \"${STATUSLINE_SCRIPT}\""

SETTINGS="${HOME}/.claude/settings.json"

usage() {
    echo "Usage: claude-statusline.sh {enable|disable|info}" >&2
    exit 2
}

# Print the currently configured statusLine command (empty if none/unset).
# Tolerates a missing or corrupt settings file.
_current_command() {
    [[ -f "${SETTINGS}" ]] || { echo ""; return; }
    python3 - "${SETTINGS}" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    print(""); sys.exit(0)
if not isinstance(data, dict):
    print(""); sys.exit(0)
sl = data.get("statusLine")
print(sl.get("command", "") if isinstance(sl, dict) else "")
PY
}

_backup() {
    local backup
    backup="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${SETTINGS}" "${backup}"
    echo "${backup}"
}

cmd_enable() {
    if [[ ! -x "${STATUSLINE_SCRIPT}" ]]; then
        echo "❌ Statusline script not found or not executable: ${STATUSLINE_SCRIPT}"
        echo "💡 Update sparkdock (git pull) and try again."
        exit 1
    fi

    mkdir -p "${HOME}/.claude"
    [[ -f "${SETTINGS}" ]] || printf '{}\n' > "${SETTINGS}"

    if [[ "$(_current_command)" == "${COMMAND}" ]]; then
        echo "ℹ️  SparkFabrik statusline already enabled in ${SETTINGS}"
        exit 0
    fi

    local backup
    backup="$(_backup)"

    # Merge atomically, preserving every other key; warn before replacing a
    # different existing statusLine command.
    python3 - "${SETTINGS}" "${COMMAND}" <<'PY'
import json, os, sys, tempfile
path, command = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    data = {}
if not isinstance(data, dict):
    data = {}
existing = data.get("statusLine")
if isinstance(existing, dict) and existing.get("command") and existing.get("command") != command:
    print(f"⚠️  Replacing existing statusLine command: {existing.get('command')}")
data["statusLine"] = {"type": "command", "command": command}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings.", suffix=".json")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
except BaseException:
    os.path.exists(tmp) and os.unlink(tmp)
    raise
PY

    echo "✅ SparkFabrik statusline enabled in ${SETTINGS}"
    echo "💡 Backup saved to ${backup}"
    echo "💡 Start a new Claude Code session (or it refreshes on next render)."
    echo "💡 Disable anytime with: claude-statusline-disable"
}

cmd_disable() {
    if [[ ! -f "${SETTINGS}" ]]; then
        echo "ℹ️  No ~/.claude/settings.json — nothing to disable."
        exit 0
    fi
    if [[ -z "$(_current_command)" ]]; then
        echo "ℹ️  No statusLine configured in ${SETTINGS}."
        exit 0
    fi

    local backup
    backup="$(_backup)"

    python3 - "${SETTINGS}" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    data = {}
if not isinstance(data, dict):
    data = {}
data.pop("statusLine", None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings.", suffix=".json")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
except BaseException:
    os.path.exists(tmp) and os.unlink(tmp)
    raise
PY

    echo "✅ statusLine removed from ${SETTINGS}"
    echo "💡 Backup saved to ${backup}"
}

cmd_info() {
    echo "Managed script: ${STATUSLINE_SCRIPT}"
    if [[ -x "${STATUSLINE_SCRIPT}" ]]; then
        echo "  status: present (executable)"
    else
        echo "  status: MISSING — run 'git pull' in sparkdock"
    fi
    echo

    if [[ ! -f "${SETTINGS}" ]]; then
        echo "Configured: no (${SETTINGS} does not exist)"
        return
    fi

    local current
    current="$(_current_command)"
    if [[ -z "${current}" ]]; then
        echo "Configured: no statusLine in ${SETTINGS}"
    elif [[ "${current}" == "${COMMAND}" ]]; then
        echo "Configured: ✅ SparkFabrik managed statusline"
    else
        echo "Configured: custom statusLine → ${current}"
    fi
}

case "${1:-}" in
    enable)  cmd_enable ;;
    disable) cmd_disable ;;
    info)    cmd_info ;;
    *)       usage ;;
esac
