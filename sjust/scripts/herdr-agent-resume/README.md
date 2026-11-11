# Agent resume for Herdr terminals

After a reboot, the Herdr app brings back spaces and tabs, but each Claude Code or Codex session comes back as a plain shell. This opt-in feature resumes those sessions. The legacy herdr TUI did this itself; herdr-core will support it once OSC 7501 can carry a resume reference ([herdrdev/herdr-core#13](https://github.com/herdrdev/herdr-core/issues/13), [herdrdev/herdr-core#15](https://github.com/herdrdev/herdr-core/issues/15), [herdrdev/herdr-app#406](https://github.com/herdrdev/herdr-app/issues/406)). Remove this feature when that lands.

```bash
sjust herdr-agent-resume-enable   # ajust on Linux
sjust herdr-agent-resume-info
sjust herdr-agent-resume-disable
```

After enabling, start new agent sessions and open new tabs. In Codex, open `/hooks` and trust the new `SessionStart` hook.

## What it does

- **Records** the session when Claude Code or Codex starts in the foreground of a herdr-core terminal: a random token in the `sf.agent-resume` label on that terminal, and the session details in a private file under `~/.config/spark/herdr-agent-resume/`.
- **Resumes** it when herdr-core recovers the terminal after a reboot or a lost holder: the new shell changes to the session's folder and runs `claude --resume <id>` or `codex resume <id>` once, with a `herdr-agent-resume: resuming ...` line.
- **Forgets** it when you quit Claude Code (`/exit`, Ctrl+C twice), or when you run your next command in that shell after the agent ended for any other reason. While that shell has background or suspended jobs, this waits until they are gone (a suspended agent is still alive).

Agents outside herdr-core, in the legacy herdr TUI, under tmux, or started by another agent are never recorded. `claude -p` and `codex exec` are not recorded either. Ordinary prompts and new tabs make no `hc` call.

## Requirements

- herdr-core (`hc`) on `PATH`, with the terminals marked keep (the Herdr app does this).
- zsh as the login shell. Other shells record sessions but never resume them.
- `python3`. If it or this folder disappears, the hooks and the `~/.zshrc` line do nothing.

## Known limits

- **Codex** reports every exit the same way, so quitting Codex does not clear the session. It is cleared when you run the next command in that tab. If you quit Codex and reboot before typing anything there, it comes back.
- If herdr-core is unreachable exactly when you quit Claude Code, the same applies. So does a shell with background or suspended jobs: the session is cleared on the first command after the jobs are gone, and a reboot before that can bring it back.
- If the disk refuses writes and, at the same moment, herdr-core is unreachable or another terminal holds this feature's lock, a closed session may not be recorded. The shell keeps retrying before each command; a reboot before one succeeds can bring that session back.
- A power loss within a few milliseconds of the command that follows an agent's end can lose the record of that end (zsh cannot force it to disk; the background cleanup does so right after), and the session can come back.
- Resume uses the session id only. Launch flags such as `--model` are not replayed.
- A resumed Claude Code session with a long conversation can miss the Herdr app's status handshake and stay out of the Agents panel ([herdrdev/herdr-app#537](https://github.com/herdrdev/herdr-app/issues/537)). The session itself resumes.
- An organization policy that sets `allowManagedHooksOnly` turns the Claude Code hook off; `info` reports it.
- The `sf.agent-resume` label belongs to this feature. Changing it by hand (`hc label`) is not supported.
- A herdr-core socket path full of `%` characters can be too long to use as a folder name; such a core records nothing. `info` warns about it when run from a terminal of that core.
- Sessions are tied to the herdr-core socket path, which is fixed in a default setup. If it changes, sessions recorded under the old path are not resumed.
- If a different herdr-core later uses the same socket path while the first one's sessions are still recorded, the second core records no new sessions until those are gone; `disable` reports them and keeps them.

## Files it changes

Enable and disable back up each file before changing it, and touch only their own entries:

- `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`): `SessionStart` and `SessionEnd` hooks.
- `~/.codex/hooks.json` (or `$CODEX_HOME`): a `SessionStart` hook.
- `~/.zshrc` (or `$ZDOTDIR/.zshrc`): one line tagged `# sparkdock herdr-agent-resume`. A symlinked file is edited in place.
- `~/.config/spark/herdr-agent-resume/`: the `enabled` flag and, in one folder per herdr-core (named after its socket path), the private per-terminal session files.

Disable also removes the label from every terminal of every herdr-core that recorded a session, and deletes the state folder. Nothing in this feature ever starts herdr-core: a core that is not running is reported, not started. Running agents and open shells stop acting as soon as the flag is gone.

If disable cannot finish (a malformed settings file, or a herdr-core not running so its labels cannot be removed), it still turns the feature off, keeps only what a retry needs, lists what is left, and exits with an error. Fix the cause or start the Herdr app, then run `sjust herdr-agent-resume-disable` again.

## Tests

```bash
python3 -m unittest -v sjust/scripts/lib/test_herdr_agent_resume.py
```

They cover the hook, the shell paths, enable and disable, the process checks on a real pty, and an interactive zsh driven through `zpty`. CI runs them on Linux and macOS.
