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

## Status of the build-out

Implemented and tested: `feed`, `status`, `runner`, `version`, `theme`; runnable
`app` + `splash` + `dashboard`.

Next pages (ports of the validated prototype, onto the tested `runner` backend):
Runner (streaming + pinned statusline), Password (masked, subprocess-scoped),
Log (copyable), sjust browser. Then the `tui` Ansible build tag and the
`sparkdock` dispatch + self-update wiring.
