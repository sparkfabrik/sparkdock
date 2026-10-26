"""Tests for bin/sparkdock-check-updates, the source every status row reads.

The tests run the real script. Git checks use local repositories as remotes, and
Homebrew checks use a stub brew that records each call and whether
HOMEBREW_NO_AUTO_UPDATE was set.

Run with `just test-python` (or `python3 -m unittest discover -s sjust/scripts/lib`).
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from typing import NamedTuple

SCRIPT = Path(__file__).resolve().parents[3] / "bin" / "sparkdock-check-updates"
UTILS = SCRIPT.parent / "common" / "utils.sh"

STUB_BREW = """#!/usr/bin/env bash
printf '%s|%s\\n' "$*" "${HOMEBREW_NO_AUTO_UPDATE:-}" >>"${STUB_LOG}"
case "$1 ${2:-}" in
    "update --quiet") exit "${STUB_UPDATE_RC:-0}" ;;
    "outdated --formula") printf '%s' "${STUB_FORMULAE:-}"; exit "${STUB_FORMULAE_RC:-0}" ;;
    "outdated --cask") printf '%s' "${STUB_CASKS:-}"; exit "${STUB_CASKS_RC:-0}" ;;
    "vulns --help") exit "${STUB_VULNS_HELP_RC:-0}" ;;
    "vulns --json") printf '%s' "${STUB_VULNS_JSON:-}"; exit 1 ;;
