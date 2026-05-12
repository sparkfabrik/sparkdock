# vim: set ft=make :

# Setup RTK (Rust Token Killer) for Claude Code, GitHub Copilot, and OpenCode.
# Installs hooks, instructions, and rewrites Sparkdock-managed exclude_commands.
[group('ai-coding-agents')]
sf-rtk-setup:
    {{sparkdock_path}}/sjust/scripts/rtk/setup.sh
