"""Integration tests for per-user skill enable/disable.

The scripts under test are hyphenated and cannot be imported, so they are driven
as subprocesses against a temporary HOME, the same way test_skill_categories.py
and test_claude_gh_gate.py do.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SYNC_SCRIPT = REPO_ROOT / "bin" / "sparkdock-agents-sync"
STATUS_SCRIPT = REPO_ROOT / "bin" / "sparkdock-agents-status"
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


class SkillToggleIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.home = self.root / "home"
        self.upstream = self.root / "upstream"
        self.home.mkdir()
        self.upstream.mkdir()

        self.write_skill("system", "core")
        self.write_skill("system", "gh")
        self.write_skill("angular", "angular-developer")
        (self.upstream / "config").mkdir()
        (self.upstream / "config" / "catalog.json").write_text(
            json.dumps({"skills": {}, "agents": {}}) + "\n"
        )
        self.git("init", "-b", "main")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "user.name", "Sparkdock Tests")
        self.git("add", ".")
        self.git("commit", "-m", "test fixture")
        cache = self.home / ".cache" / "sparkdock" / "agent-skills"
        cache.parent.mkdir(parents=True)
        subprocess.run(
            ["git", "clone", str(self.upstream), str(cache)],
            check=True,
            text=True,
            capture_output=True,
        )

        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.home),
                "TERM": "dumb",
                "XDG_CONFIG_HOME": str(self.home / ".config"),
                "SPARKDOCK_AGENTS_UPSTREAM_REPO": str(self.upstream),
            }
        )

    # --- helpers ---------------------------------------------------------

    def write_skill(self, category: str, name: str) -> None:
        skill_dir = self.upstream / "skills" / category / name
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Test skill\n---\n"
        )

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.upstream,
            check=True,
            text=True,
            capture_output=True,
        )

    def run_sync(
        self, *arguments: str, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SYNC_SCRIPT), *arguments],
            env=self.environment,
            check=check,
            text=True,
            capture_output=True,
        )

    def run_status(self) -> str:
        status = subprocess.run(
            [str(STATUS_SCRIPT)],
            env=self.environment | {"SPARKDOCK_SKIP_FETCH": "true"},
            check=True,
            text=True,
            capture_output=True,
        )
        return ANSI_ESCAPE.sub("", status.stdout + status.stderr).replace("│", " ")

    def read_manifest(self) -> dict[str, object]:
        manifest_path = self.home / ".cache" / "sparkdock" / "sf-skills-manifest.json"
        return json.loads(manifest_path.read_text())

    @property
    def config_path(self) -> Path:
        return self.home / ".config" / "sparkdock" / "harness.json"

    def read_config(self) -> dict[str, object]:
        return json.loads(self.config_path.read_text())

    def tool_link(self, tool: str, skill: str) -> Path:
        directories = {
            "claude": self.home / ".claude" / "skills",
            "copilot": self.home / ".copilot" / "skills",
        }
        return directories[tool] / skill

    # --- tests -----------------------------------------------------------

    def test_disable_unlinks_tools_but_keeps_the_installed_skill(self) -> None:
        self.run_sync()
        self.assertTrue(self.tool_link("claude", "core").is_symlink())

        self.run_sync("skill", "disable", "core")

        self.assertFalse(self.tool_link("claude", "core").exists())
        self.assertFalse(self.tool_link("copilot", "core").exists())
        self.assertTrue(
            (self.home / ".agents" / "skills" / "core" / "SKILL.md").is_file()
        )
        self.assertIn("core", self.read_manifest()["skills"])
        self.assertEqual(["core"], self.read_config()["disabled_skills"])
        # Untouched skills keep their links.
        self.assertTrue(self.tool_link("claude", "gh").is_symlink())

    def test_full_force_sync_does_not_relink_a_disabled_skill(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        self.run_sync("--force")

        self.assertFalse(self.tool_link("claude", "core").exists())
        self.assertFalse(self.tool_link("copilot", "core").exists())
        self.assertTrue((self.home / ".agents" / "skills" / "core").is_dir())

    def test_enable_restores_the_tool_symlinks(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        self.run_sync("skill", "enable", "core")

        expected = str(self.home / ".agents" / "skills" / "core")
        self.assertEqual(expected, os.readlink(self.tool_link("claude", "core")))
        self.assertEqual(expected, os.readlink(self.tool_link("copilot", "core")))
        self.assertEqual([], self.read_config()["disabled_skills"])

    def test_optional_category_skill_can_be_disabled(self) -> None:
        self.run_sync("category", "enable", "angular")
        self.assertTrue(self.tool_link("claude", "angular-developer").is_symlink())

        self.run_sync("skill", "disable", "angular-developer")

        self.assertFalse(self.tool_link("claude", "angular-developer").exists())
        self.assertIn(
            "angular/angular-developer", self.read_manifest()["optional_skills"]
        )

    def test_unknown_skill_is_rejected_without_writing_the_config(self) -> None:
        self.run_sync()

        result = self.run_sync("skill", "disable", "nope", check=False)

        self.assertEqual(2, result.returncode)
        self.assertIn("Unknown skill: nope", result.stdout + result.stderr)
        self.assertFalse(self.config_path.exists())

    def test_unmanaged_skill_is_rejected(self) -> None:
        self.run_sync()
        unmanaged = self.home / ".agents" / "skills" / "custom-skill"
        unmanaged.mkdir()
        (unmanaged / "SKILL.md").write_text("---\nname: custom-skill\n---\n")

        result = self.run_sync("skill", "disable", "custom-skill", check=False)

        self.assertEqual(2, result.returncode)
        self.assertIn(
            "Not a sparkdock-managed skill: custom-skill", result.stdout + result.stderr
        )
        self.assertFalse(self.config_path.exists())

    def test_force_is_rejected_on_disable(self) -> None:
        self.run_sync()

        result = self.run_sync("skill", "disable", "core", "--force", check=False)

        self.assertEqual(2, result.returncode)
        self.assertIn("Force is not supported", result.stdout + result.stderr)
        self.assertFalse(self.config_path.exists())

    def test_disable_is_idempotent(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")
        self.run_sync("skill", "disable", "core")
        self.assertEqual(["core"], self.read_config()["disabled_skills"])

        self.run_sync("skill", "enable", "core")
        self.run_sync("skill", "enable", "core")
        self.assertEqual([], self.read_config()["disabled_skills"])

    def test_skill_list_reports_owner_and_state(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        output = ANSI_ESCAPE.sub("", self.run_sync("skill", "list").stdout)
        output = output.replace("│", " ")

        self.assertRegex(output, r"core\s+system\s+disabled")
        self.assertRegex(output, r"gh\s+system\s+enabled")

    def test_status_marks_a_disabled_skill_without_reporting_an_issue(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        output = self.run_status()

        self.assertRegex(
            output, r"core\s+managed\s+disabled \(unlinked\)\s+off\s+off\s+native"
        )
        self.assertNotIn("symlink missing", output)
        self.assertNotIn("can't discover these skills", output)

    def test_a_stale_disabled_entry_is_listed_and_can_be_cleared(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        # The skill disappears upstream, so the sync removes it and its manifest
        # entry, leaving only the config entry behind.
        (self.upstream / "skills" / "system" / "core" / "SKILL.md").unlink()
        (self.upstream / "skills" / "system" / "core").rmdir()
        self.git("add", "-A")
        self.git("commit", "-m", "drop core")
        self.run_sync()
        self.assertNotIn("core", self.read_manifest()["skills"])

        output = ANSI_ESCAPE.sub("", self.run_sync("skill", "list").stdout)
        self.assertRegex(output.replace("│", " "), r"core\s+unknown\s+disabled")

        self.run_sync("skill", "enable", "core")
        self.assertEqual([], self.read_config()["disabled_skills"])

    def test_disable_keeps_a_user_alias_that_only_shares_the_name(self) -> None:
        self.run_sync()
        # A hand-made alias in the tool directory: named after one managed skill,
        # pointing at a different one. Disabling "core" must not delete it.
        alias = self.tool_link("claude", "core")
        alias.unlink()
        alias.symlink_to(
            self.home / ".agents" / "skills" / "gh", target_is_directory=True
        )

        self.run_sync("skill", "disable", "core")

        self.assertTrue(alias.is_symlink(), "user alias was removed")
        self.assertEqual(
            str(self.home / ".agents" / "skills" / "gh"), os.readlink(alias)
        )

    def test_the_writer_refuses_to_rewrite_a_config_the_reader_rejects(self) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        original = json.dumps({"version": 1, "disabled_skills": ["Bad Name"]}) + "\n"
        self.config_path.write_text(original)

        script = (
            f'set -euo pipefail; source "{REPO_ROOT}/bin/common/skill-categories.sh"; '
            "set_skill_disabled_state disable core"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            env=self.environment,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(original, self.config_path.read_text())

    def test_help_is_reachable_by_every_spelling(self) -> None:
        for spelling in ("help", "-h", "--help"):
            with self.subTest(spelling=spelling):
                result = self.run_sync("skill", spelling)
                self.assertIn("skill <enable|disable> <name>", result.stdout)
                self.assertIn("stays installed", result.stdout)

    def test_an_unknown_action_exits_two_and_shows_the_help(self) -> None:
        result = self.run_sync("skill", "bogus", check=False)

        self.assertEqual(2, result.returncode)
        output = result.stdout + result.stderr
        self.assertIn("must be list, enable, disable, or help", output)
        self.assertIn("skill <enable|disable> <name>", output)

    def test_disabled_state_is_rendered_in_the_attention_colour(self) -> None:
        self.run_sync()
        self.run_sync("skill", "disable", "core")

        # 220 is the repo's "attention, not broken" tier, shared with
        # render_table() in sparkdock-agents-status.
        listing = subprocess.run(
            [str(SYNC_SCRIPT), "skill", "list"],
            env=self.environment | {"CLICOLOR_FORCE": "1"},
            check=True,
            text=True,
            capture_output=True,
        )
        self.assertIn("\x1b[38;5;220mdisabled\x1b[0m", listing.stdout)

        status = subprocess.run(
            [str(STATUS_SCRIPT)],
            env=self.environment
            | {"SPARKDOCK_SKIP_FETCH": "true", "CLICOLOR_FORCE": "1"},
            check=True,
            text=True,
            capture_output=True,
        )
        self.assertIn("\x1b[38;5;220mdisabled (unlinked)\x1b[0m", status.stdout)

    def test_a_malformed_disabled_skills_value_fails_closed(self) -> None:
        self.run_sync()
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        self.config_path.write_text(
            json.dumps({"version": 1, "disabled_skills": ["Bad Name"]}) + "\n"
        )

        listing = self.run_sync("skill", "list", check=False)
        self.assertNotEqual(0, listing.returncode)
        self.assertIn("Invalid harness config", listing.stdout + listing.stderr)

        # A full sync must abort too, rather than silently treating the broken
        # config as "nothing is disabled" and re-linking everything.
        sync = self.run_sync(check=False)
        self.assertNotEqual(0, sync.returncode)
        self.assertIn("Invalid harness config", sync.stdout + sync.stderr)


if __name__ == "__main__":
    unittest.main()
