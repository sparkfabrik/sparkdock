#!/usr/bin/env python3
"""Unit tests for claude-output-style.py.

The script has a hyphenated filename, so it cannot be imported as a module.
These tests drive it as a subprocess with a patched ``$HOME``, the same way
``test_claude_gh_gate.py`` drives the gate. Stdlib ``unittest`` only.

Run via ``python3 -m unittest discover -s sjust/scripts/lib -p 'test_*.py'``.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "claude-output-style.py"


class OutputStyleTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        self.settings = self.home / ".claude" / "settings.json"
        self.addCleanup(self._tmp.cleanup)

    def run_script(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
            check=False,
            # Keep the ambient environment: dropping LANG/LC_* can make the
            # child's stdout ASCII, and the script prints emoji.
            env={**os.environ, "HOME": str(self.home)},
        )

    def write_settings(self, text):
        self.settings.parent.mkdir(parents=True, exist_ok=True)
        self.settings.write_text(text)

    def backups(self):
        parent = self.settings.parent
        if not parent.exists():
            return []
        return list(parent.glob("settings.json.bak.*"))

    # --- set -------------------------------------------------------------- #

    def test_creates_settings_when_missing(self):
        r = self.run_script("set")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(
            json.loads(self.settings.read_text()), {"outputStyle": "Concise"}
        )

    def test_no_backup_when_settings_did_not_exist(self):
        self.run_script("set")
        self.assertEqual(self.backups(), [])

    def test_adds_key_and_preserves_everything_else(self):
        self.write_settings(
            json.dumps(
                {
                    "permissions": {"deny": ["Read(./.env)"]},
                    "statusLine": {"type": "command"},
                }
            )
        )
        r = self.run_script("set")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(self.settings.read_text())
        self.assertEqual(data["outputStyle"], "Concise")
        self.assertEqual(data["permissions"], {"deny": ["Read(./.env)"]})
        self.assertEqual(data["statusLine"], {"type": "command"})

    def test_backs_up_before_modifying_an_existing_file(self):
        self.write_settings("{}")
        self.run_script("set")
        self.assertEqual(len(self.backups()), 1)

    def test_does_not_overwrite_a_users_own_choice(self):
        self.write_settings(json.dumps({"outputStyle": "Explanatory"}))
        before = self.settings.read_bytes()
        r = self.run_script("set")
        self.assertEqual(r.returncode, 0)
        self.assertIn("already set", r.stdout)
        self.assertIn("Explanatory", r.stdout)
        self.assertEqual(self.settings.read_bytes(), before)
        self.assertEqual(self.backups(), [])

    def test_second_run_is_a_no_op(self):
        self.run_script("set")
        after_first = self.settings.read_bytes()
        r = self.run_script("set")
        self.assertIn("already set", r.stdout)
        self.assertEqual(self.settings.read_bytes(), after_first)

    def test_accepts_an_explicit_style(self):
        self.run_script("set", "Explanatory")
        self.assertEqual(
            json.loads(self.settings.read_text())["outputStyle"], "Explanatory"
        )

    # --- corrupt input ----------------------------------------------------- #

    def test_corrupt_json_fails_without_touching_the_file(self):
        self.write_settings("{not json")
        r = self.run_script("set")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not valid JSON", r.stderr)
        self.assertIn(str(self.settings), r.stderr)
        self.assertEqual(self.settings.read_text(), "{not json")
        self.assertEqual(self.backups(), [])

    def test_invalid_utf8_fails_without_touching_the_file(self):
        self.settings.parent.mkdir(parents=True, exist_ok=True)
        self.settings.write_bytes(b'{"outputStyle": "\xff\xfe"}')
        before = self.settings.read_bytes()
        r = self.run_script("set")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not valid UTF-8", r.stderr)
        self.assertIn("Nothing was modified", r.stderr)
        self.assertEqual(self.settings.read_bytes(), before)
        self.assertEqual(self.backups(), [])

    def test_explicit_null_counts_as_a_users_choice(self):
        self.write_settings(json.dumps({"outputStyle": None}))
        before = self.settings.read_bytes()
        r = self.run_script("set")
        self.assertEqual(r.returncode, 0)
        self.assertIn("already set", r.stdout)
        self.assertEqual(self.settings.read_bytes(), before)

    def test_non_object_json_fails_without_touching_the_file(self):
        self.write_settings("[1, 2, 3]")
        r = self.run_script("set")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("does not contain a JSON object", r.stderr)
        self.assertEqual(self.settings.read_text(), "[1, 2, 3]")
        self.assertEqual(self.backups(), [])

    # --- reset ------------------------------------------------------------- #

    def test_reset_removes_only_the_key(self):
        self.write_settings(
            json.dumps({"outputStyle": "Concise", "permissions": {"deny": []}})
        )
        r = self.run_script("reset")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(self.settings.read_text())
        self.assertNotIn("outputStyle", data)
        self.assertEqual(data["permissions"], {"deny": []})

    def test_reset_is_a_no_op_when_no_style_is_set(self):
        self.write_settings("{}")
        r = self.run_script("reset")
        self.assertEqual(r.returncode, 0)
        self.assertIn("No output style set", r.stdout)
        self.assertEqual(self.backups(), [])

    def test_reset_on_a_missing_file_is_clean(self):
        r = self.run_script("reset")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self.settings.exists())

    # --- info and usage ----------------------------------------------------- #

    def test_info_reports_the_current_style(self):
        self.write_settings(json.dumps({"outputStyle": "Learning"}))
        r = self.run_script("info")
        self.assertEqual(r.returncode, 0)
        self.assertIn("Learning", r.stdout)

    def test_info_on_a_missing_file_is_clean(self):
        r = self.run_script("info")
        self.assertEqual(r.returncode, 0)
        self.assertIn("does not exist", r.stdout)

    def test_no_arguments_is_a_usage_error(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 2)
        self.assertIn("Usage:", r.stderr)


if __name__ == "__main__":
    unittest.main()
