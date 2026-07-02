# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Platform Support

**Apple Silicon Only**: Sparkdock supports **only Apple Silicon Macs**. Intel-based Macs are **not supported**.

## Overview

Sparkdock is an automated macOS development environment provisioner built with Ansible. It provides containerized workflows and modern tooling with an integrated HTTP proxy system for local development.

## Common Commands

### Running Ansible Provisioning

```bash
# Run full system provisioning
sparkdock

# Run specific Ansible tags
make run-ansible-playbook TAGS="docker,http-proxy"
just run-ansible-playbook "http-proxy"
```

### SparkJust Task Runner (sjust)

```bash
# Show available commands and list all tasks
sjust
sjust --list

# Install just the sjust tool (for manual migrations)
make install-sjust
```

**Important: Just Recipe Parameters**

Just recipes use **positional arguments**, not `parameter=value` syntax:

```bash
# ✅ Correct: positional arguments
sjust shell-enable force

# ❌ Wrong: parameter=value syntax doesn't work
sjust shell-enable force=true
```

**Exporting Parameters as Environment Variables:**

Prefix parameters with `$` to export them as environment variables in shebang recipes:

```just
my-recipe $param="default":
    #!/usr/bin/env bash
    # $param is now available as environment variable
    echo "Value: ${param}"
```

Without the `$` prefix, parameters require `{{param}}` interpolation in recipe lines.

**Deprecated Command Aliases:**

When renaming commands, use `[private] alias` to route old names to new ones without body duplication. Private aliases are hidden from `--list` but still callable:

```just
# Deprecated aliases (hidden from --list, silently route to new names)
[private]
alias old-name := new-name
```

This avoids tech debt from duplicated recipe bodies. Old names work silently — users discover new names naturally from `sjust --list`. Never duplicate full recipe bodies for backward compatibility; always use this pattern instead.

### HTTP Proxy Management

```bash
spark-http-proxy start           # Start proxy services
spark-http-proxy stop            # Stop proxy services
spark-http-proxy status          # Check service status
```

### Development Workflow

```bash
# Run specific Ansible tasks by tags
sjust install-tags "docker,keyboard"
```

## Architecture

### Directory Structure

- `/opt/sparkdock/` - Main installation directory
- `ansible/` - Ansible playbooks and configuration
- `sjust/` - SparkJust task runner with recipes
- `config/` - System configuration files and package lists
- `bin/` - Executable scripts
- `http-proxy/` - HTTP proxy system (cloned separately)

### Core Components

**Ansible Provisioning System:**

- Main playbook: `ansible/macos.yml` → `ansible/macos/macos/base.yml`
- Package definitions: `config/packages/all-packages.yml`
- Supports tagging for selective installation

**Privilege escalation (`become`/sudo).** The play in `ansible/macos/macos/base.yml` runs **unprivileged** (`become: no`); root work is elevated per-task, so the run never forces a sudo password for the whole playbook. The become password is collected natively by `ansible-playbook` itself: the `just run-ansible-playbook` recipe passes `--ask-become-pass` for interactive runs (prompts once, populating `ansible_become_pass`) and `--become` in CI (no prompt, gated by `CI`/`GITHUB_ACTIONS`). There is no `ANSIBLE_BECOME_PASS` env var anymore — the password is held in memory, never exported. Because Homebrew refuses to run as root, the brew/cask/npm tasks stay `become: false`; cask tasks (which can't use Ansible's become at all) pass the same natively-collected password to the module via `sudo_password: "{{ ansible_become_pass | default(omit) }}"`. **To run a task as root, add `become: yes` to that task** (the play does not elevate, so root tasks must opt in explicitly). Guard root tasks that must not run in CI with `when: not is_non_interactive`.

**SparkJust Task Runner:**

- Wrapper around Just task runner: `sjust/sjust.sh`
- Recipe files in `sjust/recipes/` with modular task definitions
- User customizations via `~/.config/sjust/100-custom.just`
- Keep recipe files clean and focused on task orchestration
- Extract complex logic into reusable functions in `sjust/libs/libshell.sh`
- Use `source "{{source_directory()}}/../libs/libshell.sh"` to load shared utilities

**HTTP Proxy Integration:**

- Clones SparkFabrik HTTP proxy to `/opt/sparkdock/http-proxy`
- Configures DNS resolver for `.loc` domains
- Manages SSL certificates with mkcert

### Package Management

- Homebrew packages and casks defined in YAML
- Automatic tap management and cleanup
- Version-specific packages (Node 20, PHP 8.2)
- Removed packages tracking for clean uninstalls

