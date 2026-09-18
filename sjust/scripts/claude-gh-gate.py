#!/usr/bin/env python3
"""Require available platform/writing skills before recognized gh/glab commands.

The historical filename and management commands remain the provisioning entry
point. This is a fail-open workflow aid, not a shell security boundary. See
../../docs/claude-writing-guard.md for scope, bypasses and lifecycle behavior.
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import writing_guard as guard

GATED_SKILLS = guard.SKILLS
SCRIPT_PATH = str(Path(__file__).resolve())
HOOK_COMMAND = f"python3 {shlex.quote(SCRIPT_PATH)} --hook"
HOOKS = {
    "PreToolUse": guard.MATCHER,
    "UserPromptSubmit": "*",
    "PostToolUse": "Skill",
    "PostToolUseFailure": "Skill",
    "SessionStart": "startup|clear|compact",
}


def _settings_lib():
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import claude_settings

    return claude_settings


def _skill_available(name, cwd):
    # Use Claude-visible locations, never the unlinked ~/.agents/skills copy.
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
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
    if guard.lifecycle(payload, state):
        return 0, [], []
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0, [], []
    if payload.get("tool_name") == "Skill":
        name = tool_input.get("skill") or tool_input.get("name")
        if not isinstance(name, str) or name not in GATED_SKILLS:
            return 0, [], []
        if event == "PostToolUse":
            if name not in state["loaded"]:
                state["loaded"].append(name)
            if name in state["failed"]:
                state["failed"].remove(name)
        elif event == "PostToolUseFailure":
            if name not in state["failed"]:
                state["failed"].append(name)
        return 0, [], []
    if event != "PreToolUse":
        return 0, [], []
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not Path(cwd).is_absolute():
        return 0, [], []
    required = guard.requirements(payload)
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
        if "sf-writing-style" in required:
            state["reviewed"] = ["sf-writing-style"]
        state["requested"].extend(needed)
        notices.append(
            "Load these skills with the Skill tool: "
            + ", ".join(needed)
            + ". Apply their guidance to any prepared text, then retry this command."
        )
        return 2, notices, []
    return 0, notices, guard.reminder(required, state)


def run_hook():
    return guard.run_hook(_process, "claude")


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
    data = json.loads(settings.read_text())
    cs.validate_hooks(data, HOOKS)
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
    data = json.loads(settings.read_text())
    cs.validate_hooks(data, HOOKS)
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
        "Requires gh/glab; supported CLI and Slack/GitHub/GitLab MCP writes require sf-writing-style."
    )
    print(
        "Partial registration is repaired by claude-gh-gate-enable. Missing skills are skipped."
    )
    for variable in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
        print(f"{variable}: {'off' if guard.disabled(variable) else 'on'}")
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
        try:
            return actions[arg]()
        except (OSError, ValueError, TypeError) as error:
            print(f"Claude writing guard: {error}", file=sys.stderr)
            return 1
    sys.stderr.write("Usage: claude-gh-gate.py {--hook|enable|disable|info}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
