"""Tests for herdr-agent-resume: hook, shell paths, management and the zsh snippet."""

import importlib.util
import contextlib
import io
import itertools
import json
import os
import pty
import shlex
import socket
import shutil
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent / "herdr-agent-resume"
SCRIPT = ROOT / "herdr-agent-resume.py"
SNIPPET = ROOT / "herdr-agent-resume.zsh"
spec = importlib.util.spec_from_file_location("herdr_agent_resume", SCRIPT)
har = importlib.util.module_from_spec(spec)
spec.loader.exec_module(har)

SID = "82b43bc5-d3d5-435f-b7a0-3fa629d1a4b2"

def tok(value):
    """The label value for a session dict, or the value itself."""
    return value["gen"] if isinstance(value, dict) else value


def mtext(value):
    """Marker file content for a session dict, or the value itself."""
    return har.marker_text(value) if isinstance(value, dict) else value


FAKE_HC = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json, os, sys
    path = os.environ["FAKE_HC_STATE"]
    core = os.path.basename(os.environ.get("HC_SOCKET", "default.sock"))[: -len(".sock")]
    if core != "default":
        path += "." + core  # each core has its own terminals
    state = json.load(open(path))
    args = sys.argv[1:]
    state.setdefault("calls", []).append(args)
    def save():
        json.dump(state, open(path, "w"))
    terms = state["terminals"]
    if args[:1] == ["get"] and args[1] in terms:
        t = dict(terms[args[1]]); t["address"] = args[1]
        print(json.dumps(t)); save(); sys.exit(0)
    if args[:2] == ["server", "status"]:
        print(json.dumps({"core": {"id": state.get("core_id", "00112233445566778899aabbccddee" + core.encode().hex()[:2].ljust(2, "0"))}}))
        save(); sys.exit(0)
    if args[:1] == ["ls"]:
        print(json.dumps({"terminals": [{"address": a} for a in terms]})); save(); sys.exit(0)
    if args[:1] == ["label"] and args[1] in terms and not state.get("fail_label"):
        for kv in args[2:]:
            k, v = kv.split("=", 1)
            if v: terms[args[1]]["labels"][k] = v
            else: terms[args[1]]["labels"].pop(k, None)
        save(); sys.exit(0)
    save(); sys.exit(1)
    """
)


class Env(unittest.TestCase):
    """Temporary HOME, fake hc on PATH and a herdr-core terminal environment."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.project = self.root / "project"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        hc = self.bin / "hc"
        hc.write_text(FAKE_HC)
        hc.chmod(0o755)
        self.state_file = self.root / "hc.json"
        self.save_state({"terminals": {"t1": {"pid": 4242, "labels": {}}}})
        self.socket = self.listen("default")
        self.env = {
            "HOME": str(self.home),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FAKE_HC_STATE": str(self.state_file),
            "HC_TERMINAL_ID": "t1",
            "HC_TERMINAL_SOCKET": str(self.socket),
            "SHELL": "/bin/zsh",
            "CLAUDE_CONFIG_DIR": str(self.home / ".claude"),
            "CODEX_HOME": str(self.home / ".codex"),
        }
        patcher = patch.dict(os.environ, self.env, clear=False)
        patcher.start()
        self.addCleanup(patcher.stop)
        os.environ.pop("HERDR_ENV", None)
        os.environ.pop("ZDOTDIR", None)
        self.core = har.core_key(str(self.socket))
        self.marker = har.core_dir(self.core) / "t1"

    def listen(self, core):
        """A listening socket stands in for a running core (hc() checks it first)."""
        path = self.root / f"{core}.sock"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        server.listen(16)
        self.addCleanup(server.close)
        return path

    def wait_until(self, check, timeout=10):
        """The zsh cleanup runs in the background: poll for its effect."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if check():
                return True
            time.sleep(0.1)
        return check()

    def ended(self, session):
        """The ended record of a session's generation (a session dict or a token)."""
        return har.ended_path(self.marker, tok(session))

    def records(self):
        return har.ended_records(self.marker)

    def live_id(self):
        """The id the (fake) core on this test's socket reports."""
        with har.on_core(str(self.socket)):
            return har.core_id()

    def old_folder(self, core_id):
        """A folder of this core under an older socket path, holding this terminal's marker."""
        folder = har.core_dir(har.core_key(str(self.root / "old-run" / "default.sock")))
        folder.mkdir(parents=True)
        (folder / ".core-id").write_text(core_id + "\n")
        return folder

    def save_state(self, state):
        self.state_file.write_text(json.dumps(state))

    def state(self):
        return json.loads(self.state_file.read_text())

    def labels(self, terminal="t1"):
        return self.state()["terminals"][terminal]["labels"]

    def calls(self):
        return self.state().get("calls", [])

    def enable_flag(self):
        har.core_dir(self.core).mkdir(parents=True, exist_ok=True)
        har.enabled_file().touch()
        (har.core_dir(self.core) / ".pruned").touch()  # no detached prune spawned by tests
        (har.core_dir(self.core) / ".core-id").write_text(self.live_id() + "\n")  # a healthy core
        state = self.state()
        state["calls"] = []  # the setup's own hc call does not count
        self.save_state(state)

    def put_label(self, value, terminal="t1", fail=False):
        """`value` is a session (its token goes in the label) or a raw label string."""
        state = self.state()
        state["terminals"][terminal]["labels"][har.LABEL] = tok(value)
        state["fail_label"] = fail
        self.save_state(state)

    def label_value(self, agent="claude", sid=SID, cwd=None, transcript=None):
        return har.new_session(agent, sid, str(cwd or self.project), transcript)


class LabelTest(unittest.TestCase):
    def test_marker_round_trip(self):
        session = har.new_session("codex", SID, "/tmp", None, gen="0123456789abcdef")
        self.assertEqual(
            har.parse_marker(har.marker_text(session)),
            {"agent": "codex", "id": SID, "cwd": "/tmp", "transcript": None, "gen": "0123456789abcdef"},
        )
        self.assertEqual(har.marker_text(session).split("\n")[0], "0123456789abcdef")

    def test_each_start_gets_a_new_token(self):
        self.assertNotEqual(
            har.new_session("codex", SID, "/tmp", None)["gen"], har.new_session("codex", SID, "/tmp", None)["gen"]
        )

    def test_marker_with_mismatched_or_bad_token_is_rejected(self):
        session = har.new_session("codex", SID, "/tmp", None)
        text = har.marker_text(session)
        self.assertIsNone(har.parse_marker("ffffffffffffffff" + text[16:]))
        for gen in ("", "XYZ", "0" * 15, "0" * 17):
            data = dict(session, gen=gen)
            blob = har.base64.b64encode(json.dumps(data).encode()).decode()
            self.assertIsNone(har.parse_marker(f"{gen}\n{blob}\n"), gen)

    def test_rejects_unsafe_values(self):
        for args in (
            ("bash", SID, "/tmp", None),
            ("claude", "x; rm -rf ~", "/tmp", None),
            ("claude", "-rf", "/tmp", None),
            ("claude", SID, "relative", None),
            ("claude", SID, "/tmp/a\nb", None),
            ("claude", SID, "/tmp", "relative.jsonl"),
            ("claude", SID, "/" + "a" * 5000, None),
        ):
            self.assertIsNone(har.new_session(*args), args)

    def test_parse_rejects_garbage(self):
        for text in (None, "", "not a marker", "0123456789abcdef\nnot base64!\n", "0123456789abcdef\ne30=\n"):
            self.assertIsNone(har.parse_marker(text))

    def test_label_shows_only_the_token(self):
        session = har.new_session("claude", SID, "/tmp/private-project", "/x/t.jsonl")
        self.assertTrue(har.valid_token(session["gen"]))
        self.assertNotIn("tmp", session["gen"])


class CoreFolderTest(unittest.TestCase):
    def test_terminal_of_maps_each_file_to_its_terminal(self):
        cases = {
            "t1": "t1",
            "t1.ended.0123456789abcdef": "t1",
            "t1.ended.garbage": "t1",
            ".t1.lock": "t1",
            ".lock": None,
            ".core-id": None,
            ".pruned": None,
            ".t1.ended.0123456789abcdef.x1y2z3": None,  # a temp file
        }
        for name, expected in cases.items():
            self.assertEqual(har.terminal_of(Path("/x") / name), expected, name)

    def test_moved_needs_the_saved_id_running_under_another_key_only(self):
        with patch.object(har, "saved_core_id", return_value="a" * 16):
            self.assertTrue(har.moved("old", {"new": "a" * 16}))
            self.assertTrue(har.moved("old", {"old": "b" * 16, "new": "a" * 16}))
            self.assertFalse(har.moved("old", {"old": "a" * 16, "new": "a" * 16}))
            self.assertFalse(har.moved("old", {"old": "a" * 16}))
            self.assertFalse(har.moved("old", {}))
        with patch.object(har, "saved_core_id", return_value=None):
            self.assertFalse(har.moved("old", {"new": "a" * 16}))


