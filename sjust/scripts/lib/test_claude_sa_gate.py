#!/usr/bin/env python3
"""Unit tests for the claude-sa-gate.py runtime hook (`--hook`).

The gate script has a hyphenated filename, so it cannot be imported as a module.
These tests drive it as a subprocess exactly as Claude Code does: feed a JSON
payload on stdin and assert the exit code (2 = block, 0 = allow). Stdlib
``unittest`` only.

Run via ``python3 -m unittest discover -s sjust/scripts/lib -p 'test_*.py'``.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE = str(Path(__file__).resolve().parent.parent / "claude-sa-gate.py")
# A placeholder project; the real one is supplied by the org at runtime and is
# not referenced here (this repo is public).
TEST_PROJECT = "example-agents"
SA_SUFFIX = f"@{TEST_PROJECT}.iam.gserviceaccount.com"


class SaGateHookTest(unittest.TestCase):
    def setUp(self):
        self.keydir = tempfile.TemporaryDirectory()
        self.addCleanup(self.keydir.cleanup)

    def _active_env(self):
        """Environment in which the gate is genuinely active."""
        return {
            "PATH": os.environ.get("PATH", ""),
            "SF_AGENT_SA_GUARD": "enforce",
            "FSCLI_AGENT_SA_PROJECT": TEST_PROJECT,
        }

    @staticmethod
    def bash(command, session_id="s1"):
        return {
            "session_id": session_id,
            "tool_name": "Bash",
            "tool_input": {"command": command},
        }

    def _write_key(self, client_email):
        path = Path(self.keydir.name) / "key.json"
        path.write_text(json.dumps({"client_email": client_email}))
        return str(path)

    def run_hook(self, command, phase: "str | None" = "enforce", gac=None, extra_env=None):
        # A minimal environment: inheriting the developer's real
        # SF_AGENT_SA_GUARD / GOOGLE_APPLICATION_CREDENTIALS would make results
        # differ between a laptop with fs-cli configured and CI.
        env = {"PATH": os.environ.get("PATH", "")}
        env["FSCLI_AGENT_SA_PROJECT"] = TEST_PROJECT
        if phase is not None:
            env["SF_AGENT_SA_GUARD"] = phase
        else:
            env.pop("SF_AGENT_SA_GUARD", None)
        if gac is not None:
            # Both variables: the gate requires the gcloud-honored override too,
            # because gcloud/bq/gsutil ignore GOOGLE_APPLICATION_CREDENTIALS.
            env["GOOGLE_APPLICATION_CREDENTIALS"] = gac
            env["CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE"] = gac
        if extra_env:
            env.update(extra_env)
        payload = {
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": {"command": command},
        }
        return subprocess.run(
            [sys.executable, GATE, "--hook"],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
        )

    # -- phase gating ------------------------------------------------------- #

    def test_off_when_phase_unset(self):
        self.assertEqual(self.run_hook("gcloud projects list", phase=None).returncode, 0)

    def test_off_when_phase_unknown(self):
        self.assertEqual(
            self.run_hook("gcloud projects list", phase="loud").returncode, 0
        )

    def test_off_when_project_unset(self):
        # Even in enforce, the gate is inert without FSCLI_AGENT_SA_PROJECT.
        self.assertEqual(
            self.run_hook(
                "gcloud projects list",
                phase="enforce",
                extra_env={"FSCLI_AGENT_SA_PROJECT": ""},
            ).returncode,
            0,
        )

    def test_warn_surfaces_message_without_blocking(self):
        # Exit 1 is a non-blocking error: the command still runs, but the
        # message reaches the user. Exit 0 would discard stderr entirely.
        r = self.run_hook("gcloud projects list", phase="warn")
        self.assertEqual(r.returncode, 1)
        self.assertIn("personal credentials", r.stderr.lower())

    def test_enforce_blocks(self):
        r = self.run_hook("gcloud projects list", phase="enforce")
        self.assertEqual(r.returncode, 2)
        self.assertIn("personal credentials", r.stderr.lower())

    # -- credential detection ---------------------------------------------- #

    def test_agent_credentials_allow(self):
        gac = self._write_key("test-user" + SA_SUFFIX)
        self.assertEqual(
            self.run_hook("gcloud projects list", phase="enforce", gac=gac).returncode,
            0,
        )

    def test_non_agent_sa_key_still_gated(self):
        gac = self._write_key("someone@other-project.iam.gserviceaccount.com")
        self.assertEqual(
            self.run_hook("gcloud projects list", phase="enforce", gac=gac).returncode,
            2,
        )

    def test_missing_gac_file_gated(self):
        self.assertEqual(
            self.run_hook(
                "gcloud projects list", phase="enforce", gac="/nonexistent/key.json"
            ).returncode,
            2,
        )

    # -- command matching --------------------------------------------------- #

    def test_terraform_bq_gsutil_gated(self):
        for cmd in ("terraform apply", "bq query 'x'", "gsutil ls"):
            self.assertEqual(
                self.run_hook(cmd, phase="enforce").returncode, 2, f"gate: {cmd!r}"
            )

    def test_gcp_in_chain_gated(self):
        self.assertEqual(
            self.run_hook("cd /x && gcloud compute instances list").returncode, 2
        )

    def test_non_gcp_command_allowed(self):
        self.assertEqual(self.run_hook("git push", phase="enforce").returncode, 0)

    def test_word_in_argument_not_a_false_positive(self):
        for cmd in ('echo "run terraform later"', "grep gcloud notes.txt"):
            self.assertEqual(
                self.run_hook(cmd, phase="enforce").returncode, 0, f"allow: {cmd!r}"
            )

    # -- auth login block --------------------------------------------------- #

    def test_auth_login_blocked_in_enforce(self):
        r = self.run_hook("gcloud auth login", phase="enforce")
        self.assertEqual(r.returncode, 2)
        self.assertIn("human credentials", r.stderr.lower())

    def test_auth_login_blocked_in_warn(self):
        # Minting human credentials is blocked even in the warn phase.
        r = self.run_hook("gcloud auth login --no-launch-browser", phase="warn")
        self.assertEqual(r.returncode, 2)

    def test_adc_login_blocked(self):
        self.assertEqual(
            self.run_hook(
                "gcloud auth application-default login", phase="enforce"
            ).returncode,
            2,
        )

    def test_auth_login_off_when_phase_unset(self):
        self.assertEqual(self.run_hook("gcloud auth login", phase=None).returncode, 0)

    # -- escape hatch and robustness --------------------------------------- #

    def test_escape_hatch_disables_gate(self):
        for val in ("0", "off", "false", "no"):
            r = self.run_hook(
                "gcloud projects list",
                phase="enforce",
                extra_env={"SPARKDOCK_SA_GATE": val},
            )
            self.assertEqual(r.returncode, 0, f"value {val!r} should disable the gate")

    def test_malformed_stdin_fails_open(self):
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input="{not json",
            capture_output=True,
            text=True,
            env=self._active_env(),
        )
        self.assertEqual(r.returncode, 0)

    def test_unrelated_tool_allowed(self):
        payload = {"session_id": "s1", "tool_name": "Read", "tool_input": {"file": "x"}}
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=self._active_env(),
        )
        self.assertEqual(r.returncode, 0)

    def test_gate_is_active_in_active_env(self):
        # Guards the two tests above: if _active_env() ever stopped activating
        # the gate they would pass vacuously, proving nothing.
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input=json.dumps(self.bash("gcloud projects list")),
            capture_output=True,
            text=True,
            env=self._active_env(),
        )
        self.assertEqual(r.returncode, 2)

    # -- indirection the gate cannot see (documented limits, asserted so a
    #    future change to the regex does not silently claim more than it does)

    def test_known_indirection_is_not_caught(self):
        for cmd in (
            "bash ./deploy.sh",
            "sh -c 'gcloud projects list'",
            "just tf plan",
            "make apply",
            "docker run --rm hashicorp/terraform:1.5.2 apply",
        ):
            self.assertEqual(
                self.run_hook(cmd).returncode,
                0,
                f"documented limit changed for: {cmd!r}",
            )

    # -- forms that MUST be caught

    def test_leading_whitespace_is_gated(self):
        self.assertEqual(self.run_hook("  gcloud projects list").returncode, 2)

    def test_absolute_and_home_paths_are_gated(self):
        for cmd in (
            "/usr/bin/gcloud projects list",
            "~/google-cloud-sdk/bin/gcloud projects list",
            "./terraform apply",
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 2, f"should gate: {cmd!r}")

    def test_prefix_words_are_gated(self):
        for cmd in (
            "sudo gcloud projects list",
            "env gcloud projects list",
            "command gcloud projects list",
            "time terraform apply",
            "nohup gsutil ls",
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 2, f"should gate: {cmd!r}")

    def test_inside_conditional_and_loop_is_gated(self):
        for cmd in (
            "if [ -f main.tf ]; then terraform apply; fi",
            "for p in a b; do gcloud projects describe $p; done",
            "{ gcloud projects list; }",
            "while read l; do terraform apply; done < f",
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 2, f"should gate: {cmd!r}")

    def test_substitution_forms_are_gated(self):
        for cmd in (
            "P=$(gcloud projects list) && echo $P",
            "cat x | gcloud projects list",
            "make build && terraform apply",
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 2, f"should gate: {cmd!r}")

    def test_additional_iac_clis_are_gated(self):
        for cmd in ("tofu apply", "terragrunt apply"):
            self.assertEqual(self.run_hook(cmd).returncode, 2, f"should gate: {cmd!r}")

    # -- false positives that must NOT be blocked

    def test_credential_free_subcommands_allowed(self):
        for cmd in (
            "terraform fmt -check",
            "terraform validate",
            "terraform -version",
            "gcloud --version",
            "gcloud config list",
            "gcloud components list",
            "tofu fmt",
            "bq version",
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 0, f"should allow: {cmd!r}")

    def test_quoted_mentions_with_separators_allowed(self):
        for cmd in (
            'echo "see (terraform docs)"',
            'git commit -m "chore: bump; terraform 1.9 now"',
            "grep -rn 'gcloud auth login' docs/",
            'echo "run gcloud auth login first" > note.txt',
        ):
            self.assertEqual(self.run_hook(cmd).returncode, 0, f"should allow: {cmd!r}")

    # -- credential detection hardening

    def test_sdk_variable_alone_is_not_enough(self):
        # gcloud, bq and gsutil ignore GOOGLE_APPLICATION_CREDENTIALS, so the
        # SDK variable on its own must not green-light a gcloud command.
        key = self._write_key("test-user" + SA_SUFFIX)
        r = self.run_hook(
            "gcloud projects list",
            extra_env={"GOOGLE_APPLICATION_CREDENTIALS": key},
        )
        self.assertEqual(r.returncode, 2)

    def test_non_utf8_key_file_does_not_crash(self):
        path = Path(self.keydir.name) / "binary.json"
        path.write_bytes(b"\xff\xfe\x00\x01not json")
        r = self.run_hook("gcloud projects list", gac=str(path))
        # Must stay a clean block, not a traceback (exit 1 would be read as a
        # non-blocking error and would let the command through).
        self.assertEqual(r.returncode, 2)
        self.assertNotIn("Traceback", r.stderr)

    def test_directory_as_key_path_is_gated(self):
        r = self.run_hook("gcloud projects list", gac=self.keydir.name)
        self.assertEqual(r.returncode, 2)
        self.assertNotIn("Traceback", r.stderr)


if __name__ == "__main__":
    unittest.main()
