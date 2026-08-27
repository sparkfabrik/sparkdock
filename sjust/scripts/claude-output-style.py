#!/usr/bin/env python3
"""Set the default Claude Code output style in ``~/.claude/settings.json``.

Output styles modify Claude Code's system prompt, so the guidance is
prompt-cached, survives context compaction, and Claude Code issues its own
reminders to follow it during a conversation.

This installs a *default*, not a policy. The key is written only when it is
absent, so anyone who picks a different style keeps it across provisioning
runs. ``/config`` writes to ``.claude/settings.local.json``, which outranks
user settings, so a per-project choice keeps working either way.

A settings.json that exists but is not valid JSON aborts the run with a clear
message rather than being overwritten. ``claude_settings.load()`` degrades a
corrupt file to ``{}``, which a following write would clobber, so this parses
the file itself before touching anything.

Usage: claude-output-style.py {set [style]|reset|info}
"""

import json
import sys
from pathlib import Path

DEFAULT_STYLE = "Concise"
KEY = "outputStyle"


def _settings_lib():
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import claude_settings

    return claude_settings


def _load_strict(settings):
    """Parse settings.json, or exit non-zero without writing anything."""
    if not settings.exists():
        return {}
    try:
        data = json.loads(settings.read_text())
    except json.JSONDecodeError as exc:
        print(f"❌ {settings} is not valid JSON ({exc}).", file=sys.stderr)
        print(
            "   Nothing was modified. Fix the file, then run this again.",
            file=sys.stderr,
        )
        sys.exit(1)
    except OSError as exc:
        print(
            f"❌ Cannot read {settings}: {exc}. Nothing was modified.", file=sys.stderr
        )
        sys.exit(1)
    if not isinstance(data, dict):
        print(f"❌ {settings} does not contain a JSON object.", file=sys.stderr)
        print("   Nothing was modified.", file=sys.stderr)
        sys.exit(1)
    return data


def cmd_set(style) -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    data = _load_strict(settings)

    current = data.get(KEY)
    if current is not None:
        print(f"ℹ️  Output style already set to '{current}' in {settings}")
        return 0

    backup = cs.backup() if settings.exists() else None
    data[KEY] = style
    cs.atomic_write(data)

    print(f"✅ Output style set to '{style}' in {settings}")
    if backup:
        print(f"💡 Backup saved to {backup}")
    print("💡 Takes effect in a new session, or after /clear.")
    print("💡 Change it anytime with /config, or with: sjust claude-output-style-reset")
    return 0


def cmd_reset() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    if not settings.exists():
        print(f"ℹ️  {settings} does not exist, nothing to reset")
        return 0

    data = _load_strict(settings)
    if KEY not in data:
        print(f"ℹ️  No output style set in {settings}")
        return 0

    backup = cs.backup()
    removed = data.pop(KEY)
    cs.atomic_write(data)
    print(f"✅ Removed output style '{removed}' from {settings}")
    print(f"💡 Backup saved to {backup}")
    return 0


def cmd_info() -> int:
    cs = _settings_lib()
    settings = cs.settings_path()
    print(f"Settings file:  {settings}")
    print(f"Managed default: {DEFAULT_STYLE}")
    if not settings.exists():
        print("Current style:  none (settings.json does not exist)")
        return 0
    data = _load_strict(settings)
    print(f"Current style:  {data.get(KEY, 'none (Claude Code default)')}")
    print("Note: a per-project choice in .claude/settings.local.json overrides this.")
    return 0


def usage() -> int:
    print("Usage: claude-output-style.py {set [style]|reset|info}", file=sys.stderr)
    return 2


def main() -> int:
    args = sys.argv[1:]
    if not args:
        return usage()
    if args[0] == "set":
        return cmd_set(args[1] if len(args) > 1 else DEFAULT_STYLE)
    if args[0] == "reset":
        return cmd_reset()
    if args[0] == "info":
        return cmd_info()
    return usage()


if __name__ == "__main__":
    sys.exit(main())
