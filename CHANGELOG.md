# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added secure OpenCode permissions config with regex-based deny rules to block dangerous commands (rm -rf, sudo, docker prune, kubectl delete, terraform destroy, git force push, etc.) requiring user confirmation before execution
- Added OpenSpec (@fission-ai/openspec) npm package to default package list for spec-driven development with AI coding assistants
- Added opencode AI coding tool to default package list (now officially supported by Copilot)
- Added OpenCode shell alias: `c` as a simple alias to `opencode` command
- Added automated Slack notifications for significant feature releases merged to master branch (using Claude AI to analyze changelog and generate user-friendly announcements for #tech channel)
- Added Visual Studio Code Insiders to default package list for early access to new VSCode features
- Added global OpenCode configuration to disable OpenCode Zen free models provider for privacy compliance

### Changed
- Changed `c` alias from `clear` to OpenCode main command. Use `clear` command directly or ctrl+l for clearing screen instead

### Fixed
- Fixed Slack notification system to correctly identify new tool/package additions as significant features (improved prompt clarity to distinguish between dependency version bumps and new capabilities)
- Fixed `NODE_EXTRA_CA_CERTS` path in copilot function to point to the correct keychain certificate bundle location (`${HOME}/.local/spark/copilot/keychain.pem`)
- Fixed GitHub Copilot CLI idempotency issue where copilot binary was incorrectly removed on subsequent runs when cask was already installed
- Fixed GitHub Copilot CLI npm to brew cask transition by reordering cleanup tasks to run before cask installation, preventing binary conflict at `/opt/homebrew/bin/copilot`
- Aligned `sparkdock` command with `sjust http-proxy-install-update` by adding service restart to Ansible http-proxy tasks (spark-http-proxy handles container cleanup via Docker Compose)
- Added `set -e` to `install.macos` to fail fast on errors
- Fixed Python interpreter not found error by implementing `ensure_python3()` function that checks for missing python3 symlink and automatically relinks Python packages before running Ansible playbook
- Fixed sjust zsh completion file ownership issue where `_sjust` file could be owned by root, causing Ansible task failures
- Fixed Ghostty configuration overrides being ignored by implementing two-file setup (main config + user overrides file) to ensure proper load order per Ghostty's config-file directive documentation
- Fixed eza alias to display group ownership by default using `-g` flag in all ls commands

### Added
- Added Copilot CLI shell aliases for multiple AI models with one-shot mode (co/cos/coh/coc/cog/coo), interactive mode (ico/icos/icoh/icoc/icog/icoo), and session management (cocon/cores)
- Added automatic disabling of gcloud survey prompts during Google Cloud SDK configuration (both in Ansible provisioning and `sjust system-gcloud-reconfigure`)
- Added Chrome web app integration for menubar URL links - URL menu items now open as standalone Chrome windows without browser UI using the `--app` flag

#### Shell Configuration System ([#248](https://github.com/sparkfabrik/sparkdock/pull/248))
- Added Sparkdock shell configuration system with modern CLI tools (eza, bat, ripgrep, fd, zoxide, fzf, starship, thefuck, chafa)
- Added new sjust commands for shell management:
  - `sjust shell-enable` - Enable Sparkdock shell configuration in ~/.zshrc
  - `sjust shell-disable` - Disable and remove Sparkdock shell configuration
  - `sjust shell-info` - Display shell status, features, and all configured aliases
  - `sjust shell-omz-setup` - Install oh-my-zsh with plugins (zsh-completions, zsh-autosuggestions, zsh-syntax-highlighting, ssh-agent)
  - `sjust shell-omz-update-plugins` - Update oh-my-zsh plugins to latest versions
- Added smart aliases with conditional loading (ff, zd/cd with zoxide, ls with sorting, docker, git, kubernetes)
- Added seamless integration with existing oh-my-zsh/starship installations and user customization via `~/.config/spark/shell.zsh`
- See `config/shell/README.md` for complete documentation and architecture details

#### Other Additions

- Added python@3.13 and python@3.14 to base packages to fix broken Python installations for tools like google-cloud-sdk
- Added an experimental Sparkdock AI helper (with `sjust sparkdock-ai` and `sjust sparkdock-configure-llm`) that routes questions via a classifier, verifies Copilot plugins/auth, renders a Gum UI with logo/help, and logs activity as “living documentation”
- Added font-caskaydia-mono-nerd-font (Cascadia Code Nerd Font)
- Added Ghostty config-file directive setup for easier customization (user config loads Sparkdock base via config-file directive)
- Added Context7 MCP server configuration for Just documentation lookup
- Added custom instructions file for Just recipes (`.github/instructions/just.instructions.md`)
- Added Claude Code GitHub workflow for AI-assisted code reviews and issue handling
- Added `ensure-python3` command mode to `sparkdock.macos` for checking and fixing Python3 symlink issues (callable via `sparkdock ensure-python3`)
- Added UDP port forwarding support in Lima (see https://github.com/lima-vm/lima/issues/4040)
- Added `docker-desktop-diagnose` task to run Docker Desktop diagnostics with optional upload functionality
- Added `docker-desktop-install-version-4412` task to download Docker Desktop 4.41.2 to work around network issues
- Added Universal Definition of Done link to menubar company links
- Added Lima version display to `lima-quick-setup` task output

### Changed

- Consolidated Slack notification script git diff functions into single parameterized function with configurable commit count
- Migrated GitHub Copilot CLI from npm package (`@github/copilot`) to Homebrew cask (`copilot-cli`) for improved installation and update management
- Updated system requirements documentation to clarify Apple Silicon-only support (removed Intel Mac references)
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` with improved description and updated output messages
- Lima quick setup now uses dynamic CPU and memory defaults like Docker Desktop: all available processors and 50% of host memory
- Default terminal for menu bar app changed from Terminal.app to Ghostty

### Fixed

- Fixed `lima-destroy` command to handle VMs that are already stopped, preventing fatal error when VM is not running
- Fixed `docker-desktop-install-version-4412` task to automatically remove incompatible docker-mcp plugin that blocks Docker Desktop 4.41.2 from starting
