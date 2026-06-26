# sparkdock-tui

Terminal hub for sparkdock (issue #542). Go + [bubbletea](https://github.com/charmbracelet/bubbletea),
following the Elm architecture with a clean separation between pure core logic
and injected side effects.

## Layout

```
cmd/sparkdock-tui/      entrypoint: dispatch (TTY -> TUI, else headless), wiring
internal/
  feed/      pure parser for the @@PHASE/@@TASK/@@STAT/@@DONE callback protocol
  theme/     all colours, glyphs, and lipgloss styles (single source of style)
  version/   git commit/branch/timestamps of /opt/sparkdock (no semver)
  status/    Checker interface + CmdChecker over sparkdock-check-updates / brew
  runner/    Runner: exec ansible-playbook, stream feed.Events, cancel, become-env
  ui/        shared page ids + navigation messages
  ui/app/        root model: page router, size broadcast, input routing
  ui/splash/     launch splash (block wordmark + spark glyph)
  ui/dashboard/  flat grouped status/actions list
```

## Design principles

- **Pure core, injected effects.** `feed` is a pure function. `status`, `runner`,
  and `version` take their side effects (command runner, command builder, git
  func) as injected dependencies, so each is unit-tested without touching the
  real environment.
- **One style source.** Pages never hardcode colours; they call `theme.New()`.
- **Decoupled pages.** Pages communicate only via `ui` messages; the `app`
  router owns navigation. No page imports another.
- **Status is never recomputed.** The dashboard reads `status.Checker`; freshness
  semantics live in the shell backend, shared with the menu bar app.

## Build & test

```sh
go build ./...
go test ./...
```

## Pages

- `splash` — launch wordmark + version.
- `dashboard` — flat grouped status/actions list (live status).
- `runview` — streaming run with a pinned statusline; cancel, retry, open log.
- `password` — masked become-password entry (subprocess-scoped, session-cached).
- `logview` — scrollable, copyable run log written to `~/.cache/sparkdock/last-run.log`.
- `sjust` — recipe browser that runs the selected recipe through the runner.

The `app` router wires these together: it builds the `runner.Handle` per action,
gates sudo actions behind the password page, caches the become password in
memory for the session, and re-prompts on a sudo authentication failure.

## Install & run

Built and installed during provisioning by the `tui` Ansible tag. Launch with
`sparkdock tui` (it builds itself on first use, no sudo needed), or rebuild on
demand with `sjust sparkdock-tui-install`. The Ansible stdout callback that
drives the streaming view lives at `ansible/callback_plugins/sparkdock.py`.

## Not yet wired

- The `sparkdock` default command still provisions; flipping bare `sparkdock` to
  the hub (with `sparkdock update` kept headless) and the in-hub self-update
  remain a deliberate, separately-reviewed migration step.
- Dashboard `proxy`, `device`, and Company actions, and `Update Sparkdock`, are
  not yet handled (they no-op back to the dashboard).
