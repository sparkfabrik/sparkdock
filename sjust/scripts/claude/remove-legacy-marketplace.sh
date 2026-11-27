#!/usr/bin/env bash
set -euo pipefail

# Remove the legacy sparkfabrik-plugins marketplace from Claude Code.
#
# The plugins of sparkfabrik/sf-claude-plugins now reach everyone through the
# claude.ai organization sync (<plugin>@synced). The marketplace, registered by
# earlier managed settings or added by hand, clones a private repository: it
# fails for people without access and duplicates the synced plugins for the
# others. This removes its plugins, its declarations, the marketplace and their
# cached copies. It does nothing on machines that never had it.
#
# Usage: remove-legacy-marketplace.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_LIB_DIR="${SCRIPT_DIR}/../lib"
MARKETPLACE="sparkfabrik-plugins"

# Claude Code's official installer puts the binary in <user>/.local/bin, which
# non-interactive provisioning (Ansible, sudo/become on Linux) often lacks on
# PATH. Resolve the effective user's home the same way caveman/setup.sh does.
user_home="${HOME}"
if command -v getent >/dev/null 2>&1; then
    resolved_home="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || true)"
    [[ -n "${resolved_home}" ]] && user_home="${resolved_home}"
fi
export PATH="${user_home}/.local/bin:/opt/homebrew/bin:${PATH}"
PLUGINS_DIR="${user_home}/.claude/plugins"

if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code not installed, nothing to clean up."
    exit 0
fi

# Print "<scope>\t<projectPath or ->\t<plugin id>" for every install of a plugin
# from the legacy marketplace, read from Claude Code's own registry.
legacy_installs() {
    local registry="${PLUGINS_DIR}/installed_plugins.json"
    [[ -f "${registry}" ]] || return 0
    python3 - "${registry}" "${MARKETPLACE}" <<'EOF'
import json
import sys

registry, marketplace = sys.argv[1], sys.argv[2]
with open(registry, encoding="utf-8") as handle:
    data = json.load(handle)
plugins = data.get("plugins", data) if isinstance(data, dict) else {}
for plugin_id, installs in plugins.items():
    if not plugin_id.endswith("@" + marketplace):
        continue
    for install in installs if isinstance(installs, list) else [installs]:
        if not isinstance(install, dict):
            continue
        scope = install.get("scope") or "user"
        print(scope, install.get("projectPath") or "-", plugin_id, sep="\t")
EOF
}

# True when the marketplace is cloned or still declared in the user settings
marketplace_present() {
    python3 - "${PLUGINS_DIR}/known_marketplaces.json" "${user_home}/.claude/settings.json" "${MARKETPLACE}" <<'EOF'
import json
import sys

known, settings, marketplace = sys.argv[1:4]


def load(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


declared = load(settings).get("extraKnownMarketplaces") or {}
sys.exit(0 if marketplace in load(known) or marketplace in declared else 1)
EOF
}

# Drop enabledPlugins entries of the legacy marketplace from the user
# settings, with a backup and an atomic write; prints each removed id.
drop_enabled_entries() {
    PYTHONPATH="${SETTINGS_LIB_DIR}" python3 - "${user_home}/.claude/settings.json" "${MARKETPLACE}" <<'EOF'
import sys
from pathlib import Path

import claude_settings

path, marketplace = Path(sys.argv[1]), sys.argv[2]
if not path.exists():
    sys.exit(0)
data = claude_settings.load(path)
enabled = data.get("enabledPlugins") or {}
stale = [plugin_id for plugin_id in enabled if plugin_id.endswith("@" + marketplace)]
if not stale:
    sys.exit(0)
claude_settings.backup(path)
for plugin_id in stale:
    del enabled[plugin_id]
claude_settings.atomic_write(data, path)
print("\n".join(stale))
EOF
}

changed=0

while IFS=$'\t' read -r scope project plugin_id; do
    [[ -n "${plugin_id:-}" ]] || continue
    case "${scope}" in
        user)
            if claude plugin uninstall --scope user "${plugin_id}" >/dev/null 2>&1; then
                echo "Uninstalled ${plugin_id}"
                changed=1
            else
                echo "Could not uninstall ${plugin_id}, continuing"
            fi
            ;;
        project | local)
            if [[ -d "${project}" ]] && (cd "${project}" && claude plugin uninstall --scope "${scope}" "${plugin_id}" >/dev/null 2>&1); then
                echo "Uninstalled ${plugin_id} from ${project} (${scope})"
                changed=1
            else
                echo "Could not uninstall ${plugin_id} from ${project} (${scope}), continuing"
            fi
            ;;
        *)
            # Managed installs follow the managed settings, which no longer
            # list this marketplace; Claude Code drops them on its own.
            echo "Skipping ${plugin_id} (${scope} scope)"
            ;;
    esac
done < <(legacy_installs)

while read -r plugin_id; do
    [[ -n "${plugin_id}" ]] || continue
    echo "Removed ${plugin_id} from enabledPlugins"
    changed=1
done < <(drop_enabled_entries || echo "")

if marketplace_present; then
    if claude plugin marketplace remove "${MARKETPLACE}" >/dev/null 2>&1; then
        echo "Removed the ${MARKETPLACE} marketplace"
        changed=1
    else
        echo "Could not remove the ${MARKETPLACE} marketplace, continuing"
    fi
fi

for leftover in "${PLUGINS_DIR}/cache/${MARKETPLACE}" "${PLUGINS_DIR}/marketplaces/${MARKETPLACE}"; do
    if [[ -d "${leftover}" ]]; then
        rm -rf "${leftover}"
        echo "Removed ${leftover}"
        changed=1
    fi
done

if [[ "${changed}" -eq 0 ]]; then
    echo "No ${MARKETPLACE} leftovers found."
fi
