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

    def _write_key(self, client_email):
        path = Path(self.keydir.name) / "key.json"
        path.write_text(json.dumps({"client_email": client_email}))
        return str(path)

    def run_hook(self, command, phase: "str | None" = "enforce", gac=None, extra_env=None):
        env = dict(os.environ)
        env.pop("SPARKDOCK_SA_GATE", None)
        env.pop("GOOGLE_APPLICATION_CREDENTIALS", None)
        env["FSCLI_AGENT_SA_PROJECT"] = TEST_PROJECT
        if phase is not None:
            env["SF_AGENT_SA_GUARD"] = phase
        else:
            env.pop("SF_AGENT_SA_GUARD", None)
        if gac is not None:
            env["GOOGLE_APPLICATION_CREDENTIALS"] = gac
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

    def test_warn_allows_but_messages(self):
        r = self.run_hook("gcloud projects list", phase="warn")
        self.assertEqual(r.returncode, 0)
        self.assertIn("personal credentials", r.stderr.lower())

    def test_enforce_blocks(self):
        r = self.run_hook("gcloud projects list", phase="enforce")
        self.assertEqual(r.returncode, 2)
        self.assertIn("personal credentials", r.stderr.lower())

    # -- credential detection ---------------------------------------------- #

    def test_agent_credentials_allow(self):
        gac = self._write_key("paolo-mainardi" + SA_SUFFIX)
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
        env = dict(os.environ)
        env["SF_AGENT_SA_GUARD"] = "enforce"
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input="{not json",
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(r.returncode, 0)

    def test_unrelated_tool_allowed(self):
        env = dict(os.environ)
        env["SF_AGENT_SA_GUARD"] = "enforce"
        payload = {"session_id": "s1", "tool_name": "Read", "tool_input": {"file": "x"}}
        r = subprocess.run(
            [sys.executable, GATE, "--hook"],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
