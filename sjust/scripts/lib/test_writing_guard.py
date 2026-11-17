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


class CodexFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / "codex"
        self.env = dict(
            os.environ,
            CODEX_HOME=str(self.config),
            HOME=str(self.root / "home"),
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

    def state(self):
        path = next((self.root / "cache/sparkdock/codex-skill-gate").glob("*.json"))
        return json.loads(path.read_text())

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


class CodexGuardTest(CodexFixture):
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

    def test_cut_output_asks_only_for_the_missing_lines(self):
        p = self.skills["sf-writing-style"]
        lines = [f"Rule {i}: " + "x" * 60 for i in range(1500)]
        p.write_text("\n".join(lines) + "\n")
        self.run_hook(self.payload())
        self.read("\n".join(lines[:400] + ["[... output cut ...]"] + lines[1100:]))
        self.assertNotIn("sf-writing-style", self.state()["loaded"])
        notice = codex.read_notice([p], self.state(), "")
        ranges = [c.split("'")[1] for c in notice.split("sed -n ")[1:]]
        self.assertEqual(ranges[0].split(",")[0], "401")
        self.assertEqual(ranges[-1].split(",")[1], "1100p")
        for r in ranges:
            a, b = (int(n) for n in r.rstrip("p").split(","))
            self.assertLessEqual(len("\n".join(lines[a - 1 : b])), codex.CHUNK_BYTES)
            self.read("\n".join(lines[a - 1 : b]))
        self.assertIn("sf-writing-style", self.state()["loaded"])

    def test_one_skill_read_does_not_count_for_another(self):
        self.run_hook(self.payload())
        glab = self.skills["glab"]
        self.run_hook(
            self.payload()
            | {
                "hook_event_name": "PostToolUse",
                "tool_name": "Bash",
                "tool_input": {"command": f"cat {glab}"},
                "tool_response": {
                    "output": self.skills["sf-writing-style"].read_text()
                },
            }
        )
        self.assertNotIn("sf-writing-style", self.state()["loaded"])

    def test_skills_in_agents_folders_are_found(self):
        moved = self.skills["sf-writing-style"]
        for root in (self.root / "home", self.root):
            with self.subTest(root=root):
                path = root / ".agents/skills/sf-writing-style/SKILL.md"
                path.parent.mkdir(parents=True, exist_ok=True)
                moved.rename(path)
                r = self.run_hook(self.payload() | {"session_id": str(root)})
                self.assertEqual(r.returncode, 2)
                self.assertIn(str(path), r.stderr)
                moved = path

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


class CodexReferenceTest(CodexFixture):
    def setUp(self):
        super().setUp()
        self.refs = {}
        for name, relative in guard.REFERENCES.items():
            path = self.skills["sf-writing-style"].parent / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"Full {name} reference.\nSecond line.\n")
            self.refs[name] = path
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for cli in ("gh", "glab"):
            stub = bin_dir / cli
            stub.write_text("#!/bin/sh\nexit 0\n")
            stub.chmod(0o755)
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]

    def cat(self, name, body=None):
        path = self.refs[name]
        return self.run_hook(
            self.payload()
            | {
                "hook_event_name": "PostToolUse",
                "tool_name": "Bash",
                "tool_input": {"command": f"cat {path}"},
                "tool_response": {
                    "output": path.read_text() if body is None else body,
                    "exit_code": 0,
                },
            }
        )

    def test_publishing_waits_for_full_reference_reads(self):
        self.run_hook(self.payload())
        self.read()
        r = self.run_hook(self.payload())
        self.assertEqual(r.returncode, 2)
        self.assertIn(str(self.refs["platforms"]), r.stderr)
        self.cat("platforms", body="Full platforms")
        r = self.run_hook(self.payload())
        self.assertEqual(r.returncode, 2, "a partial read must not count")
        self.cat("platforms")
        self.assertEqual(self.run_hook(self.payload()).returncode, 0)

    def test_pr_description_needs_the_pr_reference(self):
        self.run_hook(self.payload())
        self.read()
        self.cat("platforms")
        pr = self.payload("Bash") | {
            "tool_input": {"command": "gh pr create --body 'Add a filter.'"}
        }
        for skill in ("gh",):
            p = self.skills[skill]
            self.run_hook(
                self.payload()
                | {
                    "hook_event_name": "PostToolUse",
                    "tool_name": "Bash",
                    "tool_input": {"command": f"cat {p}"},
                    "tool_response": {"output": p.read_text()},
                }
            )
        r = self.run_hook(pr)
        self.assertEqual(r.returncode, 2)
        self.assertIn(str(self.refs["pr-mr-descriptions"]), r.stderr)
        self.cat("pr-mr-descriptions")
        self.assertEqual(self.run_hook(pr).returncode, 0)

    def test_unconfirmed_reference_stops_blocking_after_two_requests(self):
        self.run_hook(self.payload())
        self.read()
        for _ in range(2):
            self.assertEqual(self.run_hook(self.payload()).returncode, 2)
        r = self.run_hook(self.payload())
        self.assertEqual(r.returncode, 0)
        self.assertIn("full read not confirmed", r.stdout)


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
    def test_heredoc_descriptions_are_classified(self):
        cases = {
            "gh pr create --title t --body \"$(cat <<'EOF'\nBody\nEOF\n)\"": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            'GL_USERNAME=$(glab api user | jq -r .username)\nglab mr create --draft \\\n  --description "$(cat <<EOF\nBody\nEOF\n)"': (
                {"glab", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            'cd x && glab issue note 4 -m "$(cat <<EOF\nhi\nEOF\n)"': (
                {"glab", "sf-writing-style"},
                {"platforms"},
            ),
            "echo glab is great <<EOF\nx\nEOF": (set(), set()),
            "env gh pr create --body-file - <<'EOF'\nBody\nEOF": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            "rtk proxy gh pr create --body-file - <<'EOF'\nBody\nEOF": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            "cat <<'EOF' | gh pr create --body-file -\nBody\nEOF": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            "cat > notes.md <<'EOF'\ngh pr create --body example\nEOF": (set(), set()),
            "echo \"example; gh pr create --body example\" <<'EOF'\nignored\nEOF": (
                set(),
                set(),
            ),
            "gh api --hostname github.com --method POST repos/o/r/pulls -f head=feature"
            " -f base=master -f maintainer_can_modify=true -f title=Example"
            " --input - <<'EOF'\n{}\nEOF": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            "gh api -H 'Accept: application/vnd.github+json' --method PATCH"
            " repos/o/r/pulls/1 -f body='Update the filter.'": (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            "gh api repos/o/r/pulls/42/comments -f body='Review comment'": (
                {"gh", "sf-writing-style"},
                {"platforms"},
            ),
            "glab api projects/1/merge_requests/42/notes -f body='Review comment'": (
                {"glab", "sf-writing-style"},
                {"platforms"},
            ),
            # A quoted header keeps its spaces, so the endpoint is still found.
            "gh api -H 'Accept: application/vnd.github+json' --method PATCH"
            ' repos/o/r/pulls/1 --input - <<\'EOF\'\n{"body": "x"}\nEOF': (
                {"gh", "sf-writing-style"},
                {"platforms", "pr-mr-descriptions"},
            ),
            # A comment never runs.
            "# example; gh pr create --body example\ncat > notes.md <<'EOF'\nx\nEOF": (
                set(),
                set(),
            ),
            "cat > notes.md <<'EOF' # gh pr create --body example\nx\nEOF": (
                set(),
                set(),
            ),
        }
        with patch.object(guard.shutil, "which", return_value="/usr/bin/cli"):
            for command, (needed, references) in cases.items():
                with self.subTest(command=command):
                    payload = {"tool_name": "Bash", "tool_input": {"command": command}}
                    self.assertEqual(guard.requirements(payload), needed)
                    self.assertEqual(guard.reference_requirements(payload), references)

    def test_graphql_description_mutations_need_the_pr_reference(self):
        cases = {
            'mutation { updatePullRequest(input: {pullRequestId: "PR_x", body: "New"}) { pullRequest { id } } }': {
                "platforms",
                "pr-mr-descriptions",
            },
            'mutation { createPullRequest(input: {repositoryId: "R", title: "T", body: "B"}) { pullRequest { id } } }': {
                "platforms",
                "pr-mr-descriptions",
            },
            'mutation { mergeRequestUpdate(input: {projectPath: "g/p", iid: "1", description: "D"}) { errors } }': {
                "platforms",
                "pr-mr-descriptions",
            },
            'mutation { mergeRequestCreate(input: {projectPath: "g/p", title: "T", description: "D"}) { errors } }': {
                "platforms",
                "pr-mr-descriptions",
            },
            'mutation { addComment(input: {subjectId: "PR_x", body: "Thanks"}) { clientMutationId } }': {
                "platforms"
            },
            'mutation { createNote(input: {noteableId: "gid://gitlab/MergeRequest/1", body: "Done"}) { errors } }': {
                "platforms"
            },
        }
        with patch.object(guard.shutil, "which", return_value="/usr/bin/cli"):
            for query, references in cases.items():
                for command in (
                    f"gh api graphql -f query='{query}'",
                    f"gh api graphql -f query='{query}' <<'EOF'\nx\nEOF",
                ):
                    with self.subTest(command=command):
                        payload = {
                            "tool_name": "Bash",
                            "tool_input": {"command": command},
                        }
                        self.assertEqual(
                            guard.reference_requirements(payload), references
                        )

    def test_api_calls_without_prose_fields_are_not_prose(self):
        for args in (
            ["api", "-X", "POST", "projects/1/pipeline", "-f", "ref=main"],
            ["api", "repos/o/r/issues/1/labels", "-f", "labels[]=bug"],
        ):
            with self.subTest(args=args):
                self.assertFalse(guard._writes_prose(args))
        self.assertTrue(
            guard._writes_prose(
                ["api", "projects/1/merge_requests/2", "-f", "description=x"]
            )
        )

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
