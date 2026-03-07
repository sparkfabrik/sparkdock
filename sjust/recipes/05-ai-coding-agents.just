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

# --- Backward-compatible aliases ---

# (alias for sf-agents-refresh) Refresh agent resources from upstream.
[group('ai-coding-agents')]
sf-skills-refresh force="":
    @just --justfile "{{justfile()}}" sf-agents-refresh {{force}}

# (alias for sf-agents-status) Show status of agent resources.
[group('ai-coding-agents')]
sf-skills-status:
    @just --justfile "{{justfile()}}" sf-agents-status
