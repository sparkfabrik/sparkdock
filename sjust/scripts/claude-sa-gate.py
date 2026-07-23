#!/usr/bin/env python3
"""claude-sa-gate — keep agent GCP commands on the coding-agent service account.

This script has two roles, selected by the first argument:

  --hook              Act as a Claude Code PreToolUse hook. Reads the hook
                      payload as JSON on stdin and decides allow/deny.
  enable|disable|info Patch the user's ~/.claude/settings.json to register or
                      remove the PreToolUse hook entry (matcher "Bash"), or
                      report current status.

Why a gate: a long-running agent should authenticate as the user's dedicated
coding-agent service account, not ride the user's personal Google session
(which Google's 16-hour Cloud session rollout expires). The credential helper
`fs-cli-agent-exec` launches the agent with the SA key materialized and
`GOOGLE_APPLICATION_CREDENTIALS` exported. This gate detects GCP commands run
without that agent identity and, additionally, blocks an agent from minting
human credentials with `gcloud auth login`.

Phases, selected by the SF_AGENT_SA_GUARD environment variable (normally set
org-wide in the managed Claude Code settings):

  unset / anything else   Gate is inert (off). Nothing is checked.
  warn                    A GCP command without agent credentials is allowed
                          but a remediation message is printed.
  enforce                 The same command is blocked (exit 2).

The gate also stays inert unless FSCLI_AGENT_SA_PROJECT names the agent SA
project (also org-supplied); no project name is hard-coded in this script.

In both the warn and enforce phases, `gcloud auth login` and
`gcloud auth application-default login` are always blocked: an agent must never
create human credentials.

Escape hatch: set SPARKDOCK_SA_GATE=0 (or off/false/no) to disable the gate at
runtime regardless of phase. Disable persistently with
`sjust claude-sa-gate-disable`.

The runtime hook is self-contained (it reads stdin and its own environment).
The installer reuses ``sjust/scripts/lib/claude_settings.py`` for the atomic,
backed-up settings.json read/write and marker-based hook register/unregister.
"""

import json
import os
import re
import sys
from pathlib import Path

# The agent SA project, supplied by the organization (normally through the
# managed Claude Code settings, alongside SF_AGENT_SA_GUARD) and shared with
# the fs-cli credential helper via the same variable. No project name is baked
# in: when it is unset the gate stays inert, since it cannot tell which key
# counts as the agent identity.
SA_PROJECT = os.environ.get("FSCLI_AGENT_SA_PROJECT", "").strip()
SA_EMAIL_SUFFIX = f"@{SA_PROJECT}.iam.gserviceaccount.com" if SA_PROJECT else ""

# Match a GCP CLI only in command position: start of string or just after a
# shell separator (; | & newline, or an opening paren), optionally preceded by
# env-var assignments (FOO=bar gcloud ...). The name must be followed by
# whitespace or end-of-string, so a bare command is caught while a mention of
# the word inside an argument is not.
_GCP_RE = re.compile(
    r"(?:^|[;&|\n(]\s*)(?:\w+=\S*\s+)*(gcloud|terraform|bq|gsutil)(?:\s|$)"
)

# `gcloud auth login` and `gcloud auth application-default login`, allowing
# flags in between (e.g. `gcloud auth login --no-launch-browser`).
_AUTH_LOGIN_RE = re.compile(
    r"\bgcloud\s+auth\s+(?:application-default\s+)?login\b"
)

# Stable identifier embedded in the registered command so the installer can find
# and remove exactly our entry without disturbing other hooks.
SCRIPT_PATH = str(Path(__file__).resolve())
HOOK_COMMAND = f'python3 "{SCRIPT_PATH}" --hook'
EVENT = "PreToolUse"
MATCHERS = ("Bash",)

_WARN_MSG = (
    "This GCP command is running with personal credentials, not the "
    "coding-agent service account.\n"
    "Launch the agent through `fs-cli-agent-exec` so it authenticates as your "
    "agent SA (a stable identity that survives your Google session expiry). "
    "See the coding-agent credentials docs. Run `fs-cli-agent-init` once to "
    "provision the key.\n"
)

