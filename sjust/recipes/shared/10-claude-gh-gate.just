# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/10-claude-gh-gate.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_gh_gate_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-gh-gate.py"

# Enable the Claude platform and writing skill gate (idempotent; missing skills are skipped).
[group('claude')]
claude-gh-gate-enable:
    @python3 "{{_claude_gh_gate_py}}" enable

# Disable the skill gate (removes only its managed hook entries).
[group('claude')]
claude-gh-gate-disable:
    @python3 "{{_claude_gh_gate_py}}" disable

# Show skill gate registration, runtime bypasses and the managed script path.
[group('claude')]
claude-gh-gate-info:
    @python3 "{{_claude_gh_gate_py}}" info
