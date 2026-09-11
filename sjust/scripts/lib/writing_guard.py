"""Shared writing classification and private hook state for Claude and Codex."""

import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import sys
import time
from pathlib import Path

SKILLS = {"gh", "glab", "sf-writing-style"}
MATCHER = "Bash|mcp__.*"
REMINDER = "Apply sf-writing-style to the prepared text: lead with the change, use useful bullets, remove implementation history and repetition, and keep required actions. Review the actual outgoing body, then retry."


def disabled(variable):
    return os.environ.get(variable, "").strip().lower() in {"0", "off", "false", "no"}


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
        and (
            args[1] in {"create", "edit", "update", "comment", "note", "review"}
            or (
                args[1] == "close"
                and any(
                    a in {"--comment", "-c"} or a.startswith("--comment=")
                    for a in args[2:]
                )
            )
        )
    )


def requirements(payload):
    required = set()
    tool = payload.get("tool_name", "")
    args = payload.get("tool_input", {})
    if tool == "Bash":
        command = args.get("command")
        if not isinstance(command, str):
            return required
        for words in _commands(command):
            cli = Path(words[0]).name
            if cli in {"gh", "glab"} and shutil.which(words[0]) is not None:
                required.add(cli)
                if _writes_prose(words[1:]):
                    required.add("sf-writing-style")
    elif isinstance(tool, str) and tool.startswith("mcp__"):
        parts = tool.split("__", 2)
        if len(parts) != 3:
            return required
        server, operation = parts[1].lower(), parts[2].lower()
        if ("slack" in server or operation.startswith("slack_")) and operation in {
            "slack_send_message",
            "slack_update_message",
            "slack_schedule_message",
            "slack_post_message",
            "slack_reply_to_thread",
            "send_message",
            "update_message",
            "post_message",
            "reply_to_thread",
            "schedule_message",
        }:
            required.add("sf-writing-style")
        platform_operation = operation
        for platform in ("github", "gitlab"):
            if operation.startswith(platform + "_"):
                server = platform
                platform_operation = operation[len(platform) + 1 :]
                break
        if any(platform in server for platform in ("github", "gitlab")) and (
            platform_operation
            in {
                "create_issue",
                "update_issue",
                "add_issue_comment",
                "add_comment_to_issue",
                "update_issue_comment",
                "create_pull_request",
                "update_pull_request",
                "create_merge_request",
                "update_merge_request",
                "create_note",
                "create_release",
                "update_release",
                "add_review_to_pr",
                "reply_to_review_comment",
                "update_review_comment",
            }
            or (
                platform_operation == "issue_write"
                and args.get("method") in {"create", "update"}
            )
        ):
            required.add("sf-writing-style")
    if disabled("SPARKDOCK_WRITING_GUARD"):
        required.discard("sf-writing-style")
    return required


def lifecycle(payload, state):
    if payload.get("hook_event_name") == "UserPromptSubmit":
        state["reviewed"] = []
        return True
    if payload.get("hook_event_name") == "SessionStart":
        if payload.get("source") in {"startup", "clear", "compact"}:
            for key in ("loaded", "requested", "failed", "reviewed"):
                state[key] = []
        return True
    return False


def reminder(required, state):
    if (
        "sf-writing-style" in required
        and "sf-writing-style" in state["loaded"]
        and not state["reviewed"]
    ):
        state["reviewed"] = ["sf-writing-style"]
        return 2, [REMINDER]
    return 0, []


def run_hook(process, engine):
    if disabled("SPARKDOCK_GH_GATE"):
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
        cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
        directory = cache / "sparkdock" / f"{engine}-skill-gate"
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
            deadline = time.monotonic() + 1.0
            while True:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        return 0
                    time.sleep(0.05)
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
            state.setdefault("reviewed", [])
            result, notices = process(payload, state)
            if payload.get("hook_event_name") == "PreToolUse" and requirements(payload):
                state["last_check"] = {
                    "tool": payload.get("tool_name"),
                    "decision": "retry" if result == 2 else "continue",
                    "required": sorted(requirements(payload)),
                    "notices": notices,
                    "loaded": state["loaded"],
                    "skipped": state["warned"],
                }
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
    except (OSError, ValueError, TypeError, AttributeError, KeyError):
        return 0
