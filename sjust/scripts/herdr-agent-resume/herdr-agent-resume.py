#!/usr/bin/env python3
"""Resume Claude Code and Codex sessions in recovered herdr-core terminals.

Stopgap until herdr-core resumes agents natively through OSC 7501
(herdrdev/herdr-core#13, #15). See README.md next to this file.

Modes:
  --hook claude|codex     agent hook (stdin: hook JSON). Always exits 0, prints nothing.
  --shell-startup <pid>   called by the zsh snippet in a new shell; prints a resume plan.
  --shell-cleanup <pid> <token>
                          started in the background by the zsh snippet before a command;
                          clears the label of an agent that ended.
  --shell-clear <pid> [token]
                          last resort when zsh cannot write its local records; clears now.
  --prune                 deletes garbage markers; started detached by the hook once a day.
  --core-id               prints the current core's id (zsh asks once per shell).
  enable | disable | info management, run by the sjust recipes.
"""

import base64
import contextlib
import binascii
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))

LABEL = "sf.agent-resume"
OWNER = "herdr-agent-resume.py"  # substring that identifies our hook entries
ZSHRC_TAG = "# sparkdock herdr-agent-resume"
# Same line, when enable had to end the previous last line with a newline:
# disable then removes that newline again, restoring the file byte for byte.
ZSHRC_EOL_PREFIX = ZSHRC_TAG + " (added a final newline to a file hashing "
ZSHRC_EOL_RE = re.compile(re.escape(ZSHRC_EOL_PREFIX) + r"([0-9a-f]{16})\)$")
SCRIPT_PATH = Path(__file__).resolve()
SNIPPET_PATH = SCRIPT_PATH.with_name("herdr-agent-resume.zsh")
AGENTS = ("claude", "codex")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{7,127}$")
GEN_RE = re.compile(r"^[0-9a-f]{16}$")
ENDED_MAX_AGE = 86400  # prune: an ended record this old whose label moved on is garbage
NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")  # also keeps names free of "/"
MAX_MARKER = 4096
HC_TIMEOUT = 1.0
NO_START_STATE = "/dev/null/herdr-agent-resume"
HOOK_TIMEOUT = 15  # above the worst case: hc calls (1.5 s each with the probe), a ps scan, one 3 s lock budget
PRUNE_EVERY = 86400
SESSION_START_MATCHER = "startup|resume|clear|compact"
# Codex global options that take a value (`codex --help`, 0.167).
CODEX_VALUE_OPTIONS = frozenset(
    "-c --config --enable --disable --remote --remote-auth-token-env -i --image -m --model "
    "--local-provider -p --profile -s --sandbox -C --cd --add-dir -a --ask-for-approval".split()
)
# Claude only. Codex SessionEnd always reports "other", also on SIGTERM.
EXPLICIT_EXIT = ("prompt_input_exit", "logout")
CLAUDE_HOOKS = {"SessionStart": SESSION_START_MATCHER, "SessionEnd": "|".join(EXPLICIT_EXIT)}
CODEX_HOOKS = {"SessionStart": SESSION_START_MATCHER}
MANAGED_CLAUDE_SETTINGS = (
    "/Library/Application Support/ClaudeCode",
    "/etc/claude-code",
)


# ---------------------------------------------------------------- state paths
#
# Every file below is written whole and atomically: a temp file next to it, then
# a rename, so a reader never sees half a file.


