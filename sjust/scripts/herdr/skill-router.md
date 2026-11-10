---
name: herdr
description: "Control Herdr: the Herdr TUI (`herdr`), herdr-core (`hc`), or the Herdr desktop app (`herdr-app`). Use only when the user explicitly mentions Herdr, hc, herdr-core or herdr-app, or asks to use Herdr to inspect or control panes, tabs, terminals, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires a Herdr TUI pane (HERDR_ENV=1) or an hc terminal (HC_TERMINAL_ID)."
---

# Herdr

Two Herdr runtimes exist, and they do not share agents. The Herdr TUI runs panes in its own server and is driven with `herdr`. The Herdr desktop app runs its terminals in herdr-core, driven with `hc`, and its window is driven with `herdr-app`. Each runtime marks its processes with its own environment variables.

## Detect the runtime

Run this before any other Herdr command. It confirms the variable against the owning server, so a stale or inherited value does not pass:

```bash
if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] && [ -S "${HERDR_SOCKET_PATH:-}" ] \
  && herdr pane get "$HERDR_PANE_ID" >/dev/null 2>&1; then
  echo herdr-tui
elif [ -n "${HC_TERMINAL_ID:-}" ] && hc get "$HC_TERMINAL_ID" --json >/dev/null 2>&1; then
  echo hc
else
  echo none
fi
```

The Herdr TUI is checked first because it is the innermost runtime: a TUI started inside an hc terminal passes `HC_TERMINAL_ID` on to its panes, and that terminal is still alive. In an hc terminal, `HC_TERMINAL_ID` is also your caller identity: terminals and agents you start from it become your children.

## Load the manual for that runtime

- **`hc`:** read [references/hc.md](references/hc.md) and follow it. If [references/herdr-app.md](references/herdr-app.md) exists, read it as well: it covers the window the person sees (spaces, tabs, panes).
- **`herdr-tui`:** read [references/herdr-tui.md](references/herdr-tui.md) and follow it.
- **`none`:** say you are running neither inside an hc terminal nor inside a Herdr TUI pane, and stop.

Read only the files for the detected runtime. If its required file (`references/hc.md` or `references/herdr-tui.md`) is missing, say that runtime's manual is not installed (`sjust sf-herdr-skill-install` on macOS, `ajust sf-herdr-skill-install` on Linux, regenerates it) and stop.
