# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added NPM supply-chain attack detector tool (`bin/security/npm-supply-chain-detector`) with support for multiple attack campaigns (Shai-Hulud 2.0, September 2025 qix- account hijacking)
- Added sjust security commands: `sjust security-scan-npm`, `sjust security-scan-npm-attack`, `sjust security-list-attacks`

### Fixed
- Added `set -e` to `install.macos` to fail fast on errors
- Fixed Python interpreter not found error by implementing `ensure_python3()` function that checks for missing python3 symlink and automatically relinks Python packages before running Ansible playbook
- Fixed sjust zsh completion file ownership issue where `_sjust` file could be owned by root, causing Ansible task failures
- Fixed Ghostty configuration overrides being ignored by implementing two-file setup (main config + user overrides file) to ensure proper load order per Ghostty's config-file directive documentation
- Fixed eza alias to display group ownership by default using `-g` flag in all ls commands

### Added

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

- Added an experimental Sparkdock AI helper (with `sjust sparkdock-ai` and `sjust sparkdock-configure-llm`) that routes questions via a classifier, verifies Copilot plugins/auth, renders a Gum UI with logo/help, and logs activity as “living documentation”
- Added font-caskaydia-mono-nerd-font (Cascadia Code Nerd Font)
- Added Ghostty config-file directive setup for easier customization (user config loads Sparkdock base via config-file directive)
- Added Context7 MCP server configuration for Just documentation lookup
- Added custom instructions file for Just recipes (`.github/instructions/just.instructions.md`)
- Added Claude Code GitHub workflow for AI-assisted code reviews and issue handling
- Added `ensure-python3` command mode to `sparkdock.macos` for checking and fixing Python3 symlink issues (callable via `sparkdock ensure-python3`)
- Added GitHub Copilot CLI (`@github/copilot`) as a default npm package installation
- Added UDP port forwarding support in Lima (see https://github.com/lima-vm/lima/issues/4040)
- Added `docker-desktop-diagnose` task to run Docker Desktop diagnostics with optional upload functionality
- Added `docker-desktop-install-version-4412` task to download Docker Desktop 4.41.2 to work around network issues
- Added Universal Definition of Done link to menubar company links
- Added Lima version display to `lima-quick-setup` task output

### Changed

- Updated system requirements documentation to clarify Apple Silicon-only support (removed Intel Mac references)
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` with improved description and updated output messages
- Lima quick setup now uses dynamic CPU and memory defaults like Docker Desktop: all available processors and 50% of host memory
- Default terminal for menu bar app changed from Terminal.app to Ghostty

### Fixed

- Fixed `lima-destroy` command to handle VMs that are already stopped, preventing fatal error when VM is not running
- Fixed `docker-desktop-install-version-4412` task to automatically remove incompatible docker-mcp plugin that blocks Docker Desktop 4.41.2 from starting
