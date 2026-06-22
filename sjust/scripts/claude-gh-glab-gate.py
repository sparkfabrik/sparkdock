#!/usr/bin/env python3
"""claude-gh-glab-gate — block raw gh/glab commands until the matching skill loads.

This script has two roles, selected by the first argument:

  --hook              Act as a Claude Code PreToolUse hook. Reads the hook
                      payload as JSON on stdin and decides allow/deny.
  enable|disable|info Patch the user's ~/.claude/settings.json to register or
                      remove the two PreToolUse hook entries (matcher "Skill"
                      and matcher "Bash"), or report current status.

Why a gate: the gh/glab skills carry auth handling, structured output, and the
SparkFabrik conventions for issues/MRs/PRs. Running gh/glab raw bypasses them.
A skill's description cannot force the agent to load it, but a hook can.

How the gate works (a "true gate", per session):
  - When the gh or glab skill is loaded via the Skill tool, the Skill event
    creates a per-session sentinel file.
  - A gh/glab Bash command is blocked (exit 2) only while that sentinel is
    absent. Once the skill has been loaded this session, every later gh/glab
    call is allowed. The hook still runs on every call; it just stops blocking.
  - The sentinel is keyed by session_id under the temp dir, so a new session
    starts gated again and nothing needs cleanup.

Escape hatch: set SPARKDOCK_GHGLAB_GATE=0 (or off/false) to disable the gate at
runtime, e.g. for headless automation. Disable persistently with
`sjust claude-gh-glab-gate-disable`.

The runtime hook is self-contained (it only reads stdin and touches a sentinel).
The installer reuses ``sjust/scripts/lib/claude_settings.py`` for the atomic,
backed-up settings.json read/write and marker-based hook register/unregister, so
future gates can share the same plumbing.
"""

import json
import os
import re
import sys
from pathlib import Path

GATED_SKILLS = {"gh", "glab"}

# Match a gh/glab invocation anywhere in the command string: at the start, or
# after whitespace, a separator (; & |), an opening paren, or an env-var
# assignment (GITLAB_HOST=... glab ...). Requires trailing whitespace so
# "github" / "glab-foo" do not match. Also catches RTK-wrapped "rtk-run glab ".
_GH_GLAB_RE = re.compile(r"(?:^|[\s;&|(=])(?:gh|glab)\s")

# Stable identifier embedded in the registered command so the installer can find
# and remove exactly our entries without disturbing other hooks (RTK, caveman).
SCRIPT_PATH = str(Path(__file__).resolve())
HOOK_COMMAND = f'python3 "{SCRIPT_PATH}" --hook'
EVENT = "PreToolUse"
MATCHERS = ("Skill", "Bash")


def _settings_lib():
    """Lazily import the shared settings helper (installer only)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import claude_settings

    return claude_settings


# --------------------------------------------------------------------------- #
# Runtime hook
# --------------------------------------------------------------------------- #


def _sentinel_path(session_id: str) -> Path:
    tmp = Path(os.environ.get("TMPDIR", "/tmp"))
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "nosession")
    return tmp / f"sparkdock-ghglab-gate-{safe}"


def _gate_disabled() -> bool:
    return os.environ.get("SPARKDOCK_GHGLAB_GATE", "").strip().lower() in {
        "0",
        "off",
        "false",
        "no",
    }


def run_hook() -> int:
    # Allow on any malformed payload: a gate must never break the tool flow on
    # an unexpected input shape.
    try:
        payload = json.load(sys.stdin)
    except (OSError, json.JSONDecodeError):
        return 0
    if not isinstance(payload, dict):
        return 0

    if _gate_disabled():
        return 0

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    sentinel = _sentinel_path(payload.get("session_id", ""))

    if tool_name == "Skill":
        # The exact field for the skill name is not documented; read both.
        name = (tool_input.get("skill") or tool_input.get("name") or "").strip()
        if name in GATED_SKILLS:
            try:
                sentinel.touch()
            except OSError:
                pass  # if we cannot record it, fail open on the next Bash call
        return 0

    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if not isinstance(command, str) or not _GH_GLAB_RE.search(command):
            return 0
        if sentinel.exists():
            return 0
        sys.stderr.write(
            "Load the GitLab/GitHub CLI skill before running this command.\n"
            "This command uses `gh` or `glab`, but the matching skill is not "
            "loaded yet in this session. Invoke the Skill tool first:\n"
            "  - `glab` for any GitLab work (merge requests, issues, CI, glab)\n"
            "  - `gh` for any GitHub work (pull requests, issues, Actions, gh)\n"
            "The skill carries auth handling, structured output, and SparkFabrik "
            "conventions. After loading it, re-run this command.\n"
        )
        return 2

    return 0


# --------------------------------------------------------------------------- #
# Installer (settings.json patching, via the shared claude_settings lib)
# --------------------------------------------------------------------------- #


def cmd_enable() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text("{}\n")

    data = cs.load()
    if cs.registered_matchers(data, EVENT, SCRIPT_PATH) >= set(MATCHERS):
        print(f"ℹ️  gh/glab gate already enabled in {settings}")
        return 0

    backup = cs.backup()
    for matcher in MATCHERS:
        cs.register_hook(data, EVENT, matcher, HOOK_COMMAND, SCRIPT_PATH)
    cs.atomic_write(data)

    print(f"✅ gh/glab gate enabled in {settings}")
    print(f"💡 Backup saved to {backup}")
    print("💡 Start a new Claude Code session for it to take effect.")
    print("💡 Disable anytime with: claude-gh-glab-gate-disable")
    return 0


def cmd_disable() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        print(f"ℹ️  No {settings} — nothing to disable.")
        return 0
    data = cs.load()
    if not cs.registered_matchers(data, EVENT, SCRIPT_PATH):
        print(f"ℹ️  gh/glab gate not registered in {settings}.")
        return 0

    backup = cs.backup()
    cs.unregister_hook(data, EVENT, SCRIPT_PATH)
    cs.atomic_write(data)
    print(f"✅ gh/glab gate removed from {settings}")
    print(f"💡 Backup saved to {backup}")
    return 0


def cmd_info() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    print(f"Managed script: {SCRIPT_PATH}")
    if not settings.exists():
        print(f"Configured: no ({settings} does not exist)")
        return 0
    matchers = cs.registered_matchers(cs.load(), EVENT, SCRIPT_PATH)
    if matchers >= set(MATCHERS):
        print(f"Configured: ✅ enabled (PreToolUse: Skill + Bash) in {settings}")
    elif matchers:
        print(f"Configured: ⚠️  partial (only {sorted(matchers)}) in {settings}")
    else:
        print(f"Configured: no gh/glab gate in {settings}")
    if _gate_disabled():
        print("Runtime: SPARKDOCK_GHGLAB_GATE is set to a disabling value (gate off).")
    return 0


def usage() -> int:
    sys.stderr.write("Usage: claude-gh-glab-gate.py {--hook|enable|disable|info}\n")
    return 2


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--hook":
        return run_hook()
    if arg == "enable":
        return cmd_enable()
    if arg == "disable":
        return cmd_disable()
    if arg == "info":
        return cmd_info()
    return usage()


if __name__ == "__main__":
    sys.exit(main())
