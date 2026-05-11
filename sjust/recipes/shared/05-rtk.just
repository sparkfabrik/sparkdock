# vim: set ft=make :

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, instructions, and generates config.toml with safety exclusions.
[group('ai-coding-agents')]
sf-rtk-setup:
    {{sparkdock_path}}/sjust/scripts/rtk/setup.sh

# Initialize RTK Copilot hooks for the current project.
# Run this from the root of a git repository.
[group('ai-coding-agents')]
sf-rtk-copilot:
    {{sparkdock_path}}/sjust/scripts/rtk/project-init.sh
