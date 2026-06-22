"""Shared helpers for managing the user's Claude Code settings.json.

Reusable by sparkdock scripts that register or remove hooks (or other keys) in
``~/.claude/settings.json``. Everything uses the standard library only (no jq,
no third-party deps); writes are atomic (temp file + ``os.replace``) with a
timestamped backup; a missing or corrupt settings file degrades to ``{}``.

Hook entries are identified by a caller-chosen ``marker`` substring embedded in
the entry's command. That lets a script find and remove exactly its own entries
without disturbing hooks owned by other tools (RTK, caveman, statusline).

Typical use::

    import claude_settings as cs
    data = cs.load()
    cs.register_hook(data, "PreToolUse", "Bash", MY_COMMAND, MY_MARKER)
    cs.atomic_write(data)
"""

import json
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path


def settings_path() -> Path:
    """Path to the user's Claude Code settings.json (honors $HOME)."""
    return Path.home() / ".claude" / "settings.json"


def load(path=None) -> dict:
    """Load settings.json as a dict; return {} on missing/corrupt/non-object."""
    path = Path(path) if path else settings_path()
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def backup(path=None) -> str:
    """Copy settings.json to a timestamped .bak file; return the backup path.

    Uses ``shutil.copy2`` so the backup inherits the source mode and metadata
    (``settings.json`` is often mode 600 and may reference secrets, so a
    broader-permission copy would leak it). The timestamp includes microseconds
    so two backups in the same second do not collide.
    """
    path = Path(path) if path else settings_path()
    dst = f"{path}.bak.{datetime.now().strftime('%Y%m%d%H%M%S%f')}"
    shutil.copy2(path, dst)
    return dst


def atomic_write(data: dict, path=None) -> None:
    """Write data to settings.json atomically (temp file + os.replace)."""
    path = Path(path) if path else settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        dir=str(path.parent), prefix=".settings.", suffix=".json"
    )
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _entry_has_marker(entry, marker) -> bool:
    if not isinstance(entry, dict):
        return False
    for hook in entry.get("hooks", []) or []:
        if isinstance(hook, dict) and marker in str(hook.get("command", "")):
            return True
    return False


def registered_matchers(data: dict, event: str, marker: str) -> set:
    """Set of matchers for our (marker-owned) entries under hooks[event]."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return set()
    entries = hooks.get(event)
    if not isinstance(entries, list):
        return set()
    return {e.get("matcher") for e in entries if _entry_has_marker(e, marker)}


def register_hook(
    data: dict, event: str, matcher: str, command: str, marker: str
) -> None:
    """Idempotently add a ``{matcher -> command}`` entry under ``hooks[event]``.

    Any prior entry of ours with the same marker and matcher is dropped first so
    the command is refreshed. Entries owned by other tools are left untouched.
    Mutates ``data`` in place.
    """
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        hooks = data["hooks"] = {}
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        entries = hooks[event] = []
    entries[:] = [
        e
        for e in entries
        if not (
            isinstance(e, dict)
            and e.get("matcher") == matcher
            and _entry_has_marker(e, marker)
        )
    ]
    entries.append(
        {"matcher": matcher, "hooks": [{"type": "command", "command": command}]}
    )


def unregister_hook(data: dict, event: str, marker: str) -> bool:
    """Remove all our (marker-owned) entries under ``hooks[event]``.

    Prunes the event list and the ``hooks`` object if they become empty. Returns
    True if anything was removed. Mutates ``data`` in place.
    """
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return False
    entries = hooks.get(event)
    if not isinstance(entries, list):
        return False
    before = len(entries)
    entries[:] = [e for e in entries if not _entry_has_marker(e, marker)]
    removed = len(entries) < before
    if not entries:
        hooks.pop(event, None)
    if not hooks:
        data.pop("hooks", None)
    return removed