def atomic_write(path, text, sync=False, mode=None):
    """Write `text` to `path` through a temp file and a rename. `sync` makes the
    rename survive a power loss (raises OSError when it may not); `mode` sets
    the permissions (mkstemp creates 0600)."""
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", newline="") as f:
            f.write(text)
            if sync:
                f.flush()
                os.fsync(f.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    if sync:
        sync_dir(path.parent)


def sync_dir(folder):
    """Make a rename in `folder` survive a power loss. Raises OSError on failure:
    a caller relying on the record must know it may not be durable."""
    fd = os.open(folder, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def flock_until(fd, mode, deadline):
    """Take `flock(fd, mode)`, retrying until `deadline`. True when held."""
    import fcntl

    while True:
        try:
            fcntl.flock(fd, mode | fcntl.LOCK_NB)
            return True
        except OSError:
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.05)


def state_dir():
    return Path.home() / ".config" / "spark" / "herdr-agent-resume"


def lock_dir():
    """The lock is a `flock` on `~/.config/spark` itself: enable and disable
    create and delete the state folder inside it, never this folder, so every
    waiter and every holder share one lock (no stale lock-file generations)."""
    return state_dir().parent


@contextlib.contextmanager
def state_lock(exclusive, wait):
    """Yield True while holding the state lock; False when busy past `wait`."""
    import fcntl

    try:
        fd = os.open(lock_dir(), os.O_RDONLY)
    except OSError:
        yield False
        return
    try:
        mode = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        yield flock_until(fd, mode, time.monotonic() + wait)
    finally:
        os.close(fd)


@contextlib.contextmanager
def writer_lock(marker, wait):
    """A writer's lock: the state lock shared (disable and prune deletions take it
    exclusively, so they wait for writers and stop new ones) plus an exclusive
    lock on this terminal alone. Writers for different terminals never wait on
    each other; two for the same terminal never interleave."""
    import fcntl

    deadline = time.monotonic() + wait  # one budget for both stages
    with state_lock(exclusive=False, wait=wait) as held:
        # Under the lock, before creating anything: disable may have run while we waited.
        if not held or not enabled_file().exists():
            yield False
            return
        try:
            make_private_dir(marker.parent)
            fd = os.open(marker.parent / f".{marker.name}.lock", os.O_RDWR | os.O_CREAT, 0o600)
        except OSError:
            yield False
            return
        try:
            yield flock_until(fd, fcntl.LOCK_EX, deadline)
        finally:
            os.close(fd)


def make_private_dir(folder):
    """Create a core folder readable by its owner alone (zsh writes ended records
    with the person's umask; the folder keeps them private)."""
    folder.mkdir(parents=True, exist_ok=True)
    os.chmod(folder, 0o700)


def enabled_file():
    return state_dir() / "enabled"


def markers_dir():
    return state_dir() / "markers"


CORE = {"socket": None}  # the core management commands are talking to right now


def current_socket():
    """The core socket for hc calls: the one a management loop selected, else the
    terminal's own core. None outside herdr-core: then hc is never called."""
    return CORE["socket"] or os.environ.get("HC_TERMINAL_SOCKET") or None


@contextlib.contextmanager
def on_core(path):
    """Point hc calls at the core on `path` for the duration of the block."""
    CORE["socket"] = path
    try:
        yield
    finally:
        CORE["socket"] = None


def core_key(path):
    """A core's folder name: its full socket path, with `%` and `/` encoded.

    Two cores never share a folder (sockets differ in name or directory), the
    socket can be read back from the name, and zsh computes the same key with
    parameter expansion alone.
    """
    if not isinstance(path, str) or not os.path.isabs(path) or "\0" in path or "\n" in path:
        return None
    key = path.replace("%", "%25").replace("/", "%2F")
    return key if len(key) <= 240 else None


def core_socket(key):
    path = key.replace("%2F", "/").replace("%25", "%")
    return path if core_key(path) == key else None


def core_label(key):
    """Readable name for messages: the socket file name without `.sock`."""
    name = Path(core_socket(key) or key).name
    return name[: -len(".sock")] if name.endswith(".sock") else name


def core_name(env=None):
    """The current core's key, or None outside herdr-core."""
    return core_key(current_socket() if env is None else env.get("HC_TERMINAL_SOCKET"))


def core_dir(core):
    """One folder per core, named by core_key."""
    return markers_dir() / core


def marker_name(terminal):
    """A terminal's marker file name inside its core folder, or None for unsafe names."""
    terminal = terminal.replace("/", "_")
    return terminal if NAME_RE.match(terminal) else None


def marker_path(env=None):
    env = os.environ if env is None else env
    core = core_name(env)
    name = marker_name(env.get("HC_TERMINAL_ID", ""))
    return core_dir(core) / name if core and name else None


def known_cores():
    """({core key: socket}, [unresolved keys]) for every core folder plus the
    current terminal's core. A folder whose name is not a socket key is
    unresolved: its labels cannot be reached from here."""
    cores, unresolved = {}, []
    if markers_dir().is_dir():
        for folder in sorted(markers_dir().iterdir()):
            if not folder.is_dir():
                continue
            path = core_socket(folder.name)
            if path:
                cores[folder.name] = path
            else:
                unresolved.append(folder.name)
    own = core_key(os.environ.get("HC_TERMINAL_SOCKET"))
    if own:
        cores[own] = core_socket(own)
    return cores, unresolved


CORE_ID_RE = re.compile(r"^[0-9a-f]{16,64}$")


def core_id():
    """The current core's id from `hc server status`: stable across restarts and
    socket moves (herdr-core keeps it in its state), unlike the socket path."""
    status = hc("server", "status", "--json")
    core = status.get("core") if isinstance(status, dict) else None
    value = core.get("id") if isinstance(core, dict) else None
    return value if isinstance(value, str) and CORE_ID_RE.match(value) else None


def saved_core_id(key):
    value = first_line(read_marker(core_dir(key) / ".core-id"))
    return value if value and CORE_ID_RE.match(value) else None


def remember_core_id(key, value):
    """Atomic write of the folder's core id (part of a successful start)."""
    if saved_core_id(key) != value:
        atomic_write(core_dir(key) / ".core-id", value + "\n")


def running_core_ids(cores):
    """{key: core id} for the cores that answer now."""
    ids = {}
    for key, path in cores.items():
        with on_core(path):
            value = core_id()
        if value:
            ids[key] = value
    return ids


def holds_sessions(key):
    folder = core_dir(key)
    return folder.is_dir() and any(not p.name.startswith(".") for p in folder.iterdir())


def confirmed(key, live_id):
    """The core answering on this folder's socket is the one that wrote it: its
    id is known and equals the saved one. Without that positive match, a folder
    that holds sessions is never read for a resume nor changed."""
    return bool(live_id) and saved_core_id(key) == live_id


def moved(key, running):
    """A folder of a core that now answers on another socket: its saved core id
    belongs to a running core under a different key. Same socket name alone
    proves nothing: separate cores can share it."""
    value = saved_core_id(key)
    return bool(value) and value in running.values() and running.get(key) != value


UNREADABLE = object()  # a file that exists but cannot be read


def read_marker(path):
    """File content, None when absent, UNREADABLE when it exists but cannot be read."""
    try:
        return path.read_text()
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError):
        return UNREADABLE


def first_line(text):
    return text.split("\n", 1)[0].strip() if isinstance(text, str) else None


def write_ended(marker, token):
    """Atomic, synced write of the ended record of one generation."""
    atomic_write(ended_path(marker, token), token + "\n", sync=True)


def ended_path(marker, token):
    """`<terminal>.ended.<token>`: written before the next command runs (zsh) or at
    an explicit exit (hook) for the generation that ended. One file per
    generation, so a late exit of an older session can never replace a newer
    one's: recovery blocks when the record of the label's own token exists."""
    return marker.with_name(f"{marker.name}.ended.{token}")


def ended_records(marker):
    """All ended records of this terminal, any generation."""
    prefix = marker.name + ".ended."
    folder = marker.parent
    return [p for p in folder.iterdir() if p.name.startswith(prefix)] if folder.is_dir() else []


def ended_token(path):
    """The generation in an ended record's name, or None."""
    token = path.name.rsplit(".ended.", 1)[-1] if ".ended." in path.name else None
    return token if valid_token(token) else None


# -------------------------------------------------------------------- session
#
# The terminal label holds only a random token, new on every start: it shows in
# process lists and in herdr-core, so it carries nothing about the session. The
# session (agent, id, folder, transcript) lives in the private marker file:
#
#     <token>
#     <base64 JSON {agent, id, cwd, transcript, gen: <token>}>
#
# A new token per start means restarting the same session (`codex resume <id>`)
# never matches the ended record of its previous run.


def new_session(agent, session_id, cwd, transcript, gen=None):
    data = {
        "agent": agent,
        "id": session_id,
        "cwd": cwd,
        "transcript": transcript,
        "gen": gen or os.urandom(8).hex(),
    }
    return data if valid_session(data) and len(marker_text(data)) <= MAX_MARKER else None


def marker_text(session):
    blob = base64.b64encode(json.dumps(session, separators=(",", ":")).encode()).decode()
    return f"{session['gen']}\n{blob}\n"


