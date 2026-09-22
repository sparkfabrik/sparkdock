"""Tests for the managed Claude Code statusline: the settings manager and the renderer.

Run with `just test-python` (or `python3 -m unittest discover -s sjust/scripts/lib`).
"""

import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))

# The manager is a hyphenated script, so it is loaded by path rather than imported.
_spec = importlib.util.spec_from_file_location(
    "claude_statusline", SCRIPTS_DIR / "claude-statusline.py"
)
claude_statusline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(claude_statusline)

RENDERER = (
    SCRIPTS_DIR.parent.parent / "config" / "bin" / "sparkfabrik-claude-statusline"
)


def render(payload, env=None):
    """Run the real renderer on a payload and return its output with SGR codes removed."""
    with tempfile.TemporaryDirectory() as config_dir:
        run_env = os.environ.copy()
        run_env["CLAUDE_CONFIG_DIR"] = config_dir
        if env:
            run_env.update(env)
        result = subprocess.run(
            ["bash", str(RENDERER)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            check=False,
            env=run_env,
        )
    return result.returncode, re.sub(r"\033\[[0-9;]*m", "", result.stdout)


class ResolveDeadlinesTest(unittest.TestCase):
    def test_relative_offsets_become_absolute_epochs(self):
        resolved = claude_statusline._resolve_deadlines(
            {"rate_limits": {"five_hour": {"resets_at": "+9000"}}}, 1000
        )
        self.assertEqual(resolved["rate_limits"]["five_hour"]["resets_at"], 10000)

    def test_other_values_and_comments_pass_through(self):
        resolved = claude_statusline._resolve_deadlines(
            {"_comment": "gone", "a": "+nope", "b": 3, "c": ["+5", "x"]}, 100
        )
        self.assertNotIn("_comment", resolved)
        self.assertEqual(resolved["a"], "+nope")
        self.assertEqual(resolved["b"], 3)
        self.assertEqual(resolved["c"], [105, "x"])


class SettingsManagerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.old_cfg = os.environ.get("CLAUDE_CONFIG_DIR")
        os.environ["CLAUDE_CONFIG_DIR"] = self.tmp.name
        self.settings = Path(self.tmp.name) / "settings.json"

    def tearDown(self):
        if self.old_cfg is None:
            os.environ.pop("CLAUDE_CONFIG_DIR", None)
        else:
            os.environ["CLAUDE_CONFIG_DIR"] = self.old_cfg

    def test_enable_writes_the_key_and_keeps_the_others(self):
        self.settings.write_text(json.dumps({"model": "opus"}))
        self.assertEqual(claude_statusline.cmd_enable(), 0)
        data = json.loads(self.settings.read_text())
        self.assertEqual(data["model"], "opus")
        self.assertEqual(data["statusLine"]["command"], claude_statusline.COMMAND)

    def test_enable_is_idempotent(self):
        claude_statusline.cmd_enable()
        before = sorted(p.name for p in Path(self.tmp.name).iterdir())
        claude_statusline.cmd_enable()
        self.assertEqual(sorted(p.name for p in Path(self.tmp.name).iterdir()), before)

    def test_backup_keeps_the_source_mode(self):
        self.settings.write_text(json.dumps({"statusLine": {"command": "other"}}))
        self.settings.chmod(0o600)
        claude_statusline.cmd_enable()
        backups = [p for p in Path(self.tmp.name).iterdir() if ".bak." in p.name]
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_disable_removes_only_the_status_line(self):
        self.settings.write_text(
            json.dumps(
                {"model": "opus", "statusLine": {"command": claude_statusline.COMMAND}}
            )
        )
        self.assertEqual(claude_statusline.cmd_disable(), 0)
        data = json.loads(self.settings.read_text())
        self.assertNotIn("statusLine", data)
        self.assertEqual(data["model"], "opus")

    def test_disable_without_settings_is_a_no_op(self):
        self.assertEqual(claude_statusline.cmd_disable(), 0)
        self.assertFalse(self.settings.exists())

    def test_corrupt_settings_does_not_lose_the_file(self):
        self.settings.write_text("{not json")
        self.assertEqual(claude_statusline.cmd_enable(), 0)
        self.assertEqual(
            json.loads(self.settings.read_text())["statusLine"]["command"],
            claude_statusline.COMMAND,
        )
        self.assertTrue([p for p in Path(self.tmp.name).iterdir() if ".bak." in p.name])


class RendererTest(unittest.TestCase):
    def setUp(self):
        self.config_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.config_dir.cleanup)
        self.render_env = {"CLAUDE_CONFIG_DIR": self.config_dir.name}

    def test_exits_zero_on_an_empty_payload(self):
        code, _ = render({})
        self.assertEqual(code, 0)

    def test_countdowns_replace_reset_timestamps(self):
        now = int(time.time())
        _, out = render(
            {
                "cwd": "/tmp",
                "rate_limits": {
                    "five_hour": {"used_percentage": 24, "resets_at": now + 9000},
                    "seven_day": {"used_percentage": 41, "resets_at": now + 180000},
                },
            }
        )
        self.assertIn("5h 24% ↻2h30m", out)
        self.assertIn("7d 41% ↻2d", out)

    def test_a_past_deadline_drops_the_countdown_but_keeps_the_percentage(self):
        _, out = render(
            {
                "cwd": "/tmp",
                "rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 1}},
            }
        )
        self.assertIn("5h 5%", out)
        self.assertNotIn("↻", out)

    def test_spend_limit_reports_past_one_hundred(self):
        _, out = render(
            {"cwd": "/tmp", "rate_limits": {"spend_limit": {"used_percentage": 137}}}
        )
        self.assertIn("$ 137%", out)

    def test_absent_windows_render_nothing(self):
        _, out = render({"cwd": "/tmp", "model": {"display_name": "Opus 5"}})
        for label in ("5h", "7d", "$"):
            self.assertNotIn(label, out)

    def test_context_bar_tracks_the_percentage_and_names_a_non_default_window(self):
        _, out = render(
            {
                "cwd": "/tmp",
                "context_window": {
                    "used_percentage": 42,
                    "context_window_size": 1000000,
                },
            }
        )
        self.assertIn("▰▰▱▱▱ 42% 1M", out)

    def test_the_ordinary_window_is_not_named(self):
        _, out = render(
            {
                "cwd": "/tmp",
                "context_window": {
                    "used_percentage": 10,
                    "context_window_size": 200000,
                },
            }
        )
        self.assertIn("10%", out)
        self.assertNotIn("200k", out)

    def test_control_bytes_in_the_payload_are_stripped(self):
        _, out = render({"cwd": "/tmp", "model": {"display_name": "Opus\033[31m\0075"}})
        self.assertNotIn("\033[31m", out)
        self.assertNotIn("\007", out)
        self.assertIn("Opus[31m5", out)

    def test_the_context_suffix_is_dropped_from_the_model_name(self):
        _, out = render(
            {"cwd": "/tmp", "model": {"display_name": "Opus 5 (1M context)"}}
        )
        self.assertIn("Opus 5", out)
        self.assertNotIn("(1M context)", out)

    def test_a_warm_cache_shows_no_snowflake_and_a_cold_one_does(self):
        _, warm = render(
            {"cwd": "/tmp", "prompt_cache": {"warm": True, "caching_observed": True}}
        )
        self.assertNotIn("❄", warm)
        _, cold = render(
            {"cwd": "/tmp", "prompt_cache": {"warm": False, "caching_observed": True}}
        )
        self.assertIn("❄", cold)

    def test_a_session_that_never_cached_shows_no_snowflake(self):
        _, out = render(
            {"cwd": "/tmp", "prompt_cache": {"warm": False, "caching_observed": False}}
        )
        self.assertNotIn("❄", out)

    def test_the_default_output_style_is_hidden(self):
        _, out = render({"cwd": "/tmp", "output_style": {"name": "default"}})
        self.assertNotIn("✎", out)

    def test_caveman_full_renders_without_a_mode_suffix(self):
        (Path(self.config_dir.name) / ".caveman-active").write_text("full")
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertIn("CAVEMAN", out)
        self.assertNotIn("CAVEMAN:", out)

    def test_caveman_ultra_renders_its_mode(self):
        (Path(self.config_dir.name) / ".caveman-active").write_text("ultra")
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertIn("CAVEMAN:ULTRA", out)

    def test_caveman_off_renders_nothing(self):
        (Path(self.config_dir.name) / ".caveman-active").write_text("off")
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertNotIn("CAVEMAN", out)

    def test_caveman_without_a_flag_renders_nothing(self):
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertNotIn("CAVEMAN", out)

    def test_caveman_symlink_renders_nothing(self):
        target = Path(self.config_dir.name) / "mode"
        target.write_text("full")
        (Path(self.config_dir.name) / ".caveman-active").symlink_to(target)
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertNotIn("CAVEMAN", out)

    def test_caveman_strips_terminal_escape_injection(self):
        (Path(self.config_dir.name) / ".caveman-active").write_text("\033[31mfull")
        _, out = render({"cwd": "/tmp"}, self.render_env)
        self.assertNotIn("\033", out)

    def test_every_preview_fixture_renders(self):
        for variant in ("typical", "full"):
            with self.subTest(variant=variant):
                bar = claude_statusline._preview(variant)
                self.assertTrue(bar.strip())
                self.assertNotIn("unavailable", bar)


if __name__ == "__main__":
    unittest.main()
