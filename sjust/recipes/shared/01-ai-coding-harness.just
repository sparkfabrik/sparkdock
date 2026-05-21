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

# Upgrade the full AI coding harness: brew formulae, skills, agent profiles,
# RTK hooks, and caveman. Runs via Ansible (no sudo required).
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
        -v --tags "ai-harness-sync"

# Show full AI coding harness status: token optimization tools, skills, and agent profiles.
[group('ai-coding-harness')]
sf-harness-status:
    @{{sparkdock_path}}/sjust/scripts/harness-status.sh

# Deprecated: use sf-harness-sync instead.
[group('ai-coding-harness')]
sf-agents-sync $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOTE: sf-agents-sync is deprecated, use sf-harness-sync instead." >&2
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        {{sparkdock_path}}/bin/sparkdock-agents-sync --force
    else
        {{sparkdock_path}}/bin/sparkdock-agents-sync
    fi

# Deprecated: use sf-harness-upgrade instead.
[group('ai-coding-harness')]
sf-agents-upgrade $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOTE: sf-agents-upgrade is deprecated, use sf-harness-upgrade instead." >&2
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        export SPARKDOCK_AGENTS_FORCE=true
    fi
    ansible-playbook -i "{{sparkdock_path}}/ansible/inventory.ini" \
        "{{sparkdock_path}}/ansible/macos/macos/base.yml" \
        -v --tags "ai-harness-sync"

# Deprecated: use sf-harness-status instead.
[group('ai-coding-harness')]
sf-agents-status:
    #!/usr/bin/env bash
    echo "NOTE: sf-agents-status is deprecated, use sf-harness-status instead." >&2
    {{sparkdock_path}}/sjust/scripts/harness-status.sh

# Deprecated: use sf-harness-sync instead.
[group('ai-coding-harness')]
sf-agents-refresh $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "NOTE: sf-agents-refresh is deprecated, use sf-harness-sync instead." >&2
    if [[ "${force}" == "force" || "${force}" == "--force" ]]; then
        {{sparkdock_path}}/bin/sparkdock-agents-sync --force
    else
        {{sparkdock_path}}/bin/sparkdock-agents-sync
    fi

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
