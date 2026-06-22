#!/usr/bin/env python3
"""Unit tests for claude_settings.py.

Standard-library ``unittest`` only (the repo declares no test framework, and the
module under test is itself stdlib-only). Run from anywhere:

    python3 -m unittest discover -s sjust/scripts/lib -p 'test_*.py'

or directly:

    python3 sjust/scripts/lib/test_claude_settings.py
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import claude_settings as cs  # noqa: E402

MARKER = "/opt/sparkdock/sjust/scripts/claude-gh-glab-gate.py"
COMMAND = f'python3 "{MARKER}" --hook'
OTHER = {"matcher": "Bash", "hooks": [{"type": "command", "command": "rtk-run-hook"}]}


class LoadTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "settings.json"
        self.addCleanup(self.tmp.cleanup)

    def test_missing_file_returns_empty(self):
        self.assertEqual(cs.load(self.path), {})

    def test_corrupt_json_returns_empty(self):
        self.path.write_text("{not valid json")
        self.assertEqual(cs.load(self.path), {})

    def test_non_object_returns_empty(self):
        self.path.write_text("[1, 2, 3]")
        self.assertEqual(cs.load(self.path), {})

    def test_valid_object_round_trips(self):
        self.path.write_text('{"model": "opus"}')
        self.assertEqual(cs.load(self.path), {"model": "opus"})


class AtomicWriteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_creates_parent_and_round_trips(self):
        path = Path(self.tmp.name) / "nested" / "dir" / "settings.json"
        cs.atomic_write({"a": 1, "hooks": {}}, path)
        self.assertTrue(path.exists())
        self.assertEqual(cs.load(path), {"a": 1, "hooks": {}})

    def test_output_is_indented_and_newline_terminated(self):
        path = Path(self.tmp.name) / "settings.json"
        cs.atomic_write({"a": 1}, path)
        text = path.read_text()
        self.assertTrue(text.endswith("\n"))
        self.assertIn("\n  ", text)  # indent=2

    def test_no_temp_file_left_behind(self):
        path = Path(self.tmp.name) / "settings.json"
        cs.atomic_write({"a": 1}, path)
        leftovers = [p.name for p in Path(self.tmp.name).iterdir()]
        self.assertEqual(leftovers, ["settings.json"])


class BackupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_backup_copies_content_and_returns_path(self):
        path = Path(self.tmp.name) / "settings.json"
        path.write_text('{"model": "opus"}\n')
        backup = cs.backup(path)
        self.assertTrue(os.path.exists(backup))
        self.assertTrue(backup.startswith(f"{path}.bak."))
        self.assertEqual(Path(backup).read_text(), '{"model": "opus"}\n')


class SettingsPathTest(unittest.TestCase):
    def test_honors_home(self):
        with tempfile.TemporaryDirectory() as home:
            old = os.environ.get("HOME")
            os.environ["HOME"] = home
            try:
                self.assertEqual(
                    cs.settings_path(), Path(home) / ".claude" / "settings.json"
                )
            finally:
                if old is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old


class RegisterHookTest(unittest.TestCase):
    def test_creates_structure_when_absent(self):
        data = {}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        entries = data["hooks"]["PreToolUse"]
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["matcher"], "Bash")
        self.assertEqual(entries[0]["hooks"][0]["command"], COMMAND)

    def test_preserves_foreign_entries(self):
        data = {"model": "opus", "hooks": {"PreToolUse": [dict(OTHER)]}}
        cs.register_hook(data, "PreToolUse", "Skill", COMMAND, MARKER)
        entries = data["hooks"]["PreToolUse"]
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0], OTHER)
        self.assertEqual(data["model"], "opus")

    def test_is_idempotent_per_matcher(self):
        data = {}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        self.assertEqual(len(data["hooks"]["PreToolUse"]), 1)

    def test_refreshes_command_for_same_matcher(self):
        # An older command that still carries the marker (e.g. a flag changed)
        # is recognized as ours and replaced, not duplicated.
        data = {}
        old_command = f'python3 "{MARKER}" --hook --legacy-flag'
        cs.register_hook(data, "PreToolUse", "Bash", old_command, MARKER)
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        entries = data["hooks"]["PreToolUse"]
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["hooks"][0]["command"], COMMAND)

    def test_differing_command_without_marker_is_treated_as_foreign(self):
        # Defensive: an entry whose command lacks the marker is never touched.
        data = {"hooks": {"PreToolUse": [dict(OTHER)]}}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        entries = data["hooks"]["PreToolUse"]
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0], OTHER)

    def test_two_matchers_coexist(self):
        data = {}
        cs.register_hook(data, "PreToolUse", "Skill", COMMAND, MARKER)
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        self.assertEqual(
            cs.registered_matchers(data, "PreToolUse", MARKER), {"Skill", "Bash"}
        )

    def test_coerces_non_dict_hooks(self):
        data = {"hooks": "garbage"}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        self.assertEqual(len(data["hooks"]["PreToolUse"]), 1)

    def test_coerces_non_list_event(self):
        data = {"hooks": {"PreToolUse": "garbage"}}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        self.assertEqual(len(data["hooks"]["PreToolUse"]), 1)


class RegisteredMatchersTest(unittest.TestCase):
    def test_empty_when_no_hooks(self):
        self.assertEqual(cs.registered_matchers({}, "PreToolUse", MARKER), set())

    def test_ignores_foreign_entries(self):
        data = {"hooks": {"PreToolUse": [dict(OTHER)]}}
        self.assertEqual(cs.registered_matchers(data, "PreToolUse", MARKER), set())

    def test_tolerates_malformed_shapes(self):
        self.assertEqual(
            cs.registered_matchers({"hooks": "x"}, "PreToolUse", MARKER), set()
        )
        self.assertEqual(
            cs.registered_matchers(
                {"hooks": {"PreToolUse": "x"}}, "PreToolUse", MARKER
            ),
            set(),
        )


class UnregisterHookTest(unittest.TestCase):
    def _seed(self):
        data = {"model": "opus", "hooks": {"PreToolUse": [dict(OTHER)]}}
        cs.register_hook(data, "PreToolUse", "Skill", COMMAND, MARKER)
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        return data

    def test_removes_only_ours_and_preserves_foreign(self):
        data = self._seed()
        self.assertTrue(cs.unregister_hook(data, "PreToolUse", MARKER))
        entries = data["hooks"]["PreToolUse"]
        self.assertEqual(entries, [OTHER])
        self.assertEqual(data["model"], "opus")

    def test_prunes_empty_event_and_hooks(self):
        data = {}
        cs.register_hook(data, "PreToolUse", "Bash", COMMAND, MARKER)
        self.assertTrue(cs.unregister_hook(data, "PreToolUse", MARKER))
        self.assertNotIn("hooks", data)

    def test_returns_false_when_nothing_to_remove(self):
        data = {"hooks": {"PreToolUse": [dict(OTHER)]}}
        self.assertFalse(cs.unregister_hook(data, "PreToolUse", MARKER))
        self.assertEqual(data["hooks"]["PreToolUse"], [OTHER])

    def test_returns_false_on_missing_hooks(self):
        self.assertFalse(cs.unregister_hook({}, "PreToolUse", MARKER))


class EndToEndTest(unittest.TestCase):
    """enable/disable cycle as the gate driver uses it, via files."""

    def test_register_write_load_unregister(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "settings.json"
            path.write_text('{"model": "opus", "hooks": {"PreToolUse": []}}\n')
            data = cs.load(path)
            data["hooks"]["PreToolUse"].append(dict(OTHER))
            for matcher in ("Skill", "Bash"):
                cs.register_hook(data, "PreToolUse", matcher, COMMAND, MARKER)
            cs.atomic_write(data, path)

            reloaded = cs.load(path)
            self.assertEqual(len(reloaded["hooks"]["PreToolUse"]), 3)
            self.assertEqual(
                cs.registered_matchers(reloaded, "PreToolUse", MARKER),
                {"Skill", "Bash"},
            )

            cs.unregister_hook(reloaded, "PreToolUse", MARKER)
            cs.atomic_write(reloaded, path)
            final = cs.load(path)
            self.assertEqual(final["hooks"]["PreToolUse"], [OTHER])
            self.assertEqual(final["model"], "opus")
            # the file is still valid JSON
            json.loads(path.read_text())


if __name__ == "__main__":
    unittest.main()