def parse_marker(text):
    """The session in a marker, or None unless it is complete and consistent."""
    if not isinstance(text, str) or len(text) > MAX_MARKER:
        return None
    lines = text.split("\n")
    if len(lines) < 2:
        return None
    try:
        data = json.loads(base64.b64decode(lines[1].strip(), validate=True).decode())
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    if not valid_session(data) or data["gen"] != lines[0].strip():
        return None
    return data


def valid_token(value):
    return isinstance(value, str) and bool(GEN_RE.match(value))


def valid_session(data):
    if not isinstance(data, dict):
        return False
    transcript = data.get("transcript")
    cwd = data.get("cwd")
    return (
        data.get("agent") in AGENTS
        and valid_token(data.get("gen"))
        and isinstance(data.get("id"), str)
        and bool(ID_RE.match(data["id"]))
        and isinstance(cwd, str)
        and os.path.isabs(cwd)
        and "\n" not in cwd
        and "\t" not in cwd
        and (transcript is None or (isinstance(transcript, str) and os.path.isabs(transcript)))
    )


def resume_command(session):
    if session["agent"] == "claude":
        return f"claude --resume {session['id']}"
    return f"codex resume {session['id']}"


# ------------------------------------------------------------------------- hc


def core_alive(path):
    """A core answers on its socket. Cheap gate before running hc; the real
    guarantee against starting a core is NO_START_STATE (see hc())."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.5)
            probe.connect(path)
        return True
    except OSError:
        return False


def hc(*args):
    """Run hc against current_socket() with a hard timeout; return parsed JSON,
    True, or None on failure (also when the core is not running)."""
    exe = shutil.which("hc")
    path = current_socket()
    if not exe or not path or not core_alive(path):
        return None
    try:
        result = subprocess.run(
            [exe, *args],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=HC_TIMEOUT,
            # hc starts a core when it cannot connect, after creating its state
            # folder: one under /dev/null cannot exist, so that start always fails.
            env=dict(os.environ, HC_SOCKET=path, XDG_STATE_HOME=NO_START_STATE),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    if "--json" not in args:
        return True
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


def get_record(terminal):
    record = hc("get", terminal, "--json")
    return record if isinstance(record, dict) else None


def labels_of(record):
    labels = record.get("labels") if isinstance(record, dict) else None
    return labels if isinstance(labels, dict) else {}


def set_label(terminal, value):
    return hc("label", terminal, f"{LABEL}={value}") is True


def clear_label(terminal):
    return hc("label", terminal, f"{LABEL}=") is True


def local_terminals():
    listing = hc("ls", "--json")
    if not isinstance(listing, dict) or not isinstance(listing.get("terminals"), list):
        return None
    return [
        t["address"]
        for t in listing["terminals"]
        if isinstance(t, dict) and isinstance(t.get("address"), str) and "/" not in t["address"]
    ]


def in_herdr_core(env=None):
    env = os.environ if env is None else env
    return bool(env.get("HC_TERMINAL_ID")) and env.get("HERDR_ENV") != "1"


# ---------------------------------------------------------------- process tree


def process_table():
    """{pid: (ppid, pgid, tpgid)} from ps; works with BSD and procps. Command
    lines come from process_argv: ps joins arguments with spaces."""
    try:
        out = subprocess.run(
            ["ps", "-A", "-o", "pid=,ppid=,pgid=,tpgid="],
            capture_output=True,
            text=True,
            timeout=HC_TIMEOUT,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    table = {}
    for line in out.splitlines():
        try:
            pid, ppid, pgid, tpgid = (int(p) for p in line.split())
        except ValueError:
            continue
        table[pid] = (ppid, pgid, tpgid)
    return table


def process_argv(pid):
    """Exact argv of `pid` (ps joins it with spaces), or None when unavailable."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            data = f.read()
        if data:
            return [a.decode(errors="replace") for a in data.rstrip(b"\0").split(b"\0")]
    except OSError:
        pass
    return darwin_argv(pid) if sys.platform == "darwin" else None


def darwin_argv(pid):
    """argv through sysctl KERN_PROCARGS2: argc, exec path, padding, then argv."""
    import ctypes
    import ctypes.util

    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
        size = ctypes.c_size_t(0)
        if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0:
            return None
        buf = ctypes.create_string_buffer(size.value)
        if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
            return None
        raw = buf.raw[: size.value]
        argc = int.from_bytes(raw[:4], sys.byteorder)
        rest = raw[4:]
        rest = rest[rest.find(b"\0") :].lstrip(b"\0")
        args = rest.split(b"\0")[:argc]
        return [a.decode(errors="replace") for a in args] if len(args) == argc else None
    except (OSError, ValueError, AttributeError):
        return None


def agent_of(argv):
    """"claude" or "codex" when argv runs one of them, else None."""
    name = os.path.basename(argv[0]) if argv else None
    return name if name in AGENTS else None


def one_shot(argv, agent):
    """Non-interactive runs (exact argv): `claude -p`, `codex exec`/`e`."""
    if agent == "claude":
        return any(a in ("-p", "--print") or a.startswith("--print=") for a in argv[1:])
    return codex_subcommand(argv) in ("exec", "e")


def codex_subcommand(argv):
    """First positional argument, skipping global options and their values."""
    args = iter(argv[1:])
    for arg in args:
        if arg == "--":
            return None
        if arg.startswith("-"):
            if arg in CODEX_VALUE_OPTIONS:
                next(args, None)
            continue
        return arg
    return None


def foreground_agent(table, start, record_pid, agent, argv_of=process_argv):
    """True when the nearest `agent` above `start` runs in the terminal's foreground.

    The walk must reach the terminal's process. No other Claude or Codex may sit
    between the nearest agent and the terminal (nested agents started by tools,
    of either type), and the
    process right below the terminal, or the terminal itself when it is the agent,
    must be the tty's foreground process group (rules out tmux and background jobs).

    Returns None when the process table or an argv in the chain could not be
    read: callers decide which way is safe (a start records nothing; an exit
    still ends the session).
    """
    if not table or start not in table:
        return None
    chain, pid = [], start
    for _ in range(64):
        if pid not in table:
            return False
        chain.append(pid)
        if pid == record_pid:
            break
        pid = table[pid][0]
        if pid <= 1:
            return False
    else:
        return False
    # Exact argv for every process in the chain: ps joins arguments with spaces,
    # so an executable under a path with spaces would be misread from its words.
    argv = {p: argv_of(p) for p in chain}
    if any(value is None for value in argv.values()):
        return None  # cannot identify every process reliably: fail closed
    agents = [p for p in chain if agent_of(argv[p])]
    if len(agents) != 1 or agent_of(argv[agents[0]]) != agent:
        return False
    nearest = agents[0]
    if one_shot(argv[nearest], agent):
        return False
    top = record_pid if nearest == record_pid else chain[-2]
    _, pgid, tpgid = table[top]
    return tpgid > 0 and pgid == tpgid


