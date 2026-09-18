"""Exercise the real hook subprocess with isolated skills, cache and CLI stubs."""

import fcntl
import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from pathlib import Path
from unittest.mock import patch

GATE = Path(__file__).resolve().parent.parent / "claude-gh-gate.py"
spec = importlib.util.spec_from_file_location("claude_gate", GATE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class GateHookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "config"
        self.project = self.root / "project"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("gh", "glab"):
            cli = self.bin / name
            cli.write_text("#!/bin/sh\nexit 0\n")
            cli.chmod(0o755)
        for name in gate.GATED_SKILLS:
            path = self.skill_path(name)
            path.parent.mkdir(parents=True)
            path.write_text(
                f"---\nname: {name}\ndescription: Test skill\n---\nTest guidance.\n"
            )
        self.env = dict(os.environ)
        self.env.update(
            CLAUDE_CONFIG_DIR=str(self.config),
            XDG_CACHE_HOME=str(self.root / "cache"),
            PATH=str(self.bin),
        )
        for name in ("SPARKDOCK_GH_GATE", "SPARKDOCK_WRITING_GUARD"):
            self.env.pop(name, None)

    def skill_path(self, name):
        return self.config / "skills" / name / "SKILL.md"

    def state_path(self, session="s1"):
        return (
            self.root
            / "cache"
            / "sparkdock"
            / "claude-skill-gate"
            / (hashlib.sha256(session.encode()).hexdigest() + ".json")
        )

    def run_hook(self, payload, extra_env=None):
        return subprocess.run(
            [sys.executable, str(GATE), "--hook"],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
            env=self.env | (extra_env or {}),
        )

    def bash(self, command, session="s1"):
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
            "session_id": session,
            "cwd": str(self.project),
        }

    def skill(self, name, event="PostToolUse", session="s1"):
        return {
            "hook_event_name": event,
            "tool_name": "Skill",
            "tool_input": {"skill": name},
            "session_id": session,
            "cwd": str(self.project),
            "tool_response": {"success": True},
        }

    def load(self, *names, session="s1"):
        for name in names:
            self.assertEqual(
                self.run_hook(self.skill(name, session=session)).returncode, 0
            )

    def test_platform_and_writing_requirements(self):
        for cli in ("gh", "glab"):
            with self.subTest(cli=cli):
                r = self.run_hook(
                    self.bash(f"{cli} issue create --title Example", session=cli)
                )
                self.assertEqual(r.returncode, 2)
                self.assertIn(cli, r.stderr)
                self.assertIn("sf-writing-style", r.stderr)

    def test_read_only_needs_platform_only(self):
        for cli in ("gh", "glab"):
            r = self.run_hook(self.bash(f"{cli} issue list", session=cli))
            self.assertEqual(r.returncode, 2)
            self.assertNotIn("sf-writing-style", r.stderr)

    def test_successful_loads_remind_once_without_blocking(self):
        self.load("gh", "sf-writing-style")
        first = self.run_hook(self.bash("gh pr create"))
        self.assertEqual((first.returncode, first.stderr), (0, ""))
        output = json.loads(first.stdout)["hookSpecificOutput"]
        self.assertNotIn("permissionDecision", output)
        self.assertIn("text was not evaluated", output["additionalContext"])
        self.assertNotIn("systemMessage", json.loads(first.stdout))
        for _ in range(3):
            r = self.run_hook(self.bash("gh pr create --body 'Add a filter.'"))
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
        state = json.loads(self.state_path().read_text())
        self.assertEqual(state["last_check"]["decision"], "continue")

    def test_slack_loads_writing_without_cli_skill(self):
        payload = self.bash("") | {
            "tool_name": "mcp__claude_ai_Slack__slack_send_message",
            "tool_input": {"text": "Hello"},
        }
        first = self.run_hook(payload)
        self.assertEqual(first.returncode, 2)
        self.assertIn("sf-writing-style", first.stderr)
        self.assertNotIn("gh,", first.stderr)
        self.load("sf-writing-style")
        self.assertEqual(self.run_hook(payload).returncode, 0)
        self.run_hook({"hook_event_name": "UserPromptSubmit", "session_id": "s1"})
        reminder = self.run_hook(payload)
        self.assertEqual((reminder.returncode, reminder.stderr), (0, ""))
        context = json.loads(reminder.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("sf-writing-style", context)
        self.assertNotIn("Skill tool", context)
        self.assertEqual(self.run_hook(payload).stdout, "")

    def test_pretooluse_is_not_success(self):
        self.run_hook(self.skill("gh", event="PreToolUse"))
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 2)

    def test_failed_load_is_skipped_once_without_retry_loop(self):
        self.load("gh")
        self.run_hook(self.skill("sf-writing-style", event="PostToolUseFailure"))
        r = self.run_hook(self.bash("gh pr create"))
        self.assertEqual(r.returncode, 0)
        self.assertIn("sf-writing-style", r.stdout)
        self.assertEqual(self.run_hook(self.bash("gh pr create")).stdout, "")
        self.assertNotIn(
            "sf-writing-style", json.loads(self.state_path().read_text())["loaded"]
        )

    def test_unconfirmed_load_does_not_loop(self):
        self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 2)
        r = self.run_hook(self.bash("gh pr create"))
        self.assertEqual(r.returncode, 0)
        self.assertIn("load not confirmed", r.stdout)
        self.assertEqual(self.run_hook(self.bash("gh pr create")).stdout, "")

    def test_success_after_failure_is_recorded(self):
        self.run_hook(self.skill("gh", event="PostToolUseFailure"))
        self.load("gh")
        self.assertEqual(self.run_hook(self.bash("gh pr list")).stdout, "")
        self.assertEqual(json.loads(self.state_path().read_text())["failed"], [])

    def test_sessions_are_independent(self):
        self.load("gh", session="one")
        self.assertEqual(
            self.run_hook(self.bash("gh pr list", session="two")).returncode, 2
        )

    def test_subagent_load_does_not_unblock_parent_or_sibling(self):
        self.run_hook(self.skill("gh") | {"agent_id": "child"})
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 2)
        self.assertEqual(
            self.run_hook(self.bash("gh pr list") | {"agent_id": "sibling"}).returncode,
            2,
        )
        self.assertEqual(
            self.run_hook(self.bash("gh pr list") | {"agent_id": "child"}).returncode, 0
        )

    def test_brief_lock_contention_preserves_skill_confirmation(self):
        self.run_hook(self.bash("gh pr list"))
        with ThreadPoolExecutor(max_workers=1) as pool:
            with self.state_path().open("r+") as stream:
                fcntl.flock(stream, fcntl.LOCK_EX)
                pending = pool.submit(self.load, "gh")
                try:
                    with self.assertRaises(TimeoutError):
                        pending.result(timeout=0.2)
                finally:
                    fcntl.flock(stream, fcntl.LOCK_UN)
            pending.result(timeout=3)
        self.assertIn("gh", json.loads(self.state_path().read_text())["loaded"])

    def test_busy_state_fails_open(self):
        self.load("gh")
        with self.state_path().open("r+") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            r = self.run_hook(self.bash("gh pr create"))
            self.assertEqual((r.returncode, r.stderr), (0, ""))

    def test_invalid_json_fails_open(self):
        r = subprocess.run(
            [sys.executable, str(GATE), "--hook"],
            input="{not json",
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
        )
        self.assertEqual((r.returncode, r.stderr), (0, ""))

    def test_missing_skill_notice_is_not_repeated_after_compaction(self):
        self.config.rename(self.root / "unlinked-config")
        self.assertNotEqual(self.run_hook(self.bash("gh pr create")).stdout, "")
        self.run_hook(
            {"hook_event_name": "SessionStart", "source": "compact", "session_id": "s1"}
        )
        self.assertEqual(self.run_hook(self.bash("gh pr create")).stdout, "")

    def test_compaction_and_clear_require_fresh_confirmation(self):
        for source in ("compact", "clear", "startup"):
            self.load("gh", "sf-writing-style")
            self.run_hook(
                {
                    "hook_event_name": "SessionStart",
                    "source": source,
                    "session_id": "s1",
                }
            )
            self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 2)

    def test_resume_keeps_confirmation(self):
        self.load("gh", "sf-writing-style")
        self.run_hook(self.bash("gh pr create"))
        self.run_hook(
            {"hook_event_name": "SessionStart", "source": "resume", "session_id": "s1"}
        )
        self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 0)

    def test_full_bypass(self):
        for value in ("0", "off", "false", "no", " OFF "):
            r = self.run_hook(
                self.bash("gh pr create && glab mr create"),
                {"SPARKDOCK_GH_GATE": value},
            )
            self.assertEqual((r.returncode, r.stdout), (0, ""))
        self.assertFalse(self.state_path().exists())

    def test_writing_bypass_keeps_platform_guard(self):
        for index, value in enumerate(("0", "off", "false", "no", " OFF ")):
            session = str(index)
            env = {"SPARKDOCK_WRITING_GUARD": value}
            r = self.run_hook(self.bash("glab mr create", session), env)
            self.assertEqual(r.returncode, 2)
            self.assertNotIn("sf-writing-style", r.stderr)
            self.load("glab", session=session)
            self.assertEqual(
                self.run_hook(self.bash("glab mr create", session), env).returncode, 0
            )

    def test_absent_skill_does_not_block_available_skill(self):
        self.skill_path("sf-writing-style").rename(self.root / "removed-skill")
        r = self.run_hook(self.bash("gh pr create"))
        self.assertEqual(r.returncode, 2)
        self.assertIn("skipping sf-writing-style", r.stderr)
        self.load("gh")
        self.assertEqual((r := self.run_hook(self.bash("gh pr create"))).returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_missing_all_skills_warns_once(self):
        self.config.rename(self.root / "unlinked-config")
        for index in range(2):
            r = self.run_hook(self.bash("gh pr create"))
            self.assertEqual(r.returncode, 0)
            self.assertEqual(bool(r.stdout), index == 0)

    def test_broken_symlink_is_missing(self):
        path = self.skill_path("gh")
        path.rename(path.with_suffix(".saved"))
        path.symlink_to(self.root / "absent")
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 0)

    def test_project_skill_and_valid_symlink_are_found(self):
        source = self.skill_path("gh")
        target = self.project / ".claude" / "skills" / "gh" / "SKILL.md"
        target.parent.mkdir(parents=True)
        source.rename(target)
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 2)
        source.symlink_to(target)
        self.assertEqual(self.run_hook(self.bash("gh pr list", "new")).returncode, 2)

    def test_disabled_skills_are_skipped(self):
        for value in ("off", "user-invocable-only"):
            (self.config / "settings.json").write_text(
                json.dumps({"skillOverrides": {"gh": value}})
            )
            self.assertEqual(
                self.run_hook(self.bash("gh pr list", value)).returncode, 0
            )

    def test_manual_only_skill_is_skipped(self):
        self.skill_path("gh").write_text(
            "---\ndisable-model-invocation: true\n---\nTest\n"
        )
        self.assertEqual(self.run_hook(self.bash("gh pr list")).returncode, 0)

    def test_commands_and_wrappers(self):
        for index, command in enumerate(
            (
                "gh",
                "  gh pr list",
                "cd /x && gh pr list",
                "FOO=1 gh pr list",
                "env FOO=1 glab issue list",
                "command gh pr list",
                "gh pr list\nglab mr list",
                "cat x | gh pr create",
                "rtk gh pr list",
                "rtk proxy glab mr list",
                "rtk-run gh issue list",
                "rtk-run 'cd /x && gh pr list'",
                f"{self.bin}/gh pr list",
            )
        ):
            with self.subTest(command=command):
                self.assertEqual(
                    self.run_hook(self.bash(command, str(index))).returncode, 2
                )

    def test_prose_commands(self):
        for index, command in enumerate(
            (
                "gh -R owner/repo pr create",
                "glab --repo owner/repo mr update",
                "gh pr comment 1",
                "glab issue note 1",
                "gh pr review 1",
                "gh release edit v1",
                "gh api repos/o/r/issues -f title=test",
                "glab api projects/1/issues --method POST",
                "gh api graphql -f query='mutation { test }'",
                "gh api x --method=PATCH",
            )
        ):
            session = str(index)
            self.load("gh", "glab", session=session)
            r = self.run_hook(self.bash(command, session))
            self.assertEqual(r.returncode, 2, command)
            self.assertIn("sf-writing-style", r.stderr)

    def test_no_writing_requirement_for_reads(self):
        self.load("gh", "glab")
        for command in (
            "gh pr view 1",
            "glab issue list",
            "gh api repos/o/r",
            "gh api x -X GET -f q=test",
            "glab api x --method=GET",
            "gh auth status",
        ):
            self.assertEqual(self.run_hook(self.bash(command)).returncode, 0, command)

    def test_quoted_prose_is_not_a_command(self):
        for command in (
            "git push",
            'git commit -m "use gh; gh pr create"',
            'echo "gh pr create"',
            'echo ";" "gh"',
            'printf "a\\ngh pr create"',
            "rg gh .",
            "github-release-tool run",
        ):
            self.assertEqual(self.run_hook(self.bash(command)).returncode, 0, command)

    def test_absent_cli_is_not_gated(self):
        self.assertEqual(
            self.run_hook(
                self.bash("gh pr create"), {"PATH": str(self.root / "absent")}
            ).returncode,
            0,
        )

    def test_bad_payloads_fail_open(self):
        for payload in (
            None,
            [],
            1,
            {},
            {"session_id": []},
            self.bash(42),
            self.skill([]),
            self.bash("gh 'unterminated"),
            self.bash("gh") | {"cwd": 12},
            self.bash("gh") | {"tool_input": "invalid"},
        ):
            r = self.run_hook(payload)
            self.assertEqual((r.returncode, r.stderr), (0, ""), repr(payload))

    def test_corrupt_state_and_storage_failure_fail_open(self):
        self.load("gh")
        self.state_path().write_text("not json")
        self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 0)
        bad_cache = self.root / "file"
        bad_cache.write_text("not a directory")
        r = self.run_hook(self.bash("gh pr create"), {"XDG_CACHE_HOME": str(bad_cache)})
        self.assertEqual((r.returncode, r.stderr), (0, ""))

    def test_symlink_state_is_not_followed(self):
        target = self.root / "untouched"
        target.write_text("keep")
        path = self.state_path()
        path.parent.mkdir(parents=True)
        path.symlink_to(target)
        self.assertEqual(self.run_hook(self.bash("gh pr create")).returncode, 0)
        self.assertEqual(target.read_text(), "keep")

    def test_missing_session_does_not_share_state(self):
        r = self.run_hook(self.bash("gh pr create") | {"session_id": ""})
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self.state_path().exists())

    def test_unreadable_skill_fails_open(self):
        with (
            patch.object(Path, "read_text", side_effect=PermissionError),
            patch.dict(os.environ, self.env),
            patch("sys.stdin", io.StringIO(json.dumps(self.bash("gh pr create")))),
            patch("sys.stdout", io.StringIO()),
        ):
            self.assertEqual(gate.run_hook(), 0)


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.settings = Path(self.tmp.name) / "settings.json"
        self.cs = gate._settings_lib()
        self.patch = patch.object(self.cs, "settings_path", return_value=self.settings)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.output = patch("sys.stdout", io.StringIO())
        self.output.start()
        self.addCleanup(self.output.stop)

    def test_migrate_enable_repeat_disable_preserves_other_hooks(self):
        other = {
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "other-hook"}],
        }
        old = {"hooks": {"PreToolUse": [other]}, "outputStyle": "Concise"}
        for matcher in ("Skill", "Bash"):
            self.cs.register_hook(
                old, "PreToolUse", matcher, gate.HOOK_COMMAND, gate.SCRIPT_PATH
            )
        self.settings.write_text(json.dumps(old))
        self.assertEqual(gate.cmd_enable(), 0)
        data = json.loads(self.settings.read_text())
        self.assertTrue(gate._configured(data, self.cs))
        self.assertIn(other, data["hooks"]["PreToolUse"])
        self.assertEqual(data["outputStyle"], "Concise")
        saved = self.settings.read_bytes()
        before = list(self.settings.parent.glob("*.bak.*"))
        self.assertEqual(gate.cmd_enable(), 0)
        self.assertEqual(self.settings.read_bytes(), saved)
        self.assertEqual(list(self.settings.parent.glob("*.bak.*")), before)
        self.assertEqual(gate.cmd_disable(), 0)
        self.assertEqual(
            json.loads(self.settings.read_text()),
            {"hooks": {"PreToolUse": [other]}, "outputStyle": "Concise"},
        )

    def test_fresh_and_partial_settings(self):
        self.assertEqual(gate.cmd_enable(), 0)
        data = json.loads(self.settings.read_text())
        self.cs.unregister_hook(data, "PostToolUse", gate.SCRIPT_PATH)
        self.settings.write_text(json.dumps(data))
        gate.cmd_info()
        self.assertIn("partial", sys.stdout.getvalue())
        gate.cmd_enable()
        self.assertTrue(
            gate._configured(json.loads(self.settings.read_text()), self.cs)
        )


if __name__ == "__main__":
    unittest.main()
