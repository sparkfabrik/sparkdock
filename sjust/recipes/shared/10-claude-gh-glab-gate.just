# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/10-claude-gh-glab-gate.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_gh_glab_gate_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-gh-glab-gate.py"

# Enable the gh/glab skill gate in ~/.claude/settings.json (idempotent). Blocks gh/glab commands until the matching skill is loaded.
[group('claude')]
claude-gh-glab-gate-enable:
    @python3 "{{_claude_gh_glab_gate_py}}" enable

# Disable the gh/glab skill gate (removes only its PreToolUse entries).
[group('claude')]
claude-gh-glab-gate-disable:
    @python3 "{{_claude_gh_glab_gate_py}}" disable

# Show whether the gh/glab skill gate is registered and the managed script path.
[group('claude')]
claude-gh-glab-gate-info:
    @python3 "{{_claude_gh_glab_gate_py}}" info
