# vim: set ft=make :

# Provisioning installs the guards into a root-owned directory. Use that copy
# when present, else the one in this checkout, which this file lives in at
# <sparkdock_root>/sjust/recipes/shared/.
_managed_guards := "/opt/sparkfabrik/sf-managed-harness-config/guards"
_guards := if path_exists(_managed_guards) == "true" { _managed_guards } else { clean(source_directory() / "../../..") / "sjust/scripts" }
_claude_gh_gate_py := _guards / "claude-gh-gate.py"

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

_codex_writing_guard_py := _guards / "codex-writing-guard.py"

# Install both writing guards; Codex requires review in /hooks.
[group('ai-harness')]
writing-guard-enable: claude-gh-gate-enable codex-writing-guard-enable

# Remove both guards' registrations, preserving unrelated hooks.
[group('ai-harness')]
writing-guard-disable: claude-gh-gate-disable codex-writing-guard-disable

# Inspect both guards.
[group('ai-harness')]
writing-guard-info: claude-gh-gate-info codex-writing-guard-info

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