# ----------------------------------------------------------------------- hook


def active_marker():
    """This terminal's marker path while the feature is on inside herdr-core, else None."""
    if not enabled_file().exists() or not in_herdr_core():
        return None
    return marker_path()


def run_hook(agent):
    marker = active_marker()
    if agent not in AGENTS or marker is None:
        return 0
    try:
        payload = json.loads(sys.stdin.read(1 << 20) or "{}")
    except ValueError:
        return 0
    if not isinstance(payload, dict):
        return 0
    terminal = os.environ["HC_TERMINAL_ID"]
    event = payload.get("hook_event_name")
    if event not in ("SessionStart", "SessionEnd"):
        return 0
    record = get_record(terminal)
    if record is None or not isinstance(record.get("pid"), int):
        return 0

    if event == "SessionEnd":
        if agent != "claude" or payload.get("reason") not in EXPLICIT_EXIT:
            return 0
        token = labels_of(record).get(LABEL)
        if not valid_token(token):
            return 0
        # Skip only when the scan positively shows another process (a Claude
        # elsewhere that inherited the terminal's variables). An unreadable
        # process table still ends the session: a closed session never resumes.
        if foreground_agent(process_table(), os.getpid(), record["pid"], agent) is False:
            return 0
        raw = read_marker(marker)
        session = parse_marker(raw)
        ours = (
            session
            and session["gen"] == token
            and session["agent"] == agent
            and session["id"] == payload.get("session_id")
        )
        if raw is not UNREADABLE and not ours:
            return 0
        # First, durably and without any lock: the ended record blocks a resume
        # even if the cleanup below cannot run now.
        try:
            write_ended(marker, token)
        except OSError:
            # No durable ended record (the disk refuses writes). Under the
            # exclusive lock, serialized with any new start: delete this
            # generation's marker (without one, recovery resumes nothing) and
            # clear the label while it still holds this generation. When the
            # lock stays busy too, this double failure is a documented limit.
            with writer_lock(marker, wait=3.0) as held:
                if not held:
                    return 0
                if first_line(read_marker(marker)) == token:
                    try:
                        marker.unlink()
                        sync_dir(marker.parent)
                    except OSError:
                        pass
                current = get_record(terminal)
                if current is not None and labels_of(current).get(LABEL) == token:
                    clear_label(terminal)
            return 0
        # Then the cleanup, under the exclusive lock (a new start, also exclusive,
        # cannot interleave). Busy: the next command's cleanup finishes it.
        with writer_lock(marker, wait=3.0) as held:
            if held and first_line(read_marker(marker)) == token and clear_label(terminal):
                marker.unlink(missing_ok=True)
                ended_path(marker, token).unlink(missing_ok=True)
        return 0

    if not foreground_agent(process_table(), os.getpid(), record["pid"], agent):
        return 0
    transcript = payload.get("transcript_path")
    session = new_session(
        agent,
        payload.get("session_id"),
        payload.get("cwd"),
        transcript if isinstance(transcript, str) and transcript else None,
    )
    if session is None or not os.path.isdir(session["cwd"]):
        return 0
    # Exclusive: two starts in one terminal must not interleave their label and
    # marker writes (and disable, cleanup and exits are serialized with them).
    with writer_lock(marker, wait=3.0) as held:
        # Disable removes the flag under the exclusive state lock: re-check it here.
        if not (held and enabled_file().exists()):
            return 0
        cid = core_id()
        key = marker.parent.name
        # Sessions here that this core cannot be shown to own: leave them alone.
        if not cid or (holds_sessions(key) and not confirmed(key, cid)):
            return 0
        try:
            remember_core_id(key, cid)  # writer_lock created the folder
        except OSError:
            return 0
        if not set_label(terminal, session["gen"]):
            return 0
        try:
            atomic_write(marker, marker_text(session))
        except OSError:
            clear_label(terminal)  # never leave a label without its marker
            return 0
        # Ended records of earlier generations can never match again.
        for old in ended_records(marker):
            if ended_token(old) != session["gen"]:
                old.unlink(missing_ok=True)
    maybe_prune()
    return 0


# ---------------------------------------------------------------------- shell


def shell_startup(shell_pid):
    """Print the resume plan for a recovered terminal, one tab-separated line."""
    marker = active_marker()
    if marker is None:
        return 0
    if not os.path.lexists(marker) and not ended_records(marker):
        return 0  # nothing recorded here: no hc call
    terminal = os.environ["HC_TERMINAL_ID"]
    record = get_record(terminal)
    if record is None or record.get("pid") != shell_pid:
        return 0
    if not confirmed(marker.parent.name, core_id()):
        return 0  # not shown to be this core's files: leave them alone
    token = labels_of(record).get(LABEL)
    session = parse_marker(read_marker(marker))
    # The label's own generation ended (its record exists, whatever it holds).
    ended_blocks = valid_token(token) and os.path.lexists(ended_path(marker, token))
    # Remove first: a failed or interrupted resume never repeats. No removal, no resume.
    if token is not None and not clear_label(terminal):
        return 0
    marker.unlink(missing_ok=True)
    for old in ended_records(marker):
        old.unlink(missing_ok=True)
    # Resume only the session the marker was written for, and never when its
    # ended record exists. Fail closed.
    if session is None or session["gen"] != token or ended_blocks:
        return 0
    if not os.path.isdir(session["cwd"]):
        print(f"msg\tfolder gone, not resuming {session['agent']} {session['id']}")
    elif session["transcript"] and not os.path.exists(session["transcript"]):
        print(f"msg\tnothing to resume for {session['agent']} {session['id']}")
    else:
        print(f"resume\t{session['agent']}\t{session['id']}\t{session['cwd']}")
    return 0


