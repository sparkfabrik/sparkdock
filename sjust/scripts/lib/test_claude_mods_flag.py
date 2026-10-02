#!/usr/bin/env python3
"""Unit tests for claude-mods-flag.py, driven as a subprocess with a temp HOME."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "claude-mods-flag.py"
FLAG = "tengu_plugin_hooks_modules"


class ModsFlagTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = Path(self._tmp.name)
        self.state = self.home / ".claude.json"

    def run_script(self, *args, env=None):
        environment = {**os.environ, "HOME": str(self.home)}
        environment.pop("CLAUDE_CONFIG_DIR", None)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
            check=False,
            env={**environment, **(env or {})},
        )

    def write(self, data):
        self.state.write_text(json.dumps(data))
        self.state.chmod(0o600)

    def test_clears_a_cached_false_and_keeps_the_rest(self):
        self.write(
            {"userID": "u", "cachedGrowthBookFeatures": {FLAG: False, "other": 1}}
        )
        result = self.run_script("clear")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Cleared", result.stdout)
        self.assertEqual(
            json.loads(self.state.read_text()),
            {"userID": "u", "cachedGrowthBookFeatures": {"other": 1}},
        )
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)

    def test_leaves_true_and_absent_values_alone(self):
        for features in ({FLAG: True}, {"other": 1}):
            self.write({"cachedGrowthBookFeatures": features})
            before = self.state.read_text()
            result = self.run_script("clear")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("not cached as false", result.stdout)
            self.assertEqual(self.state.read_text(), before)

    def test_missing_state_file_is_not_an_error(self):
        result = self.run_script("clear")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state.exists())

    def test_invalid_json_fails_without_writing(self):
        self.state.write_text("{not json")
        result = self.run_script("clear")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.state.read_text(), "{not json")

    def test_honours_claude_config_dir(self):
        config = self.home / "config"
        config.mkdir()
        (config / ".claude.json").write_text(
            json.dumps({"cachedGrowthBookFeatures": {FLAG: False}})
        )
        result = self.run_script("clear", env={"CLAUDE_CONFIG_DIR": str(config)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads((config / ".claude.json").read_text()),
            {"cachedGrowthBookFeatures": {}},
        )

    def test_info_reports_the_cached_value(self):
        self.write({"cachedGrowthBookFeatures": {FLAG: False}})
        result = self.run_script("info")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"{FLAG}: false", result.stdout)


if __name__ == "__main__":
    unittest.main()
