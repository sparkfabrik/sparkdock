#!/usr/bin/env python3
"""Install or inspect both agent writing guards without changing other hooks."""

import subprocess
import sys
from pathlib import Path


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else ""
    if action not in {"enable", "disable", "info"}:
        print("Usage: agent-writing-guard.py {enable|disable|info}", file=sys.stderr)
        return 2
    results = []
    unchanged = True
    for script in ("claude-gh-gate.py", "codex-writing-guard.py"):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name(script)), action],
            check=False,
            text=True,
            capture_output=True,
        )
        results.append(result.returncode)
        if (
            action == "enable"
            and result.returncode == 0
            and "already enabled" in result.stdout
        ):
            print(f"{script}: unchanged")
        else:
            unchanged = False
            print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
    if action == "enable" and unchanged:
        print("Writing guards already enabled.")
    return max(results)


if __name__ == "__main__":
    sys.exit(main())
