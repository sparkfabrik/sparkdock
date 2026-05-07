# vim: set ft=make :

# Refresh AI coding agent resources (skills + agent profiles) from upstream.
# Pass "force" or "--force" to overwrite local modifications.
[group('ai-coding-agents')]
sf-agents-refresh $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
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
# When --update is used, sudo is required to write to the system-wide config path.
# Requires GitHub Copilot authentication (gh CLI or OpenCode).
# Refs: https://github.com/anomalyco/models.dev/issues/1136
#       https://github.com/anomalyco/opencode/issues/16129
[group('ai-coding-agents')]
sf-copilot-model-limits *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    if [[ " {{args}} " == *" --update "* ]]; then
        sudo node "{{sparkdock_path}}/sjust/scripts/copilot-models.mjs" {{args}}
    else
        node "{{sparkdock_path}}/sjust/scripts/copilot-models.mjs" {{args}}
    fi

# List available Copilot model IDs (one per line). Useful for scripting with machine names.
# Requires GitHub Copilot authentication (gh CLI or OpenCode).
[group('ai-coding-agents')]
sf-copilot-model-list:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    node "{{sparkdock_path}}/sjust/scripts/copilot-models.mjs" --list

# Show current personal GitHub Copilot premium request usage.
# Pass --json to output the raw API response for scripting.
# Requires GitHub Copilot authentication (gh CLI or OpenCode).
[group('ai-coding-agents')]
sf-copilot-premium-usage *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    node "{{sparkdock_path}}/sjust/scripts/copilot-usage.mjs" {{args}}