_AUTH_MSG = (
    "An agent must not create human credentials.\n"
    "`gcloud auth login` and `gcloud auth application-default login` are "
    "blocked in agent sessions. Provision the coding-agent service account "
    "key with `fs-cli-agent-init` and run commands via `fs-cli-agent-exec`.\n"
)


def _settings_lib():
    """Lazily import the shared settings helper (installer only)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import claude_settings

    return claude_settings


# --------------------------------------------------------------------------- #
# Runtime hook
# --------------------------------------------------------------------------- #


def _phase() -> str:
    """Active gate phase: 'warn', 'enforce', or '' (off)."""
    value = os.environ.get("SF_AGENT_SA_GUARD", "").strip().lower()
    return value if value in {"warn", "enforce"} else ""


def _gate_disabled() -> bool:
    return os.environ.get("SPARKDOCK_SA_GATE", "").strip().lower() in {
        "0",
        "off",
        "false",
        "no",
    }


def _agent_credentials_active() -> bool:
    """True when GOOGLE_APPLICATION_CREDENTIALS points at an agent SA key."""
    path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not path:
        return False
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False
    email = data.get("client_email", "") if isinstance(data, dict) else ""
    return isinstance(email, str) and email.endswith(SA_EMAIL_SUFFIX)


def run_hook() -> int:
    # Allow on any malformed payload: a gate must never break the tool flow on
    # an unexpected input shape.
    try:
        payload = json.load(sys.stdin)
    except (OSError, json.JSONDecodeError):
        return 0
    if not isinstance(payload, dict):
        return 0

    phase = _phase()
    # Inert unless the org has both activated a phase and named the SA project.
    if not phase or not SA_PROJECT or _gate_disabled():
        return 0

    if payload.get("tool_name", "") != "Bash":
        return 0
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return 0

    # Minting human credentials is always blocked once the gate is active.
    if _AUTH_LOGIN_RE.search(command):
        sys.stderr.write(_AUTH_MSG)
        return 2

    if not _GCP_RE.search(command):
        return 0
    if _agent_credentials_active():
        return 0

    sys.stderr.write(_WARN_MSG)
    return 2 if phase == "enforce" else 0


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
        print(f"ℹ️  SA gate already enabled in {settings}")
        return 0

    backup = cs.backup()
    for matcher in MATCHERS:
        cs.register_hook(data, EVENT, matcher, HOOK_COMMAND, SCRIPT_PATH)
    cs.atomic_write(data)

    print(f"✅ SA gate enabled in {settings}")
    print(f"💡 Backup saved to {backup}")
    print("💡 Set SF_AGENT_SA_GUARD=warn (or enforce) to activate it.")
    print("💡 Disable anytime with: claude-sa-gate-disable")
    return 0


def cmd_disable() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        print(f"ℹ️  No {settings} — nothing to disable.")
        return 0
    data = cs.load()
    if not cs.registered_matchers(data, EVENT, SCRIPT_PATH):
        print(f"ℹ️  SA gate not registered in {settings}.")
        return 0

    backup = cs.backup()
    cs.unregister_hook(data, EVENT, SCRIPT_PATH)
    cs.atomic_write(data)
    print(f"✅ SA gate removed from {settings}")
    print(f"💡 Backup saved to {backup}")
    return 0


def cmd_info() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    print(f"Managed script: {SCRIPT_PATH}")
    if not settings.exists():
        print(f"Configured: no ({settings} does not exist)")
    else:
        matchers = cs.registered_matchers(cs.load(), EVENT, SCRIPT_PATH)
        if matchers >= set(MATCHERS):
            print(f"Configured: ✅ enabled (PreToolUse: Bash) in {settings}")
        else:
            print(f"Configured: no SA gate in {settings}")
    phase = _phase()
    print(f"Phase: {phase or 'off (SF_AGENT_SA_GUARD unset or not warn/enforce)'}")
    if _gate_disabled():
        print("Runtime: SPARKDOCK_SA_GATE is set to a disabling value (gate off).")
    return 0


def usage() -> int:
    sys.stderr.write("Usage: claude-sa-gate.py {--hook|enable|disable|info}\n")
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
