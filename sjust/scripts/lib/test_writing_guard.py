"""Shared transport coverage and Codex runtime/installer regressions."""

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import writing_guard as guard

SCRIPT = Path(__file__).resolve().parent.parent / "codex-writing-guard.py"
spec = importlib.util.spec_from_file_location("codex_guard", SCRIPT)
codex = importlib.util.module_from_spec(spec)
spec.loader.exec_module(codex)


class CodexGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "codex"
        self.env = dict(
            os.environ,
            CODEX_HOME=str(self.config),
            XDG_CACHE_HOME=str(self.root / "cache"),
        )
        for var in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
            self.env.pop(var, None)
        self.skills = {}
        for name in guard.SKILLS:
            p = self.config / "skills" / name / "SKILL.md"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(f"---\nname: {name}\n---\nComplete guidance for {name}.\n")
            self.skills[name] = p

    def payload(self, name="mcp__claude_ai_Slack__slack_send_message"):
        return {
            "session_id": "test",
            "cwd": str(self.root),
            "hook_event_name": "PreToolUse",
            "tool_name": name,
            "tool_input": {"text": "Hello"},
        }

    def run_hook(self, payload, extra=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--hook"],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            env=self.env | (extra or {}),
            check=False,
        )

    def read(self, body=None):
        p = self.skills["sf-writing-style"]
        return self.run_hook(
            self.payload()
            | {
                "hook_event_name": "PostToolUse",
                "tool_name": "Bash",
                "tool_input": {"command": f"cat {p}"},
                "tool_response": {
                    "output": p.read_text() if body is None else body,
                    "exit_code": 0,
                },
            }
        )

    def test_slack_requires_read_and_retries_without_reload(self):
        first = self.run_hook(self.payload())
        self.assertEqual(first.returncode, 2)
        self.assertIn(str(self.skills["sf-writing-style"]), first.stderr)
        self.assertIn("task-specific references", first.stderr)
        self.read()
        for _ in range(2):
            r = self.run_hook(self.payload())
            self.assertEqual((r.returncode, r.stderr), (0, ""))
        self.run_hook(self.payload() | {"hook_event_name": "UserPromptSubmit"})
        r = self.run_hook(self.payload())
        self.assertEqual((r.returncode, r.stderr), (0, ""))
        output = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertNotIn("permissionDecision", output)
        self.assertIn("text was not evaluated", output["additionalContext"])
        self.assertIn("task-specific reference", output["additionalContext"])
        self.assertNotIn("Read these skill files", r.stdout)
        self.assertEqual(self.run_hook(self.payload()).stdout, "")

    def test_partial_read_never_counts_as_loaded(self):
        self.run_hook(self.payload())
        self.read("Complete guidance")
        r = self.run_hook(self.payload())
        self.assertEqual(r.returncode, 0)
        self.assertIn("full read not confirmed", r.stdout)

    def test_compaction_requires_new_read(self):
        self.run_hook(self.payload())
        self.read()
        self.run_hook(
            self.payload() | {"hook_event_name": "SessionStart", "source": "compact"}
        )
        r = self.run_hook(self.payload())
        self.assertEqual(r.returncode, 2)
        self.assertIn("Read these skill files", r.stderr)

    def test_missing_manual_and_disabled_skills_fail_open(self):
        for mode in ("missing", "manual", "disabled"):
            with self.subTest(mode=mode):
                p = self.skills["sf-writing-style"]
                if mode == "missing":
                    p.rename(p.with_suffix(".saved"))
                else:
                    p.write_text(
                        "---\ndisable-model-invocation: true\n---\nDo not auto load"
                        if mode == "manual"
                        else "Writing guidance"
                    )
                if mode == "disabled":
                    (self.config / "config.toml").write_text(
                        f'[[skills.config]]\npath = "{p}"\nenabled = false\n'
                    )
                r = self.run_hook(self.payload() | {"session_id": mode})
                self.assertEqual(r.returncode, 0)
                self.assertIn("skipping sf-writing-style", r.stdout)

    def test_bypass_and_reads_do_not_request_skill(self):
        for name in (
            "mcp__slack__slack_search_channels",
            "mcp__slack__slack_get_thread",
            "mcp__filesystem__send_message",
        ):
            self.assertEqual(self.run_hook(self.payload(name)).returncode, 0)
        for variable in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
            self.assertEqual(
                self.run_hook(self.payload(), {variable: "0"}).returncode, 0
            )

    def test_malformed_input_and_state_fail_open(self):
        for payload in (None, [], {}, self.payload() | {"tool_input": "oops"}):
            self.assertEqual(self.run_hook(payload).returncode, 0)
        self.run_hook(self.payload())
        for p in (self.root / "cache/sparkdock/codex-skill-gate").glob("*.json"):
            p.write_text("broken")
        self.assertEqual(self.run_hook(self.payload()).returncode, 0)

    def test_installer_preserves_other_hooks_and_trust_config(self):
        path = self.config / "hooks.json"
        other = {
            "hooks": {
                "SessionStart": [{"hooks": [{"type": "command", "command": "other"}]}]
            }
        }
        path.write_text(json.dumps(other))
        config = self.config / "config.toml"
        config.write_text('[hooks.state."other"]\ntrusted_hash = "keep"\n')
        with patch.dict(os.environ, self.env), patch("sys.stdout", io.StringIO()):
            codex.manage("enable")
            saved = path.read_bytes()
            codex.manage("enable")
            self.assertEqual(path.read_bytes(), saved)
            codex.manage("disable")
        self.assertEqual(json.loads(path.read_text()), other)
        self.assertIn('trusted_hash = "keep"', config.read_text())

    def test_invalid_settings_are_not_overwritten(self):
        path = self.config / "hooks.json"
        path.write_text("broken")
        with patch.dict(os.environ, self.env), self.assertRaises(ValueError):
            codex.manage("enable")
        self.assertEqual(path.read_text(), "broken")

    def test_shared_installer_reports_partial_changes(self):
        script = SCRIPT.with_name("agent-writing-guard.py")
        env = self.env | {"CLAUDE_CONFIG_DIR": str(self.root / "claude")}

        def enable():
            result = subprocess.run(
                [sys.executable, str(script), "enable"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

        self.assertNotIn("already enabled", enable())
        self.assertIn("already enabled", enable())
        path = self.config / "hooks.json"
        data = json.loads(path.read_text())
        data["hooks"].pop("PostToolUse")
        path.write_text(json.dumps(data))
        self.assertNotIn("already enabled", enable())
        self.assertIn("already enabled", enable())


class InstallerSafetyTest(unittest.TestCase):
    def test_malformed_hooks_preserve_file_on_enable_and_disable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for script, variable, filename in (
                ("claude-gh-gate.py", "CLAUDE_CONFIG_DIR", "settings.json"),
                ("codex-writing-guard.py", "CODEX_HOME", "hooks.json"),
            ):
                for event in (
                    {"custom": "keep"},
                    "invalid",
                    [{"hooks": "invalid"}],
                    [{"hooks": ["invalid"]}],
                ):
                    for action in ("enable", "disable"):
                        with self.subTest(script=script, event=event, action=action):
                            path = root / filename
                            original = json.dumps({"hooks": {"PreToolUse": event}})
                            path.write_text(original)
                            result = subprocess.run(
                                [sys.executable, str(SCRIPT.with_name(script)), action],
                                env=os.environ | {variable: tmp},
                                capture_output=True,
                                text=True,
                                check=False,
                            )
                            self.assertEqual(result.returncode, 1, result.stdout)
                            self.assertEqual(path.read_text(), original)

    def test_empty_config_variables_use_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for script, directory, filename in (
                ("claude-gh-gate.py", ".claude", "settings.json"),
                ("codex-writing-guard.py", ".codex", "hooks.json"),
            ):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT.with_name(script)), "enable"],
                    cwd=tmp,
                    env=os.environ
                    | {"HOME": tmp, "CLAUDE_CONFIG_DIR": "", "CODEX_HOME": ""},
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((root / directory / filename).is_file())
                self.assertFalse((root / filename).exists())

    def test_empty_cache_variable_uses_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = os.environ | {
                "HOME": tmp,
                "XDG_CACHE_HOME": "",
                "SPARKDOCK_GH_GATE": "1",
            }
            for script, engine in (
                ("claude-gh-gate.py", "claude"),
                ("codex-writing-guard.py", "codex"),
            ):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT.with_name(script)), "--hook"],
                    input=json.dumps(
                        {
                            "session_id": "empty-cache",
                            "hook_event_name": "UserPromptSubmit",
                        }
                    ),
                    cwd=tmp,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(
                    list(
                        (root / ".cache/sparkdock" / f"{engine}-skill-gate").glob(
                            "*.json"
                        )
                    )
                )
            self.assertFalse((root / "sparkdock").exists())


class ClassificationTest(unittest.TestCase):
    def test_close_comments_require_writing_style(self):
        for noun in ("pr", "issue"):
            for flag in ("--comment text", "-c text", "--comment=text"):
                self.assertTrue(
                    guard._writes_prose([noun, "close", "5", *flag.split()])
                )
            self.assertFalse(guard._writes_prose([noun, "close", "5"]))

    def test_known_connector_writes(self):
        for tool in (
            "mcp__claude_ai_Slack__slack_send_message",
            "mcp__codex_apps__slack_update_message",
            "mcp__github__create_issue",
            "mcp__codex_apps__github_create_issue",
            "mcp__codex_apps__github_add_review_to_pr",
            "mcp__gitlab__create_merge_request",
        ):
            with patch.dict(os.environ, {"SPARKDOCK_WRITING_GUARD": "1"}):
                self.assertEqual(
                    guard.requirements({"tool_name": tool, "tool_input": {}}),
                    {"sf-writing-style"},
                )


if __name__ == "__main__":
    unittest.main()
