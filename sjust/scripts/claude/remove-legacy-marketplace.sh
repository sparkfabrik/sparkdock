#!/usr/bin/env bash
set -euo pipefail

# Remove the legacy sparkfabrik-plugins marketplace from Claude Code.
#
# The plugins of sparkfabrik/sf-claude-plugins now reach everyone through the
# claude.ai organization sync (<plugin>@synced). The marketplace, registered by
# earlier managed settings or added by hand, clones a private repository: it
# fails for people without access and duplicates the synced plugins for the
# others. This removes its plugins, the marketplace and their cached copies.
# It does nothing on machines that never had it.
#
# Usage: remove-legacy-marketplace.sh

MARKETPLACE="sparkfabrik-plugins"
PLUGINS_DIR="${HOME}/.claude/plugins"

if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code not installed, nothing to clean up."
    exit 0
fi

# Plugin ids installed from the legacy marketplace, read from Claude Code's
# own registry
legacy_plugins() {
    local registry="${PLUGINS_DIR}/installed_plugins.json"
    [[ -f "${registry}" ]] || return 0
    python3 - "${registry}" "${MARKETPLACE}" <<'EOF'
import json
import sys

registry, marketplace = sys.argv[1], sys.argv[2]
with open(registry, encoding="utf-8") as handle:
    data = json.load(handle)
plugins = data.get("plugins", data) if isinstance(data, dict) else {}
for plugin_id in plugins:
    if plugin_id.endswith("@" + marketplace):
        print(plugin_id)
EOF
}

marketplace_registered() {
    local known="${PLUGINS_DIR}/known_marketplaces.json"
    [[ -f "${known}" ]] && python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    sys.exit(0 if sys.argv[2] in json.load(handle) else 1)
' "${known}" "${MARKETPLACE}"
}

changed=0

while IFS= read -r plugin_id; do
    [[ -n "${plugin_id}" ]] || continue
    echo "Uninstalling ${plugin_id}"
    claude plugin uninstall "${plugin_id}" >/dev/null || echo "Could not uninstall ${plugin_id}, continuing"
    changed=1
done < <(legacy_plugins)

if marketplace_registered; then
    echo "Removing the ${MARKETPLACE} marketplace"
    claude plugin marketplace remove "${MARKETPLACE}" >/dev/null || echo "Could not remove the ${MARKETPLACE} marketplace, continuing"
    changed=1
fi

for leftover in "${PLUGINS_DIR}/cache/${MARKETPLACE}" "${PLUGINS_DIR}/marketplaces/${MARKETPLACE}"; do
    if [[ -d "${leftover}" ]]; then
        echo "Removing ${leftover}"
        rm -rf "${leftover}"
        changed=1
    fi
done

if [[ "${changed}" -eq 0 ]]; then
    echo "No ${MARKETPLACE} leftovers found."
fi
