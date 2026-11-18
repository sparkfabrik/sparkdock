# Agent resume for Herdr terminals

After a reboot, the Herdr app brings back spaces and tabs, but each Claude Code or Codex session comes back as a plain shell. This opt-in feature resumes those sessions. The legacy herdr TUI did this itself; herdr-core will support it once OSC 7501 can carry a resume reference ([herdrdev/herdr-core#13](https://github.com/herdrdev/herdr-core/issues/13), [herdrdev/herdr-core#15](https://github.com/herdrdev/herdr-core/issues/15), [herdrdev/herdr-app#406](https://github.com/herdrdev/herdr-app/issues/406)). Remove this feature when that lands.

```bash
sjust herdr-agent-resume-enable   # ajust on Linux
sjust herdr-agent-resume-info
sjust herdr-agent-resume-doctor [fix]
sjust herdr-agent-resume-editor
sjust herdr-agent-resume-disable
```

After enabling, start new agent sessions and open new tabs. In Codex, open `/hooks` and trust the new `SessionStart` hook.

## What it does

- **Records** the session when Claude Code or Codex starts in the foreground of a herdr-core terminal: a random token in the `sf.agent-resume` label on that terminal, and the session details in a private file under `~/.config/spark/herdr-agent-resume/`.
- **Resumes** it when herdr-core recovers the terminal after a reboot or a lost holder: the new shell changes to the session's folder and runs `claude --resume <id>` or `codex resume <id>` once, with a `herdr-agent-resume: resuming ...` line.
- **Forgets** it when you quit Claude Code (`/exit`, Ctrl+C twice), or when you run your next command in that shell after the agent ended for any other reason. While that shell has background or suspended jobs, this waits until they are gone (a suspended agent is still alive).

Agents outside herdr-core, in the legacy herdr TUI, under tmux, in a nested interactive shell, or started by another agent are never recorded. `claude -p` and `codex exec` are not recorded either. Ordinary prompts and new tabs make no `hc` call.

## Doctor

`herdr-agent-resume-doctor` checks the feature's health (the `enabled` flag, the hooks, the `~/.zshrc` line, `hc`, and the warnings `info` shows) and every recorded session on every herdr-core that recorded one. Each row shows the terminal's place (space and tab), the agent, the folder and the reason.

- **Keep**: the agent still runs in that terminal, in the foreground, suspended or in the background (`running`); the terminal's shell started less than two minutes ago, so a recovery may be in progress (`starting`); or the process list could not be read (`not checked`).
- **Closed**: the terminal was removed or finished, the agent no longer runs in its terminal (for example Codex quit and no command followed), its end was recorded but not cleaned up yet, or its folder or transcript is gone.
- **Leftovers**: records that can never resume: a marker without its label or the other way round, an unreadable marker, ended records of older sessions, and lock files and exclusions of terminals that no longer exist.

On a terminal it then asks `Purge N entries? [y/N]`. Without a terminal it only reports. With `fix` it purges without asking and lists what it purged. A purge removes a session only while its terminal still holds the generation the report saw, so an agent started in the meantime is kept.

A herdr-core that is not running is reported with the number of sessions it holds and never changed: open the Herdr app, then run the doctor again. The doctor never starts herdr-core. A missing or stale hook or `~/.zshrc` line is reported, not repaired: run `herdr-agent-resume-enable`. The doctor exits 1 when it finds something to purge or a health problem, or when a purge fails, and 0 otherwise. While the feature is disabled it reports that and changes nothing.

## Editor

`herdr-agent-resume-editor` shows a checklist of the recorded sessions (checked) and the excluded ones (unchecked), with place, agent, folder, terminal title and status. It uses `gum` when installed and a numbered prompt otherwise (type numbers to toggle, Enter to finish, `q` to cancel). It lists the changes and asks `Apply? [Y/n]`. It needs a terminal: without one it points to `herdr-agent-resume-info`.

- **Unchecking** a session forgets it and excludes it: that terminal is not resumed after a reboot, and its hook does not record the same session id again there, so Claude Code compaction, `/clear` to the same session or a manual `--resume` of that id do not bring it back. A different session in that terminal is recorded normally and ends the exclusion. A session of a herdr-core that is not running can be unchecked too; it is not resumed when that core starts.
- **Checking** an excluded session records it again, only when its herdr-core is running, its terminal is live and no newer session is recorded there.

`info` lists the excluded sessions. The daily prune and the doctor remove the exclusions of terminals that no longer exist; disable removes them with the rest of the state.

## Requirements

- herdr-core (`hc`) on `PATH`, with the terminals marked keep (the Herdr app does this).
- zsh as the login shell. Other shells record sessions but never resume them.
- `python3`. If it or this folder disappears, the hooks and the `~/.zshrc` line do nothing.
- `gum` (optional), for the editor's checklist.

## Known limits

- **Codex** reports every exit the same way, so quitting Codex does not clear the session. It is cleared when you run the next command in that tab. If you quit Codex and reboot before typing anything there, it comes back.
- If herdr-core is unreachable exactly when you quit Claude Code, the same applies. So does a shell with background or suspended jobs: the session is cleared on the first command after the jobs are gone, and a reboot before that can bring it back.
- If the disk refuses writes when a session ends, its end may not be recorded, and a reboot can bring it back.
- A power loss within a few milliseconds of the command that follows an agent's end can lose the record of that end (zsh cannot force it to disk; the background cleanup does so right after), and the session can come back.
- Resume uses the session id only. Launch flags such as `--model` are not replayed.
- A resumed Claude Code session with a long conversation can miss the Herdr app's status handshake and stay out of the Agents panel ([herdrdev/herdr-app#537](https://github.com/herdrdev/herdr-app/issues/537)). The session itself resumes.
- An organization policy that sets `allowManagedHooksOnly` turns the Claude Code hook off; `info` reports it.
- The `sf.agent-resume` label belongs to this feature. Changing it by hand (`hc label`) is not supported.
- A herdr-core socket path full of `%` characters can be too long to use as a folder name; such a core records nothing. `info` warns about it when run from a terminal of that core.
- Sessions are tied to the herdr-core socket path, which is fixed in a default setup. If it changes, sessions recorded under the old path are not resumed.
- Claude Code installed through npm runs as `node`, so it is not recorded. The native installer and the Homebrew cask are supported.
- The doctor keeps a closed session while another process of the same agent (`claude` or `codex`) runs anywhere in that terminal, for example one started by a tool.
- An excluded session stays excluded in its terminal while it keeps its id, also when you resume it there by hand. Check it again in the editor to record it.

## Files it changes

Enable and disable back up each file before changing it, and touch only their own entries:

- `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`): `SessionStart` and `SessionEnd` hooks.
- `~/.codex/hooks.json` (or `$CODEX_HOME`): a `SessionStart` hook.
- `~/.zshrc` (or `$ZDOTDIR/.zshrc`): one line tagged `# sparkdock herdr-agent-resume`. A symlinked file is edited in place.
- `~/.config/spark/herdr-agent-resume/`: the `enabled` flag and, in one folder per herdr-core (named after its socket path), the private per-terminal session files and the editor's exclusions.

Disable also removes the label from every terminal of every herdr-core that recorded a session, and deletes the state folder. Nothing in this feature ever starts herdr-core: a core that is not running is reported, not started. Running agents and open shells stop acting as soon as the flag is gone.

If disable cannot finish (a malformed settings file, or a herdr-core not running so its labels cannot be removed), it still removes the `enabled` flag, keeps only what a retry needs, lists what is left, and exits with an error. The feature is off once the flag is gone; if the flag itself cannot be removed, disable says so and the feature may still act until a retry succeeds. Fix the cause or start the Herdr app, then run `sjust herdr-agent-resume-disable` again.

## Tests

```bash
python3 -m unittest -v sjust/scripts/lib/test_herdr_agent_resume.py
```

They cover the hook, the shell paths, enable and disable, the doctor and the editor (with a stub `gum`), the process checks on a real pty, and an interactive zsh driven through `zpty`. CI runs them on Linux and macOS.
