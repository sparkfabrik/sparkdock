# vim: set ft=make :

# Setup RTK (Rust Token Killer) for GitHub Copilot and OpenCode.
# Installs hooks and instructions with idempotent marker-based injection.
[group('ai-coding-agents')]
sf-rtk-setup:
    {{sparkdock_path}}/sjust/scripts/rtk/setup.sh