def shell_cleanup(shell_pid, expected):
    """The top-level shell ran a command: an agent recorded here has ended.

    Runs in the background, so a slow or hung core never delays the shell. zsh
    wrote the ended record (the session token) before starting this process.
    Under the exclusive lock (a new agent's hook takes it too), the
    label is cleared only while it still holds that token, and the marker and the
    ended record are deleted only while they still hold it: a new session survives.
    """
    marker = active_marker()
    if marker is None or not valid_token(expected):
        return 0
    ended = ended_path(marker, expected)
    if not os.path.lexists(ended):
        return 0
    terminal = os.environ["HC_TERMINAL_ID"]
    try:
        sync_dir(marker.parent)  # first, lock or not: zsh wrote it without syncing
    except OSError:
        pass
    # Read-only checks before the lock, so a new start never waits on them.
    record = get_record(terminal)
    # A shell nested inside a running agent must not clear that agent's label.
    if record is None or record.get("pid") != shell_pid:
        return 0
    if not confirmed(marker.parent.name, core_id()):
        return 0  # retried on the next command
    with writer_lock(marker, wait=5.0) as held:
        # Still busy (another cleanup, a hook writing, or disable): the next
        # command retries; the synced ended record already blocks a resume.
        if not held or not os.path.lexists(ended):
            return 0
        # A start writes its label and marker together under the lock,
        # so while the marker still holds this token, so does the label: one
        # hc call under the lock, and a newer start is never touched.
        if first_line(read_marker(marker)) == expected:
            if clear_label(terminal):
                marker.unlink(missing_ok=True)
                ended.unlink(missing_ok=True)
        else:
            ended.unlink(missing_ok=True)  # the marker is gone or a newer start's
    return 0


def shell_clear(shell_pid, token=None):
    """Last resort, run synchronously by zsh when it could neither write the ended
    record nor remove the marker: clear the label now. zsh calls it only from the
    top-level shell with no jobs, so no agent runs in this terminal. With a token,
    only that start's label is cleared; a newer label means nothing is left to do.
    Exit 0 when nothing is left to clear, 1 otherwise: zsh retries later."""
    if not enabled_file().exists() or not in_herdr_core():
        return 0
    terminal = os.environ["HC_TERMINAL_ID"]
    # Shared state lock only: this runs when the disk refuses writes, so no
    # terminal lock file can be created; no agent runs in this shell meanwhile.
    with state_lock(exclusive=False, wait=2.0) as held:
        record = get_record(terminal) if held else None
        if record is None or record.get("pid") != shell_pid:
            return 1
        current = labels_of(record).get(LABEL)
        if current is None or (token is not None and current != token):
            return 0
        return 0 if clear_label(terminal) else 1


def terminal_of(path):
    """The terminal a core folder file belongs to: its marker `<t>`, its ended
    records `<t>.ended.<token>` and its writer lock `.<t>.lock`. None for the
    folder's own dot files (`.core-id`, `.pruned`, temp files)."""
    name = path.name
    if name.startswith("."):
        return name[1:-5] if name.endswith(".lock") and name != ".lock" else None
    return name.split(".ended.", 1)[0]


def prune_markers():
    """Delete this core's markers and ended records that are garbage.

    Every hc call runs without the lock, so a hook starting a session never
    waits on hc. Two passes judge the files, the second confirming the same core
    (its id still answers and equals the folder's saved id) and a fresh listing.
    The short exclusive lock covers only local checks: files unchanged since
    (a hook writes its marker under the lock; a rewrite gets a new mtime).
    """
    core = core_name()
    if not core:
        return None
    folder = core_dir(core)
    started = time.time()
    live = core_id()
    if not live or (holds_sessions(core) and not confirmed(core, live)):
        return None  # sessions of a core not shown to be this one: never prune them
    addresses = local_terminals()
    if addresses is None or not folder.is_dir():
        return None
    keep = {marker_name(a) for a in addresses}

    def outdated(path, base):
        """An old ended record whose terminal moved on to another token (kept
        while the terminal still holds that token: a cleanup may need it)."""
        record = get_record(base)
        return record is not None and labels_of(record).get(LABEL) != ended_token(path)

    doomed = {}  # path -> (mtime, content) seen when it was judged garbage
    for path in folder.iterdir():  # literal names: a core name may hold glob characters
        base = terminal_of(path)
        if base is None or not path.is_file():
            continue
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        content = read_marker(path)
        if path.name.startswith("."):
            # A terminal's writer lock: garbage once its terminal is gone. Under
            # the exclusive state lock below, no writer can hold it.
            if base not in keep:
                doomed[path] = (mtime, content)
        elif content is UNREADABLE:
            continue  # cannot judge it: keep it
        elif base not in keep:
            doomed[path] = (mtime, content)
        elif ".ended." in path.name and started - mtime >= ENDED_MAX_AGE and outdated(path, base):
            doomed[path] = (mtime, content)
    if doomed:
        # Second pass, still without the lock: the socket may have changed hands
        # since the listing, so bind every decision to the same core again and
        # confirm each file is still garbage against a fresh listing.
        if core_id() != live or saved_core_id(core) != live:
            return None
        fresh = local_terminals()
        if fresh is None:
            return None
        still = {marker_name(a) for a in fresh}
        for path in list(doomed):
            base = terminal_of(path)
            # Its terminal is back, unless this is an ended record it moved on from.
            if base in still and not (".ended." in path.name and outdated(path, base)):
                del doomed[path]
    removed = 0
    # The lock covers only local checks, so a hook waiting for it waits briefly.
    with state_lock(exclusive=True, wait=2.0) as held:
        if not held or (doomed and saved_core_id(core) != live):
            return None
        for path, (mtime, content) in doomed.items():
            try:
                if path.stat().st_mtime == mtime and read_marker(path) == content and mtime < started:
                    path.unlink()
                    removed += 1
            except OSError:
                continue
        (folder / ".pruned").touch()  # the per-core stamp maybe_prune() reads
    return removed


def spawn_detached(argv):
    """Start argv in its own session with stdio on /dev/null, without keeping a
    process handle around (no ResourceWarning on a hook's stderr)."""
    devnull = os.open(os.devnull, os.O_RDWR)
    try:
        os.posix_spawn(
            argv[0],
            argv,
            dict(os.environ),
            file_actions=[(os.POSIX_SPAWN_DUP2, devnull, fd) for fd in (0, 1, 2)],
            setsid=True,
        )
    finally:
        os.close(devnull)