class ForegroundTest(unittest.TestCase):
    def setUp(self):
        # Fake pids have no real argv: by default each table entry is exact.
        real = har.foreground_agent
        self.tables = []

        def walk(table, start, record_pid, agent, argv_of=None):
            ps = {pid: row[:3] for pid, row in table.items()}  # what process_table returns
            return real(ps, start, record_pid, agent, argv_of=argv_of or (lambda pid: table[pid][3]))

        patcher = patch.object(har, "foreground_agent", walk)
        patcher.start()
        self.addCleanup(patcher.stop)

    # pid: (ppid, pgid, tpgid, argv)
    def table(self, **extra):
        base = {
            100: (1, 100, 300, ["zsh"]),  # terminal shell (record)
            300: (100, 300, 300, ["claude"]),  # agent, foreground job
            400: (300, 400, 300, ["sh", "-c", "hook"]),
            500: (400, 400, 300, ["python3", "hook"]),
        }
        base.update(extra)
        return base

    def test_agent_in_shell(self):
        self.assertTrue(har.foreground_agent(self.table(), 500, 100, "claude"))

    def test_agent_is_the_terminal_program(self):
        table = {
            100: (1, 100, 100, ["claude"]),
            400: (100, 400, 100, ["sh"]),
            500: (400, 400, 100, ["python3"]),
        }
        self.assertTrue(har.foreground_agent(table, 500, 100, "claude"))

    def test_wrapper_script(self):
        table = self.table()
        table[300] = (200, 200, 200, ["claude"])
        table[200] = (100, 200, 200, ["bash", "/usr/local/bin/myclaude"])
        table[100] = (1, 100, 200, ["zsh"])
        self.assertTrue(har.foreground_agent(table, 500, 100, "claude"))

    def test_nested_agent_rejected(self):
        table = self.table()
        table[600] = (300, 300, 300, ["bash", "-c", "claude -x"])
        table[700] = (600, 300, 300, ["claude"])
        table[800] = (700, 800, 300, ["python3", "hook"])
        self.assertFalse(har.foreground_agent(table, 800, 100, "claude"))

    def test_nested_agent_of_other_type_rejected(self):
        for outer, inner in (("claude", "codex"), ("codex", "claude")):
            table = self.table()
            table[300] = (100, 300, 300, [outer])
            table[600] = (300, 300, 300, ["bash", "-c", inner])
            table[700] = (600, 300, 300, [inner])
            table[800] = (700, 800, 300, ["python3", "hook"])
            self.assertFalse(har.foreground_agent(table, 800, 100, inner), (outer, inner))
            self.assertTrue(har.foreground_agent(table, 500, 100, outer), (outer, inner))

    def test_background_agent_rejected(self):
        table = self.table()
        table[300] = (100, 300, 100, ["claude"])
        self.assertFalse(har.foreground_agent(table, 500, 100, "claude"))

    def test_tmux_rejected(self):
        table = self.table()
        table[300] = (900, 300, 300, ["claude"])
        table[900] = (1, 900, -1, ["tmux"])
        self.assertFalse(har.foreground_agent(table, 500, 100, "claude"))

    def test_one_shot_rejected(self):
        for argv in (["claude", "-p", "hi"], ["claude", "--print"]):
            table = self.table()
            table[300] = (100, 300, 300, argv)
            self.assertFalse(har.foreground_agent(table, 500, 100, "claude"))
        for argv in (["codex", "exec", "x"], ["codex", "--model", "m", "exec", "x"], ["codex", "-c", "k=v", "e"]):
            table = self.table()
            table[300] = (100, 300, 300, argv)
            self.assertFalse(har.foreground_agent(table, 500, 100, "codex"), argv)

    def test_codex_option_values_are_not_subcommands(self):
        for argv in (["codex", "-p", "e"], ["codex", "--profile", "exec"], ["codex", "-m", "exec", "fix it"]):
            self.assertFalse(har.one_shot(argv, "codex"), argv)
        for argv in (["codex", "-p", "work", "exec", "x"], ["codex", "--model=m", "e"]):
            self.assertTrue(har.one_shot(argv, "codex"), argv)

    def test_exact_argv_keeps_quoted_values_together(self):
        argv = ["codex", "-c", 'developer_instructions="two words"', "exec"]
        table = self.table()
        table[300] = (100, 300, 300, " ".join(argv).split())
        self.assertFalse(har.foreground_agent(table, 500, 100, "codex", argv_of=lambda pid: argv if pid == 300 else table[pid][3]))
        interactive = ["codex", "-c", 'developer_instructions="two words"']
        table[300] = (100, 300, 300, " ".join(interactive).split())
        self.assertTrue(
            har.foreground_agent(table, 500, 100, "codex", argv_of=lambda pid: interactive if pid == 300 else table[pid][3])
        )

    def test_unreadable_argv_fails_closed(self):
        table = self.table()
        table[300] = (100, 300, 300, ["/tmp/Claude", "Install/claude"])
        exact = {500: ["python3", "hook"], 400: ["sh"], 100: ["zsh"]}  # 300 unreadable
        self.assertIsNone(har.foreground_agent(table, 500, 100, "claude", argv_of=exact.get))

    def test_process_argv_keeps_boundaries(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(10)", "two words"])
        self.addCleanup(child.wait)
        self.addCleanup(child.kill)
        argv = None
        for _ in range(50):
            argv = har.process_argv(child.pid)
            if argv and argv[-1] == "two words":
                break
            time.sleep(0.05)
        self.assertEqual(argv[-1], "two words")

    def test_nested_agent_under_a_spaced_install_path_is_seen(self):
        table = self.table()
        table[300] = (100, 300, 300, ["/tmp/Claude", "Install/claude"])  # what ps shows
        table[600] = (300, 300, 300, ["bash"])
        table[700] = (600, 300, 300, ["codex"])
        table[800] = (700, 800, 300, ["python3", "hook"])
        exact = {300: ["/tmp/Claude Install/claude"], 700: ["codex"]}
        self.assertFalse(har.foreground_agent(table, 800, 100, "codex", argv_of=lambda pid: exact.get(pid)))

    def test_wrong_agent(self):
        self.assertFalse(har.foreground_agent(self.table(), 500, 100, "codex"))


@unittest.skipUnless(shutil.which("bash"), "bash required")
class RealProcessTreeTest(unittest.TestCase):
    """Check the ps parsing and ancestry against a real pty on this OS."""

    def run_in_pty(self, command):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        probe = Path(tmp.name) / "probe.py"
        probe.write_text(
            "import importlib.util, os\n"
            f"s = importlib.util.spec_from_file_location('h', {str(SCRIPT)!r})\n"
            "m = importlib.util.module_from_spec(s); s.loader.exec_module(m)\n"
            "rec = int(os.environ['REC'])\n"
            "print('RESULT', m.foreground_agent(m.process_table(), os.getpid(), rec, 'claude'))\n"
        )
        agent = Path(tmp.name) / "agent.py"
        # Pin the interpreter: with argv0 "claude", sys.executable would resolve to a real claude.
        agent.write_text(f"import subprocess\nsubprocess.run([{sys.executable!r}, {str(probe)!r}])\n")
        pid, fd = pty.fork()
        if pid == 0:
            os.environ["REC"] = str(os.getpid())
            run = f"exec -a claude {shlex.quote(sys.executable)} {shlex.quote(str(agent))}"
            os.execvp("bash", ["bash", "-c", command.format(run=run)])
        out = b""
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        os.waitpid(pid, 0)
        return out.decode(errors="replace")

    def test_shell_runs_agent(self):
        self.assertIn("RESULT True", self.run_in_pty("({run}); true"))

    def test_agent_is_terminal_program(self):
        self.assertIn("RESULT True", self.run_in_pty("{run}"))

    def test_background_agent(self):
        self.assertIn("RESULT False", self.run_in_pty("set -m; ({run}) & wait"))


class HookTest(Env):
    def run_hook(self, payload, agent="claude", ok=True):
        stdout = io.StringIO()
        with patch.object(har, "foreground_agent", return_value=ok), patch.object(
            sys, "stdin", io.StringIO(json.dumps(payload))
        ), redirect_stdout(stdout):
            self.assertEqual(har.main(["x", "--hook", agent]), 0)
        self.assertEqual(stdout.getvalue(), "")

    def start(self, **extra):
        return {"hook_event_name": "SessionStart", "session_id": SID, "cwd": str(self.project), **extra}

    def test_start_records_label_and_marker(self):
        self.enable_flag()
        self.run_hook(self.start(transcript_path="/x/t.jsonl"))
        session = har.parse_marker(self.marker.read_text())
        self.assertEqual(session["id"], SID)
        self.assertEqual(session["transcript"], "/x/t.jsonl")
        self.assertEqual(session["gen"], self.labels()[har.LABEL])
        self.assertTrue(har.valid_token(self.labels()[har.LABEL]))

    def test_inert_when_disabled_outside_herdr_or_in_tui(self):
        self.run_hook(self.start())
        self.assertEqual(self.calls(), [])
        self.enable_flag()
        with patch.dict(os.environ, {"HERDR_ENV": "1"}):
            self.run_hook(self.start())
        del os.environ["HC_TERMINAL_ID"]
        self.run_hook(self.start())
        self.assertEqual(self.calls(), [])

    def test_not_foreground_or_bad_payload(self):
        self.enable_flag()
        self.run_hook(self.start(), ok=False)
        self.run_hook(self.start(session_id="bad id"))
        self.run_hook(self.start(cwd=str(self.root / "missing")))
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists())

    def test_garbage_stdin_is_silent(self):
        self.enable_flag()
        with patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(har.main(["x", "--hook", "claude"]), 0)

    def test_session_end_explicit_exit_clears(self):
        self.enable_flag()
        session = self.label_value()
        self.put_label(session)
        self.marker.write_text(mtext(session))
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"})
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists())

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_session_end_with_unreadable_marker_records_the_end(self):
        self.enable_flag()
        session = self.label_value()
        self.put_label(session)
        self.marker.write_text(mtext(session))
        self.marker.chmod(0)
        self.addCleanup(lambda: self.marker.exists() and self.marker.chmod(0o600))
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"})
        self.assertEqual(self.ended(session).read_text().strip(), tok(session))

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_unrelated_exit_with_unreadable_marker_changes_nothing(self):
        self.enable_flag()
        session = self.label_value()
        self.put_label(session)
        self.marker.write_text(mtext(session))
        self.marker.chmod(0)
        self.addCleanup(lambda: self.marker.exists() and self.marker.chmod(0o600))
        self.run_hook(
            {"hook_event_name": "SessionEnd", "session_id": "ffffffff-9999", "reason": "prompt_input_exit"},
            ok=False,  # a nested Claude: not the terminal's foreground agent
        )
        self.assertEqual(self.records(), [])
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_start_prunes_in_a_detached_process(self):
        self.enable_flag()
        with patch.object(har, "maybe_prune") as prune:
            self.run_hook(self.start())
        prune.assert_called_once()
        (har.core_dir(self.core) / ".pruned").unlink()
        with patch.object(har, "spawn_detached") as spawn:
            har.maybe_prune()
        self.assertEqual(spawn.call_args[0][0][-1], "--prune")
        with patch.object(har, "spawn_detached") as spawn:
            har.maybe_prune()  # the stamp is fresh: no second prune today
        spawn.assert_not_called()

    def test_spawn_detached_runs_in_its_own_session(self):
        out = self.root / "sid"
        har.spawn_detached([sys.executable, "-c", f"import os; open({str(out)!r}, 'w').write(str(os.getsid(0) == os.getpid()))"])
        self.assertTrue(self.wait_until(lambda: out.exists() and out.read_text() == "True"))

    def test_start_saves_the_core_id(self):
        self.enable_flag()
        self.run_hook(self.start())
        self.assertTrue(har.CORE_ID_RE.match((self.marker.parent / ".core-id").read_text().strip()))

    def test_start_never_takes_over_another_cores_sessions(self):
        self.enable_flag()
        (self.marker.parent / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        (self.marker.parent / "t7").write_text("another core's session")
        self.run_hook(self.start())
        self.assertEqual(self.labels(), {})
        self.assertEqual((self.marker.parent / ".core-id").read_text().strip(), "f" * 32)

    def test_start_records_nothing_without_a_core_id(self):
        self.enable_flag()
        with patch.object(har, "core_id", return_value=None):
            self.run_hook(self.start())
        self.assertEqual(self.labels(), {})

    def test_start_files_the_marker_under_the_full_socket_path(self):
        self.enable_flag()
        self.run_hook(self.start())
        self.assertEqual(self.marker.parent.name, str(self.socket).replace("/", "%2F"))
        self.assertEqual(har.core_socket(self.marker.parent.name), str(self.socket))

    def test_session_end_needs_the_marker_of_that_label(self):
        self.enable_flag()
        session = self.label_value()
        self.put_label(session)
        self.marker.write_text(mtext(self.label_value()))  # another start's marker
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"})
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_session_end_keeps_on_shutdown_other_session_or_codex(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.marker.write_text(mtext(value))
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "other"})
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "clear"})
        self.run_hook(
            {"hook_event_name": "SessionEnd", "session_id": "aaaaaaaa-0000", "reason": "prompt_input_exit"}
        )
        self.run_hook(
            {"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"}, agent="codex"
        )
        self.assertEqual(self.labels()[har.LABEL], tok(value))

    def test_a_start_keeps_the_core_folder_private(self):
        self.enable_flag()
        har.core_dir(self.core).chmod(0o755)
        self.run_hook(self.start())
        self.assertTrue(self.marker.exists())
        self.assertEqual(oct(har.core_dir(self.core).stat().st_mode & 0o777), "0o700")

    def test_failed_marker_write_removes_the_label(self):
        self.enable_flag()
        real = har.atomic_write

        def refuse_marker(path, *args, **kwargs):
            if path == self.marker:
                raise OSError("read-only")
            return real(path, *args, **kwargs)

        with patch.object(har, "atomic_write", side_effect=refuse_marker):
            self.run_hook(self.start())
        self.assertIn(har.LABEL, " ".join(map(str, self.calls())))  # the label was set first
        self.assertEqual(self.labels(), {})

    def test_session_end_removes_the_ended_record(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.marker.write_text(mtext(value))
        self.ended(value).write_text(tok(value))
        self.run_hook({"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"})
        self.assertEqual(self.records(), [])

    def test_start_deletes_an_older_ended_record(self):
        self.enable_flag()
        self.ended(self.label_value()).write_text("x")
        self.run_hook(self.start())
        self.assertIn(har.LABEL, self.labels())
        self.assertEqual(self.records(), [])

    def test_same_session_restart_is_not_its_earlier_exit(self):
        self.enable_flag()
        self.run_hook(self.start())
        first = self.labels()[har.LABEL]
        har.ended_path(self.marker, first).write_text(first)  # zsh: the first run ended
        self.run_hook(self.start())  # `codex resume <same id>`
        second = self.labels()[har.LABEL]
        self.assertNotEqual(first, second)
        self.assertEqual(self.records(), [])

    def test_writers_of_different_terminals_never_wait_on_each_other(self):
        self.enable_flag()
        other = self.marker.parent / "t2"
        with har.writer_lock(self.marker, wait=1) as held:
            self.assertTrue(held)
            started = time.monotonic()
            with har.writer_lock(other, wait=3) as also:
                waited = time.monotonic() - started
            self.assertTrue(also)
            self.assertLess(waited, 0.5)
            started = time.monotonic()
            with har.writer_lock(self.marker, wait=0.5) as same:
                self.assertFalse(same)  # same terminal: serialized

    def test_a_hook_waiting_through_disable_recreates_nothing(self):
        self.enable_flag()
        result = {}

        def late_writer():
            with har.writer_lock(har.core_dir("late-core") / "t1", wait=5) as held:
                result["held"] = held

        with har.state_lock(exclusive=True, wait=1) as held:  # disable is running
            self.assertTrue(held)
            thread = threading.Thread(target=late_writer)
            thread.start()
            time.sleep(0.3)
            self.assertTrue(thread.is_alive())  # the writer waits for the lock
            shutil.rmtree(har.state_dir())  # disable removes everything
        thread.join(10)  # then the writer gets the lock
        self.assertFalse(result.get("held"))
        self.assertFalse(har.state_dir().exists())

    def test_disable_waits_for_writers_and_stops_new_ones(self):
        self.enable_flag()
        with har.state_lock(exclusive=True, wait=1) as held:
            self.assertTrue(held)
            with har.writer_lock(self.marker, wait=0.3) as writer:
                self.assertFalse(writer)

    def test_prune_removes_lock_files_of_gone_terminals(self):
        self.enable_flag()
        with har.writer_lock(self.marker.parent / "t9", wait=1):
            pass
        lock = self.marker.parent / ".t9.lock"
        self.assertTrue(lock.exists())
        old = time.time() - 60
        os.utime(lock, (old, old))
        har.prune_markers()
        self.assertFalse(lock.exists())

    def test_disable_waits_for_a_hook_in_flight(self):
        self.enable_flag()
        (self.home / ".zshrc").write_text("")
        real_set = har.set_label
        entered = threading.Event()

        def slow_set(terminal, value):
            entered.set()
            time.sleep(0.5)
            return real_set(terminal, value)

        out = {}

        def disable():
            entered.wait(5)
            out["code"] = har.main(["x", "disable"])

        thread = threading.Thread(target=disable)
        quiet = patch.object(har, "print", create=True)
        quiet.start()
        self.addCleanup(quiet.stop)
        thread.start()
        with patch.object(har, "set_label", slow_set):
            self.run_hook(self.start())
        thread.join(15)
        self.assertEqual(out.get("code"), 0)
        self.assertEqual(self.labels(), {})
        self.assertFalse(har.state_dir().exists())

    def test_hc_failure_is_silent(self):
        self.enable_flag()
        self.put_label(self.label_value(), fail=True)
        self.run_hook(self.start(session_id="bbbbbbbb-1111"))
        self.assertFalse(self.marker.exists())


class ShellTest(Env):
    def startup(self, pid=4242):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            har.main(["x", "--shell-startup", str(pid)])
        return stdout.getvalue()

    def prepare(self, value, fail=False):
        self.enable_flag()
        self.marker.write_text(mtext(value))
        self.put_label(value, fail=fail)
        self.value = value

    def cleanup(self, pid=4242, expected=None):
        token = tok(self.value if expected is None else expected)
        har.ended_path(self.marker, token).write_text(token + "\n")
        har.main(["x", "--shell-cleanup", str(pid), token])

    def test_resume_plan_clears_first(self):
        self.prepare(self.label_value())
        self.assertEqual(self.startup(), f"resume\tclaude\t{SID}\t{self.project}\n")
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists())

    def test_closed_session_is_not_resumed_when_recovery_wins_the_race(self):
        value = self.label_value()
        self.prepare(value)
        self.ended(value).write_text(tok(value) + "\n")  # cleanup did not finish
        self.assertEqual(self.startup(), "")
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists() or self.records())

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_unreadable_ended_record_blocks_resume(self):
        self.prepare(self.label_value())
        ended = self.ended(self.value)
        ended.write_text("x")
        ended.chmod(0)
        self.addCleanup(lambda: ended.exists() and ended.chmod(0o600))
        self.assertEqual(self.startup(), "")

    def test_prune_skips_while_a_hook_holds_the_lock(self):
        self.enable_flag()
        stale = har.core_dir(self.core) / "t9"
        stale.touch()
        with har.state_lock(exclusive=False, wait=1) as held:
            self.assertTrue(held)
            self.assertIsNone(har.prune_markers())
        self.assertTrue(stale.exists())

    def test_prune_never_touches_a_core_with_a_longer_name(self):
        self.enable_flag()
        other = har.core_dir(har.core_key(str(self.root / "default--b.sock"))) / "t1"
        other.parent.mkdir()
        other.write_text("x")
        old = time.time() - 60
        os.utime(other, (old, old))
        har.prune_markers()
        self.assertTrue(other.exists())

    def test_failed_prune_spawn_retries_next_time(self):
        self.enable_flag()
        (har.core_dir(self.core) / ".pruned").unlink()
        with patch.object(har, "spawn_detached", side_effect=OSError("no fork")):
            har.maybe_prune()
        with patch.object(har, "spawn_detached") as spawn:
            har.maybe_prune()
        spawn.assert_called_once()

    def test_prune_stamp_is_per_core(self):
        self.enable_flag()
        b = self.listen("b")
        har.core_dir(har.core_key(str(b))).mkdir()
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": str(b)}):
            with patch.object(har, "spawn_detached") as spawn:
                har.maybe_prune()  # default's stamp is fresh, b has none
        spawn.assert_called_once()

    def test_prune_reads_core_names_literally(self):
        self.enable_flag()
        other = har.core_dir(har.core_key(str(self.root / "a.sock"))) / "t1.ended.0123456789abcdef"  # another core
        other.parent.mkdir()
        other.write_text("x")
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(other, (old, old))
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": "/run/x/[ab].sock"}):
            har.prune_markers()
        self.assertTrue(other.exists())

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_prune_keeps_an_unreadable_ended_record(self):
        self.prepare(self.label_value())
        ended = self.ended(self.label_value())
        ended.write_text("x")
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(ended, (old, old))
        ended.chmod(0)
        self.addCleanup(lambda: ended.exists() and ended.chmod(0o600))
        har.prune_markers()
        self.assertTrue(os.path.lexists(ended))

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_prune_keeps_an_unreadable_record_of_a_missing_terminal(self):
        self.enable_flag()
        ended = har.core_dir(self.core) / "t9.ended.0123456789abcdef"
        ended.write_text("x")
        ended.chmod(0)
        self.addCleanup(lambda: ended.exists() and ended.chmod(0o600))
        har.prune_markers()
        self.assertTrue(os.path.lexists(ended))

    def test_prune_never_touches_another_cores_sessions(self):
        self.enable_flag()
        (self.marker.parent / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        foreign = self.marker.parent / "t9"  # t9 is not a terminal of the live core
        foreign.write_text("another core's session")
        old = time.time() - 60
        os.utime(foreign, (old, old))
        self.assertIsNone(har.prune_markers())
        self.assertTrue(foreign.exists())

    def test_prune_aborts_when_the_socket_changes_hands(self):
        self.enable_flag()
        stale = self.marker.parent / "t9"
        stale.write_text("gone terminal")
        old = time.time() - 60
        os.utime(stale, (old, old))
        ids = iter([self.live_id(), "ffffffffffffffffffffffffffffffff"])
        with patch.object(har, "core_id", lambda: next(ids)):
            har.prune_markers()
        self.assertTrue(stale.exists())

    def test_prune_needs_a_saved_core_id(self):
        self.enable_flag()
        (self.marker.parent / ".core-id").unlink()
        stale = self.marker.parent / "t9"
        stale.write_text("gone terminal")
        old = time.time() - 60
        os.utime(stale, (old, old))
        har.prune_markers()
        self.assertTrue(stale.exists())

    def test_prune_keeps_an_ended_record_whose_label_came_back(self):
        session = self.label_value()
        self.prepare(session)
        ended = self.ended(session)
        ended.write_text(tok(session))
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(ended, (old, old))
        real_get = har.get_record
        calls = []

        def get(terminal):  # the label differs at first, then is back under the lock
            calls.append(terminal)
            record = real_get(terminal)
            if len(calls) == 1 and record:
                record = dict(record, labels={har.LABEL: "ffffffffffffffff"})
            return record

        with patch.object(har, "get_record", get):
            har.prune_markers()
        self.assertTrue(ended.exists())

    def test_slow_prune_never_starves_a_starting_session(self):
        self.prepare(self.label_value())
        for n in range(4):
            ended = self.marker.parent / f"t1{n}.ended.ffffffffffffffff"
            ended.write_text("ffffffffffffffff")
            old = time.time() - 2 * har.ENDED_MAX_AGE
            os.utime(ended, (old, old))
        state = self.state()
        for n in range(4):
            state["terminals"][f"t1{n}"] = {"pid": 5, "labels": {}}
        self.save_state(state)
        real_get = har.get_record

        def slow_get(terminal):
            time.sleep(0.9)
            return real_get(terminal)

        with patch.object(har, "get_record", slow_get):
            thread = threading.Thread(target=har.prune_markers)
            thread.start()
            time.sleep(0.2)
            started = time.monotonic()
            with har.state_lock(exclusive=False, wait=3.0) as held:
                waited = time.monotonic() - started
            thread.join(30)
        self.assertTrue(held)
        self.assertLess(waited, 1.0)

    def test_an_older_starts_ended_record_does_not_block(self):
        session = self.label_value()
        self.prepare(session)
        self.ended(self.label_value()).write_text("x")  # a late old exit
        self.assertTrue(self.startup().startswith("resume\tclaude\t"))

    def explicit_exit(self, **patches):
        payload = {"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"}
        stdout = io.StringIO()
        with contextlib.ExitStack() as stack:
            for name, value in patches.items():
                stack.enter_context(patch.object(har, name, value))
            stack.enter_context(patch.object(sys, "stdin", io.StringIO(json.dumps(payload))))
            stack.enter_context(redirect_stdout(stdout))
            har.main(["x", "--hook", "claude"])
        self.assertEqual(stdout.getvalue(), "")

    def test_explicit_exit_survives_a_busy_lock(self):
        session = self.label_value()
        self.prepare(session)
        with har.state_lock(exclusive=False, wait=1) as held:
            self.assertTrue(held)
            self.explicit_exit(process_table=lambda: {}, state_lock=lambda **kw: contextlib.nullcontext(False))
        self.assertEqual(self.ended(session).read_text().strip(), tok(session))
        self.assertEqual(self.startup(), "")  # recovery refuses it

    def test_explicit_exit_survives_a_failed_process_scan(self):
        session = self.label_value()
        self.prepare(session)
        self.explicit_exit(process_table=lambda: {})
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists())

    def test_a_late_old_exit_cannot_reopen_a_closed_newer_session(self):
        a, b = self.label_value(), self.label_value()
        self.prepare(b)  # B started after A
        self.ended(b).write_text(tok(b))  # and B was closed
        har.write_ended(self.marker, tok(a))  # then A's delayed exit hook writes
        self.assertTrue(self.ended(b).exists())
        self.assertEqual(self.startup(), "")

    def test_failed_ended_write_clears_only_its_own_generation(self):
        a, b = self.label_value(), self.label_value()
        self.prepare(b)
        self.marker.write_text(mtext(b))
        with patch.object(har, "write_ended", side_effect=OSError("full")), patch.object(
            har, "parse_marker", return_value=dict(b, gen=tok(a))
        ):
            state = self.state()
            state["terminals"]["t1"]["labels"][har.LABEL] = tok(a)  # A's view when the hook began
            self.save_state(state)
            real_get = har.get_record
            calls = []

            def get(terminal):  # B starts while A's hook runs
                record = real_get(terminal)
                calls.append(1)
                if len(calls) > 1:
                    record = dict(record, labels={har.LABEL: tok(b)})
                return record

            with patch.object(har, "get_record", get):
                self.explicit_exit()
        self.assertTrue(self.labels().get(har.LABEL))  # B's label was not cleared

    def test_ended_records_are_synced(self):
        self.prepare(self.label_value())
        with patch.object(har.os, "fsync", wraps=os.fsync) as fsync:
            har.write_ended(self.marker, self.value["gen"])
        self.assertGreaterEqual(fsync.call_count, 2)  # the file and its folder

    def test_failed_ended_write_fails_closed_under_the_lock(self):
        session = self.label_value()
        self.prepare(session)
        self.explicit_exit(process_table=lambda: {}, write_ended=lambda *a: (_ for _ in ()).throw(OSError("full")))
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.labels(), {})
        self.assertEqual(self.startup(), "")

    def test_failed_ended_write_never_deletes_a_newer_marker(self):
        a, b = self.label_value(), self.label_value()
        self.prepare(a)
        real_lock = har.state_lock

        @contextlib.contextmanager
        def lock_after_b_started(**kw):
            # B's start wins the race for the lock: its marker and label are in place.
            self.marker.write_text(mtext(b))
            self.put_label(b)
            with real_lock(**kw) as held:
                yield held

        self.explicit_exit(
            process_table=lambda: {},
            write_ended=lambda *a: (_ for _ in ()).throw(OSError("full")),
            state_lock=lock_after_b_started,
        )
        self.assertEqual(self.marker.read_text(), mtext(b))
        self.assertEqual(self.labels()[har.LABEL], tok(b))

    def test_folder_sync_failure_is_not_a_successful_write(self):
        self.prepare(self.label_value())
        with patch.object(har, "sync_dir", side_effect=OSError("io")):
            with self.assertRaises(OSError):
                har.write_ended(self.marker, self.value["gen"])

    def test_cleanup_syncs_before_waiting_for_the_lock(self):
        value = self.label_value()
        self.prepare(value)
        self.ended(value).write_text(tok(value))
        with patch.object(har, "sync_dir") as sync, patch.object(
            har, "state_lock", lambda **kw: contextlib.nullcontext(False)
        ):
            har.main(["x", "--shell-cleanup", "4242", tok(value)])
        sync.assert_called_once()

    def test_cleanup_holds_the_lock_for_at_most_one_hc_call(self):
        value = self.label_value()
        self.prepare(value)
        self.ended(value).write_text(tok(value))
        real_lock, under_lock, active = har.state_lock, [], []
        real_hc = har.hc

        @contextlib.contextmanager
        def lock(**kw):
            with real_lock(**kw) as held:
                under_lock.append([])
                active.append(True)
                try:
                    yield held
                finally:
                    active.pop()

        def hc(*args):
            if active:
                under_lock[-1].append(args[0])
            return real_hc(*args)

        with patch.object(har, "state_lock", lock), patch.object(har, "hc", hc):
            har.main(["x", "--shell-cleanup", "4242", tok(value)])
        self.assertEqual(under_lock, [["label"]])
        self.assertEqual(self.labels(), {})

    def test_session_end_from_outside_the_terminal_changes_nothing(self):
        session = self.label_value()
        self.prepare(session)
        stdout = io.StringIO()
        payload = {"hook_event_name": "SessionEnd", "session_id": SID, "reason": "prompt_input_exit"}
        with patch.object(har, "foreground_agent", return_value=False), patch.object(
            sys, "stdin", io.StringIO(json.dumps(payload))
        ), redirect_stdout(stdout):
            har.main(["x", "--hook", "claude"])
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_prune_keeps_a_marker_written_during_the_listing(self):
        self.enable_flag()
        state = self.state()
        state["terminals"]["t2"] = {"pid": 7, "labels": {}}
        self.save_state(state)
        late = har.core_dir(self.core) / "t2"
        real_ls = har.local_terminals

        def listing():
            found = real_ls()
            late.write_text("written after the listing")  # a new terminal's hook
            return [a for a in found if a != "t2"]

        with patch.object(har, "local_terminals", listing):
            har.prune_markers()
        self.assertTrue(late.exists())

    def test_prune_does_not_hold_the_lock_while_calling_hc(self):
        self.prepare(self.label_value())
        ended = self.ended(self.label_value())
        ended.write_text("x")
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(ended, (old, old))
        real_get = har.get_record
        held_during_get = []

        def get(terminal):
            with har.state_lock(exclusive=False, wait=0) as free:
                held_during_get.append(not free)
            return real_get(terminal)

        with patch.object(har, "get_record", get):
            har.prune_markers()
        # Judged, then re-checked, always without the lock.
        self.assertEqual(held_during_get, [False, False])
        self.assertFalse(ended.exists())

    def test_shell_clear_with_a_token_spares_a_newer_label(self):
        old, new = self.label_value(), self.label_value()
        self.prepare(new)
        self.assertEqual(har.main(["x", "--shell-clear", "4242", tok(old)]), 0)
        self.assertEqual(self.labels()[har.LABEL], tok(new))

    def test_prune_mode_runs_prune(self):
        self.enable_flag()
        stale = har.core_dir(self.core) / "t9"
        stale.touch()
        old = time.time() - 60
        os.utime(stale, (old, old))
        self.assertEqual(har.main(["x", "--prune"]), 0)
        self.assertFalse(stale.exists())

    def test_shell_clear_reports_failure(self):
        self.prepare(self.label_value(), fail=True)
        self.assertEqual(har.main(["x", "--shell-clear", "4242"]), 1)
        with har.state_lock(exclusive=False, wait=1):
            self.assertEqual(har.main(["x", "--shell-clear", "4242"]), 1)
        state = self.state()
        state["fail_label"] = False
        self.save_state(state)
        self.assertEqual(har.main(["x", "--shell-clear", "4242"]), 0)
        self.assertEqual(self.labels(), {})

    def test_any_ended_record_blocks_resume(self):
        for content in ("", "garbage", "0123456789abcdef"):
            session = self.label_value()
            self.prepare(session)
            self.ended(session).write_text(content)  # whatever it holds
            self.assertEqual(self.startup(), "", repr(content))
            self.assertEqual(self.labels(), {})

    def test_prune_removes_old_ended_records_whose_label_moved_on(self):
        self.prepare(self.label_value())
        ended = self.ended(self.label_value())  # an older start's record
        ended.write_text("x")
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(ended, (old, old))
        har.prune_markers()
        self.assertFalse(ended.exists())

    def test_prune_keeps_young_or_matching_ended_records(self):
        value = self.label_value()
        self.prepare(value)
        young = self.ended(self.label_value())
        young.write_text("x")  # young: a cleanup may still run
        har.prune_markers()
        self.assertTrue(young.exists())
        ended = self.ended(value)
        ended.write_text(tok(value))  # old but still matching: still needed
        old = time.time() - 2 * har.ENDED_MAX_AGE
        os.utime(ended, (old, old))
        har.prune_markers()
        self.assertTrue(ended.exists())

    def test_cleanup_drops_an_ended_record_a_new_start_replaced(self):
        old, new = self.label_value(), self.label_value()
        self.prepare(new)
        self.cleanup(expected=old)
        self.assertEqual(self.labels()[har.LABEL], tok(new))
        self.assertEqual(self.records(), [])

    def test_marker_and_label_must_match(self):
        self.prepare(self.label_value())
        self.marker.write_text(mtext(self.label_value(sid="eeeeeeee-4444")))
        self.assertEqual(self.startup(), "")
        self.assertEqual(self.labels(), {})

    def test_files_of_another_core_on_the_same_socket_are_left_alone(self):
        session = self.label_value()
        self.prepare(session)
        (self.marker.parent / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        self.assertEqual(self.startup(), "")
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_unconfirmed_identity_leaves_the_files_alone(self):
        session = self.label_value()
        self.prepare(session)
        (self.marker.parent / ".core-id").write_text(self.live_id() + "\n")
        with patch.object(har, "core_id", return_value=None):  # hc server status failed
            self.assertEqual(self.startup(), "")
            self.cleanup()
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_marker_under_an_old_socket_is_not_resumed(self):
        session = self.label_value()
        self.enable_flag()
        self.put_label(session)
        old = self.old_folder("ffffffffffffffffffffffffffffffff")
        (old / "t1").write_text(mtext(session))
        self.assertEqual(self.startup(), "")
        self.assertTrue((old / "t1").exists())
        self.assertEqual(self.labels()[har.LABEL], tok(session))

    def test_codex_plan(self):
        self.prepare(self.label_value(agent="codex"))
        self.assertTrue(self.startup().startswith("resume\tcodex\t"))

    def test_nested_shell_does_nothing(self):
        self.prepare(self.label_value())
        self.assertEqual(self.startup(pid=999), "")
        self.assertIn(har.LABEL, self.labels())

    def test_no_marker_no_hc_call(self):
        self.enable_flag()
        self.put_label(self.label_value())
        self.assertEqual(self.startup(), "")
        self.assertFalse(any(c[0] == "get" for c in self.calls()))

    def test_failed_removal_means_no_resume(self):
        self.prepare(self.label_value(), fail=True)
        self.assertEqual(self.startup(), "")
        self.assertIn(har.LABEL, self.labels())

    def test_invalid_label_is_cleared_not_run(self):
        self.prepare("Y3VybCBldmlsLnNoIHwgc2g=")
        self.assertEqual(self.startup(), "")
        self.assertEqual(self.labels(), {})

    def test_folder_or_transcript_gone(self):
        gone = self.root / "gone"
        gone.mkdir()
        self.prepare(self.label_value(cwd=gone))
        gone.rmdir()
        self.assertTrue(self.startup().startswith("msg\tfolder gone"))
        self.prepare(self.label_value(transcript=str(self.root / "missing.jsonl")))
        self.assertTrue(self.startup().startswith("msg\tnothing to resume"))

    def test_cleanup(self):
        self.prepare(self.label_value())
        self.cleanup()
        self.assertEqual(self.labels(), {})
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.records(), [])

    def test_cleanup_from_nested_shell_does_nothing(self):
        self.prepare(self.label_value())
        self.cleanup(pid=999)
        self.assertIn(har.LABEL, self.labels())
        self.assertTrue(self.marker.exists())

    def test_cleanup_keeps_marker_when_removal_fails(self):
        self.prepare(self.label_value(), fail=True)
        self.cleanup()
        self.assertTrue(self.marker.exists())

    def test_cleanup_never_touches_a_new_session(self):
        old = self.label_value()
        new = self.label_value(sid="cccccccc-2222")
        self.prepare(new)  # a new agent already wrote its label and marker
        self.cleanup(expected=old)
        self.assertEqual(self.labels()[har.LABEL], tok(new))
        self.assertEqual(self.marker.read_text(), mtext(new))

    def test_cleanup_skips_while_the_lock_is_busy(self):
        self.prepare(self.label_value())
        with har.writer_lock(self.marker, wait=1) as held:  # another writer of this terminal
            self.assertTrue(held)
            with patch.object(har.time, "monotonic", side_effect=itertools.count(0, 10).__next__):
                self.cleanup()
        self.assertIn(har.LABEL, self.labels())
        self.cleanup()
        self.assertEqual(self.labels(), {})

    def test_prune_stale_markers(self):
        self.enable_flag()
        self.marker.touch()
        stale = har.core_dir(self.core) / "t9"
        other_core = har.core_dir(har.core_key("/run/other/other.sock")) / "t9"
        other_core.parent.mkdir()
        stale.touch()
        other_core.touch()
        har.ended_path(self.marker, "0123456789abcdef").touch()
        self.assertEqual(har.prune_markers(), 1)
        self.assertTrue(har.ended_path(self.marker, "0123456789abcdef").exists())
        self.assertTrue(self.marker.exists() and other_core.exists())
        self.assertFalse(stale.exists())


