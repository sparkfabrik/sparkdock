#!/usr/bin/env python3
"""Require available platform/writing skills before recognized gh/glab commands.

The historical filename and management commands remain the provisioning entry
point. This is a fail-open workflow aid, not a shell security boundary. See
../../docs/claude-writing-guard.md for scope, bypasses and lifecycle behavior.
"""

import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import sys
from pathlib import Path

GATED_SKILLS = {"gh", "glab", "sf-writing-style"}
SCRIPT_PATH = str(Path(__file__).resolve())
HOOK_COMMAND = f"python3 {shlex.quote(SCRIPT_PATH)} --hook"
HOOKS = {
    "PreToolUse": "Bash",
    "PostToolUse": "Skill",
    "PostToolUseFailure": "Skill",
    "SessionStart": "startup|clear|compact",
}
OFF_VALUES = {"0", "off", "false", "no"}


def _settings_lib():
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import claude_settings

    return claude_settings


def _disabled(variable):
    return os.environ.get(variable, "").strip().lower() in OFF_VALUES


def _commands(command, depth=0):
    """Recognize simple shell commands and known wrappers without executing any."""
    if depth > 3:
        return
    # Preserve quotes until command separators have been identified. shlex alone
    # either loses that distinction or splits quoted assignment values.
    token_pattern = re.compile(
        r"""\#[^\n]*|(?:[^\s;&|()<>'"\\]|\\.|'[^']*'|"(?:\\.|[^"\\])*")+|[;&|()<>\n]+|[ \t\r]+"""
    )
    tokens = []
    offset = 0
    while offset < len(command):
        match = token_pattern.match(command, offset)
        if match is None:
            raise ValueError("Unsupported shell syntax")
        token = match.group()
        offset = match.end()
        if not token.startswith("#") and token.strip(" \t\r") != "":
            tokens.append(token)
    # A heredoc's body is data, not a command. Leave complex shell to the caller.
    if any(t.startswith("<<") for t in tokens):
        return
    segment = []
    for token in [*tokens, ";"]:
        if token and all(c in ";&|()\n" for c in token):
            if segment:
                words = [shlex.split(t)[0] if t else "" for t in segment]
                while words and (
                    re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])
                    or words[0] in {"env", "command", "--"}
                ):
                    words.pop(0)
                if words:
                    name = Path(words[0]).name
                    if name in {"rtk", "rtk-run"}:
                        rest = words[1:]
                        if rest and rest[0] == "proxy":
                            rest = rest[1:]
                        if len(rest) == 1:
                            yield from _commands(rest[0], depth + 1)
                        elif rest:
                            yield rest
                    else:
                        yield words
                segment = []
        else:
            segment.append(token)


def _writes_prose(args):
    # Skip supported global options before the subcommand.
    args = list(args)
    while args and args[0].startswith("-"):
        flag = args.pop(0)
        if flag in {"-R", "--repo", "--hostname", "--host"} and args:
            args.pop(0)
    if not args:
        return False
    if args[0] == "api":
        # Explicit API writes can carry prose, including GraphQL mutations.
        method = next(
            (
                args[i + 1].upper()
                for i, a in enumerate(args[:-1])
                if a in {"-X", "--method"}
            ),
            "",
        )
        if any(a.upper() in {"--METHOD=GET", "--METHOD=HEAD"} for a in args):
            return False
        if method in {"GET", "HEAD"}:
            return False
        return bool(method) or any(
            a in {"-f", "-F", "--field", "--raw-field", "--input"}
            or a.startswith(
                ("--method=", "--field=", "--raw-field=", "--input=", "-f", "-F", "-X")
            )
            for a in args[1:]
        )
    return (
        len(args) > 1
        and args[0] in {"issue", "pr", "mr", "release", "discussion", "gist", "snippet"}
        and args[1] in {"create", "edit", "update", "comment", "note", "review"}
    )


def _skill_available(name, cwd):
    # Use Claude-visible locations, never the unlinked ~/.agents/skills copy.
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
    roots = [config, *(p / ".claude" for p in (cwd, *cwd.parents))]
    for root in roots:
        for filename in ("settings.json", "settings.local.json"):
            path = root / filename
            if path.is_file():
                settings = json.loads(path.read_text())
                if isinstance(settings, dict) and settings.get(
                    "skillOverrides", {}
                ).get(name) in {"off", "user-invocable-only"}:
                    return False
    for root in roots:
        path = root / "skills" / name / "SKILL.md"
        if path.is_file():
            try:
                content = path.read_text()
            except (OSError, UnicodeError):
                return False
            frontmatter = content.split("---", 2)
            return bool(content.strip()) and not (
                len(frontmatter) == 3
                and re.search(
                    r"(?m)^disable-model-invocation:\s*true\s*$", frontmatter[1]
                )
            )
    return False


