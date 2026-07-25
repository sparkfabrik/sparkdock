# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/11-claude-sa-gate.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_sa_gate_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-sa-gate.py"

# Enable the coding-agent SA gate in ~/.claude/settings.json (idempotent). Activate it with SF_AGENT_SA_GUARD=warn|enforce.
[group('claude')]
claude-sa-gate-enable:
    @python3 "{{_claude_sa_gate_py}}" enable

# Disable the coding-agent SA gate (removes only its PreToolUse entry).
[group('claude')]
claude-sa-gate-disable:
    @python3 "{{_claude_sa_gate_py}}" disable

# Show whether the coding-agent SA gate is registered, its phase, and the managed script path.
[group('claude')]
claude-sa-gate-info:
    @python3 "{{_claude_sa_gate_py}}" info
