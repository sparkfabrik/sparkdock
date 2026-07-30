# vim: set ft=make :

# Sync AI coding harness skills and profiles from upstream (fast, no sudo).
# Pass "force" or "--force" to overwrite local modifications.
[group('ai-coding-harness')]
sf-harness-sync $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        {{sparkdock_path}}/bin/sparkdock-agents-sync --force
    else
        {{sparkdock_path}}/bin/sparkdock-agents-sync
    fi

# List, enable, or disable globally managed optional skill categories.
# Examples: sf-harness-category list
#           sf-harness-category enable angular
#           sf-harness-category disable angular --force
[group('ai-coding-harness')]
[no-exit-message]
sf-harness-category $action="list" $category="" $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(category "${action}")
    if [[ "${action}" != "list" ]]; then
        [[ -n "${category}" ]] || { echo "ERROR: category name is required for ${action}."; exit 2; }
        args+=("${category}")
    fi
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        args+=(--force)
    fi
    {{sparkdock_path}}/bin/sparkdock-agents-sync "${args[@]}"

# Upgrade the full AI coding harness: brew formulae, skills, agent profiles,
# RTK hooks, caveman, and the OpenSpec CLI + global skills. Runs via Ansible (no sudo required).
# Pass "force" or "--force" to overwrite locally modified resources.
[group('ai-coding-harness')]
sf-harness-upgrade $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        export SPARKDOCK_AGENTS_FORCE=true
    fi
    ansible-playbook -i "{{sparkdock_path}}/ansible/inventory.ini" \
        "{{sparkdock_path}}/ansible/macos/macos/base.yml" \
        -e "dev_env_dir={{sparkdock_path}}" \
        -v --tags "ai-harness-sync"

# Show full AI coding harness status: token optimization tools, skills, and agent profiles.
[group('ai-coding-harness')]
sf-harness-status:
    @{{sparkdock_path}}/sjust/scripts/harness-status.sh

# Deprecated aliases (hidden from --list, silently route to new names)
[private]
alias sf-agents-sync := sf-harness-sync
[private]
alias sf-agents-upgrade := sf-harness-upgrade
[private]
alias sf-agents-status := sf-harness-status
[private]
alias sf-agents-refresh := sf-harness-sync

# Check Copilot model context/output limits against the current opencode.json config.
# Pass --update to automatically write the correct limits to opencode.json.
# Requires GitHub Copilot authentication (gh CLI or OpenCode).
# Refs: https://github.com/anomalyco/models.dev/issues/1136
#       https://github.com/anomalyco/opencode/issues/16129
[group('ai-coding-harness')]
sf-copilot-model-limits *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    node "{{sparkdock_path}}/sjust/scripts/copilot-models.mjs" {{args}}

# List available Copilot model IDs (one per line). Useful for scripting with machine names.
# Requires GitHub Copilot authentication (gh CLI or OpenCode).
[group('ai-coding-harness')]
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
[group('ai-coding-harness')]
sf-copilot-premium-usage *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null 2>&1; then
        echo "ERROR: Node.js is required but not found."
        exit 1
    fi
    node "{{sparkdock_path}}/sjust/scripts/copilot-usage.mjs" {{args}}

# Install/update caveman output compression for Claude Code, OpenCode, and Copilot.
# Clones (or updates) the caveman repo, writes default config, then installs
# hooks/plugins/skills per agent. Safe to re-run — always deploys latest.
[group('ai-coding-harness')]
sf-caveman-install:
    @{{sparkdock_path}}/sjust/scripts/caveman/setup.sh install

# Remove caveman from all AI coding tools.
[group('ai-coding-harness')]
sf-caveman-uninstall:
    @{{sparkdock_path}}/sjust/scripts/caveman/setup.sh uninstall
