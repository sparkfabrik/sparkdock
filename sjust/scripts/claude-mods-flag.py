#!/usr/bin/env python3
"""Clear a cached `false` for Claude Code's mods rollout flag.

Claude Code caches feature flags in ``~/.claude.json``. A cached
``tengu_plugin_hooks_modules: false`` turns installed mods off even though
the client default is on (anthropics/claude-code#91870). Removing the key
lets the client default apply again. Only a cached ``false`` is removed.

Usage: claude-mods-flag.py {clear|info}
"""

import json
import os
import sys
import tempfile
from pathlib import Path

FLAG = "tengu_plugin_hooks_modules"


def state_path():
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(config) / ".claude.json" if config else Path.home() / ".claude.json"


def load(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError(f"{path} does not contain a JSON object")
    return data


def cmd_clear():
    path = state_path()
    if not path.exists():
        print(f"Mods flag not cached: {path} does not exist")
        return 0
    data = load(path)
    features = data.get("cachedGrowthBookFeatures")
    if not isinstance(features, dict) or features.get(FLAG) is not False:
        print(f"Mods flag not cached as false in {path}")
        return 0
    del features[FLAG]
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2)
        os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    print(f"Cleared the cached mods flag in {path}. Start a new Claude Code session.")
    return 0


def cmd_info():
    path = state_path()
    value = "<not cached>"
    if path.exists():
        features = load(path).get("cachedGrowthBookFeatures")
        if isinstance(features, dict) and FLAG in features:
            value = json.dumps(features[FLAG])
    print(f"State file: {path}")
    print(f"{FLAG}: {value}")
    return 0


def main():
    actions = {"clear": cmd_clear, "info": cmd_info}
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg not in actions:
        print("Usage: claude-mods-flag.py {clear|info}", file=sys.stderr)
        return 2
    try:
        return actions[arg]()
    except (OSError, ValueError, TypeError) as error:
        print(f"Claude mods flag: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