def _process(payload, state):
    event = payload.get("hook_event_name")
    if event == "SessionStart":
        if payload.get("source") in {"startup", "clear", "compact"}:
            for key in ("loaded", "requested", "failed"):
                state[key] = []
        return 0, []
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0, []
    if payload.get("tool_name") == "Skill":
        name = tool_input.get("skill") or tool_input.get("name")
        if not isinstance(name, str) or name not in GATED_SKILLS:
            return 0, []
        if event == "PostToolUse":
            if name not in state["loaded"]:
                state["loaded"].append(name)
            if name in state["failed"]:
                state["failed"].remove(name)
        elif event == "PostToolUseFailure":
            if name not in state["failed"]:
                state["failed"].append(name)
        return 0, []
    if event != "PreToolUse" or payload.get("tool_name") != "Bash":
        return 0, []
    command = tool_input.get("command")
    cwd = payload.get("cwd")
    if (
        not isinstance(command, str)
        or not isinstance(cwd, str)
        or not Path(cwd).is_absolute()
    ):
        return 0, []
    required = set()
    for words in _commands(command):
        cli = Path(words[0]).name
        if cli not in {"gh", "glab"} or shutil.which(words[0]) is None:
            continue
        required.add(cli)
        if not _disabled("SPARKDOCK_WRITING_GUARD") and _writes_prose(words[1:]):
            required.add("sf-writing-style")
    needed, notices = [], []
    for name in sorted(required - set(state["loaded"])):
        if (
            name in state["failed"]
            or name in state["requested"]
            or not _skill_available(name, Path(cwd))
        ):
            if name not in state["warned"]:
                notices.append(
                    f"Writing guard: skipping {name}; unavailable or load not confirmed."
                )
                state["warned"].append(name)
            continue
        needed.append(name)
    if needed:
        state["requested"].extend(needed)
        notices.append(
            "Load these skills with the Skill tool: "
            + ", ".join(needed)
            + ". Apply their guidance to any prepared text, then retry this command."
        )
        return 2, notices
    return 0, notices


def run_hook():
    if _disabled("SPARKDOCK_GH_GATE"):
        return 0
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        session_id = payload.get("session_id")
        if not isinstance(session_id, str) or not session_id:
            return 0
        agent_id = payload.get("agent_id", "")
        if not isinstance(agent_id, str):
            return 0
        if agent_id:
            session_id = json.dumps([session_id, agent_id])
        # A private, locked file avoids cross-session collisions and lost updates
        # from concurrent hooks. Never follow a state-file symlink.
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        directory = cache / "sparkdock" / "claude-skill-gate"
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = directory / (hashlib.sha256(session_id.encode()).hexdigest() + ".json")
        fd = os.open(
            path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600
        )
        with os.fdopen(fd, "r+") as stream:
            info = os.fstat(stream.fileno())
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or info.st_nlink != 1
            ):
                return 0
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            raw = stream.read()
            state = (
                json.loads(raw)
                if raw
                else {k: [] for k in ("loaded", "requested", "failed", "warned")}
            )
            if not isinstance(state, dict) or any(
                not isinstance(state.get(k), list)
                or any(not isinstance(v, str) for v in state[k])
                for k in ("loaded", "requested", "failed", "warned")
            ):
                return 0
            result, notices = _process(payload, state)
            stream.seek(0)
            json.dump(state, stream)
            stream.truncate()
            stream.flush()
        # Emit only after state has been saved: storage failure must fail open.
        if result == 2:
            sys.stderr.write("\n".join(notices) + "\n")
        elif notices:
            print(json.dumps({"systemMessage": "\n".join(notices)}))
        return result
    except (OSError, ValueError, TypeError, AttributeError):
        return 0


def _configured(data, cs):
    return all(
        cs.registered_matchers(data, event, SCRIPT_PATH) == {matcher}
        for event, matcher in HOOKS.items()
    )


def cmd_enable():
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text("{}\n")
    data = cs.load()
    if _configured(data, cs):
        print(f"Skill gate already enabled in {settings}")
        return 0
    backup = cs.backup()
    for event, matcher in HOOKS.items():
        cs.unregister_hook(data, event, SCRIPT_PATH)
        cs.register_hook(data, event, matcher, HOOK_COMMAND, SCRIPT_PATH)
    cs.atomic_write(data)
    print(f"Skill gate enabled in {settings}. Backup: {backup}")
    print("Start a new Claude Code session. Disable with: claude-gh-gate-disable")
    return 0


def cmd_disable():
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        print(f"No {settings}; nothing to disable.")
        return 0
    data = cs.load()
    if not any(cs.registered_matchers(data, event, SCRIPT_PATH) for event in HOOKS):
        print(f"Skill gate not registered in {settings}.")
        return 0
    backup = cs.backup()
    for event in HOOKS:
        cs.unregister_hook(data, event, SCRIPT_PATH)
    cs.atomic_write(data)
    print(f"Skill gate removed from {settings}. Backup: {backup}")
    return 0


def cmd_info():
    cs = _settings_lib()
    data = cs.load()
    print(f"Managed script: {SCRIPT_PATH}")
    configured = (
        "enabled"
        if _configured(data, cs)
        else "partial"
        if any(cs.registered_matchers(data, event, SCRIPT_PATH) for event in HOOKS)
        else "disabled"
    )
    print(f"Configured: {configured} in {cs.settings_path()}")
    print(
        "Requires gh/glab; authoring also requires sf-writing-style. Missing skills are skipped."
    )
    for variable in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
        print(f"{variable}: {'off' if _disabled(variable) else 'on'}")
    return 0


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    actions = {
        "--hook": run_hook,
        "enable": cmd_enable,
        "disable": cmd_disable,
        "info": cmd_info,
    }
    if arg in actions:
        return actions[arg]()
    sys.stderr.write("Usage: claude-gh-gate.py {--hook|enable|disable|info}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
