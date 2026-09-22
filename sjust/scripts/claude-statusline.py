#!/usr/bin/env python3
"""Enable, disable, inspect and preview the SparkFabrik managed statusline.

Invoked by the shared sjust/ajust recipes
(``sjust/recipes/shared/07-claude-statusline.just``); see those for usage.

The statusline itself is ``config/bin/sparkfabrik-claude-statusline``. This
script only owns the ``statusLine`` key in the user's ``settings.json``, and it
delegates loading, backing up and writing that file to ``lib/claude_settings``,
the same module every other sparkdock settings mutator uses, so a backup keeps
the source's mode (settings.json is often 600) and a write is atomic.

The preview never hardcodes a copy of the bar: it feeds a payload fixture from
``statusline-payloads/`` to the real renderer, so any change to the renderer
shows up here automatically.
"""

import json
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SPARKDOCK_ROOT = SCRIPT_DIR.parent.parent
STATUSLINE_SCRIPT = SPARKDOCK_ROOT / "config" / "bin" / "sparkfabrik-claude-statusline"
PAYLOAD_DIR = SCRIPT_DIR / "statusline-payloads"
COMMAND = f'bash "{STATUSLINE_SCRIPT}"'


def _settings_lib():
    sys.path.insert(0, str(SCRIPT_DIR / "lib"))
    import claude_settings

    return claude_settings


def _current_command(cs) -> str:
    """The configured statusLine command, or '' when none is set."""
    entry = cs.load().get("statusLine")
    return entry.get("command", "") if isinstance(entry, dict) else ""


def _resolve_deadlines(value, now):
    """Turn every "+seconds" string in the fixture into an absolute epoch."""
    if isinstance(value, dict):
        return {
            k: _resolve_deadlines(v, now) for k, v in value.items() if k != "_comment"
        }
    if isinstance(value, list):
        return [_resolve_deadlines(v, now) for v in value]
    if isinstance(value, str) and value.startswith("+") and value[1:].isdigit():
        return now + int(value[1:])
    return value


def _preview(variant="typical") -> str:
    if not STATUSLINE_SCRIPT.is_file():
        return "(unavailable — script missing)"
    fixture = PAYLOAD_DIR / f"{variant}.json"
    if not fixture.is_file():
        return f"(unavailable — no payload fixture named {variant})"
    payload = _resolve_deadlines(json.loads(fixture.read_text()), int(time.time()))
    payload.setdefault("workspace", {})["current_dir"] = str(SPARKDOCK_ROOT)
    payload["cwd"] = str(SPARKDOCK_ROOT)
    result = subprocess.run(
        ["bash", str(STATUSLINE_SCRIPT)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout or "(renderer printed nothing)"


def cmd_enable(cs) -> int:
    if not STATUSLINE_SCRIPT.is_file():
        print(f"❌ Statusline script not found: {STATUSLINE_SCRIPT}")
        print("💡 Update sparkdock (git pull) and try again.")
        return 1

    settings = cs.settings_path()
    if _current_command(cs) == COMMAND:
        print(f"ℹ️  SparkFabrik statusline already enabled in {settings}")
        return 0

    backup = cs.backup(settings) if settings.exists() else ""
    data = cs.load()
    existing = data.get("statusLine")
    if isinstance(existing, dict) and existing.get("command"):
        print(f"⚠️  Replacing existing statusLine command: {existing['command']}")
    data["statusLine"] = {"type": "command", "command": COMMAND}
    cs.atomic_write(data)

    print(f"✅ SparkFabrik statusline enabled in {settings}")
    if backup:
        print(f"💡 Backup saved to {backup}")
    print()
    print("Preview:")
    print(f"  {_preview()}")
    print()
    print("💡 Start a new Claude Code session (or it refreshes on next render).")
    print("💡 Disable anytime with: claude-statusline-disable")
    return 0


def cmd_disable(cs) -> int:
    settings = cs.settings_path()
    if not settings.exists():
        print(f"ℹ️  No {settings} — nothing to disable.")
        return 0
    if not _current_command(cs):
        print(f"ℹ️  No statusLine configured in {settings}.")
        return 0

    backup = cs.backup(settings)
    data = cs.load()
    data.pop("statusLine", None)
    cs.atomic_write(data)

    print(f"✅ statusLine removed from {settings}")
    print(f"💡 Backup saved to {backup}")
    return 0


def cmd_info(cs) -> int:
    print(f"Managed script: {STATUSLINE_SCRIPT}")
    print(
        f"  status: {'present' if STATUSLINE_SCRIPT.is_file() else 'MISSING — run git pull in sparkdock'}"
    )
    print()

    settings = cs.settings_path()
    if not settings.exists():
        print(f"Configured: no ({settings} does not exist)")
        return 0

    current = _current_command(cs)
    if not current:
        print(f"Configured: no statusLine in {settings}")
    elif current == COMMAND:
        print("Configured: ✅ SparkFabrik managed statusline")
    else:
        print(f"Configured: custom statusLine → {current}")
    print()
    print("Preview:")
    print(f"  {_preview()}")
    return 0


def main(argv) -> int:
    action = argv[0] if argv else ""
    if action == "preview":
        variant = argv[1] if len(argv) > 1 and argv[1] else "typical"
        print(_preview(variant))
        return 0
    if action not in ("enable", "disable", "info"):
        print(
            "Usage: claude-statusline.py {enable|disable|info|preview [full]}",
            file=sys.stderr,
        )
        return 2
    cs = _settings_lib()
    return {"enable": cmd_enable, "disable": cmd_disable, "info": cmd_info}[action](cs)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
