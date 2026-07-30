"""Integration tests for global optional skill category management."""

from __future__ import annotations

import hashlib
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


class SkillCategoryIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.home = self.root / "home"
        self.upstream = self.root / "upstream"
        self.home.mkdir()
        self.upstream.mkdir()

        self.write_skill("system", "core")
        self.write_skill("angular", "angular-developer")
        self.write_skill("angular", "angular-new-app")
        self.write_skill("drupal", "drupal-development")
        (self.upstream / "config").mkdir()
        (self.upstream / "config" / "catalog.json").write_text(
            json.dumps(
                {
                    "skills": {
                        "core": {"description": "Required core skill"},
                        "angular-developer": {"description": "Angular development"},
                        "angular-new-app": {
                            "description": "Create Angular applications"
                        },
                        "drupal-development": {"description": "Drupal development"},
                    },
                    "agents": {},
                }
            )
            + "\n"
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
            }
        )

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

    def read_manifest(self) -> dict[str, object]:
        manifest_path = self.home / ".cache" / "sparkdock" / "sf-skills-manifest.json"
        return json.loads(manifest_path.read_text())

    def read_config(self) -> dict[str, object]:
        config_path = self.home / ".config" / "sparkdock" / "harness.json"
        return json.loads(config_path.read_text())

    def test_default_sync_keeps_optional_categories_disabled(self) -> None:
        self.run_sync()

        self.assertTrue((self.home / ".agents" / "skills" / "core").is_dir())
        self.assertFalse(
            (self.home / ".agents" / "skills" / "angular-developer").exists()
        )
        manifest = self.read_manifest()
        self.assertEqual(3, manifest["version"])
        self.assertEqual(["core"], sorted(manifest["skills"]))
        self.assertNotIn("optional_skills", manifest)

        result = self.run_sync("category", "list")
        output = ANSI_ESCAPE.sub("", result.stdout).replace("│", " ")
        self.assertTrue(output.startswith("\nSkill Categories"), output)
        self.assertRegex(output, r"angular\s+optional\s+disabled\s+2")
        self.assertRegex(output, r"drupal\s+optional\s+disabled\s+1")
        self.assertRegex(output, r"system\s+required\s+always\s+1")
        self.assertIn("sf-harness-category enable <category>", output)

    def test_status_lists_unmanaged_skill_paths(self) -> None:
        self.run_sync()
        skills_dir = self.home / ".agents" / "skills"
        unmanaged_skill = skills_dir / "custom-skill"
        unmanaged_skill.mkdir()
        (unmanaged_skill / "SKILL.md").write_text("---\nname: custom-skill\n---\n")

        external_skill = self.home / ".external" / "linked-skill"
        external_skill.mkdir(parents=True)
        (external_skill / "SKILL.md").write_text("---\nname: linked-skill\n---\n")
        (skills_dir / "linked-skill").symlink_to(
            external_skill, target_is_directory=True
        )
        (self.home / ".claude" / "skills" / "linked-skill").symlink_to(
            external_skill, target_is_directory=True
        )

        status_environment = self.environment | {"SPARKDOCK_SKIP_FETCH": "true"}
        status = subprocess.run(
            [str(STATUS_SCRIPT)],
            env=status_environment,
            check=True,
            text=True,
            capture_output=True,
        )
        output = ANSI_ESCAPE.sub("", status.stdout + status.stderr).replace("│", " ")
        self.assertIn("Unmanaged skills", output)
        self.assertRegex(
            output,
            r"custom-skill\s+-\s+~/.agents/skills/custom-skill\s+-\s+-\s+ok",
        )
        self.assertRegex(
            output,
            r"linked-skill\s+-\s+~/.agents/skills/linked-skill"
            r"\s+->\s+~/.external/linked-skill\s+ok\s+-\s+ok",
        )

    def test_enable_and_disable_are_idempotent(self) -> None:
        self.run_sync("category", "enable", "angular")
        self.run_sync("category", "enable", "angular")

        self.assertEqual(["angular"], self.read_config()["enabled_skill_categories"])
        manifest = self.read_manifest()
        self.assertEqual(
            ["angular/angular-developer", "angular/angular-new-app"],
            sorted(manifest["optional_skills"]),
        )
        for skill_name in ("angular-developer", "angular-new-app"):
            self.assertTrue((self.home / ".agents" / "skills" / skill_name).is_dir())
            self.assertTrue(
                (self.home / ".claude" / "skills" / skill_name).is_symlink()
            )
            self.assertTrue(
                (self.home / ".copilot" / "skills" / skill_name).is_symlink()
            )

        self.run_sync("category", "disable", "angular")
        self.run_sync("category", "disable", "angular")

        self.assertEqual([], self.read_config()["enabled_skill_categories"])
        self.assertEqual({}, self.read_manifest()["optional_skills"])
        self.assertFalse(
            (self.home / ".agents" / "skills" / "angular-developer").exists()
        )

    def test_disable_preserves_local_modifications_without_force(self) -> None:
        self.run_sync("category", "enable", "angular")
        skill_file = self.home / ".agents" / "skills" / "angular-developer" / "SKILL.md"
        skill_file.write_text(skill_file.read_text() + "\nLocal change\n")

        result = self.run_sync("category", "disable", "angular")
        self.assertIn("locally modified", result.stderr)
        self.assertTrue(skill_file.exists())
        self.assertIn(
            "angular/angular-developer", self.read_manifest()["optional_skills"]
        )

        status_environment = self.environment | {"SPARKDOCK_SKIP_FETCH": "true"}
        status = subprocess.run(
            [str(STATUS_SCRIPT)],
            env=status_environment,
            check=True,
            text=True,
            capture_output=True,
        )
        output = ANSI_ESCAPE.sub("", status.stdout + status.stderr)
        self.assertRegex(
            output,
            r"angular\s*│\s*optional\s*│\s*disabled\s*│\s*1/2\s*│\s*preserved conflict",
        )
        self.assertIn("Skills: angular (disabled, preserved)", output)

        self.run_sync("category", "disable", "angular", "--force")
        self.assertFalse(skill_file.exists())
        self.assertEqual({}, self.read_manifest()["optional_skills"])

    def test_invalid_actions_do_not_change_configuration(self) -> None:
        unknown = self.run_sync("category", "enable", "unknown", check=False)
        self.assertEqual(2, unknown.returncode)
        self.assertFalse(
            (self.home / ".config" / "sparkdock" / "harness.json").exists()
        )

        required = self.run_sync("category", "disable", "system", check=False)
        self.assertEqual(2, required.returncode)
        self.assertFalse(
            (self.home / ".config" / "sparkdock" / "harness.json").exists()
        )

    def test_name_collision_fails_before_configuration_change(self) -> None:
        self.write_skill("react", "core")
        self.git("add", ".")
        self.git("commit", "-m", "add collision")

        result = self.run_sync("category", "enable", "react", check=False)

        self.assertEqual(1, result.returncode)
        self.assertIn("Skill name collision", result.stderr)
        self.assertFalse(
            (self.home / ".config" / "sparkdock" / "harness.json").exists()
        )
        self.assertFalse((self.home / ".agents" / "skills").exists())

    def test_v2_system_manifest_is_preserved_during_migration(self) -> None:
        source = self.upstream / "skills" / "system" / "core" / "SKILL.md"
        target = self.home / ".agents" / "skills" / "core" / "SKILL.md"
        target.parent.mkdir(parents=True)
        target.write_text(source.read_text())
        sha256 = hashlib.sha256(source.read_bytes()).hexdigest()
        manifest_path = self.home / ".cache" / "sparkdock" / "sf-skills-manifest.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        system_entry = {
            "sha256": sha256,
            "installed_at": "2026-01-01T00:00:00Z",
            "source_commit": "legacy",
        }
        manifest_path.write_text(
            json.dumps({"version": 2, "skills": {"core": system_entry}, "agents": {}})
            + "\n"
        )

        self.run_sync("category", "enable", "angular")

        manifest = self.read_manifest()
        self.assertEqual(3, manifest["version"])
        self.assertEqual(system_entry, manifest["skills"]["core"])
        self.assertEqual(
            ["angular/angular-developer", "angular/angular-new-app"],
            sorted(manifest["optional_skills"]),
        )


if __name__ == "__main__":
    unittest.main()
