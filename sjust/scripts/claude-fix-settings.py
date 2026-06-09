#!/usr/bin/env python3
"""Repair sparkdock-managed Claude Code hooks in ~/.claude/settings.json.

Invoked by claude-fix-settings.sh (which resolves the stable node path and the
settings location). Two idempotent fixes are available:

  1. Caveman hook node path (always) — the caveman installer bakes the
     *resolved* node binary (e.g. /opt/homebrew/Cellar/node/26.0.0/bin/node)
     into the SessionStart/UserPromptSubmit hook commands, which breaks on every
     node version bump. Rewrite it to the stable Homebrew symlink passed via
     --node.
  2. claude-usage hooks (opt-in, --remove-claude-usage) — remove the
     SessionStart/SessionEnd hooks that the upstream claude-usage installer
     wires in. Opt-in because users may have installed them deliberately, so the
     automatic provisioning pass leaves them alone.

All JSON work happens here (no jq dependency); writes are atomic (temp file +
os.replace) with a timestamped backup, and a missing/corrupt/non-object
settings file is a clean no-op.
"""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time

CAVEMAN_SCRIPTS = ("caveman-activate.js", "caveman-mode-tracker.js")
# Leading command token: a quoted "..." path or a bare \S+ run, then the rest.
_NODE_TOKEN = re.compile(r'^("(?P<q>[^"]*)"|(?P<b>\S+))(?P<rest>\s.*)$', re.DOTALL)


def normalize_node_path(cmd, node):
    """Rewrite the node binary in a caveman hook command to ``node``.

    Returns ``(new_cmd, changed)``. Only caveman-managed commands are touched,
    and only when a stable node path is known and differs from the baked-in one.
    """
    if not node or not any(s in cmd for s in CAVEMAN_SCRIPTS):
        return cmd, False
    m = _NODE_TOKEN.match(cmd)
    if not m:
        return cmd, False
    current = m.group("q") if m.group("q") is not None else m.group("b")
    if current == node:
        return cmd, False
    return f'"{node}"{m.group("rest")}', True


def repair(data, node, remove_claude_usage):
    """Apply the enabled fixes to ``data`` in place. Returns a list of change strings.

    The caveman node-path normalization always runs. claude-usage hook removal
    only runs when ``remove_claude_usage`` is true; it is opt-in because users
    may have installed those hooks deliberately, so the automatic provisioning
    pass must not strip them.
    """
    changes = []
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return changes

    for event in list(hooks.keys()):
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                kept_groups.append(group)
                continue
            kept_entries = []
            for entry in group["hooks"]:
                if isinstance(entry, dict) and isinstance(entry.get("command"), str):
                    cmd = entry["command"]
                    # Op 2 (opt-in): drop claude-usage hooks entirely.
                    if remove_claude_usage and "claude-usage" in cmd:
                        changes.append(f"removed claude-usage hook from {event}")
                        continue
                    # Op 1: normalize the caveman hook node path.
                    new_cmd, changed = normalize_node_path(cmd, node)
                    if changed:
                        entry["command"] = new_cmd
                        changes.append(
                            f"normalized caveman node path in {event} -> {node}"
                        )
                kept_entries.append(entry)
            if kept_entries:
                group["hooks"] = kept_entries
                kept_groups.append(group)
            else:
                changes.append(f"removed empty hook group from {event}")
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
            changes.append(f"removed empty event '{event}'")

    if not hooks:
        data.pop("hooks", None)
    return changes


def write_atomic(path, data):
    """Write ``data`` to ``path`` atomically (temp file + os.replace)."""
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings.", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main():
    parser = argparse.ArgumentParser(
        description="Repair Claude Code hooks in settings.json."
    )
    parser.add_argument("settings", help="path to ~/.claude/settings.json")
    parser.add_argument("--mode", choices=("fix", "info"), default="info")
    parser.add_argument("--node", default="", help="stable node path for caveman hooks")
    parser.add_argument(
        "--remove-claude-usage",
        action="store_true",
        help="also remove claude-usage session hooks (opt-in; not run automatically)",
    )
    args = parser.parse_args()

    path, dry = args.settings, args.mode == "info"

    if not os.path.exists(path):
        print(f"ℹ️  {path} does not exist — nothing to do.")
        return 0
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        print(f"⚠️  {path} is missing or not valid JSON — skipping.")
        return 0
    if not isinstance(data, dict):
        print(f"⚠️  {path} is not a JSON object — skipping.")
        return 0

    changes = repair(data, args.node, args.remove_claude_usage)

    if not changes:
        print("✅ Already clean — no changes needed.")
        return 0

    for c in changes:
        print(("would fix: " if dry else "fixed: ") + c)

    if dry:
        print(
            f"\nℹ️  {len(changes)} change(s) pending. Run 'claude-fix-settings' to apply."
        )
        return 0

    backup = f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copy2(path, backup)
    write_atomic(path, data)
    print(f"\n✅ Applied {len(changes)} change(s) to {path}")
    print(f"💡 Backup saved to {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