class ManagementTest(Env):
    def run_cmd(self, name):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = har.main(["x", name])
        return code, stdout.getvalue()

    def claude_settings(self):
        return json.loads((self.home / ".claude" / "settings.json").read_text())

    def codex_hooks(self):
        return json.loads((self.home / ".codex" / "hooks.json").read_text())

    def seed(self):
        other = {"hooks": {"SessionStart": [{"matcher": "*", "hooks": [{"type": "command", "command": "other"}]}]}}
        for folder, name in ((".claude", "settings.json"), (".codex", "hooks.json")):
            (self.home / folder).mkdir()
            (self.home / folder / name).write_text(json.dumps(other))
        (self.home / ".zshrc").write_text("export FOO=1")

    def test_enable_disable_round_trip(self):
        self.seed()
        self.put_label("x", terminal="t1")
        code, out = self.run_cmd("enable")
        self.assertEqual(code, 0, out)
        claude, codex = self.claude_settings()["hooks"], self.codex_hooks()["hooks"]
        self.assertEqual(len(claude["SessionStart"]), 2)
        self.assertEqual(claude["SessionEnd"][0]["matcher"], "prompt_input_exit|logout")
        self.assertNotIn("SessionEnd", codex)
        self.assertEqual(claude["SessionStart"][1]["hooks"][0]["timeout"], har.HOOK_TIMEOUT)
        zshrc = (self.home / ".zshrc").read_text()
        self.assertTrue(zshrc.startswith("export FOO=1\n") and har.ZSHRC_TAG in zshrc)
        self.assertTrue(har.enabled_file().exists())
        self.assertEqual(oct(har.state_dir().stat().st_mode & 0o777), "0o700")
        self.assertIn("already", self.run_cmd("enable")[1])

        code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        for data in (self.claude_settings(), self.codex_hooks()):
            self.assertEqual(data["hooks"]["SessionStart"][0]["hooks"][0]["command"], "other")
            self.assertEqual(len(data["hooks"]), 1)
        self.assertEqual((self.home / ".zshrc").read_text(), "export FOO=1")  # byte for byte
        self.assertEqual(self.labels(), {})
        self.assertFalse(har.state_dir().exists())
        self.assertIn("already", self.run_cmd("disable")[1])

    def test_enable_changes_nothing_when_a_file_is_malformed(self):
        self.seed()
        claude_before = (self.home / ".claude" / "settings.json").read_text()
        (self.home / ".codex" / "hooks.json").write_text("{broken")
        code, out = self.run_cmd("enable")
        self.assertEqual(code, 1)
        self.assertIn("Nothing changed", out)
        self.assertEqual((self.home / ".claude" / "settings.json").read_text(), claude_before)
        self.assertNotIn(har.ZSHRC_TAG, (self.home / ".zshrc").read_text())
        self.assertFalse(har.state_dir().exists())

    def test_disable_reports_unreadable_terminal_and_kept_state(self):
        self.run_cmd("enable")
        state = self.state()
        state["terminals"]["t2"] = {"pid": 1, "labels": {}}
        self.save_state(state)
        hc = self.bin / "hc"
        hc.write_text(FAKE_HC.replace('if args[:1] == ["get"] and args[1] in terms:', 'if args[:1] == ["get"] and args[1] in terms and args[1] != "t2":'))
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("not readable", out)
        self.assertIn("kept default", out)
        self.assertTrue(har.core_dir(self.core).exists())

    def test_disable_reports_a_state_folder_it_cannot_remove(self):
        self.run_cmd("enable")
        with patch.object(har.shutil, "rmtree"):
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("could not be removed", out)

    def test_disable_names_the_file_of_each_error(self):
        self.run_cmd("enable")
        for folder, name in ((".claude", "settings.json"), (".codex", "hooks.json")):
            (self.home / folder / name).write_text("[]")
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("Not done: claude:", out)
        self.assertIn("Not done: codex:", out)

    def test_disable_changes_nothing_without_the_lock(self):
        self.run_cmd("enable")
        with patch.object(har, "state_lock", lambda **kw: contextlib.nullcontext(False)):
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("holds the lock", out)
        self.assertTrue(har.enabled_file().exists())
        self.assertIn(har.ZSHRC_TAG, (self.home / ".zshrc").read_text())

    def test_info_survives_malformed_file_and_lists_markers(self):
        self.run_cmd("enable")
        self.marker.parent.mkdir(exist_ok=True)
        self.marker.touch()
        (self.home / ".claude" / "settings.json").write_text("{broken")
        code, out = self.run_cmd("info")
        self.assertEqual(code, 0)
        self.assertIn("Claude Code hooks: unreadable", out)
        self.assertIn("zsh line: present", out)
        self.assertIn(f"Markers: 1 ({self.core}/t1)", out)

    def test_disable_keeps_lookalike_lines_and_hooks(self):
        self.seed()
        comment = "# I tried # sparkdock herdr-agent-resume once\n"
        (self.home / ".zshrc").write_text(comment)
        custom = {"matcher": "*", "hooks": [{"type": "command", "command": "my-wrapper herdr-agent-resume.py"}]}
        path = self.home / ".codex" / "hooks.json"
        data = json.loads(path.read_text())
        data["hooks"]["SessionStart"].append(custom)
        path.write_text(json.dumps(data))
        self.run_cmd("enable")
        self.run_cmd("disable")
        self.assertEqual((self.home / ".zshrc").read_text(), comment)
        self.assertIn(custom, json.loads(path.read_text())["hooks"]["SessionStart"])

    def test_owned_line_with_space_and_apostrophe_in_path(self):
        path = "/Users/o'neil/my tools/herdr-agent-resume.zsh"
        q = shlex.quote(path)
        self.assertTrue(har.owned_line(f"[[ -r {q} ]] && source {q}  {har.ZSHRC_TAG}\n"))

    def test_unrelated_empty_group_is_kept(self):
        data = {"hooks": {"SessionStart": [{"matcher": "x", "hooks": []}]}}
        data["hooks"]["SessionStart"].append({"matcher": "*", "hooks": [har.expected_hook("claude")]})
        har.unregister(data, "SessionStart")
        self.assertEqual(data, {"hooks": {"SessionStart": [{"matcher": "x", "hooks": []}]}})

    def test_rollback_keeps_a_concurrent_edit(self):
        self.seed()
        settings = self.home / ".claude" / "settings.json"
        real = har.update_hooks

        def update(path, hooks, agent, enable, cs):
            if agent == "codex":
                data = json.loads(settings.read_text())
                data["theme"] = "dark"  # someone else edits after our Claude write
                settings.write_text(json.dumps(data))
                raise OSError("disk full")
            return real(path, hooks, agent, enable, cs)

        with patch.object(har, "update_hooks", update):
            code, out = self.run_cmd("enable")
        self.assertEqual(code, 1)
        self.assertIn("Not rolled back", out)
        self.assertEqual(json.loads(settings.read_text())["theme"], "dark")

    def test_owned_line_matches_only_the_generated_shape(self):
        self.assertTrue(har.owned_line(har.zshrc_line() + "\n"))
        stale = "[[ -r '/old dir/herdr-agent-resume.zsh' ]] && source '/old dir/herdr-agent-resume.zsh'  # sparkdock herdr-agent-resume\n"
        self.assertTrue(har.owned_line(stale))
        for line in (
            "# sparkdock herdr-agent-resume\n",
            "source /x/herdr-agent-resume.zsh  # sparkdock herdr-agent-resume\n",
            "[[ -r /a/other.zsh ]] && source /a/other.zsh  # sparkdock herdr-agent-resume\n",
        ):
            self.assertFalse(har.owned_line(line), line)

    def test_rollback_knows_a_write_whose_output_failed(self):
        self.seed()
        settings = self.home / ".claude" / "settings.json"
        before = settings.read_text()
        real_print = print
        calls = []

        def broken_print(*args, **kwargs):
            calls.append(args)
            if len(calls) == 1:
                raise BrokenPipeError("stdout closed")
            return real_print(*args, **kwargs)

        with patch.object(har, "print", broken_print, create=True):
            with self.assertRaises(BrokenPipeError):
                har.cmd_enable()
        self.assertEqual(settings.read_text(), before)
        self.assertFalse(har.state_dir().exists())

    def test_failed_enable_rolls_back(self):
        self.seed()
        before = {p: p.read_text() for p in (self.home / ".claude" / "settings.json", self.home / ".codex" / "hooks.json", self.home / ".zshrc")}
        with patch.object(har, "update_zshrc", side_effect=OSError("disk full")):
            code, out = self.run_cmd("enable")
        self.assertEqual(code, 1)
        self.assertIn("rolled back", out)
        for path, text in before.items():
            self.assertEqual(path.read_text(), text, path)
        self.assertFalse(har.state_dir().exists())

    def test_enable_refuses_without_hc(self):
        with patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}):
            if shutil.which("hc"):
                self.skipTest("a real hc is installed in /usr/bin")
            code, out = self.run_cmd("enable")
        self.assertEqual(code, 1)
        self.assertIn("nothing changed", out)
        self.assertFalse((self.home / ".claude").exists() or har.state_dir().exists())

    def test_disable_keeps_a_line_added_after_enable(self):
        (self.home / ".zshrc").write_bytes(b"export A=1")
        self.run_cmd("enable")
        path = self.home / ".zshrc"
        lines = path.read_text().splitlines(keepends=True)
        lines.insert(len(lines) - 1, "export B=2\n")  # the person adds a line later
        path.write_text("".join(lines))
        self.run_cmd("disable")
        self.assertEqual(path.read_bytes(), b"export A=1\nexport B=2\n")

    def test_disable_keeps_an_identical_line_at_the_same_position(self):
        (self.home / ".zshrc").write_bytes(b"export B=2\nexport A=1")
        self.run_cmd("enable")
        path = self.home / ".zshrc"
        lines = path.read_text().splitlines(keepends=True)
        del lines[0]  # the person removes B ...
        lines.insert(len(lines) - 1, "export A=1\n")  # ... and adds the same A line again
        path.write_text("".join(lines))
        self.run_cmd("disable")
        self.assertEqual(path.read_bytes(), b"export A=1\nexport A=1\n")

    def test_disable_keeps_an_identical_line_added_later(self):
        (self.home / ".zshrc").write_bytes(b"export A=1")
        self.run_cmd("enable")
        path = self.home / ".zshrc"
        lines = path.read_text().splitlines(keepends=True)
        lines.insert(len(lines) - 1, "export A=1\n")  # the same text, added later
        path.write_text("".join(lines))
        self.run_cmd("disable")
        self.assertEqual(path.read_bytes(), b"export A=1\nexport A=1\n")

    def test_disable_on_a_fresh_home_takes_the_lock(self):
        self.assertFalse(har.lock_dir().exists())
        seen = []
        real = har.state_lock

        def lock(**kw):
            seen.append(har.lock_dir().exists())
            return real(**kw)

        with patch.object(har, "state_lock", lock):
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        self.assertEqual(seen, [True])  # the folder existed before locking

    def test_disable_never_claims_off_while_the_flag_remains(self):
        self.run_cmd("enable")

        class Stuck:
            def unlink(self, missing_ok=False):
                raise OSError("immutable")

            def __fspath__(self):
                return str(real_flag)

            def __str__(self):
                return str(real_flag)

        real_flag = har.enabled_file()
        with patch.object(har, "enabled_file", lambda: Stuck()), patch.object(har.shutil, "rmtree"):
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("may still be active", out)
        self.assertNotIn("The feature is off", out)

    def test_explicit_prune_writes_the_per_core_stamp(self):
        self.run_cmd("enable")
        har.core_dir(self.core).mkdir(parents=True, exist_ok=True)
        stamp = har.core_dir(self.core) / ".pruned"
        stamp.unlink(missing_ok=True)
        with har.on_core(str(self.socket)):
            har.prune_markers()
        self.assertTrue(stamp.exists())

    def test_crlf_zshrc_round_trips(self):
        (self.home / ".zshrc").write_bytes(b"export A=1\r\nexport B=2\r\n")
        self.run_cmd("enable")
        self.run_cmd("disable")
        self.assertEqual((self.home / ".zshrc").read_bytes(), b"export A=1\r\nexport B=2\r\n")

    def test_disable_continues_when_the_flag_cannot_be_removed(self):
        self.run_cmd("enable")

        class Stuck:
            def unlink(self, missing_ok=False):
                raise OSError("busy")

            def exists(self):
                return True

            def __str__(self):
                return "enabled"

        real = har.enabled_file
        with patch.object(har, "enabled_file", lambda: Stuck()):
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("Not done: enabled", out)
        self.assertNotIn(har.ZSHRC_TAG, (self.home / ".zshrc").read_text())

    def test_disable_waits_for_a_running_enable(self):
        self.seed()
        entered, release = threading.Event(), threading.Event()
        real_update = har.update_hooks

        def slow_update(path, hooks, agent, enable, cs):
            result = real_update(path, hooks, agent, enable, cs)
            if enable and agent == "claude":
                entered.set()
                release.wait(5)
            return result

        out = {}
        quiet = patch.object(har, "print", create=True)
        quiet.start()
        self.addCleanup(quiet.stop)
        with patch.object(har, "update_hooks", slow_update):
            enabler = threading.Thread(target=lambda: out.setdefault("enable", har.main(["x", "enable"])))
            enabler.start()
            entered.wait(5)
            disabler = threading.Thread(target=lambda: out.setdefault("disable", har.main(["x", "disable"])))
            disabler.start()
            time.sleep(0.5)
            self.assertTrue(disabler.is_alive())  # it waits for the enable
            release.set()
            enabler.join(15)
            disabler.join(15)
        self.assertEqual(out, {"enable": 0, "disable": 0})
        self.assertFalse(har.enabled_file().exists())
        self.assertNotIn("herdr-agent-resume.py", (self.home / ".claude" / "settings.json").read_text())
        self.assertNotIn("herdr-agent-resume.py", (self.home / ".codex" / "hooks.json").read_text())

    def test_zshrc_without_final_newline_round_trips(self):
        (self.home / ".zshrc").write_bytes(b"export FOO=bar")
        self.run_cmd("enable")
        self.assertIn(har.ZSHRC_EOL_PREFIX, (self.home / ".zshrc").read_text())
        self.assertIn("already", self.run_cmd("enable")[1])
        self.run_cmd("disable")
        self.assertEqual((self.home / ".zshrc").read_bytes(), b"export FOO=bar")

    def test_symlinked_zshrc_keeps_link(self):
        dotfiles = self.root / "dotfiles"
        dotfiles.mkdir()
        (dotfiles / "zshrc").write_text("# mine\n")
        (self.home / ".zshrc").symlink_to(dotfiles / "zshrc")
        self.run_cmd("enable")
        self.assertTrue((self.home / ".zshrc").is_symlink())
        self.assertIn(har.ZSHRC_TAG, (dotfiles / "zshrc").read_text())
        self.run_cmd("disable")
        self.assertTrue((self.home / ".zshrc").is_symlink())
        self.assertEqual((dotfiles / "zshrc").read_text(), "# mine\n")

    def test_disable_with_core_down_fails_until_retried(self):
        self.run_cmd("enable")
        state = self.state_file.read_text()
        self.state_file.write_text("broken")
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("labels not checked", out)
        self.assertFalse(har.enabled_file().exists())
        self.state_file.write_text(state)
        self.put_label(self.label_value())
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.labels(), {})

    def test_hc_runs_with_a_state_home_where_no_core_can_start(self):
        with patch.object(har.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "{}", "")
            har.hc("ls", "--json")
        env = run.call_args.kwargs["env"]
        self.assertEqual(env["XDG_STATE_HOME"], har.NO_START_STATE)
        self.assertEqual(env["HC_SOCKET"], str(self.socket))

    def test_same_socket_name_in_different_folders_are_different_cores(self):
        one = har.core_key("/run/user/1000/herdr-core/review.sock")
        two = har.core_key("/tmp/elsewhere/herdr-core/review.sock")
        self.assertNotEqual(one, two)
        self.assertEqual(har.core_label(one), har.core_label(two))

    def test_a_moved_core_is_handled_with_the_running_one(self):
        self.run_cmd("enable")
        stale = har.core_dir(har.core_key(str(self.root / "old" / "default.sock")))
        stale.mkdir()
        (stale / "t1").write_text("old session")
        (stale / ".core-id").write_text(self.live_id() + "\n")  # the same core
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        self.assertIn("moved", out)
        self.assertFalse(har.state_dir().exists())

    def test_disable_keeps_sessions_when_the_core_id_is_unavailable(self):
        self.run_cmd("enable")
        session = self.label_value()
        self.marker.parent.mkdir(exist_ok=True)
        (self.marker.parent / ".core-id").write_text(self.live_id() + "\n")
        self.marker.write_text(mtext(session))
        with patch.object(har, "core_id", return_value=None):  # hc server status failed
            code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("could not be matched", out)
        self.assertTrue(self.marker.exists())

    def test_disable_keeps_sessions_of_a_core_that_reused_the_socket(self):
        self.run_cmd("enable")
        folder = har.core_dir(self.core)
        folder.mkdir(exist_ok=True)
        (folder / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        (folder / "t7").write_text("another core's session")
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("could not be matched", out)
        self.assertTrue((folder / "t7").exists())

    def test_a_stopped_core_with_the_same_socket_name_is_not_moved(self):
        self.run_cmd("enable")
        other = har.core_dir(har.core_key(str(self.root / "other-root" / "default.sock")))
        other.mkdir()
        (other / "t1").write_text("a session")
        (other / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")  # a different core
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("not running", out)
        self.assertTrue((other / "t1").exists())

    def test_disable_keeps_a_core_whose_socket_is_unknown(self):
        self.run_cmd("enable")
        folder = har.core_dir("lost")
        folder.mkdir()
        (folder / "t3").write_text("a session")
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn("not a known core", out)
        self.assertTrue((folder / "t3").exists())

    def test_info_does_not_claim_no_cores_when_one_is_unresolved(self):
        self.run_cmd("enable")
        folder = har.core_dir("lost")
        folder.mkdir()
        (folder / "t3").write_text("a session")
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": ""}):
            code, out = self.run_cmd("info")
        self.assertNotIn("no core has recorded", out)
        self.assertIn("is not a known core", out)

    def test_disable_drops_an_unknown_core_with_no_sessions(self):
        self.run_cmd("enable")
        folder = har.core_dir("lost")
        folder.mkdir()
        (folder / ".pruned").touch()
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        self.assertFalse(har.state_dir().exists())

    def test_hc_is_never_called_without_a_running_core(self):
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": str(self.root / "gone.sock")}):
            self.assertIsNone(har.hc("ls", "--json"))
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": ""}):
            self.assertIsNone(har.hc("ls", "--json"))
        self.assertEqual(self.calls(), [])

    def other_core(self, running=True):
        """Core `b`, known from its folder, with one labelled terminal."""
        path = self.listen("b") if running else self.root / "b.sock"
        folder = har.core_dir(har.core_key(str(path)))
        folder.mkdir(parents=True, exist_ok=True)
        state_b = Path(str(self.state_file) + ".b")
        state_b.write_text(json.dumps({"terminals": {"t5": {"pid": 9, "labels": {har.LABEL: "0123456789abcdef"}}}}))
        return state_b

    def test_disable_clears_every_known_core(self):
        self.run_cmd("enable")
        state_b = self.other_core()
        self.put_label(self.label_value())
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.labels(), {})
        self.assertEqual(json.loads(state_b.read_text())["terminals"]["t5"]["labels"], {})
        self.assertFalse(har.state_dir().exists())

    def test_disable_keeps_a_stopped_core_for_a_retry(self):
        self.run_cmd("enable")
        self.other_core(running=False)
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertIn(f"core b ({self.root / 'b.sock'}): not running", out)
        self.assertTrue(har.core_dir(har.core_key(str(self.root / "b.sock"))).exists())
        self.assertFalse(har.enabled_file().exists())
        self.assertFalse(har.core_dir(self.core).exists())

    def test_disable_continues_past_a_malformed_file(self):
        self.run_cmd("enable")
        (self.home / ".claude" / "settings.json").write_text("{not json")
        code, out = self.run_cmd("disable")
        self.assertEqual(code, 1)
        self.assertNotIn("herdr-agent-resume.py", (self.home / ".codex" / "hooks.json").read_text())
        self.assertNotIn(har.ZSHRC_TAG, (self.home / ".zshrc").read_text())
        self.assertFalse(har.state_dir().exists())

    def test_enable_repairs_a_stale_hook(self):
        self.run_cmd("enable")
        path = self.home / ".claude" / "settings.json"
        data = json.loads(path.read_text())
        data["hooks"]["SessionStart"][0]["hooks"][0]["command"] = har.hook_prefix("claude") + "/old/place/herdr-agent-resume.py"
        path.write_text(json.dumps(data))
        code, out = self.run_cmd("enable")
        self.assertNotIn("already", out.splitlines()[0])
        entries = json.loads(path.read_text())["hooks"]["SessionStart"]
        self.assertEqual([e["hooks"][0]["command"] for e in entries], [har.hook_command("claude")])

    def test_hook_command_is_silent_when_script_is_gone(self):
        command = har.hook_command("claude").replace(str(SCRIPT), str(self.root / "gone.py"))
        result = subprocess.run(["sh", "-c", command], input="{}", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_hook_command_runs_script(self):
        self.enable_flag()
        result = subprocess.run(
            ["sh", "-c", har.hook_command("claude")], input="{}", capture_output=True, text=True
        )
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_info(self):
        self.run_cmd("enable")
        session = self.label_value()
        self.put_label(session)
        self.marker.parent.mkdir(exist_ok=True)
        (self.marker.parent / ".core-id").write_text(self.live_id() + "\n")
        self.marker.write_text(mtext(session))
        code, out = self.run_cmd("info")
        self.assertEqual(code, 0)
        self.assertIn(f"Labels (default ({self.socket})): 1", out)
        self.assertIn(f"t1: claude --resume {SID}", out)
        self.assertNotIn(session["cwd"], self.labels()[har.LABEL])

    def test_info_names_the_core_when_pruning(self):
        self.run_cmd("enable")
        session = self.label_value()
        self.put_label(session)
        self.marker.parent.mkdir(exist_ok=True)
        (self.marker.parent / ".core-id").write_text(self.live_id() + "\n")
        self.marker.write_text(mtext(session))
        stale = har.core_dir(self.core) / "t9"
        stale.touch()
        old = time.time() - 60
        os.utime(stale, (old, old))
        code, out = self.run_cmd("info")
        self.assertIn(f"Markers (default ({self.socket})): pruned 1 stale", out)

    def test_info_hides_another_cores_sessions(self):
        self.run_cmd("enable")
        session = self.label_value()
        self.put_label(session)
        self.marker.parent.mkdir(exist_ok=True)
        (self.marker.parent / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        self.marker.write_text(mtext(session))
        code, out = self.run_cmd("info")
        self.assertIn("belong to another core", out)
        self.assertNotIn(f"claude --resume {SID}", out)

    def test_core_id_mode_prints_the_id(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            har.main(["x", "--core-id"])
        self.assertEqual(stdout.getvalue().strip(), self.live_id())

    def test_warns_about_a_socket_path_too_long_to_record(self):
        long_path = "/" + "%" * 90 + "/x.sock"
        with patch.dict(os.environ, {"HC_TERMINAL_SOCKET": long_path}):
            self.assertTrue(any("too long" in w for w in har.warnings()))

    def test_warnings(self):
        with patch.dict(os.environ, {"SHELL": "/bin/bash"}):
            self.assertTrue(any("not zsh" in w for w in har.warnings()))


ZSH = shutil.which("zsh")

# Inserted into the fake hc: the record pid is the interactive zsh above it.
WALK = """import subprocess
def interactive_zsh():
    cache = path + ".zshpid"  # the ps walk is slow; retries use a 0.25 s timeout
    if os.path.exists(cache):
        return int(open(cache).read())
    found = walk_to_zsh()
    if found > 0:
        open(cache, "w").write(str(found))
    return found
def walk_to_zsh():
    pid = os.getppid()
    for _ in range(10):
        out = subprocess.run(["ps", "-o", "ppid=,args=", "-p", str(pid)], capture_output=True, text=True).stdout.split(None, 1)
        if len(out) < 2:
            return -1
        if out[1].split()[:2] in (["zsh", "-i"], ["zsh", "-il"]):
            return pid
        pid = int(out[0])
    return -1
"""

ZPTY_DRIVER = r"""
zmodload zsh/zpty
zpty -b sh "$HAR_SPAWN"
out=
for i in {1..80}; do
  zpty -r -t sh chunk 2>/dev/null && out+=$chunk
  [[ $out == *READY* ]] && break
  sleep 0.1
done
for cmd in "$@"; do
  zpty -w sh "$cmd"
  sleep 1
  while zpty -r -t sh chunk 2>/dev/null; do out+=$chunk; done
done
zpty -w sh 'exit'
sleep 0.3
while zpty -r -t sh chunk 2>/dev/null; do out+=$chunk; done
zpty -d sh
print -r -- "$out"
"""


@unittest.skipUnless(ZSH, "zsh required")
class ZshSnippetTest(Env):
    """Drive a real interactive zsh: startup resume, preexec cleanup and guards."""

    def setUp(self):
        super().setUp()
        self.zdot = self.root / "zdot"
        self.zdot.mkdir()
        self.log = self.root / "agent.log"
        for agent in ("claude", "codex"):
            fake = self.bin / agent
            fake.write_text(f'#!/bin/sh\necho "{agent} $* in $(pwd)" >> "{self.log}"\n')
            fake.chmod(0o755)
        (self.zdot / ".zshrc").write_text(
            f"PS1='READY> '\nsource {SNIPPET}\n" + "print -r -- SNIPPET-LOADED\n"
        )
        self.driver = self.root / "driver.zsh"
        self.driver.write_text(ZPTY_DRIVER)
        # The terminal's shell runs under the herdr-core holder: a copy of sh under
        # that name stays as the interactive zsh's parent.
        shutil.copy2("/bin/sh", self.bin / "herdr-core")

    def zsh(self, *commands, pid_follows_shell=True, under_holder=True, login=False):
        shell = "zsh -il" if login else "zsh -i"  # herdr-core starts `zsh -l` on macOS
        Path(str(self.state_file) + ".zshpid").unlink(missing_ok=True)  # a new shell, a new pid
        spawn = f"herdr-core -c '{shell}; exit'" if under_holder else shell
        env = dict(os.environ, ZDOTDIR=str(self.zdot), HAR_SPAWN=spawn)
        if pid_follows_shell:
            # The fake hc reports the interactive shell's pid as the record pid.
            hc = self.bin / "hc"
            hc.write_text(
                FAKE_HC.replace(
                    "t = dict(terms[args[1]]);",
                    "t = dict(terms[args[1]]); t['pid'] = interactive_zsh() if t['pid'] == -1 else t['pid'];",
                ).replace("terms = state", WALK + "terms = state")
            )
            state = self.state()
            state["terminals"]["t1"]["pid"] = -1
            self.save_state(state)
        result = subprocess.run(
            [ZSH, "-f", str(self.driver), *commands], env=env, capture_output=True, text=True, timeout=60
        )
        return result.stdout

    def agent_log(self):
        return self.log.read_text() if self.log.exists() else ""

    def prepare(self, value):
        self.enable_flag()
        self.marker.write_text(mtext(value))
        self.put_label(value)

    def stage_marker(self, value):
        """A command that creates the marker after startup, as a crashed agent leaves it."""
        staged = self.root / "staged-marker"
        staged.write_text(mtext(value))
        return f"cp {staged} {self.marker}"

    def test_recovered_terminal_resumes_in_folder(self):
        self.prepare(self.label_value())
        out = self.zsh()
        self.assertIn(f"herdr-agent-resume: resuming claude {SID}", out)
        self.assertEqual(self.agent_log(), f"claude --resume {SID} in {self.project}\n")
        self.assertEqual(self.labels(), {})

    def test_login_shell_resumes_and_cleans_up(self):
        self.prepare(self.label_value())
        out = self.zsh(login=True)
        self.assertIn(f"herdr-agent-resume: resuming claude {SID}", out)
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.zsh(self.stage_marker(value), "true", login=True)
        self.assertTrue(self.wait_until(lambda: self.labels() == {} and not self.marker.exists()))

    def test_codex_resume(self):
        self.prepare(self.label_value(agent="codex"))
        self.zsh()
        self.assertEqual(self.agent_log(), f"codex resume {SID} in {self.project}\n")

    def test_new_terminal_does_nothing(self):
        self.enable_flag()
        out = self.zsh("true")
        self.assertIn("SNIPPET-LOADED", out)
        self.assertEqual(self.agent_log(), "")
        self.assertEqual(self.calls(), [])

    def test_fresh_tab_prints_nothing(self):
        self.enable_flag()
        shutil.rmtree(har.core_dir(self.core))  # no folder for this core yet
        out = self.zsh("true")
        self.assertNotIn("no such file", out)
        self.assertNotIn("herdr-agent-resume", out)

    def test_disabled_does_nothing(self):
        self.prepare(self.label_value())
        har.enabled_file().unlink()
        self.zsh("true")
        self.assertEqual(self.agent_log(), "")
        self.assertIn(har.LABEL, self.labels())

    def test_preexec_clears_after_crash(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.zsh(self.stage_marker(value), "true")
        self.assertTrue(self.wait_until(lambda: self.labels() == {} and not self.marker.exists()))

    def test_preexec_retries_after_a_transient_failure(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value, fail=True)
        heal = self.root / "heal.py"
        heal.write_text(
            f"import json\np = {str(self.state_file)!r}\nd = json.load(open(p))\n"
            "d['fail_label'] = False\njson.dump(d, open(p, 'w'))\n"
        )
        self.zsh(self.stage_marker(value), "true", f"{sys.executable} {heal}", "sleep 2", "true")
        self.assertTrue(self.wait_until(lambda: self.labels() == {} and not self.marker.exists()))

    def test_shell_not_under_the_holder_never_cleans(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.zsh(self.stage_marker(value), "true", under_holder=False)
        time.sleep(1)
        self.assertEqual(self.labels().get(har.LABEL), tok(value))
        self.assertEqual(self.records(), [])

    def test_ended_record_exists_before_the_next_command_runs(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value, fail=True)  # cleanup cannot finish
        probe = self.root / "seen"
        self.zsh(self.stage_marker(value), f"cp {har.ended_path(self.marker, tok(value))} {probe}")
        self.assertEqual(probe.read_text().strip(), tok(value))

    def test_failed_ended_write_removes_the_marker(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        har.ended_path(self.marker, tok(value)).mkdir()  # the record cannot be written
        self.zsh(self.stage_marker(value), "true")
        self.assertFalse(self.marker.exists())

    @unittest.skipIf(os.geteuid() == 0, "root ignores directory permissions")
    def test_double_write_failure_clears_the_label_synchronously(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        folder = self.marker.parent
        self.addCleanup(folder.chmod, 0o700)
        # After startup: the marker appears, then the folder refuses new files and
        # deletes, so neither the ended record nor the marker removal can work.
        self.zsh(f"{self.stage_marker(value)} && chmod 500 {folder}", "true")
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.labels(), {})

    def test_failed_last_resort_retries_on_later_commands(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value, fail=True)  # the core cannot clear it yet
        folder = self.marker.parent
        self.addCleanup(folder.chmod, 0o700)
        heal = self.root / "heal.py"
        heal.write_text(
            f"import json\np = {str(self.state_file)!r}\nd = json.load(open(p))\n"
            "d['fail_label'] = False\njson.dump(d, open(p, 'w'))\n"
        )
        self.zsh(f"{self.stage_marker(value)} && chmod 500 {folder}", "true", f"{sys.executable} {heal}", "true")
        self.assertEqual(self.labels(), {})

    def test_retry_spares_a_newer_suspended_session(self):
        self.enable_flag()
        first, second = self.label_value(), self.label_value()
        self.put_label(first, fail=True)
        folder = self.marker.parent
        self.addCleanup(folder.chmod, 0o700)
        swap = self.root / "swap.py"
        swap.write_text(
            f"import json\np = {str(self.state_file)!r}\nd = json.load(open(p))\n"
            f"d['fail_label'] = False\nd['terminals']['t1']['labels']['{har.LABEL}'] = {tok(second)!r}\n"
            "json.dump(d, open(p, 'w'))\n"
        )
        self.zsh(
            f"{self.stage_marker(first)} && chmod 500 {folder}",
            "true",  # cannot record the end of `first`: a retry is pending
            f"{sys.executable} {swap}",  # a new session starts and is suspended
            "sleep 30 &",
            "true",
        )
        self.assertEqual(self.labels().get(har.LABEL), tok(second))

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_unreadable_marker_is_removed_before_the_command(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        self.zsh(f"{self.stage_marker(value)} && chmod 000 {self.marker}", "true")
        self.assertFalse(self.marker.exists())

    @unittest.skipIf(os.geteuid() == 0, "root reads mode-000 files")
    def test_snippet_works_under_ksh_arrays(self):
        self.prepare(self.label_value())
        (self.zdot / ".zshrc").write_text(
            f"PS1='READY> '\nsetopt KSH_ARRAYS\nsource {SNIPPET}\nprint -r -- SNIPPET-LOADED\n"
        )
        out = self.zsh()
        self.assertNotIn("bad output format", out)
        self.assertIn(f"herdr-agent-resume: resuming claude {SID}", out)

    def test_err_exit_does_not_skip_the_fallback(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        (self.zdot / ".zshrc").write_text(
            f"PS1='READY> '\nsetopt ERR_EXIT\nsource {SNIPPET}\nprint -r -- SNIPPET-LOADED\n"
        )
        probe = self.root / "alive"
        # An unreadable marker: the bare `read` fails, which ERR_EXIT turns into an exit.
        self.zsh(f"{self.stage_marker(value)} && chmod 000 {self.marker}", "true", f"echo yes > {probe}")
        self.assertTrue(probe.exists(), "the shell exited")
        self.assertFalse(self.marker.exists())

    def test_preexec_leaves_another_cores_session_alone(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        (self.marker.parent / ".core-id").write_text("ffffffffffffffffffffffffffffffff\n")
        self.zsh(self.stage_marker(value), "true")
        time.sleep(1)
        self.assertEqual(self.records(), [])
        self.assertTrue(self.marker.exists())
        self.assertEqual(self.labels().get(har.LABEL), tok(value))

    def test_failed_core_id_lookup_is_not_retried_on_every_command(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        hc = self.bin / "hc"
        hc.write_text(FAKE_HC.replace('if args[:2] == ["server", "status"]:', 'if False:'))
        log = self.root / "python.log"
        shim = self.bin / "python3"  # zsh calls python3 by name: log each call
        shim.write_text(f'#!/bin/sh\necho "$*" >> "{log}"\nexec "{sys.executable}" "$@"\n')
        shim.chmod(0o755)
        self.zsh(self.stage_marker(value), "true", self.stage_marker(value), "true", self.stage_marker(value), "true")
        lookups = [line for line in log.read_text().splitlines() if "--core-id" in line]
        self.assertEqual(len(lookups), 1)

    def test_preexec_keeps_label_while_job_suspended(self):
        self.enable_flag()
        value = self.label_value()
        self.put_label(value)
        # Background job stands in for a suspended agent; marker appears after startup.
        self.zsh("sleep 30 &", self.stage_marker(value), "true")
        time.sleep(1)
        self.assertEqual(self.labels().get(har.LABEL), tok(value))


if __name__ == "__main__":
    unittest.main()
