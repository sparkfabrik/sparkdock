# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/10-claude-gh-gate.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_gh_gate_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-gh-gate.py"

# Enable the gh skill gate in ~/.claude/settings.json (idempotent). Blocks gh commands until the gh skill is loaded.
[group('claude')]
claude-gh-gate-enable:
    @python3 "{{_claude_gh_gate_py}}" enable

# Disable the gh skill gate (removes only its PreToolUse entries).
[group('claude')]
claude-gh-gate-disable:
    @python3 "{{_claude_gh_gate_py}}" disable

# Show whether the gh skill gate is registered and the managed script path.
[group('claude')]
claude-gh-gate-info:
    @python3 "{{_claude_gh_gate_py}}" info
