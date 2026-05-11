# vim: set ft=make :

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, instructions, and generates config.toml with safety exclusions.
# Pass "force" to overwrite existing exclude_commands config.
[group('ai-coding-agents')]
sf-rtk-setup $force="":
    {{sparkdock_path}}/sjust/scripts/rtk/setup.sh {{force}}

