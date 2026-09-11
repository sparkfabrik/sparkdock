#!/usr/bin/env python3
"""Codex adapter for the shared platform and writing skill guard."""

import json
import os
import re
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import claude_settings as settings
import writing_guard as guard

SCRIPT_PATH = str(Path(__file__).resolve())
HOOK_COMMAND = f"python3 {shlex.quote(SCRIPT_PATH)} --hook"
HOOKS = {
    "PreToolUse": guard.MATCHER,
    "PostToolUse": "Bash",
    "SessionStart": "startup|clear|compact",
    "UserPromptSubmit": "*",
}


def config_dir():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))


def skill_path(name, cwd):
    try:
        import tomllib
    except ImportError:
        # Cannot safely check disabled skills on older Python installations.
        return None
    # Match Sparkdock's per-tool links. Do not use an unlinked managed skill.
    roots = [config_dir(), *(p / ".codex" for p in (cwd, *cwd.parents))]
    for root in roots:
        config = root / "config.toml"
        if config.is_file():
            data = tomllib.loads(config.read_text())
            for entry in data.get("skills", {}).get("config", []):
                if entry.get("enabled") is False:
                    disabled_path = Path(entry["path"]).expanduser()
                    if disabled_path.name == "SKILL.md":
                        disabled_path = disabled_path.parent
                    if disabled_path.name == name:
                        return None
    for root in roots:
        path = root / "skills" / name / "SKILL.md"
        if path.is_file():
            content = path.read_text()
            if content.strip() and not any(
                re.search(r"(?m)^disable-model-invocation:\s*true\s*$", front)
                for front in content.split("---", 2)[1:2]
            ):
                return path
    return None


def response_text(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from response_text(item)
    elif isinstance(value, list):
        for item in value:
            yield from response_text(item)


def process(payload, state):
    if guard.lifecycle(payload, state):
        return 0, []
    cwd = payload.get("cwd")
    args = payload.get("tool_input")
    if (
        not isinstance(cwd, str)
        or not Path(cwd).is_absolute()
        or not isinstance(args, dict)
    ):
        return 0, []
    cwd = Path(cwd)
    if (
        payload.get("hook_event_name") == "PostToolUse"
        and payload.get("tool_name") == "Bash"
    ):
        # Record only complete skill bodies actually returned to the model.
        # A successful exit or a command mentioning SKILL.md alone proves nothing.
        command = args.get("command", "")
        if not isinstance(command, str) or "SKILL.md" not in command:
            return 0, []
        output = list(response_text(payload.get("tool_response")))
        for name in sorted(guard.SKILLS):
            path = skill_path(name, cwd)
            if path and name not in state["loaded"]:
                body = path.read_text().strip()
                if any(body in text for text in output):
                    state["loaded"].append(name)
        return 0, []
    if payload.get("hook_event_name") != "PreToolUse":
        return 0, []
    required = guard.requirements(payload)
    needed, notices = [], []
    for name in sorted(required - set(state["loaded"])):
        path = skill_path(name, cwd)
        if path is None or name in state["requested"]:
            if name not in state["warned"]:
                state["warned"].append(name)
                notices.append(
                    f"Writing guard: skipping {name}; unavailable or full read not confirmed."
                )
            continue
        needed.append((name, path))
    if needed:
        state["requested"].extend(name for name, _ in needed)
        if "sf-writing-style" in required:
            state["reviewed"] = ["sf-writing-style"]
        notices.append(
            "Read these skill files completely with the shell tool (allow enough output for the full text): "
            + ", ".join(str(path) for _, path in needed)
            + ". Apply their guidance to the prepared text, then retry."
        )
        return 2, notices
    result, feedback = guard.reminder(required, state)
    return result, notices + feedback


def manage(action):
    path = config_dir() / "hooks.json"
    # Never replace a malformed user file with defaults.
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        raise TypeError(f"Invalid hooks object in {path}")
    matches = {
        event: settings.registered_matchers(data, event, SCRIPT_PATH) for event in HOOKS
    }
    configured = all(matches[event] == {matcher} for event, matcher in HOOKS.items())
    if action == "info":
        status = (
            "enabled"
            if configured
            else "partial"
            if any(matches.values())
            else "disabled"
        )
        print(f"Configured: {status} in {path}")
        print(
            "Runtime activation requires Codex hook support and trust. Inspect /hooks; registration does not establish trust."
        )
        print(
            "Coverage: gh/glab shell commands and supported Slack/GitHub/GitLab MCP writes."
        )
        for variable in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
            print(f"{variable}: {'off' if guard.disabled(variable) else 'on'}")
        return 0
    if (action == "enable" and configured) or (
        action == "disable" and not any(matches.values())
    ):
        print(
            f"Codex writing guard already {'enabled' if configured else 'disabled'} in {path}"
        )
        return 0
    if path.exists():
        settings.backup(path)
    for event, matcher in HOOKS.items():
        settings.unregister_hook(data, event, SCRIPT_PATH)
        if action == "enable":
            settings.register_hook(data, event, matcher, HOOK_COMMAND, SCRIPT_PATH)
    settings.atomic_write(data, path)
    print(f"Codex writing guard {action}d in {path}")
    if action == "enable":
        print(
            "Open /hooks in Codex and review/trust the new definitions. Existing hook trust is unchanged."
        )
    return 0


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--hook":
        return guard.run_hook(process, "codex")
    if arg in {"enable", "disable", "info"}:
        try:
            return manage(arg)
        except (OSError, ValueError, TypeError) as error:
            print(f"Codex writing guard: {error}", file=sys.stderr)
            return 1
    print("Usage: codex-writing-guard.py {--hook|enable|disable|info}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
