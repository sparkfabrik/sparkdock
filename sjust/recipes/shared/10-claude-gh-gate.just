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

_agent_writing_guard_py := clean(source_directory() / "../../..") / "sjust/scripts/agent-writing-guard.py"
_codex_writing_guard_py := clean(source_directory() / "../../..") / "sjust/scripts/codex-writing-guard.py"

# Install both writing guards; Codex requires review in /hooks.
[group('ai-harness')]
writing-guard-enable:
    @python3 "{{_agent_writing_guard_py}}" enable

# Remove both guards' registrations, preserving unrelated hooks.
[group('ai-harness')]
writing-guard-disable:
    @python3 "{{_agent_writing_guard_py}}" disable

# Inspect both guards.
[group('ai-harness')]
writing-guard-info:
    @python3 "{{_agent_writing_guard_py}}" info

# Install only the Codex guard; review it with /hooks.
[group('codex')]
codex-writing-guard-enable:
    @python3 "{{_codex_writing_guard_py}}" enable

# Remove only the Codex guard.
[group('codex')]
codex-writing-guard-disable:
    @python3 "{{_codex_writing_guard_py}}" disable

# Show Codex registration and bypasses.
[group('codex')]
codex-writing-guard-info:
    @python3 "{{_codex_writing_guard_py}}" info
