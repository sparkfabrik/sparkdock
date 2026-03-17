# vim: set ft=make :

# Refresh AI coding agent resources (skills + agent profiles) from upstream.
[group('ai-coding-agents')]
sf-agents-refresh $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${force}" == "force" ]]; then
        {{sparkdock_path}}/bin/sparkdock-agents-sync --force
    else
        {{sparkdock_path}}/bin/sparkdock-agents-sync
    fi

# Show status of AI coding agent resources (skills + agent profiles).
[group('ai-coding-agents')]
sf-agents-status:
    @{{sparkdock_path}}/bin/sparkdock-agents-status

# Check Copilot model context/output limits against the current opencode.json config.
# Pass --update to automatically write the correct limits to opencode.json.
# Warns if any values are outdated. Requires opencode to be authenticated with GitHub Copilot.
# Refs: https://github.com/anomalyco/models.dev/issues/1136
#       https://github.com/anomalyco/opencode/issues/16129
[group('ai-coding-agents')]
sf-copilot-model-limits *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    AUTH_FILE="${HOME}/.local/share/opencode/auth.json"
    if [[ ! -f "${AUTH_FILE}" ]]; then
        echo "ERROR: opencode auth not found at ${AUTH_FILE}"
        echo "Run opencode and authenticate with GitHub Copilot first."
        exit 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    node "{{sparkdock_path}}/config/macos/scripts/copilot-models.mjs" {{args}}
