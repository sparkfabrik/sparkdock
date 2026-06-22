#!/usr/bin/env python3
"""Unit tests for the claude-gh-gate.py runtime hook (`--hook`).

The gate script has a hyphenated filename, so it cannot be imported as a module.
These tests drive it as a subprocess exactly as Claude Code does: feed a JSON
payload on stdin and assert the exit code (2 = block, 0 = allow) and sentinel
side effects. Each test uses its own TMPDIR so per-session sentinels are
isolated. Stdlib ``unittest`` only.

Run via ``python3 -m unittest discover -s sjust/scripts/lib -p 'test_*.py'``.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE = str(Path(__file__).resolve().parent.parent / "claude-gh-gate.py")


def _sentinel(tmpdir, session_id):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "nosession")
    return Path(tmpdir) / f"sparkdock-gh-gate-{safe}"


class GateHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def run_hook(self, payload, extra_env=None):
        env = dict(os.environ)
        env["TMPDIR"] = self.tmp.name
        env.pop("SPARKDOCK_GH_GATE", None)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, GATE, "--hook"],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
        )

    @staticmethod
    def bash(command, session_id="s1"):
        return {
            "session_id": session_id,
            "tool_name": "Bash",
            "tool_input": {"command": command},
        }

    @staticmethod
    def skill(name, session_id="s1", field="skill"):
        return {
            "session_id": session_id,
            "tool_name": "Skill",
            "tool_input": {field: name},
        }

    def test_gh_blocked_when_skill_not_loaded(self):
        r = self.run_hook(self.bash("gh pr create"))
        self.assertEqual(r.returncode, 2)
        self.assertIn("gh", r.stderr.lower())

    def test_bare_gh_is_gated(self):
        # Regression: regex must match `gh` with no args (end-of-string), else
        # the gate is bypassable by running the bare command.
        self.assertEqual(self.run_hook(self.bash("gh")).returncode, 2)

    def test_gh_in_chain_is_gated(self):
        self.assertEqual(self.run_hook(self.bash("cd /x && gh pr list")).returncode, 2)

    def test_env_prefixed_gh_is_gated(self):
        self.assertEqual(self.run_hook(self.bash("FOO=1 gh pr list")).returncode, 2)

    def test_glab_is_not_gated(self):
        # Scoped to gh only; glab passes freely.
        self.assertEqual(
            self.run_hook(self.bash("GITLAB_HOST=x glab issue list")).returncode, 0
        )

    def test_github_prefix_is_not_a_false_positive(self):
        self.assertEqual(
            self.run_hook(self.bash("github-release-tool run")).returncode, 0
        )

    def test_non_gh_command_allowed(self):
        self.assertEqual(self.run_hook(self.bash("git push")).returncode, 0)

    def test_skill_load_creates_sentinel_and_unblocks(self):
        sentinel = _sentinel(self.tmp.name, "s1")
        self.assertFalse(sentinel.exists())
        self.assertEqual(self.run_hook(self.skill("gh")).returncode, 0)
        self.assertTrue(sentinel.exists())
        # gh now allowed in the same session
        self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 0)

    def test_skill_name_field_also_recognized(self):
        self.assertEqual(self.run_hook(self.skill("gh", field="name")).returncode, 0)
        self.assertTrue(_sentinel(self.tmp.name, "s1").exists())

    def test_non_gated_skill_does_not_unblock(self):
        self.run_hook(self.skill("glab"))
        self.assertFalse(_sentinel(self.tmp.name, "s1").exists())
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 2)

    def test_per_session_isolation(self):
        self.run_hook(self.skill("gh", session_id="loaded"))
        # a different session is still gated
        r = self.run_hook(self.bash("gh pr list", session_id="other"))
        self.assertEqual(r.returncode, 2)

    def test_escape_hatch_disables_gate(self):
        for val in ("0", "off", "false", "no"):
            r = self.run_hook(
                self.bash("gh pr list"), extra_env={"SPARKDOCK_GH_GATE": val}
            )
            self.assertEqual(r.returncode, 0, f"value {val!r} should disable the gate")

    def test_malformed_stdin_fails_open(self):
        env = dict(os.environ)
        env["TMPDIR"] = self.tmp.name
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input="{not json",
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(r.returncode, 0)

    def test_unrelated_tool_allowed(self):
        payload = {"session_id": "s1", "tool_name": "Read", "tool_input": {"file": "x"}}
        self.assertEqual(self.run_hook(payload).returncode, 0)


if __name__ == "__main__":
    unittest.main()