def maybe_prune():
    """Once a day per core, start a detached prune: a hook never waits on hc calls
    for old records. The stamp is written only once the prune is on its way."""
    stamp = core_dir(core_name()) / ".pruned"
    try:
        if stamp.exists() and time.time() - stamp.stat().st_mtime < PRUNE_EVERY:
            return
        spawn_detached([sys.executable, str(SCRIPT_PATH), "--prune"])
        stamp.touch()
    except OSError:
        pass


# ----------------------------------------------------------------- management


def hook_prefix(agent):
    guard = (
        'command -v python3 >/dev/null 2>&1 && test -f "$1" || exit 0; '
        f'exec python3 "$1" --hook {agent}'
    )
    return f"sh -c {shlex.quote(guard)} sh "


def hook_command(agent):
    return hook_prefix(agent) + shlex.quote(str(SCRIPT_PATH))


def owned_command(command):
    """True only for our exact wrapper, with any path to this script (stale ones too)."""
    if not isinstance(command, str):
        return False
    for agent in AGENTS:
        prefix = hook_prefix(agent)
        if command.startswith(prefix):
            try:
                rest = shlex.split(command[len(prefix) :])
            except ValueError:
                return False
            return len(rest) == 1 and rest[0].endswith("/" + OWNER)
    return False


def codex_hooks_path():
    return Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "hooks.json"


def load_json(path):
    if not path.exists():
        return {}
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise TypeError(f"{path} is not a JSON object")
    return data


def hook_files(cs):
    """(agent, hook file, {event: matcher}) for each agent."""
    return (
        ("claude", cs.settings_path(), CLAUDE_HOOKS),
        ("codex", codex_hooks_path(), CODEX_HOOKS),
    )


def expected_hook(agent):
    return {"type": "command", "command": hook_command(agent), "timeout": HOOK_TIMEOUT}


def owned(data, event):
    """[(matcher, hook)] for our hook entries under hooks[event]."""
    hooks = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
    entries = hooks.get(event) if isinstance(hooks.get(event), list) else []
    return [
        (entry.get("matcher"), hook)
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("hooks"), list)
        for hook in entry["hooks"]
        if isinstance(hook, dict) and owned_command(hook.get("command"))
    ]