esac
exit 1
"""


class GitCheck(NamedTuple):
    subsystem: str
    seed: str
    branch: str
    checkout: Path


# CLI subsystem name and the label its update notice starts with.
CLIS = {"timetracker": "Timetracker", "engram": "Engram"}

GIT_IDENTITY = {
    "GIT_AUTHOR_NAME": "Test",
    "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "Test",
    "GIT_COMMITTER_EMAIL": "test@example.com",
}


class CheckUpdatesTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.home = self.dir / "home"
        self.root = self.dir / "sparkdock"
        self.home.mkdir()
        self.root.mkdir()
        self.log = self.dir / "brew.log"
        self.log.touch()
        self.brew = self.dir / "brew"
        self.brew.write_text(STUB_BREW)
        self.brew.chmod(0o755)

    def env(self, **extra):
        env = os.environ.copy()
        env.pop("HOMEBREW_NO_AUTO_UPDATE", None)
        env.update(GIT_IDENTITY)
        env.update(
            HOME=str(self.home),
            SPARKDOCK_CHECK_ROOT=str(self.root),
            SPARKDOCK_CHECK_BREW=str(self.brew),
            STUB_LOG=str(self.log),
        )
        env.update(extra)
        return {key: value for key, value in env.items() if value is not None}

    def run_check(self, *args, **extra):
        result = subprocess.run(
            ["bash", str(SCRIPT), *args],
            capture_output=True,
            text=True,
            check=False,
            env=self.env(**extra),
        )
        return result.returncode, result.stdout

    def brew_calls(self):
        """Return (args, HOMEBREW_NO_AUTO_UPDATE) for every stub brew call."""
        return [tuple(line.split("|", 1)) for line in self.log.read_text().splitlines()]

    def git(self, cwd, *args):
        return subprocess.run(
            ["git", *args],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
            env=self.env(),
        ).stdout.strip()

    def record_provisioning(self, check=True):
        """Run the helper a successful sparkdock run ends with, on the sparkdock root."""
        return subprocess.run(
            [
                "bash",
                "-euo",
                "pipefail",
                "-c",
                'source "$1"; record_successful_provisioning "$2"',
                "_",
                str(UTILS),
                str(self.root),
            ],
            check=check,
            capture_output=True,
            env=self.env(),
        )

    def make_remote(self, name, branch):
        """Create a bare remote with one commit on branch, and return its path."""
        remote = self.dir / f"{name}.git"
        seed = self.dir / f"{name}-seed"
        self.git(self.dir, "init", "-q", "--bare", "-b", branch, str(remote))
        self.git(self.dir, "init", "-q", "-b", branch, str(seed))
        self.git(seed, "commit", "-q", "--allow-empty", "-m", "first")
        self.git(seed, "remote", "add", "origin", str(remote))
        self.git(seed, "push", "-q", "origin", branch)
        return remote

    def push_new_commit(self, name, branch):
        seed = self.dir / f"{name}-seed"
        self.git(seed, "commit", "-q", "--allow-empty", "-m", "second")
        self.git(seed, "push", "-q", "origin", branch)

    def clone(self, remote, dest):
        self.git(self.dir, "clone", "-q", str(remote), str(dest))


class ExitContractTest(CheckUpdatesTestCase):
    def test_unknown_subsystem_exits_2_with_usage(self):
        rc, out = self.run_check("nope")
        self.assertEqual(rc, 2)
        self.assertIn("Usage:", out)

    def test_help_lists_brew_and_failed_checks(self):
        rc, out = self.run_check("--help")
        self.assertEqual(rc, 0)
        self.assertIn("brew", out)
        self.assertIn("2  Check failed", out)
        self.assertIn("4  Last update did not complete", out)


class ProvisioningRecordTest(CheckUpdatesTestCase):
    def test_copy_without_git_records_only_the_time(self):
        self.assertEqual(self.record_provisioning(check=False).returncode, 0)
        time.strptime(
            (self.root / ".last_update").read_text().strip(), "%Y-%m-%d %H:%M:%S"
        )
        self.assertFalse((self.root / ".last_provisioned").exists())


class GitSubsystemsTest(CheckUpdatesTestCase):
    def setUp(self):
        super().setUp()
        self.sparkdock_remote = self.make_remote("sparkdock", "master")
        self.root.rmdir()
        self.clone(self.sparkdock_remote, self.root)
        self.proxy_remote = self.make_remote("proxy", "main")
        self.clone(self.proxy_remote, self.root / "http-proxy")
        self.skills_remote = self.make_remote("skills", "main")
        self.skills = self.home / ".cache" / "sparkdock" / "agent-skills"
        self.skills.parent.mkdir(parents=True)
        self.clone(self.skills_remote, self.skills)
        self.record_provisioning()
        # Written by the last task of the http-proxy Ansible tag.
        proxy_head = self.git(self.root / "http-proxy", "rev-parse", "HEAD")
        self.proxy_provisioned().write_text(proxy_head + "\n")

    def provisioned(self):
        return self.root / ".last_provisioned"

    def proxy_provisioned(self):
        return self.root / ".last_provisioned_http_proxy"

    def break_remote(self, checkout):
        self.git(checkout, "remote", "set-url", "origin", str(self.dir / "missing.git"))

    def test_sparkdock_dev_checkout_skips_check(self):
        if SCRIPT.parents[1] == Path("/opt/sparkdock"):
            self.skipTest("the script runs from the installed checkout")
        self.assertEqual(self.run_check("sparkdock", SPARKDOCK_CHECK_ROOT=None)[0], 1)

    def git_checks(self):
        """Each git subsystem with its remote seed, branch and checkout."""
        return [
            GitCheck("sparkdock", "sparkdock", "master", self.root),
            GitCheck("http-proxy", "proxy", "main", self.root / "http-proxy"),
            GitCheck("agents", "skills", "main", self.skills),
        ]

    def test_current(self):
        for subsystem, *_ in self.git_checks():
            with self.subTest(subsystem=subsystem):
                self.assertEqual(self.run_check(subsystem)[0], 1)

    def test_new_commits(self):
        for subsystem, seed, branch, _ in self.git_checks():
            with self.subTest(subsystem=subsystem):
                self.push_new_commit(seed, branch)
                self.assertEqual(self.run_check(subsystem)[0], 0)

    def test_fetch_fails(self):
        for subsystem, _, _, checkout in self.git_checks():
            with self.subTest(subsystem=subsystem):
                self.break_remote(checkout)
                self.assertEqual(self.run_check(subsystem)[0], 2)

    def record_checks(self):
        """Each git check with a provisioning record, and the command to run again."""
        records = {
            "sparkdock": (self.provisioned(), "sparkdock"),
            "http-proxy": (self.proxy_provisioned(), "sjust http-proxy-install-update"),
        }
        return [
            (check, *records[check.subsystem])
            for check in self.git_checks()
            if check.subsystem in records
        ]

    def test_record_holds_head(self):
        head = self.git(self.root, "rev-parse", "HEAD")
        self.assertEqual(self.provisioned().read_text().strip(), head)
        last_update = (self.root / ".last_update").read_text().strip()
        time.strptime(last_update, "%Y-%m-%d %H:%M:%S")

    def test_record_missing(self):
        for check, record, rerun in self.record_checks():
            with self.subTest(subsystem=check.subsystem):
                record.unlink()
                rc, out = self.run_check(check.subsystem)
                self.assertEqual(rc, 4)
                self.assertIn(f"run {rerun} again", out)

    def test_record_older(self):
        for check, record, _ in self.record_checks():
            with self.subTest(subsystem=check.subsystem):
                record.write_text("0" * 40 + "\n")
                self.assertEqual(self.run_check(check.subsystem)[0], 4)

    def test_new_commits_win_over_record(self):
        for check, record, _ in self.record_checks():
            with self.subTest(subsystem=check.subsystem):
                record.unlink()
                self.push_new_commit(check.seed, check.branch)
                self.assertEqual(self.run_check(check.subsystem)[0], 0)

    def test_fetch_fails_with_incomplete_record(self):
        for check, record, _ in self.record_checks():
            with self.subTest(subsystem=check.subsystem):
                record.unlink()
                self.break_remote(check.checkout)
                self.assertEqual(self.run_check(check.subsystem)[0], 2)

    def test_http_proxy_not_installed(self):
        shutil.rmtree(self.root / "http-proxy")
        self.assertEqual(self.run_check("http-proxy")[0], 1)

    def test_agents_not_synced(self):
        shutil.rmtree(self.skills)
        self.assertEqual(self.run_check("agents")[0], 3)

    def test_agents_cache_without_git(self):
        shutil.rmtree(self.skills / ".git")
        self.assertEqual(self.run_check("agents")[0], 3)

    def test_agents_without_origin_head_falls_back_to_main(self):
        self.git(self.skills, "remote", "set-head", "origin", "-d")
        self.push_new_commit("skills", "main")
        self.assertEqual(self.run_check("agents")[0], 0)


class BrewSubsystemTest(CheckUpdatesTestCase):
    def test_outdated_packages(self):
        rc, out = self.run_check(
            "brew", STUB_FORMULAE="gh\nnode\nuv\n", STUB_CASKS="claude-code@latest\n"
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "Homebrew: 3 formulae, 1 casks outdated")

    def test_nothing_outdated(self):
        rc, out = self.run_check("brew")
        self.assertEqual(rc, 1)
        self.assertEqual(out, "")

    def test_auto_update_stays_on(self):
        self.run_check("brew", STUB_FORMULAE="gh\n")
        outdated = [c for c in self.brew_calls() if c[0].startswith("outdated")]
        self.assertEqual(len(outdated), 2)
        self.assertTrue(all(flag == "" for _, flag in outdated))

    def test_outdated_formulae_fails(self):
        rc, _ = self.run_check("brew", STUB_FORMULAE="gh\n", STUB_FORMULAE_RC="1")
        self.assertEqual(rc, 2)

    def test_outdated_casks_fails(self):
        rc, _ = self.run_check("brew", STUB_FORMULAE="gh\n", STUB_CASKS_RC="1")
        self.assertEqual(rc, 2)

    def test_brew_missing(self):
        rc, _ = self.run_check("brew", SPARKDOCK_CHECK_BREW=str(self.dir / "no-brew"))
        self.assertEqual(rc, 3)

    def test_no_update_without_force(self):
        self.run_check("brew")
        self.assertNotIn("update --quiet", [c[0] for c in self.brew_calls()])

    def test_force_runs_update_then_counts(self):
        rc, out = self.run_check("brew", "--force", STUB_FORMULAE="gh\n")
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "Homebrew: 1 formulae, 0 casks outdated")
        calls = [c[0] for c in self.brew_calls()]
        self.assertEqual(calls[0], "update --quiet")

    def test_force_update_fails(self):
        rc, out = self.run_check(
            "brew", "--force", STUB_FORMULAE="gh\n", STUB_UPDATE_RC="1"
        )
        self.assertEqual(rc, 2)
        self.assertEqual(out, "")
        self.assertEqual([c[0] for c in self.brew_calls()], ["update --quiet"])


class VulnsSubsystemTest(CheckUpdatesTestCase):
    FINDINGS = '{"findings": [{"vulnerabilities": [{"severity": "HIGH"}, {"severity": "LOW"}]}]}'

    def cache(self):
        return self.home / ".cache" / "sparkdock" / "brew-vulns"

    def test_findings(self):
        rc, out = self.run_check("vulns", "--force", STUB_VULNS_JSON=self.FINDINGS)
        self.assertEqual(rc, 0)
        self.assertEqual(
            out.strip(), "Homebrew vulnerabilities: 2 in 1 formulae, 1 high or critical"
        )

    def test_clean(self):
        rc, _ = self.run_check("vulns", "--force", STUB_VULNS_JSON='{"findings": []}')
        self.assertEqual(rc, 1)

    def test_formula_without_vulnerabilities_is_clean(self):
        rc, _ = self.run_check(
            "vulns",
            "--force",
            STUB_VULNS_JSON='{"findings": [{"vulnerabilities": []}]}',
        )
        self.assertEqual(rc, 1)

    def test_unexpected_payload_is_a_failed_scan(self):
        payloads = [
            "not json",
            "[]",
            '{"findings": {}}',
            '{"findings": [{"vulnerabilities": {}}]}',
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                rc, _ = self.run_check("vulns", "--force", STUB_VULNS_JSON=payload)
                self.assertEqual(rc, 2)

    def test_scan_skips_auto_update(self):
        self.run_check("vulns", "--force", STUB_VULNS_JSON='{"findings": []}')
        self.assertTrue(all(flag == "1" for _, flag in self.brew_calls()))

    def test_unsupported(self):
        rc, _ = self.run_check("vulns", "--force", STUB_VULNS_HELP_RC="1")
        self.assertEqual(rc, 3)

    def test_brew_missing(self):
        rc, _ = self.run_check(
            "vulns", "--force", SPARKDOCK_CHECK_BREW=str(self.dir / "no-brew")
        )
        self.assertEqual(rc, 3)

    def test_failed_scan_is_not_cached(self):
        self.run_check("vulns", "--force", STUB_VULNS_JSON='{"findings": []}')
        before = self.cache().read_text()
        rc, _ = self.run_check("vulns", "--force", STUB_VULNS_JSON="")
        self.assertEqual(rc, 2)
        self.assertEqual(self.cache().read_text(), before)

    def test_cached_answer_without_force(self):
        self.run_check("vulns", "--force", STUB_VULNS_JSON=self.FINDINGS)
        self.log.write_text("")
        rc, out = self.run_check("vulns")
        self.assertEqual(rc, 0)
        self.assertIn("2 in 1 formulae", out)
        self.assertEqual(self.brew_calls(), [])

    def test_stale_cache_scans_again(self):
        self.run_check("vulns", "--force", STUB_VULNS_JSON=self.FINDINGS)
        old = time.time() - 2 * 24 * 3600
        os.utime(self.cache(), (old, old))
        self.log.write_text("")
        self.run_check("vulns", STUB_VULNS_JSON='{"findings": []}')
        self.assertIn("vulns --json", [c[0] for c in self.brew_calls()])


class CliSubsystemsTest(CheckUpdatesTestCase):
    """timetracker and engram wrap `<cli> update --check`, found on an extended PATH."""

    def setUp(self):
        super().setUp()
        for cli in CLIS:
            if shutil.which(
                cli, path="/opt/homebrew/bin:/usr/local/bin:" + os.environ["PATH"]
            ):
                self.skipTest(f"a real {cli} shadows the stub")
        self.bin_dir = self.home / ".local" / "bin"
        self.bin_dir.mkdir(parents=True)

    def install_stub(self, cli):
        stub = self.bin_dir / cli
        stub.write_text(
            '#!/usr/bin/env bash\necho "1.2.0 -> 1.3.0"\nexit "${STUB_CLI_RC}"\n'
        )
        stub.chmod(0o755)

    def test_not_installed(self):
        for cli in CLIS:
            with self.subTest(cli=cli):
                self.assertEqual(self.run_check(cli)[0], 3)

    def test_exit_codes(self):
        # 1 also covers an unreachable server; any unknown status reads as not configured.
        expected = {"0": 0, "1": 1, "3": 3, "2": 3, "127": 3}
        for cli in CLIS:
            self.install_stub(cli)
            for stub_rc, rc in expected.items():
                with self.subTest(cli=cli, stub_rc=stub_rc):
                    self.assertEqual(self.run_check(cli, STUB_CLI_RC=stub_rc)[0], rc)

    def test_update_available_prints_cli_output(self):
        for cli, label in CLIS.items():
            self.install_stub(cli)
            with self.subTest(cli=cli):
                _, out = self.run_check(cli, STUB_CLI_RC="0")
                self.assertEqual(
                    out.splitlines(), [f"{label} updates available:", "1.2.0 -> 1.3.0"]
                )


if __name__ == "__main__":
    unittest.main()
