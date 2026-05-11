# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added Claude Code (`claude-code` brew cask) to default provisioned packages
- Added `setup_claude()` to RTK setup for Claude Code global hook integration via `rtk init -g --auto-patch`
- Added `config/rtk/exclude-commands.toml` and RTK setup logic that bootstraps RTK's own `config.toml` when needed, then rewrites only `exclude_commands` with Sparkdock's destructive shortlist (including `k`, `tf`, and `d` alias assumptions) so dangerous commands bypass RTK rewrite
- Added a GitHub Actions workflow that verifies Sparkdock RTK setup installs the expected files, merges `exclude_commands` into RTK's config, and can run basic `rtk` commands end to end

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

- Reworked RTK setup to support Claude Code (global hook), OpenCode (plugin), and Copilot (instructions-only with a minimal Sparkdock-owned policy: broad RTK use for high-output local dev commands, but raw commands for destructive, infrastructure, and remote-state actions) while preserving RTK's base config and always rewriting Sparkdock-managed `exclude_commands`
- Restored automatic RTK setup in macOS provisioning now that Sparkdock only rewrites `exclude_commands` and verifies the integration in CI

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
