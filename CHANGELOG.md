# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added timetracker to the update-notification system: `sparkdock-check-updates timetracker` delegates to the CLI's own `timetracker update --check` (exit 3 when the CLI is not installed), the menu bar app gained a Timetracker status row plus an `Upgrade Timetracker` action that runs `timetracker update --apply` and tints the icon when an update is pending, the Tools menu gained "Open timetracker" and "Update timetracker" entries, and `sjust sf-timetracker-info` reports the local install state; the Timetracker menu entries and status row appear only on machines where the CLI is installed, via a new optional `requires_binary` field on menu items re-evaluated on every refresh, so installing the CLI surfaces them without restarting the app
- Added `herdr` (terminal multiplexer for coding agents, https://herdr.dev) to `homebrew_packages`
- Added `sjust sf-openspec-cleanup-project` recipe to remove OpenSpec-managed components (skills, commands and prompts) from the current project's `.claude`, `.opencode` and `.github` folders, keeping the `openspec/` folder untouched; pass `dry-run` to only list what would be removed
- Added an sjust recipe browser to `sparkdock tui` (press `s`): a filterable catalog of the public, argument-free recipes from `just --dump`, grouped and documented, with enter running the selection through the shared runner as `sjust <name>`
- Added a `?` help overlay to the `sparkdock tui` dashboard with the full key reference for the dashboard, live runs, and finished runs
- Added outdated package names to the `sparkdock tui` Brew status row (first three, folding the rest into `+N more`), and failing status checks now surface the command's first stderr line instead of a bare "check failed"
- Added a "checked Xm ago" age hint to the `sparkdock tui` dashboard footer so the freshness of the status round is visible

- Added a self-update step to the `sparkdock tui` `Update everything` action: it now force-syncs the `/opt/sparkdock` install to upstream `master` (stashing any local changes) before provisioning, matching bare `sparkdock`, so the Sparkdock status clears; the dashboard re-checks status whenever you return from any action, and advises a relaunch when the update rebuilds the hub's own binary
- Added cached (reclaimable) memory to the `sparkdock tui` system-info panel, shown beside free memory (e.g. `8 GB free · 16 GB cached / 48 GB`), the way Activity Monitor distinguishes free from "Cached Files"
- Added a `beta` badge to the `sparkdock tui` splash and header, plus a logo flourish: clicking the splash logo plays an original synthesized chime and flares the wordmark and spark glyph with a brightness ramp synced to the sound
- Added `sparkdock tui`, an opt-in terminal hub (Go/bubbletea) mirroring the menu bar app: a status dashboard with a system-info panel, and a streaming view (pinned statusline, masked never-cached sudo entry, cancel, retry, copyable log) for provisioning, `brew upgrade`, AI-harness sync, and HTTP-proxy actions, each labelled with its equivalent shell command. Built via the `tui` Ansible tag; bare `sparkdock` is unchanged
- Added a `cask_install_once_packages` list in `config/packages/all-packages.yml` for Homebrew casks that should be installed only when absent and never force-reinstalled; each entry supports an optional `app` name so a copy installed outside Homebrew (e.g. downloaded from the web) is detected via its `.app` bundle and not reinstalled
- Added an OpenSpec section to `sjust sf-harness-status` showing the `openspec` CLI version, the global `~/openspec` project state, and per-tool (claude/copilot/opencode) counts of installed `openspec-*` skills and `opsx` prompts; read-only, no-op when the CLI is absent
- Added `sjust sf-openspec-install-global [tools]` recipe and Ansible task that install or update OpenSpec skills and prompt commands globally via a home `~/openspec` project; idempotent, defaults to the `claude` tool, runs during provisioning when the `openspec` CLI is available
- Added a Claude Code `gh` skill gate: a sparkdock-managed `PreToolUse` hook (`sjust/scripts/claude-gh-gate.py`) that blocks the first `gh` command of a session until the `gh` skill is loaded via the Skill tool, then allows the rest of the session (per-session sentinel keyed by `session_id`). Scoped to `gh` only (the `glab` skill is in near-constant use and reliably loaded, so gating it would add friction with no payoff). Default-on (registered during provisioning, like the RTK/caveman hooks, on macOS and Linux); coexists with the RTK Bash hook since it only decides allow/deny. Manage it with `sjust claude-gh-gate-{enable,disable,info}`, and bypass at runtime with `SPARKDOCK_GH_GATE=0` for headless automation. Idempotent, atomic settings write with a timestamped backup, and it preserves all other hooks and settings.
- Added `sjust/scripts/lib/claude_settings.py`, a shared helper for atomic, backed-up reads/writes of `~/.claude/settings.json` and marker-based hook register/unregister, so future gates and settings managers reuse the same plumbing.
- Added `sjust claude-fix-settings` and `sjust claude-fix-settings-info` recipes that repair sparkdock-managed Claude Code hooks in `~/.claude/settings.json` — normalize the caveman hook node path to a stable Homebrew symlink and (opt-in) remove the claude-usage session hooks; idempotent, atomic write with timestamped backup, no-op on a missing/corrupt settings file. The node-path normalization also runs automatically at the end of the caveman setup so it self-heals every provisioning pass on macOS and Linux; claude-usage hook removal is opt-in and only happens via the recipe, so hooks a user added deliberately are left alone
- Added `sjust claude-usage-install [version]` and `sjust claude-usage-uninstall` recipes that wrap the official cross-platform claude-usage installer (https://github.com/sparkfabrik/claude-usage) — auto-detects macOS/Linux, arch, and desktop reader; idempotent; optional version pin. Prefers the release-published `install.sh` asset and verifies it against the release `checksums.txt` (aborting on mismatch), and falls back to the raw script for older releases that predate the asset.
- Added reasoning effort level (`⚡ high`) to the managed Claude Code statusline — reads `effortLevel` from the stdin payload when present, falling back to `~/.claude/settings.json`; magenta when `max`
- Added language server binaries for Claude Code's official code-intelligence plugins so org-level `enabledPlugins` can wire them in without per-machine setup: `intelephense`, `typescript`, `typescript-language-server`, `pyright` to `npm_packages` (covers `php-lsp`, `typescript-lsp`, `pyright-lsp` plugins) and `gopls` to `homebrew_packages` (covers `gopls-lsp` plugin). LSP processes only spawn when matching file extensions are present in the workspace, so devs not working in a given language pay no runtime cost.
- Added `cask_latest_packages` list in `config/packages/all-packages.yml` for Homebrew cask packages that should be upgraded to latest on every provisioning run; switched `claude-code` to `claude-code@latest` cask (tracks latest releases instead of stable) and moved it along with `copilot-cli` into this list so they stay current automatically
- Added `/usr/local/bin/sparkfabrik-claude-code-otel-headers` — Claude Code OTLP `otelHeadersHelper` script. Reads the bearer from Secret Manager via the user's gcloud session.
- Added drop-in snippet support: `~/.config/spark/shell.d/*.zsh` files are now sourced automatically (lexicographic order) after `~/.config/spark/shell.zsh`, enabling MDM tools and package installers to deploy isolated shell snippets without sharing an edit surface with the user's personal `shell.zsh`
- Added caveman output compression integration for Claude Code, OpenCode, and GitHub Copilot (`sjust sf-caveman-install`) — reduces AI response tokens ~50% using structured terse-output rules (default mode: full); includes `sf-caveman-uninstall` recipe, Ansible `caveman` tag, and per-agent guard clauses for easy addition/removal of agents
- Added `coreutils` (GNU core utilities) to default Homebrew packages
- Added "AI Development - Where We Are" playbook link to menu bar app Company section
- Added Claude Code (`claude-code` brew cask) to default provisioned packages
- Added `setup_claude()` to RTK setup for Claude Code global hook integration via `rtk init -g --auto-patch`
- Added `config/rtk/exclude-commands.toml` and RTK setup logic that bootstraps RTK's own `config.toml` when needed, then rewrites only `exclude_commands` with Sparkdock's destructive shortlist (including `k`, `tf`, and `d` alias assumptions) so dangerous commands bypass RTK rewrite
- Added `~/.local/bin/rtk-run`, a small helper that runs `rtk rewrite` first and otherwise falls back to the original raw command, so Copilot instructions can use one command for safe high-output local workflows
- Added a GitHub Actions workflow that verifies Sparkdock RTK setup installs the expected files, merges `exclude_commands` into RTK's config, and can run basic `rtk` commands end to end
- Added `sjust macos-defaults` recipe and an `ansible/macos/macos/base.yml` task that apply a small curated profile of universally-useful macOS system defaults (`.DS_Store` suppression on networks/USB, secure keyboard entry in Terminal, expanded save / print panels, Time Machine prompt suppression). Idempotent (no-op when already aligned), per-key snapshot and undo, dry-run preview, and per-key user overrides at `~/.local/spark/macos-defaults/overrides.yml`. Companion recipes: `macos-defaults-info` (curated profile + live ✓/✗/+ status), `macos-defaults-undo`, `macos-defaults-init-overrides`
- Added `bash` (Homebrew formula, 5.x) to `config/packages/all-packages.yml` so Sparkdock scripts can rely on bash 4+ idioms (`declare -A`, `mapfile`, `${arr[-1]}`, etc.); macOS's stock `/bin/bash` is 3.2.57 and several existing scripts (`bin/common/skills-symlink-shim.sh`, `bin/sparkdock-agents-sync`) already required this implicitly via Homebrew's `PATH` ordering — this commit makes the dependency explicit
- Added `~/.local/bin` to default zsh PATH for user-local binaries (XDG convention), auto-creating the directory if missing
- Added automatic disabling of gcloud usage reporting during Google Cloud SDK configuration (both in Ansible provisioning and `sjust system-gcloud-reconfigure`)
- Added orphan cleanup to `sparkdock-agents-sync`: detects and removes managed skills/agent profiles no longer in upstream, with `--force` to remove locally modified orphans
- Added orphan detection to `sparkdock-agents-status`: flags resources removed from upstream as `orphan` type with cleanup hint
- Added DESCRIPTION column to `sjust sf-agents-status` tables, reading short descriptions from upstream `catalog.json` with tab-delimited rendering to support commas in descriptions
- Added shellcheck Docker validation instructions to `AGENTS.md` for shell script quality checks before committing
- Added Claude Code skill symlinks: creates per-skill symlinks in `~/.claude/skills/` pointing to `~/.agents/skills/` so Claude Code can discover sparkdock-managed skills (mirrors existing Copilot CLI support, uses shared tool registry for easy extensibility)
- Added `sjust sf-copilot-premium-usage` recipe to show premium Copilot request usage in a formatted dashboard
- Added `--json` option to `sjust sf-copilot-premium-usage` for raw API output
- Added shared Copilot auth module (`sjust/scripts/lib/copilot-auth.mjs`) to deduplicate token handling across scripts
- Added `sjust sf-copilot-model-list` recipe to list available Copilot models with billing multiplier and premium status grouping
- Added `--list` flag to `copilot-models.mjs` for plain model ID output useful for scripting
- Added OpenSpec shell aliases: `os` (openspec), `osi` (init with opencode+github-copilot tools), `osl` (list), `oss` (status), `osn` (new change), `osa` (archive)
- Added `sjust githuman-open` recipe to open the browser for a running GitHuman instance or start a new one
- Added `sjust githuman-id` recipe to print the container ID of a running GitHuman instance
- Added `sjust sf-openspec-configure` recipe to deploy OpenSpec custom profile with all 11 workflows and telemetry disabled, with interactive overwrite confirmation (pass `force` for programmatic/Ansible use)
- Added Copilot CLI skill symlinks: creates per-skill symlinks in `~/.copilot/skills/` pointing to `~/.agents/skills/` so Copilot CLI can discover sparkdock-managed skills (workaround for [github/copilot-cli#1744](https://github.com/github/copilot-cli/issues/1744))
- Added secure OpenCode permissions config with 174 glob-based deny/ask rules (116 ask + 58 deny) covering system commands, git, Docker, Kubernetes, Helm, Terraform, npm/yarn, cloud CLIs (gcloud, gsutil, aws, az), BigQuery, and macOS system utilities
- Added optional import of `~/.local/spark/sparkdock/sjust/000-system.just` to allow Sparkdock externally managed tasks (such as MDM) to be included in SparkJust
- Added `sjust sf-agents-refresh` and `sjust sf-agents-status` recipes (backward-compatible `sf-skills-*` aliases kept)
- Added automatic agent skills sync system that syncs curated SparkFabrik system skills from upstream repo to `~/.agents/skills/` with SHA256 manifest tracking, conflict detection, and `--force` flag for overwriting local modifications
- Added `sparkdock-check-updates` unified update checker script with exit codes (0=updates-available, 1=up-to-date, 2=error, 3=not-configured) supporting sparkdock, http-proxy, and skills subsystems
- Added `sparkdock-skills-sync` script for syncing skills from upstream with gum spinner and summary box UI
- Added `sparkdock-skills-status` script to display managed skills status
- Added skills subsystem to Sparkdock Manager menu bar app with colored dot status and upgrade button
- Added `sjust sf-skills-refresh` and `sjust sf-skills-status` recipes
- Added Ansible provisioning task for agent skills sync (tagged with `skills`)
- Added shared logging library (`bin/common/logging.sh`) with optional gum integration providing `log_info`, `log_success`, `log_warn`, `log_error`, `log_section` with styled output and ANSI fallback
- Added shared utility library (`bin/common/utils.sh`) with `run_with_spinner`, `print_summary_box`, `compute_sha256`, and backward-compatible `print_*` aliases
- Added gcloud shell aliases: `gcloud-as` (impersonate service account), `gcloud-me` (stop impersonating), `gcloud-whoami` (show current impersonation)
- Added global OpenCode configuration to disable OpenCode Zen free models provider for privacy compliance
- Added OpenSpec (@fission-ai/openspec) npm package to default package list for spec-driven development with AI coding assistants
- Added OpenCode shell alias: `c` as a simple alias to `opencode` command
- Added opencode AI coding tool to default package list (now officially supported by Copilot)
- Added python@3.13 and python@3.14 to base packages to fix broken Python installations for tools like google-cloud-sdk
- Added automated Slack notifications for significant feature releases merged to master branch (using Claude AI to analyze changelog and generate user-friendly announcements for #tech channel)
- Added Visual Studio Code Insiders to default package list for early access to new VSCode features
- Added Copilot CLI shell aliases for multiple AI models with one-shot mode (co/cos/coh/coc/cog/coo), interactive mode (ico/icos/icoh/icoc/icog/icoo), and session management (cocon/cores)
- Added Chrome web app integration for menubar URL links - URL menu items now open as standalone Chrome windows without browser UI using the `--app` flag
- Added automatic disabling of gcloud survey prompts during Google Cloud SDK configuration (both in Ansible provisioning and `sjust system-gcloud-reconfigure`)
- Added an experimental Sparkdock AI helper (with `sjust sparkdock-ai` and `sjust sparkdock-configure-llm`) that routes questions via a classifier, verifies Copilot plugins/auth, renders a Gum UI with logo/help, and logs activity as "living documentation"
- Added Sparkdock shell configuration system with modern CLI tools (eza, bat, ripgrep, fd, zoxide, fzf, starship, thefuck, chafa)
- Added new sjust commands for shell management: `shell-enable`, `shell-disable`, `shell-info`, `shell-omz-setup`, `shell-omz-update-plugins`
- Added smart aliases with conditional loading (ff, zd/cd with zoxide, ls with sorting, docker, git, kubernetes)
- Added seamless integration with existing oh-my-zsh/starship installations and user customization via `~/.config/spark/shell.zsh`
- Added font-caskaydia-mono-nerd-font (Cascadia Code Nerd Font)
- Added Ghostty config-file directive setup for easier customization (user config loads Sparkdock base via config-file directive)
- Added Context7 MCP server configuration for Just documentation lookup
- Added custom instructions file for Just recipes (`.github/instructions/just.instructions.md`)
- Added Claude Code GitHub workflow for AI-assisted code reviews and issue handling
- Added `ensure-python3` command mode to `sparkdock.macos` for checking and fixing Python3 symlink issues (callable via `sparkdock ensure-python3`)
- Added UDP port forwarding support in Lima (see https://github.com/lima-vm/lima/issues/4040)
- Added Lima version display to `lima-quick-setup` task output
- Added `docker-desktop-diagnose` task to run Docker Desktop diagnostics with optional upload functionality
- Added Universal Definition of Done link to menubar company links
- Added `docker-desktop-install-version-4412` task to download Docker Desktop 4.41.2 to work around network issues

### Changed

- Moved `google-cloud-sdk` from `cask_packages` to `cask_latest_packages`, so an existing Google Cloud SDK is upgraded on every provisioning pass instead of staying pinned at the version installed on first provision
- Changed `sparkdock tui` status checks to run in parallel and stream into the dashboard row by row, each under a 60-second timeout so a hung command can never pin a row on the loading ellipsis; returning to the dashboard keeps the previous rows visible while the new round refreshes in the background
- Changed `sparkdock-tui update` and `--no-tui` to exec the `sparkdock` bash entrypoint (self-update plus provisioning) instead of printing a stub; a bare non-TTY invocation now refuses with guidance rather than provisioning implicitly
- Changed `sparkdock tui` run cancellation to signal the child's whole process group (nested processes included) and escalate to SIGKILL after a five-second grace period if SIGINT is ignored
- Changed the `sparkdock tui` log page clipboard copy to fall back to an OSC 52 escape when `pbcopy` cannot reach the clipboard (e.g. an SSH session)
- Set `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` so `brew` no longer upgrades casks with `auto_updates true` (Chrome, Slack, Docker Desktop, …), restoring the behaviour a recent brew change removed (https://github.com/Homebrew/brew/pull/21882). Applied in three places so every code path is covered: the managed shell init (interactive use), the Ansible play environment (provisioning), and the sparkdock TUI's brew upgrade run. Opt back in per run with `brew upgrade --greedy`
- Replaced the `ANSIBLE_BECOME_PASS` environment variable with Ansible's native `--ask-become-pass`, so the become password is held in memory instead of exported to the process environment (#541)
- Moved Docker Desktop, Google Chrome, VSCode (stable and Insiders), Slack, and Zoom from `cask_packages` to the new install-once handling, so they are installed once and never force-reinstalled on later provisioning runs; this replaces the three per-app skip blocks (Docker/Chrome/VSCode Insiders) with a single data-driven block and stops Chrome from being force-reinstalled (degrading the browser) while it is open
- The OpenSpec CLI upgrade task now runs `brew update` first (`update_homebrew: true`) so `state: latest` resolves against current formula definitions instead of a possibly stale local index
- `sjust sf-harness-upgrade` now also upgrades the OpenSpec CLI to the latest Homebrew release and refreshes the global OpenSpec skills and prompts: the OpenSpec Ansible block now carries the `ai-harness`/`ai-harness-sync` tags, so the upgrade reuses the existing `sf-openspec-configure` and `sf-openspec-install-global` recipes
- The Claude `gh` gate is now a no-op when `gh` is not installed (not on `PATH`): rather than blocking to load the skill before a command that would only fail with "command not found", it lets the command run. No effect on machines that have `gh`.
- The Claude `gh` gate now matches `gh` only when it is the command being run (start of the command, or after a `;`/`|`/`&`/newline separator, optionally preceded by env-var assignments), instead of anywhere in the command string. This prevents false-positive blocks when `gh` merely appears inside an argument, such as a commit message that mentions "gh".
- Menu bar app binary now installs to user-owned `/opt/homebrew/bin/sparkdock-manager` instead of root-owned `/usr/local/bin`, so `sjust sparkdock-menubar-install` no longer needs sudo or a become password (build and LaunchAgent were already user-level)
- Claude Code statusline context warning is now dynamic against the active model's context window: shows `ctx NN%/1M` (or `/200k`), colored cyan/amber/red by usage, using Claude Code's `context_window.used_percentage` and `context_window.context_window_size`. Falls back to the fixed `⚠ 200k+` flag on older builds that don't emit `context_window`
- Renamed sjust group `ai-coding-agents` → `ai-coding-harness` and commands `sf-agents-status` → `sf-harness-status`, `sf-agents-sync` → `sf-harness-sync`, `sf-agents-upgrade` → `sf-harness-upgrade`; old names kept as deprecated aliases with notice. Recipe file renamed `01-ai-coding-agents.just` → `01-ai-coding-harness.just`. Ansible tag updated to `ai-coding-harness` (keeping `skills` for backward compat)
- Copilot custom instructions now write only to `~/.copilot/copilot-instructions.md` (official Copilot CLI local instructions path per GitHub docs); dropped undocumented `~/.github/copilot-instructions.md`. Applies to both RTK and caveman setup scripts. Existing orphaned blocks in `~/.github/copilot-instructions.md` are cleaned up automatically on next run
- Simplified Copilot RTK helper instructions to focus on `rtk-run`, concise command examples, quoted shell operators, and raw-command fallback
- Reworked RTK setup to support Claude Code (global hook), OpenCode (plugin), and Copilot (helper + instructions with `rtk-run` for high-output local commands, but raw commands for destructive, infrastructure, and remote-state actions) while preserving RTK's base config and always rewriting Sparkdock-managed `exclude_commands`
- Restored automatic RTK setup in macOS provisioning now that Sparkdock only rewrites `exclude_commands` and verifies the integration in CI
- `sjust macos-defaults` apply output now names the specific settings that take effect at next use (no app restart needed) instead of the generic "some changes may require logout/restart" footer
- `bin/common/logging.sh` log helpers (`log_info` / `log_success` / `log_warn` / `log_error` / `log_section`) now write to stderr in the no-gum fallback path, matching gum's own default; previously the printf fallbacks went to stdout and could contaminate `var="$(my_func)"` capture patterns
- Moved opencode base configuration from `~/.config/opencode/opencode.json` to `/Library/Application Support/opencode/opencode.json` (system-wide path, user-writable) to support user-local overrides via `~/.config/opencode/opencode.json`
- Added automatic cleanup of duplicate `~/.config/opencode/opencode.json` when identical to the shipped source, with a warning when the file contains non-custom content
- Moved shell recipes (`shell-enable`, `shell-disable`, `shell-info`, `shell-omz-setup`, `shell-starship-setup`, `shell-eza-setup`, `shell-ghostty-setup`) to shared recipes directory for cross-platform reuse via ajust on Linux
- Extracted bashcompinit-based completions (gcloud) from `sparkdock.zshrc` into dedicated `config/shell/bashcompinit-completions.zsh` file for cleaner separation of concerns and easier addition of future bashcompinit tools (aws, terraform)
- Replaced tmate with upterm for terminal session sharing (tmate is deprecated in Homebrew), with a transition shell shim that guides users to the new tool
- Menubar app now auto-refreshes subsystem status after upgrade actions complete so the icon updates immediately
- Changed Copilot API auth to support multiple sources (gh CLI, OpenCode) with automatic fallback on 401/403, removing the hard dependency on OpenCode for `sf-copilot-premium-usage`, `sf-copilot-model-limits`, and `sf-copilot-model-list` recipes
- Improved `copilot-models.mjs` plain-text table output with proper column alignment when `gum` is not available, use `premium` API field for model grouping, and use unique temp file names for `gum` table rendering
- Updated Copilot shell aliases (`co`/`ico` family) to latest available models: gpt-5-mini, claude-sonnet-4.6, claude-opus-4.6, gpt-5.3-codex, gemini-3.1-pro-preview
- Moved `copilot-models.mjs` from `config/macos/scripts/` to `sjust/scripts/` to colocate with recipes
- `sf-agents-refresh` now accepts both `force` and `--force` to trigger a forced update
- `githuman-start` now opens the browser automatically when a GitHuman instance is already running for the directory
- Show upstream-available but not-yet-installed skills and agent profiles in `sf-agents-status` output, with `available / not installed` status and footer hint to run `sf-agents-refresh`
- Migrated OpenSpec installation from npm (`@fission-ai/openspec`) to Homebrew (`brew install openspec`) for simpler dependency management and version alignment, with automatic cleanup of the legacy npm package
- Changed Slack notifications to run as a daily 10:30 Europe/Rome digest that summarizes the previous day's meaningful `CHANGELOG.md` additions on `master`, with manual replay/preview support and GitHub Actions run summaries
- Refactored `sparkdock-agents-status` to use `gum table` for polished terminal output with colored status values, replacing printf-based column formatting
- Unified agent skills and agent profiles into a single sync system (`sparkdock-agents-sync`, `sparkdock-agents-status`) supporting per-tool agent profiles alongside skills, with v2 manifest and upstream conflict detection
- Adopted ruff as Python formatter/linter, run via Docker before committing
- Refactored section headers across sjust recipes (libshell.sh, 00-default.just, 01-lima.just, 03-shell.just) to use `log_section` with double-border gum style
- Disabled gh (GitHub CLI) telemetry by default via `GH_TELEMETRY=false` in shell configuration
- Disabled glab telemetry by default via `GLAB_SEND_TELEMETRY=false` in shell configuration
- Regenerate opencode and openspec zsh completion files via Ansible on every install/upgrade to keep them up to date
- Changed npm global package installation state from `present` to `latest` to ensure packages are always updated to their latest version
- Changed `c` alias from `clear` to OpenCode main command. Use `clear` command directly or ctrl+l for clearing screen instead
- Consolidated Slack notification script git diff functions into single parameterized function with configurable commit count
- Migrated GitHub Copilot CLI from npm package (`@github/copilot`) to Homebrew cask (`copilot-cli`) for improved installation and update management
- Aligned `sparkdock` command with `sjust http-proxy-install-update` by adding service restart to Ansible http-proxy tasks (spark-http-proxy handles container cleanup via Docker Compose)
- Updated system requirements documentation to clarify Apple Silicon-only support (removed Intel Mac references)
- Default terminal for menu bar app changed from Terminal.app to Ghostty
- Lima quick setup now uses dynamic CPU and memory defaults like Docker Desktop: all available processors and 50% of host memory
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` with improved description and updated output messages

### Removed

- Removed `sjust sf-skills-refresh` backward-compatible alias (use `sf-agents-refresh` instead)
- Removed `sjust sf-skills-status` backward-compatible alias (use `sf-agents-status` instead)

### Fixed

- Fixed the interactive/CI detection desync that still broke pkg-based cask installs on some machines: a CI-style variable (`CI`, `RUNNER_OS`, ...) leaked into a developer's shell made the entrypoint skip the `BECOME password:` prompt entirely, so casks failed late with `sudo: a terminal is required to read the password`. `is_ci_environment()` now always treats a real terminal as interactive (env markers only apply without a TTY, and the vestigial `ANSIBLE_SUDO_PASSWORD` check is gone), the playbook's `is_non_interactive` fact is derived from the collected become password so the two detectors can no longer disagree, and the entrypoint prints which mode it picked
- Fixed provisioning failing late with `sudo: a terminal is required to read the password` on pkg-based casks (e.g. `docker-desktop`, `zoom`) when the `BECOME password:` prompt was answered with an empty or wrong password: the become password is now validated against `sudo` right at the start of the playbook (`no_log`, never echoed) and the run aborts immediately with a clear re-run message instead of half-provisioning the machine
- Fixed `sparkdock-agents-sync` printing a spurious `WARN No 'agents/system/' directory found in upstream repo.` on every run: upstream now advertises no system agents (`catalog.json` `"agents": {}`, the-architect removed), so an absent or empty `agents/system/` is a valid state and no longer warns
- Fixed `sjust sf-openspec-install-global` ignoring the tool list once `~/openspec` exists: the script now always runs `openspec init` with the requested tools (additive and idempotent) before refreshing with `openspec update`, so new tools such as `opencode` or `github-copilot` can be added on already-provisioned machines
- Fixed `sparkdock tui` late output from a cancelled run bleeding into the next run's view (or marking the new run finished): every runner message now carries a run generation stamp and stale messages are dropped
- Fixed `sparkdock tui` child programs rendering at a stale width after a terminal resize: the child's PTY is now resized (with SIGWINCH) alongside the view
- Gated the zoxide `cd` alias behind the `CLAUDECODE`/`AI_AGENT` markers so AI coding agents get a literal `cd` (a missing relative path errors instead of frecency-jumping the agent's persistent working directory); interactive shells keep zoxide-backed `cd`, and `zd`/`z`/`zi` stay available everywhere
- Fixed the menubar provisioning aborting on the "Verify menu bar app works" task with `rc -9` (SIGKILL) on managed Macs: a freshly installed binary fires a first-exec authorization that an Endpoint Security agent (e.g. Mosyle) can deny under load; the install now clears the provenance xattr and re-applies the ad-hoc signature to warm the assessment, and the verify step retries until the agent's verdict caches
- Fixed the managed Claude Code statusline dropping the weekly (`7d`) usage when Claude Code reports a fractional `seven_day.used_percentage` (e.g. `14.0000002`): the rate-limit percentages are now reduced to their integer part before the numeric check, the same way the context percentage already is. The `5h` value was unaffected only because it happened to be a whole number.
- Fixed provisioning failing on machines that installed a package before its Homebrew tap was renamed (e.g. `skhd` pinned to `koekeishiya/formulae`): added a generic step that reinstalls any tap-qualified package whose install receipt no longer matches its declared tap, rebinding it; driven by the existing package list, no-op for fresh installs and already-correct packages
- Fixed third-party Homebrew tap installs failing on Homebrew 6.x (`HOMEBREW_REQUIRE_TAP_TRUST`) by trusting each configured tap during provisioning; guarded to no-op on Homebrew < 6
- Fixed `skhd` install failing after its upstream GitHub owner renamed `koekeishiya` → `asmvik`: repointed the tap and package to `asmvik/formulae` and added `koekeishiya/formulae` to `removed_taps`
- Fixed caveman setup silently skipping Claude Code on Linux: the official Claude installer puts `claude` in `~/.local/bin`, which is absent from the PATH during non-interactive provisioning (the sf-toolbox ansible run executes as root), so `setup_claude`'s `command -v claude` guard failed and the plugin + hooks were never wired. The caveman setup now prepends `~/.local/bin` to PATH before detecting Claude
- Fixed the caveman installer baking a version-pinned node path (e.g. `/opt/homebrew/Cellar/node/26.0.0/bin/node`) into the `~/.claude/settings.json` SessionStart/UserPromptSubmit hook commands, which broke the hooks on every node upgrade: the caveman setup now rewrites it to a version-independent value on every provisioning pass — the Homebrew symlink (`/opt/homebrew/bin/node` on macOS, `/home/linuxbrew/.linuxbrew/bin/node` for linuxbrew), a non-versioned distro path such as `/usr/bin/node` when already stable, or the bare `node` command (PATH-resolved) for version-pinned setups with no stable symlink such as nvm
- Fixed an empty `ANSIBLE_BECOME_PASS` env var silently clobbering `--ask-become-pass`: the play-level `ansible_become_pass` is now only set when the env var is non-empty (`| default(omit, true)`), so interactive become prompts (e.g. `sjust sparkdock-install-tags`) are honored instead of failing with `sudo: a password is required`
- Fixed intermittent `apply2files - Permission denied` failures during `brew install` (e.g. `gopls`) caused by root-owned `.pyc`/files under `{{ homebrew_prefix }}/lib/python*` and `Cellar/python*` — a new `become`-elevated task chowns mis-owned Python files back to the invoking user before the Homebrew package step (idempotent, no-op when ownership is already correct, skipped in non-interactive/CI runs)
- Fixed RTK rewriting `yadm` commands to `rtk git` (breaking dotfile management) by adding `^yadm` to `exclude_commands` in `config/rtk/exclude-commands.toml` — upstream bug tracked at [rtk-ai/rtk#TBD](https://github.com/rtk-ai/rtk)
- Fixed `sf-harness-upgrade` failing on non-macOS hosts (e.g. ajust on Arch Linux) with `module interpreter '/opt/homebrew/bin/python3' was not found` — `ansible/inventory.ini` now uses `ansible_python_interpreter=auto_silent` so Ansible discovers a working Python on any host, and `sf-harness-upgrade` passes `-e dev_env_dir={{sparkdock_path}}` so the playbook tracks the real sparkdock location instead of the hardcoded `/opt/sparkdock`. Same Ansible flow on macOS and Linux.
- Fixed caveman OpenCode plugin hooks never firing — upstream uses non-existent `session.created` and `tui.prompt.append` hooks; patched to use `chat.message` + `experimental.chat.system.transform` ([caveman#418](https://github.com/JuliusBrussee/caveman/issues/418))
- Added a "done" banner to the GitHub Copilot section of `sf-caveman-install` mirroring the native installer output for Claude Code and OpenCode, so the Copilot install step has matching visual weight instead of finishing on a single log line
- Improved `sf-caveman-install` log message when Copilot instructions file is a symlink — now reports whether the symlink target already contains caveman rules instead of a misleading "skipping (managed externally)" message
- Fixed caveman setup breaking OpenCode startup by removing incompatible `cavecrew-*.md` agent files that use a YAML `tools` array instead of the `permission` object OpenCode expects ([caveman#386](https://github.com/JuliusBrussee/caveman/issues/386))
- Removed `*dd *` permission pattern from OpenCode config — the wildcard prefix caused false positives on any command containing `dd ` (e.g., `git add`) by matching the substring, effectively blocking all `git add` operations
- Fixed all 113 OpenCode deny/ask permission patterns missing leading `*` wildcard, preventing command prefix bypass (e.g., `rtk git push --force`, `env rm -rf /`, `time kubectl delete`) from evading safety rules
- Fixed `shell-enable` re-prompting users who already have Sparkdock shell enhancements installed, caused by quoting mismatch in the detection string after the cross-platform refactor
- Fixed CI failure caused by `neofetch` being removed from Homebrew — dropped it from the `removed_homebrew_packages` list since the formula no longer exists
- Fixed sjust zsh tab-completion (`_clap_dynamic_completer_sjust` not found) caused by just 1.40+ switching to dynamic clap completions — replaced sed-based renaming with a custom completion file that correctly bridges sjust to just's dynamic completer
- Fixed Slack notification announcing already-released features by using zero-context git diff (`-U0`) to eliminate context lines that confused Claude AI
- Fixed zsh completions from `~/.local/share/zsh/site-functions` not being discovered when the user's `.zshrc` calls `compinit` before sourcing sparkdock
- Fixed menubar terminal commands (sjust, sparkdock, brew upgrade) closing immediately after completion by dropping into an interactive shell session
- Fixed 3 Swift compiler warnings caused by unreachable catch blocks in menubar app process-launching functions
- Fixed `gcloud-whoami` not printing the current user when not impersonating a service account
- Fixed Slack notification system to correctly identify new tool/package additions as significant features
- Fixed `NODE_EXTRA_CA_CERTS` path in copilot function to point to the correct keychain certificate bundle location (`${HOME}/.local/spark/copilot/keychain.pem`)
- Fixed GitHub Copilot CLI idempotency issue where copilot binary was incorrectly removed on subsequent runs when cask was already installed
- Fixed GitHub Copilot CLI npm to brew cask transition by reordering cleanup tasks to run before cask installation, preventing binary conflict at `/opt/homebrew/bin/copilot`
- Fixed eza alias to display group ownership by default using `-g` flag in all ls commands
- Fixed Ghostty configuration overrides being ignored by implementing two-file setup (main config + user overrides file)
- Fixed Python interpreter not found error by implementing `ensure_python3()` function that checks for missing python3 symlink and automatically relinks Python packages before running Ansible playbook
- Fixed sjust zsh completion file ownership issue where `_sjust` file could be owned by root, causing Ansible task failures
- Fixed `docker-desktop-install-version-4412` task to automatically remove incompatible docker-mcp plugin that blocks Docker Desktop 4.41.2 from starting
- Fixed `lima-destroy` command to handle VMs that are already stopped, preventing fatal error when VM is not running
- Added `set -e` to `install.macos` to fail fast on errors

### Security

- The `sparkdock tui` become password now travels the submit path as a byte slice and is zeroed right after the write to the child's PTY, instead of lingering as immutable string copies; the design is otherwise unchanged (never cached, never in argv/env/files, asked each time)