def unregister(data, event):
    """Remove our hooks under hooks[event]; drop entries, events and hooks left empty."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict) or not isinstance(hooks.get(event), list):
        return
    kept = []
    for entry in hooks[event]:
        if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
            kept.append(entry)
            continue
        rest = [h for h in entry["hooks"] if not (isinstance(h, dict) and owned_command(h.get("command")))]
        if len(rest) == len(entry["hooks"]):
            kept.append(entry)  # nothing of ours here, keep it as is (even if empty)
        elif rest:
            kept.append({**entry, "hooks": rest})
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event)
    if not hooks:
        data.pop("hooks")


def hook_state(data, hooks, agent):
    """enabled only when each event holds exactly the expected entry; stale ones are partial."""
    found = {event: owned(data, event) for event in hooks}
    if all(found[event] == [(matcher, expected_hook(agent))] for event, matcher in hooks.items()):
        return "enabled"
    return "partial" if any(found.values()) else "disabled"


def update_hooks(path, hooks, agent, enable, cs):
    data = load_json(path)
    cs.validate_hooks(data, hooks)
    state = hook_state(data, hooks, agent)
    if (enable and state == "enabled") or (not enable and state == "disabled"):
        return f"{agent}: already {'registered' if enable else 'absent'} in {path}"
    backup = cs.backup(path) if path.exists() else None
    for event, matcher in hooks.items():
        unregister(data, event)
        if enable:
            data.setdefault("hooks", {}).setdefault(event, []).append(
                {"matcher": matcher, "hooks": [expected_hook(agent)]}
            )
    cs.atomic_write(data, path)
    action = "registered in" if enable else "removed from"
    return f"{agent}: hooks {action} {path}" + (f" (backup {backup})" if backup else "")


def zshrc_line(tag=ZSHRC_TAG):
    snippet = shlex.quote(str(SNIPPET_PATH))
    return f"[[ -r {snippet} ]] && source {snippet}  {tag}"


def zshrc_path():
    return Path(os.environ.get("ZDOTDIR") or Path.home()) / ".zshrc"


def write_preserving_link(path, text):
    """Write the file a symlink points to, keeping the link and the mode."""
    target = Path(os.path.realpath(path))
    mode = target.stat().st_mode & 0o7777 if target.exists() else 0o644
    if target.exists():
        import claude_settings

        claude_settings.backup(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(target, text, mode=mode)


def zshrc_lines():
    path = zshrc_path()
    # Bytes in, no newline translation: CRLF lines stay CRLF.
    return path, (path.read_bytes().decode().splitlines(keepends=True) if path.exists() else [])


def owned_line(line):
    """True only for our generated line, with any path to the snippet (stale ones too)."""
    text = line.rstrip("\r\n")
    eol = ZSHRC_EOL_RE.search(text)
    tag = eol.group(0) if eol else ZSHRC_TAG
    if not text.endswith("  " + tag):
        return False
    try:
        tokens = shlex.split(text[: -len(tag)])
    except ValueError:
        return False
    return (
        len(tokens) == 7
        and tokens[:2] == ["[[", "-r"]
        and tokens[3:6] == ["]]", "&&", "source"]
        and tokens[2] == tokens[6]
        and tokens[2].endswith("/herdr-agent-resume.zsh")
    )


def eol_tag(content):
    """The tag recording the whole file enable ended with a newline, by hash:
    disable takes the newline back only when nothing above was edited since."""
    return f"{ZSHRC_EOL_PREFIX}{hashlib.sha256(content.encode()).hexdigest()[:16]})"


def without_our_lines(lines):
    """The file without our lines. A newline enable added is taken back only when
    the file above is unchanged since (same content, by hash)."""
    kept = []
    for index, line in enumerate(lines):
        if not owned_line(line):
            kept.append(line)
            continue
        eol = ZSHRC_EOL_RE.search(line.rstrip("\r\n"))
        # Only when nothing above was edited: the same whole file, byte for byte.
        if eol and index == len(lines) - 1 and kept and kept[-1].endswith("\n"):
            if eol_tag("".join(kept)[:-1]) == eol.group(0):
                kept[-1] = kept[-1][:-1]
    return kept


def update_zshrc(enable):
    path, lines = zshrc_lines()
    kept = without_our_lines(lines)
    if enable:
        tag = ZSHRC_TAG
        if kept and not kept[-1].endswith("\n"):
            tag = eol_tag("".join(kept))
            kept[-1] += "\n"
        kept.append(zshrc_line(tag) + "\n")
    if kept == lines:
        return f"zsh: {path} already {'set' if enable else 'clean'}"
    write_preserving_link(path, "".join(kept))
    return f"zsh: line {'added to' if enable else 'removed from'} {path}"


def managed_hooks_only():
    for folder in MANAGED_CLAUDE_SETTINGS:
        paths = [os.path.join(folder, "managed-settings.json")]
        paths += sorted(glob.glob(os.path.join(folder, "managed-settings.d", "*.json")))
        for path in paths:
            try:
                with open(path) as f:
                    if json.load(f).get("allowManagedHooksOnly") is True:
                        return path
            except (OSError, ValueError, AttributeError):
                continue
    return None


def warnings():
    found = []
    if os.path.basename(os.environ.get("SHELL", "")) != "zsh":
        found.append("your login shell is not zsh: recovered terminals will not resume")
    own = os.environ.get("HC_TERMINAL_SOCKET")
    if own and core_key(own) is None:
        found.append(f"this core's socket path is too long to record sessions: {own}")
    policy = managed_hooks_only()
    if policy:
        found.append(f"{policy} sets allowManagedHooksOnly: Claude Code ignores this hook")
    return found


def labelled_terminals():
    """({address: token}, [unreadable addresses]), or None when hc ls fails."""
    addresses = local_terminals()
    if addresses is None:
        return None
    found, unreadable = {}, []
    for address in addresses:
        record = get_record(address)
        if record is None:
            unreadable.append(address)
            continue
        labels = labels_of(record)
        if LABEL in labels:
            found[address] = labels[LABEL]
    return found, unreadable


def preflight(cs):
    """Read every file enable touches before writing any of them."""
    problems = []
    for name, path, hooks in hook_files(cs):
        try:
            cs.validate_hooks(load_json(path), hooks)
        except (OSError, ValueError, TypeError) as error:
            problems.append(f"{name}: {path}: {error}")
    try:
        zshrc_lines()
    except (OSError, ValueError) as error:
        problems.append(f"zsh: {zshrc_path()}: {error}")
    return problems


def rollback(snapshot, written, state_existed):
    """Restore each file enable wrote, unless someone changed it since."""
    for path, ours in written.items():
        try:
            current = path.read_bytes() if path.exists() else None
            if current != ours:
                print(f"Not rolled back, changed since enable wrote it: {path}. Run disable.")
            elif snapshot[path] is None:
                path.unlink(missing_ok=True)
            elif current != snapshot[path]:
                path.write_bytes(snapshot[path])
        except OSError as error:
            print(f"Rollback failed for {path}: {error}", file=sys.stderr)
    if not state_existed:
        shutil.rmtree(state_dir(), ignore_errors=True)


def cmd_enable():
    import claude_settings as cs

    if not shutil.which("hc"):
        print("herdr-core (hc) not found on PATH. Install the Herdr app first; nothing changed.")
        return 1
    problems = preflight(cs)
    if problems:
        for problem in problems:
            print(f"Cannot enable: {problem}")
        print("Nothing changed.")
        return 1
    # The whole transaction, rollback included, runs under the exclusive state
    # lock, so a disable can never interleave with it.
    try:
        lock_dir().mkdir(parents=True, exist_ok=True)
    except OSError as error:
        print(f"Cannot enable: {lock_dir()}: {error}. Nothing changed.")
        return 1
    with state_lock(exclusive=True, wait=10.0) as held:
        if not held:
            print("Not done: another herdr-agent-resume process holds the lock. Run enable again.")
            return 1
        enable_locked(cs)
    for path in known_cores()[0].values():
        with on_core(path):
            prune_markers()
    for warning in warnings():
        print(f"Warning: {warning}")
    print("Enabled. Start new agent sessions and open a new terminal tab to use it.")
    print("Codex: open /hooks in Codex and trust the new SessionStart hook.")
    return 0


def enable_locked(cs):
    # Snapshot every file first: a failed write rolls back the ones already done.
    steps = [
        (path, lambda a=agent, p=path, h=hooks: update_hooks(p, h, a, True, cs))
        for agent, path, hooks in hook_files(cs)
    ]
    steps.append((Path(os.path.realpath(zshrc_path())), lambda: update_zshrc(True)))
    snapshot = {path: path.read_bytes() if path.exists() else None for path, _ in steps}
    written = {}
    state_existed = state_dir().exists()
    try:
        for path, step in steps:
            message = step()
            written[path] = path.read_bytes() if path.exists() else None  # before any output
            print(message)
        markers_dir().mkdir(parents=True, exist_ok=True)
        os.chmod(state_dir(), 0o700)
        os.chmod(markers_dir(), 0o700)
        enabled_file().touch()
    except BaseException:
        rollback(snapshot, written, state_existed)
        print("Enable failed; changes rolled back.")
        raise


def cmd_disable():
    # The whole disable runs under the exclusive state lock: writers wait or give
    # up, and an enable cannot interleave. No lock, no change.
    # The lock folder must exist first, even on a fresh home: an enable running at
    # the same time takes the same lock, so the two never interleave.
    try:
        lock_dir().mkdir(parents=True, exist_ok=True)
    except OSError as error:
        print(f"Not done: {lock_dir()}: {error}. Nothing changed.")
        return 1
    with state_lock(exclusive=True, wait=10.0) as held:
        if not held:
            print("Not done: another herdr-agent-resume process holds the lock. Run disable again.")
            return 1
        return disable_locked()


def disable_locked():
    import claude_settings as cs

    problems = []
    # First, so running agents and shells stop acting at once. A failure here is
    # reported like any other step's, and the cleanup below still runs.
    try:
        enabled_file().unlink(missing_ok=True)
    except OSError as error:
        problems.append(f"{enabled_file()}: {error}")
    steps = [
        (f"{agent}: {path}", lambda a=agent, p=path, h=hooks: update_hooks(p, h, a, False, cs))
        for agent, path, hooks in hook_files(cs)
    ]
    steps.append((f"zsh: {zshrc_path()}", lambda: update_zshrc(False)))
    for name, step in steps:  # each step runs even when an earlier one fails
        try:
            print(step())
        except (OSError, ValueError, TypeError) as error:
            problems.append(f"{name}: {error}")
    kept = {}  # cores whose labels are not all gone: their folder stays for a retry
    cores, unresolved = known_cores()
    running = running_core_ids(cores)
    for core in unresolved:
        if holds_sessions(core):
            problems.append(f"{core_dir(core)}: not a known core, labels not checked")
            kept[core] = None
    for core, path in cores.items():
        name = f"core {core_label(core)} ({path})"
        if moved(core, running):
            print(f"{name}: moved, its labels are handled with the running core")
            continue
        if holds_sessions(core) and not confirmed(core, running.get(core)):
            problems.append(
                f"{name}: its sessions could not be matched to the core answering on this "
                "socket (core id unknown or different); they are kept and not checked"
            )
            kept[core] = path
        with on_core(path):
            result = labelled_terminals()
            if result is None:
                problems.append(f"{name}: not running, {LABEL} labels not checked")
                kept[core] = path
                continue
            found, unreadable = result
            failed = [t for t in found if not clear_label(t)]
        print(f"labels, {name}: removed {len(found) - len(failed)}")
        if failed:
            problems.append(f"{name}: labels not removed on {', '.join(failed)}")
        if unreadable:
            problems.append(f"{name}: terminals not readable, labels not checked: {', '.join(unreadable)}")
        if failed or unreadable:
            kept[core] = path
    if kept:
        for child in list(state_dir().iterdir()) if state_dir().is_dir() else []:
            if child != markers_dir():
                shutil.rmtree(child) if child.is_dir() else child.unlink(missing_ok=True)
        for child in list(markers_dir().iterdir()) if markers_dir().is_dir() else []:
            if child.name not in kept:
                shutil.rmtree(child, ignore_errors=True)
        for core in kept:  # the folder name is the core's socket: a retry finds it again
            make_private_dir(core_dir(core))
        print(f"state: kept {', '.join(sorted(core_label(k) for k in kept))} in {markers_dir()} for a retry")
    else:
        shutil.rmtree(state_dir(), ignore_errors=True)
        if state_dir().exists():
            problems.append(f"{state_dir()}: could not be removed")
        else:
            print(f"state: removed {state_dir()}")
    if problems:
        for problem in problems:
            print(f"Not done: {problem}")
        if os.path.lexists(enabled_file()):
            print(f"The feature may still be active: {enabled_file()} is still there.")
            print("Fix the above and run herdr-agent-resume-disable again.")
        else:
            print("The feature is off. Fix the above and run herdr-agent-resume-disable again.")
        return 1
    print("Disabled. Open shells keep the snippet loaded until closed, but it does nothing.")
    return 0


def cmd_info():
    import claude_settings as cs

    print(f"Script: {SCRIPT_PATH}")
    print(f"Enabled flag: {'on' if enabled_file().exists() else 'off'} ({enabled_file()})")
    for agent, path, hooks in hook_files(cs):
        try:
            state = hook_state(load_json(path), hooks, agent)
        except (OSError, ValueError, TypeError) as error:
            state = f"unreadable ({error})"
        print(f"{'Claude Code' if agent == 'claude' else 'Codex'} hooks: {state} ({path})")
    print("Codex hooks need trust: open /hooks in Codex.")
    try:
        present = any(owned_line(line) for line in zshrc_lines()[1])
        print(f"zsh line: {'present' if present else 'absent'} ({zshrc_path()})")
    except (OSError, ValueError) as error:
        print(f"zsh line: unreadable ({zshrc_path()}: {error})")
    print(f"hc: {shutil.which('hc') or 'not found'}")
    cores, unresolved = known_cores()
    if not cores and not unresolved:
        print("Labels: no core has recorded a session yet")
    for core in unresolved:
        print(f"Labels: {core_dir(core)} is not a known core")
    running = running_core_ids(cores)
    for core, path in cores.items():
        name = f"{core_label(core)} ({path})"
        if moved(core, running):
            print(f"Labels ({name}): moved, see the running core")
            continue
        with on_core(path):
            result = labelled_terminals()
            if result is None:
                print(f"Labels ({name}): core not running")
                continue
            found, unreadable = result
            print(f"Labels ({name}): {len(found)}")
            own = not holds_sessions(core) or confirmed(core, running.get(core))
            if not own:
                print("  sessions here belong to another core that used this socket; not shown")
            for address, token in sorted(found.items()):
                file = marker_name(address)
                session = parse_marker(read_marker(core_dir(core) / file)) if file and own else None
                matches = session is not None and session["gen"] == token
                print(f"  {address}: {resume_command(session) if matches else 'no matching marker'}")
            if unreadable:
                print(f"  not readable: {', '.join(unreadable)}")
            removed = prune_markers() if enabled_file().exists() else None
        if removed:
            print(f"Markers ({name}): pruned {removed} stale")
    markers = (
        sorted(
            str(p.relative_to(markers_dir()))
            for p in markers_dir().rglob("*")
            if p.is_file() and not p.name.startswith(".")
        )
        if markers_dir().is_dir()
        else []
    )
    print(f"Markers: {len(markers)}" + (f" ({', '.join(markers)})" if markers else ""))
    for warning in warnings():
        print(f"Warning: {warning}")
    return 0


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    try:
        if mode == "--hook":
            return run_hook(argv[2] if len(argv) > 2 else "")
        if mode == "--shell-startup":
            return shell_startup(int(argv[2]))
        if mode == "--shell-clear":
            return shell_clear(int(argv[2]), argv[3] if len(argv) > 3 and valid_token(argv[3]) else None)
        if mode == "--core-id":
            print(core_id() or "")
            return 0
        if mode == "--prune":
            if enabled_file().exists():
                prune_markers()
            return 0
        if mode == "--shell-cleanup":
            return shell_cleanup(int(argv[2]), argv[3] if len(argv) > 3 else "")
    except BaseException:  # noqa: BLE001 - hooks and shell paths never fail loudly
        return 0
    actions = {"enable": cmd_enable, "disable": cmd_disable, "info": cmd_info}
    if mode in actions:
        try:
            return actions[mode]()
        except (OSError, ValueError, TypeError) as error:
            print(f"herdr-agent-resume: {error}", file=sys.stderr)
            return 1
    print(
        "Usage: herdr-agent-resume.py {enable|disable|info|--hook AGENT|"
        "--shell-startup PID|--shell-cleanup PID TOKEN|--shell-clear PID [TOKEN]|--prune|--core-id}",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