## Shell Script Standards

**Bash version.** Sparkdock targets **bash 5.x** (Homebrew's `bash` formula, listed in `config/packages/all-packages.yml`). macOS ships `/bin/bash` 3.2, but `#!/usr/bin/env bash` resolves to the Homebrew interpreter on sparkdock-provisioned machines. You can use `declare -A`, `mapfile` / `readarray`, `${arr[-1]}`, `[[ -v var ]]`, and other bash 4+ idioms freely — no need for 3.2-compat workarounds.

All shell scripts must:

- Use `#!/usr/bin/env bash` shebang
- Include `set -euo pipefail` for error handling
- Use `${variable}` syntax with braces (never bare `$variable`)
- Use `local` for function variables to avoid namespace pollution
- Pass shellcheck validation (see below)
- Prefer early-return / guard-clause style over `else` branches when checking pre-conditions:

```bash
# Good: guard clause, no else
if ! command -v cirrus >/dev/null 2>&1; then
    brew install cirruslabs/cli/cirrus
fi

# Avoid: unnecessary else branch
if ! command -v cirrus >/dev/null 2>&1; then
    brew install cirruslabs/cli/cirrus
else
    echo "Cirrus CLI is already installed"
fi
```

**Shellcheck Validation**

Before committing changes to shell scripts, run shellcheck using the official Docker image:

```bash
docker run --rm -v "$(pwd):/src" koalaman/shellcheck:stable /src/bin/sparkdock-agents-status
```

## Python Standards

- Format all Python files with **ruff** before committing
- Run via Docker: `docker run --rm -v "$(pwd)/src:/src" ghcr.io/astral-sh/ruff:latest format /src`
- Lint check: `docker run --rm -v "$(pwd)/src:/src" ghcr.io/astral-sh/ruff:latest check /src`

## Go Standards

The terminal hub lives in `src/tui/` (a self-contained Go module, see the
**Sparkdock TUI** section). All Go work happens inside that directory.

**Always run these before committing any `.go` change**, in order. CI runs the
same gates (`.github/workflows/test-tui.yml`), so a skipped step here becomes a
red check on the PR:

```bash
cd src/tui
gofmt -l .               # MUST print nothing. If it lists files, run: gofmt -w .
go vet ./...             # static analysis; MUST be clean
go build ./...           # MUST compile
go test ./... -count=1 -race   # -count=1 defeats the test cache; -race matches CI
```

- **Formatting is non-negotiable.** `gofmt -l .` listing a file fails CI. Never
  hand-format; run `gofmt -w .`. Do not reformat files you did not change.
- **`-count=1`** on tests bypasses Go's result cache, so a green run reflects the
  current code rather than a cached pass.
- **Editor diagnostics about "inefficient `WriteString`" or "use `max`"** from
  staticcheck/gopls are advisory style hints, not CI gates (CI runs `go vet`, not
  staticcheck). Do not chase them unless you are already editing that code.
- **Design pattern.** Keep packages pure-core with side effects injected: parsing
  and orchestration take an injected command runner (see `internal/status`,
  `internal/sysinfo`, `internal/runner`) so they are unit-tested without invoking
  real binaries. New packages follow the same shape.
- **Cross-platform builds.** The binary ships only on macOS, but the code carries
  no build constraints and cross-compiles to linux, which is why CI runs on
  `ubuntu-latest`. Do not add `//go:build darwin` unless a file genuinely needs a
  macOS-only API; runtime tool calls (`system_profiler`, `afplay`) are plain
  strings and compile everywhere.

## Markdown Formatting

After creating or editing any Markdown file (`.md`), **always** run the
formatter before committing. Never format Markdown by hand -- delegate to
the tool.

## Code Quality Standards

**CRITICAL: Trailing Whitespace**

- **NEVER** commit trailing whitespace (spaces/tabs at end of lines)
- Git will warn about trailing whitespace during commits
- Always clean up trailing whitespace before staging changes
- Use your editor's "show whitespace" feature to identify issues
- This applies to ALL files: Swift, shell scripts, YAML, Markdown, etc.

**JavaScript Style**

- Always use braces for `if`, `for`, `while`, and similar control statements, even for single-line bodies

**CHANGELOG.md Conventions**

**MANDATORY**: Every commit that changes user-visible behavior, adds features, fixes bugs, removes functionality, or refactors existing behavior **MUST** include a corresponding `CHANGELOG.md` entry under `## [Unreleased]`. This is not optional — treat a missing changelog entry as a build failure. The only exceptions are pure documentation or test-only changes with zero user-facing impact.

This project uses a daily Slack digest that parses `CHANGELOG.md` to detect and announce new entries. Malformed sections (duplicate headers, wrong categories) **break the digest silently**. Follow these rules strictly:

- Follow [Keep a Changelog](https://keepachangelog.com/) format
- **One header per section**: Each `### Added`, `### Changed`, `### Fixed`, `### Removed`, `### Deprecated`, `### Security` must appear **exactly once** under `## [Unreleased]`. Never create a duplicate section header — always prepend entries to the existing section
- **Standard section order**: Added, Changed, Deprecated, Removed, Fixed, Security. Do not intersperse or reorder sections
- **Correct categorization**: Entries must match their section. New features/tools/commands go under `### Added`, not `### Changed`. Use `### Changed` only for modifications to existing behavior. Use `### Fixed` for bug fixes. If an entry starts with "Added", it belongs under `### Added`
- **New entries go at the top** of their section — newest first, preserving temporal order
- **Never reorder existing entries** — only prepend above them
- **One line per entry**: Keep entries concise, no excessive detail. Do not use `####` sub-headings or multi-level nesting inside `## [Unreleased]`
- **No trailing whitespace** on any line

## Testing

- Ansible playbooks should be idempotent
- Run Python unit tests with `just test-python` (stdlib `unittest`; also runs in CI via `.github/workflows/test-python.yml`)
- Test HTTP proxy with `test-http-proxy` command
- Verify package installations with assertion tasks
- Check system state with `sjust device-info`

## Sparkdock Manager (Menu Bar App)

A Swift-based menu bar application provides battery-efficient visual update notifications using modern async/await patterns:

### Key Features

- **Event-Driven Updates**: Only checks on system wake and network connectivity changes (no periodic polling)
- **Modern Swift Concurrency**: Uses structured concurrency with proper cancellation and timeout handling
- **Battery Efficient**: NWPathMonitor for lightweight network monitoring
- **Resource Debugging**: Enhanced logging for missing logo/resource troubleshooting

### Building and Testing

```bash
cd src/menubar-app
make build                    # Build the app
make test                     # Test build
make install                  # Install manually (requires sudo)
make uninstall               # Remove installation
```

### Integration

- Built automatically during Ansible provisioning with `menubar` tag
- Replaces old launchd-based update notifications
- Auto-starts at login via launch agent (local development only)
- CI environments skip LaunchAgent installation for better automation

## Sparkdock TUI (Terminal Hub)

A Go/bubbletea terminal hub under `src/tui/`, the terminal twin of the menu bar
app. It is an **opt-in front end**: launched with `sparkdock tui`, never by bare
`sparkdock` (which keeps its self-update plus full-provisioning behavior). See
the **Go Standards** section for the mandatory `gofmt`/`vet`/`build`/`test` gate.

### What it does

- A flat grouped dashboard mirrors the menu bar: a status group (Sparkdock, Brew
  packages, HTTP proxy, AI harness) fed by `sparkdock-check-updates` and `brew
outdated`, plus a background-gathered system-info panel (model, serial, chip,
  memory, disk, macOS).
- Each action shows its **equivalent shell command** as the detail, so the CLI is
  discoverable: `Update everything` (`sparkdock`), `Upgrade Brew packages` (`brew
upgrade`), `Sync AI harness` (`sjust sf-harness-sync`), the `HTTP proxy` group
  (`spark-http-proxy …`), and `d` for device info (`ayse-get-sm`).
- A shared Runner streams output above a pinned statusline via two renderers
  behind one interface: **structured** (decodes the `ansible/callback_plugins/sparkdock.py`
  stdout callback's `@@PHASE`/`@@TASK`/`@@STAT`/`@@DONE` markers) and **terminal**
  (a VT emulator for programs that redraw in place, like `brew`).
- Privileged runs use `--ask-become-pass`; the password is entered on a masked
  page and written to the process PTY. **It is never cached, never put in the
  environment, argv, or a file, and is asked for each time.** Do not add caching.

### Building and testing

```bash
cd src/tui
go build -o .build/sparkdock-tui ./cmd/sparkdock-tui   # build the binary
go test ./... -count=1                                  # run the suite
```

- The full binary is built during provisioning via the `tui` Ansible tag
  (`become: false`, no sudo). `sparkdock tui` builds it on first use and rebuilds
  whenever `src/tui` is newer than the installed binary.
- To run the binary against a dev checkout (not the installed `/opt/sparkdock`),
  set `SPARKDOCK_ROOT` to the repo root; otherwise the callback plugin and status
  binaries resolve against `/opt/sparkdock` and fail. The `sparkdock` entrypoint
  exports `SPARKDOCK_ROOT` for you.
- Disable the logo-click chime in tests or headless use with
  `SPARKDOCK_TUI_NO_AUDIO=1`. The TUI needs a TTY; with no TTY it takes a headless
  path (currently a stub).

### Not yet wired

- The dashboard's self-update action is hidden (not a dead button); the
  `Update everything` action and bare `sparkdock` cover self-update. The
  headless delegate (`sparkdock-tui update` / `--no-tui`) execs the `sparkdock`
  bash entrypoint; a bare non-TTY invocation refuses with guidance.

## macOS System Defaults

`sjust macos-defaults` applies a curated set of macOS preferences (data: `config/macos/defaults.yml`, code: `sjust/scripts/macos-defaults/`, idempotent, per-key snapshot/undo). **Keep the curated YAML to universally-useful defaults only** — personal preferences (dock, finder layout, smart-quotes, trackpad, …) go in user overrides at `~/.local/spark/macos-defaults/overrides.yml`, not the curated set. Run `sjust macos-defaults-info` to inspect.

## AI Coding Agents System

Sparkdock syncs AI coding resources from the upstream `sf-awesome-copilot` repository. This covers two resource types managed by a unified sync system:

- **Skills**: Tool-specific instruction files (e.g., `glab`) installed to `~/.agents/skills/<name>/SKILL.md`
- **Agent profiles**: Per-tool agent configurations (e.g., "The Architect") installed to tool-specific directories (`~/.copilot/agents/`, `~/.config/opencode/agents/`)

### Key Scripts

- `bin/sparkdock-agents-sync` — Unified sync script with tool registry, skill sync, agent sync, v2 manifest
- `bin/sparkdock-agents-status` — Status display for both skills and agent profiles
- `bin/sparkdock-check-updates` — Accepts both `skills` and `agents` subcommands

### Tool Registry

The sync script uses associative arrays to map each coding tool to its install directory and filename pattern. Adding support for a new tool requires only 2 lines (one in each array). Current tools: `claude`, `copilot`, `opencode`.

### Manifest

Located at `~/.cache/sparkdock/sf-skills-manifest.json`. V2 format with `skills` and `agents` top-level keys. V1 manifests upgrade organically (no migration code). Agent entries use composite keys like `the-architect/copilot`.

### Catalog Metadata

The upstream repo provides `config/catalog.json` with short human-friendly descriptions for each system skill and agent. The status script reads this file from the local cache (`~/.cache/sparkdock/agent-skills/config/catalog.json`) to display a DESCRIPTION column in the table. No sync changes are needed — the file is part of the cloned cache.

### sjust Recipes (`sjust/recipes/shared/01-ai-coding-harness.just`)

- `sf-harness-status` — Show full AI coding harness status (tools + skills + profiles)
- `sf-harness-sync [force]` — Fast sync: skills + agent profiles from upstream
- `sf-harness-upgrade [force]` — Full upgrade via Ansible (RTK + caveman + gh gate + skills)
- `claude-gh-gate-{enable,disable,info}` — manage the Claude Code gh skill gate (blocks `gh` until the `gh` skill loads; bypass at runtime with `SPARKDOCK_GH_GATE=0`)

### Ansible Tags

- `ai-coding-harness` — umbrella tag for AI coding harness tasks
- `ai-harness` — alternate umbrella (includes sync + provision)
- `ai-harness-sync` — no-sudo tasks (RTK + caveman + gh gate + skills sync)
- `claude-gh-gate` — register only the Claude Code gh skill gate hook
- `ai-harness-provision` — sudo tasks (directory creation + chmod)
- `skills` — backward-compat alias

### OpenSpec Change

Full design artifacts at `openspec/changes/unified-agents-sync/` (proposal, design, specs, tasks).

## Git Workflow

- **Default branch**: `master` (not `main`)
- Automatic stashing of local changes during updates
- Lock file at `/tmp/sparkdock.lock` prevents concurrent updates
- Built-in rollback on failed updates using stored commit hashes

## Troubleshooting

- Lock file issues: Remove `/tmp/sparkdock.lock`
- DNS issues: Run `sjust clear-dns-cache`
- Update failures trigger automatic rollback
- Menu bar app issues: Check `~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist`
- See `TROUBLESHOOTING.md` for detailed guidance
