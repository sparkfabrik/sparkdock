# sparkdock-tui

Terminal hub for sparkdock (issue #542). Go + [bubbletea](https://github.com/charmbracelet/bubbletea),
following the Elm architecture (Model / Update / View): one immutable model, a
pure `Update(msg) -> (model, Cmd)` transition, a pure `View() -> string`, and all
side effects isolated in `Cmd`s that feed results back in as messages. This keeps
a clean separation between pure core logic and injected side effects.

It is an **opt-in, beta** front end: launched with `sparkdock tui`, never by bare
`sparkdock` (which keeps its self-update and full-provisioning behaviour).

## Layout

```
cmd/sparkdock-tui/      entrypoint: dispatch (TTY -> TUI, else headless), wiring
internal/
  feed/      pure parser + \r-aware decoder for the @@PHASE/@@TASK/@@STAT/@@DONE protocol
  theme/     all colours, glyphs, and lipgloss styles (single source of style)
  version/   git commit/branch/timestamps of /opt/sparkdock (no semver)
  status/    Checker interface + CmdChecker over sparkdock-check-updates / brew
  sysinfo/   Gatherer: model/serial/chip/memory/disk via system_profiler/sysctl/df/vm_stat
  runner/    Runner: exec a command under a PTY, stream raw output, prompts, cancel
  audio/     plays a short chime on logo click (afplay; SPARKDOCK_TUI_NO_AUDIO=1 disables)
  ui/            shared page ids + navigation messages
  ui/app/        root model: page router, size broadcast, input routing, run orchestration
  ui/splash/     launch splash (block wordmark + spark glyph + beta badge)
  ui/dashboard/  flat grouped status/actions list + system-info panel
  ui/runview/    streaming run view; structured + terminal render strategies
  ui/password/   masked become-password entry
  ui/logview/    scrollable, copyable run log
```

## Design principles

- **Pure core, injected effects.** `feed` is a pure parser. `status`, `sysinfo`,
  `runner`, and `version` take their side effects (command runner, command
  builder, git func) as injected dependencies, so each is unit-tested without
  touching the real environment.
- **One style source.** Pages never hardcode colours; they call `theme.Default()`.
- **Decoupled pages.** Pages communicate only via `ui` messages; the `app` router
  owns navigation. No page imports another.
- **Status is never recomputed.** The dashboard reads `status.Checker`; freshness
  semantics live in the shell backend, shared with the menu bar app.
- **The become password is never stored.** It is entered on a masked page and
  written straight to the process PTY. It is never cached, never placed in the
  environment, argv, or a file, and is asked for each time.

## Build & test

```sh
go build ./...
go test ./... -count=1
gofmt -l .      # must print nothing
go vet ./...
```

CI runs the same gates in `.github/workflows/test-tui.yml`.

## Pages

- `splash` — block wordmark, spark glyph, version, and a `beta` badge.
- `dashboard` — flat grouped status/actions list with a system-info panel. Each
  action shows its equivalent shell command (e.g. `Update everything` -> `$ sparkdock`,
  `Upgrade Brew packages` -> `$ brew upgrade`, the `HTTP proxy` group -> `$ spark-http-proxy …`).
- `runview` — streaming run with a pinned statusline; cancel, retry, open log. Two
  render strategies behind one interface: **structured** decodes the sparkdock
  callback into a line list + tally (ansible runs); **terminal** drives a VT
  emulator for programs that redraw in place (e.g. `brew`).
- `password` — masked become-password entry, written to the process PTY, never stored.
- `logview` — scrollable, copyable run log (clipboard or file).

The `app` router wires these together: it builds the `runner.Handle` per action,
gates sudo actions behind the password page, writes the password to the PTY, and
re-prompts on a sudo authentication failure.

## Install & run

Built and installed during provisioning by the `tui` Ansible tag (`become: false`,
no sudo). Launch with `sparkdock tui`: it builds the binary on first use and
rebuilds whenever `src/tui` is newer than the installed binary, so a self-update
that touched the TUI is picked up before launch. Rebuild on demand with
`sjust sparkdock-tui-install`. The Ansible stdout callback that drives the
structured view lives at `ansible/callback_plugins/sparkdock.py`.

To run the binary against a dev checkout instead of `/opt/sparkdock`, set
`SPARKDOCK_ROOT` to the repo root (the `sparkdock` entrypoint exports it for you);
otherwise the callback plugin and status binaries resolve against `/opt/sparkdock`.

## Not yet wired

- The self-update action is hidden rather than shown as a dead button; the amber
  status dot still signals a stale install, and bare `sparkdock` self-updates.
- The headless delegate (`sparkdock-tui update` / non-TTY) is a stub.
