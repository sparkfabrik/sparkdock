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
    "PostToolUse": "Skill|Read",
    "PostToolUseFailure": "Skill",
    "SessionStart": "startup|clear|compact",
}


def _reads_tracked():
    """Whether Claude sends Read results to this hook.

    A registration made by an older sparkdock sends only Skill results, so the
    references could never be recorded and every publishing call would be denied.
    Registrations outside the user settings cannot be checked and are trusted.
    """
    try:
        cs = _settings_lib()
        matchers = cs.registered_matchers(
            cs.load(), "PostToolUse", Path(SCRIPT_PATH).name
        )
    except Exception:
        return False
    if not matchers:
        return True
    for matcher in matchers:
        if matcher in (None, "", "*"):
            return True
        try:
            if re.fullmatch(matcher, "Read"):
                return True
        except re.error:
            continue
    return False


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


def _reference_path(name, cwd):
    """The installed sf-writing-style reference file, in a Claude-visible location."""
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    for root in (config, *(p / ".claude" for p in (cwd, *cwd.parents))):
        path = root / "skills" / "sf-writing-style" / guard.REFERENCES[name]
        if path.is_file():
            return path
    return None


def _read_whole_file(tool_input, response):
    """True when the Read returned the file from its first line to its last."""
    file = response.get("file") if isinstance(response, dict) else None
    keys = ("startLine", "numLines", "totalLines")
    if isinstance(file, dict) and all(isinstance(file.get(k), int) for k in keys):
        return file["startLine"] <= 1 and file["numLines"] >= file["totalLines"]
    return tool_input.get("offset") in (None, 0, 1) and tool_input.get("limit") is None


def _record_read(tool_input, response, state):
    path = tool_input.get("file_path")
    if not isinstance(path, str) or not _read_whole_file(tool_input, response):
        return
    for name, relative in guard.REFERENCES.items():
        if path.endswith("sf-writing-style/" + relative) and name not in state["read"]:
            state["read"].append(name)


def _process(payload, state):
    event = payload.get("hook_event_name")
    if guard.lifecycle(payload, state):
        return 0, [], []
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0, [], []
    if payload.get("tool_name") == "Read":
        if event == "PostToolUse":
            _record_read(tool_input, payload.get("tool_response"), state)
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
            + ". Read and apply any task-specific references required by those skills "
            "to the prepared text, then retry this command. Read the references with the "
            "Read tool: a shell command such as cat does not count."
        )
        return 2, notices, []
    # The skill text alone does not carry its references: a description written
    # without them is badly shaped or badly formatted. Require the read, every
    # time it is missing, with the exact path, so the retry is a new action.
    missing = []
    # Like the skills, the references fail open: when sf-writing-style did not
    # load, there is nothing to read them against.
    wanted = (
        guard.reference_requirements(payload)
        if "sf-writing-style" in state["loaded"]
        else set()
    )
    if wanted - set(state["read"]) and not _reads_tracked():
        if "stale-registration" not in state["warned"]:
            notices.append(
                "Writing guard: skipping the reference check; this hook does not "
                "receive Read results. Run `sjust claude-gh-gate-enable` (`ajust` on "
                "Linux) to update its registration."
            )
            state["warned"].append("stale-registration")
        wanted = set()
    for name in sorted(wanted - set(state["read"])):
        path = _reference_path(name, Path(cwd))
        if path is None:
            if name not in state["warned"]:
                notices.append(
                    f"Writing guard: skipping the {name} reference; not installed."
                )
                state["warned"].append(name)
            continue
        missing.append(str(path))
    if missing:
        notices.append(
            "Read these sf-writing-style references with the Read tool (cat in a shell does "
            "not count) before publishing: "
            + ", ".join(missing)
            + ". Apply them to the prepared text, then retry this command."
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


def cmd_repair():
    """Update a stale registration; leave a disabled guard disabled."""
    cs = _settings_lib()
    data = cs.load()
    if not any(cs.registered_matchers(data, event, SCRIPT_PATH) for event in HOOKS):
        return 0
    if _configured(data, cs):
        return 0
    return cmd_enable()


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
        "repair": cmd_repair,
    }
    if arg in actions:
        try:
            return actions[arg]()
        except (OSError, ValueError, TypeError) as error:
            print(f"Claude writing guard: {error}", file=sys.stderr)
            return 1
    sys.stderr.write("Usage: claude-gh-gate.py {--hook|enable|disable|info|repair}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
