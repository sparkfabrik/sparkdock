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
`fs-cli-agent-exec` launches the agent with the SA key materialized and both
`GOOGLE_APPLICATION_CREDENTIALS` and `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`
exported. This gate detects GCP commands run without that agent identity and,
additionally, blocks an agent from minting human credentials with
`gcloud auth login`.

Phases, selected by the SF_AGENT_SA_GUARD environment variable (normally set
org-wide in the managed Claude Code settings):

  unset / anything else   Gate is inert (off). Nothing is checked.
  warn                    The command is allowed and a remediation message is
                          surfaced (exit 1, a non-blocking error: on exit 0 the
                          harness discards hook stderr and nobody sees it).
  enforce                 The command is blocked (exit 2).

The gate also stays inert unless FSCLI_AGENT_SA_PROJECT names the agent SA
project (also org-supplied); no project name is hard-coded in this script.

In both the warn and enforce phases, `gcloud auth login` and
`gcloud auth application-default login` are always blocked: an agent must never
create human credentials.

What this gate does NOT do. It reads one shell command string, so it is a
guardrail against accidental drift, not a control against an agent that is
trying to get around it:

  * A GCP command reached indirectly is not seen: `bash deploy.sh`,
    `sh -c "gcloud ..."`, a Makefile or `just` recipe, or anything the model
    writes to a file and then runs. `just tf`, this organization's own
    documented Terraform path, is one of these.
  * The agent can remove the gate in-band (`sjust claude-sa-gate-disable`, or
    editing ~/.claude/settings.json), because nothing here protects it.
  * Both activation variables are read from this process's own environment,
    which the agent's Bash tool cannot change for a hook, but which an
    operator-provided fake key file could satisfy.

Closing the first two requires registering the hook through root-owned managed
settings and denying edits to the settings file; closing the third is out of
scope for a command-string gate.

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
import stat
import sys
from pathlib import Path

# The agent SA project, supplied by the organization (normally through the
# managed Claude Code settings, alongside SF_AGENT_SA_GUARD) and shared with
# the fs-cli credential helper via the same variable. No project name is baked
# in: when it is unset the gate stays inert, since it cannot tell which key
# counts as the agent identity.
SA_PROJECT = os.environ.get("FSCLI_AGENT_SA_PROJECT", "").strip()
SA_EMAIL_SUFFIX = f"@{SA_PROJECT}.iam.gserviceaccount.com" if SA_PROJECT else ""

GCP_CLIS = ("gcloud", "terraform", "tofu", "terragrunt", "bq", "gsutil")

# Words that may legitimately sit between a separator and the CLI without
# changing which command actually runs.
_PREFIX = (
    r"(?:(?:\w+=\S*|sudo|env|command|time|nohup|exec|then|do|else|elif|"
    r"\{|!|-)\s+)*"
)
# A command position is the start of the string or just after a shell separator
# (; | & newline, opening paren or brace), in both cases allowing leading
# whitespace. The CLI may be given by bare name or absolute/relative path.
_POSITION = r"(?:^\s*|[;&|\n({]\s*)"
_CLI = r"(?:[\w./~-]*/)?(" + "|".join(GCP_CLIS) + r")(?:\s|$)"

_GCP_RE = re.compile(_POSITION + _PREFIX + _CLI)

# `gcloud auth login` and `gcloud auth application-default login`, in command
# position only. Anchoring this the same way as _GCP_RE keeps the gate from
# blocking a command that merely NAMES it, such as grepping or documenting it.
_AUTH_LOGIN_RE = re.compile(
    _POSITION
    + _PREFIX
    + r"(?:[\w./~-]*/)?gcloud\s+auth\s+(?:application-default\s+)?login\b"
)

# Subcommands that touch no credentials. Blocking these in enforce mode would
# stop routine work (`terraform fmt -check` and `terraform validate` are common
# pre-commit steps) while protecting nothing.
_CREDENTIAL_FREE_RE = re.compile(
    r"(?:^\s*|[;&|\n({]\s*)" + _PREFIX + r"(?:[\w./~-]*/)?(?:"
    r"terraform\s+(?:fmt|validate|version|-v|-version|--version|-help|--help)"
    r"|(?:tofu|terragrunt)\s+(?:fmt|validate|version|--version)"
    r"|gcloud\s+(?:version|--version|components|topic|help|--help)"
    r"|gcloud\s+config\s+(?:list|get|get-value)"
    r"|bq\s+(?:version|--version|help)"
    r"|gsutil\s+(?:version|help)"
    r")"
)

# Quoted spans are removed before matching, so a CLI name merely mentioned
# inside a string (a commit message, an echo, a grep pattern) is not read as a
# command, and separators inside quotes do not create false command positions.
# This also removes the body of `sh -c "..."`, which was already invisible to a
# command-string gate.
_QUOTED_RE = re.compile(r"'[^']*'|\"[^\"]*\"")


def _strip_quoted(command: str) -> str:
    """Blank out quoted spans, preserving length-independent token boundaries."""
    return _QUOTED_RE.sub(" ", command)


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
    "If your own Google session has expired, re-authenticate in your own "
    "terminal outside the agent; it cannot be done from here.\n"
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


def _key_is_agent_sa(path: str) -> bool:
    """True when path is a regular JSON key file for an SA in the agent project."""
    if not path:
        return False
    try:
        # stat first: open() on a FIFO blocks until a writer appears, which
        # would freeze the agent on every matching Bash call, and a huge file
        # would be read in full on each one.
        st = os.stat(path)
        if not stat.S_ISREG(st.st_mode) or st.st_size > 1 << 20:
            return False
        with open(path, encoding="utf-8") as f:
            data = json.loads(f.read())
    except (OSError, ValueError):
        # ValueError covers both JSONDecodeError and the UnicodeDecodeError a
        # non-UTF-8 file raises. Letting that escape would exit non-zero, which
        # Claude Code treats as a non-blocking error, silently disabling the
        # credential check.
        return False
    email = data.get("client_email", "") if isinstance(data, dict) else ""
    return isinstance(email, str) and email.endswith(SA_EMAIL_SUFFIX)


def _agent_credentials_active() -> bool:
    """True when this process is set up to run GCP tooling as the agent SA.

    Both variables are required. GOOGLE_APPLICATION_CREDENTIALS is what the
    SDKs and the Terraform provider read, but gcloud, bq and gsutil ignore it
    for their own authentication and use CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE
    (or the gcloud credential store). Accepting the SDK variable alone would
    green-light a `gcloud` command that still runs as the human, which is the
    exact confusion this gate exists to prevent. `fs-cli-agent-exec` sets both.
    """
    return _key_is_agent_sa(
        os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    ) and _key_is_agent_sa(
        os.environ.get("CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE", "").strip()
    )


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

    # Match against the command with quoted spans blanked out, so a mention of
    # a CLI inside a string is not treated as an invocation.
    scan = _strip_quoted(command)

    # Minting human credentials is always blocked once the gate is active.
    if _AUTH_LOGIN_RE.search(scan):
        sys.stderr.write(_AUTH_MSG)
        return 2

    if not _GCP_RE.search(scan):
        return 0
    if _CREDENTIAL_FREE_RE.search(scan):
        return 0
    if _agent_credentials_active():
        return 0

    sys.stderr.write(_WARN_MSG)
    # 2 blocks and feeds stderr back to the agent. In warn mode we must NOT
    # return 0: on a zero exit the harness discards hook stderr, so the message
    # would reach nobody and the warn ramp would be silent. A non-zero,
    # non-2 status is a non-blocking error, which surfaces the message while
    # letting the command run.
    return 2 if phase == "enforce" else 1


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
    inert = []
    if not phase:
        inert.append("SF_AGENT_SA_GUARD unset or not warn/enforce")
    if not SA_PROJECT:
        inert.append("FSCLI_AGENT_SA_PROJECT unset")
    if _gate_disabled():
        inert.append("SPARKDOCK_SA_GATE set to a disabling value")
    if inert:
        print(f"Phase: {phase or 'off'} (INERT: {'; '.join(inert)})")
    else:
        print(f"Phase: {phase}")
    print(f"SA project: {SA_PROJECT or 'unset'}")
    print(
        "Credentials: agent SA detected"
        if _agent_credentials_active()
        else "Credentials: agent SA not detected in this environment"
    )
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
