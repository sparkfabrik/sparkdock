# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Fixed Python interpreter not found error by implementing `ensure_python3()` function that checks for missing python3 symlink and automatically relinks Python packages before running Ansible playbook
- Fixed sjust zsh completion file ownership issue where `_sjust` file could be owned by root, causing Ansible task failures

### Added

#### Shell Configuration System
- Added comprehensive Sparkdock shell configuration system with modern CLI tools:
  - **Modern Unix replacements**: eza (ls), bat (cat), ripgrep (grep), fd (find), zoxide (cd), fzf (fuzzy finder), starship (prompt), thefuck (command corrector)
  - **chafa**: Terminal graphics/image viewer
  - **Ghostty terminal**: Added as preferred terminal emulator
- Added oh-my-zsh integration with automatic setup via `sjust shell-omz-setup`:
  - Installs oh-my-zsh if not present (with `KEEP_ZSHRC=yes` to preserve existing configuration)
  - Downloads and symlinks zsh plugins: zsh-completions, zsh-autosuggestions, zsh-syntax-highlighting
  - Auto-enables ssh-agent plugin for SSH key management
  - `sjust shell-omz-update-plugins` to update plugins
- Added shell management commands:
  - `sjust shell-enable` - Add Sparkdock config to ~/.zshrc (with optional force mode)
  - `sjust shell-disable` - Remove Sparkdock config from ~/.zshrc with backup
  - `sjust shell-info` - Display comprehensive shell status, features, and aliases
  - `sjust shell-omz-setup` - Install oh-my-zsh and plugins
  - `sjust shell-omz-update-plugins` - Update oh-my-zsh plugins
- Added smart shell aliases with command existence checks:
  - `ff` - fzf with bat preview
  - `zd` (aliased to `cd`) - Smart directory navigation with zoxide fallback
  - Smart `ls` function with `-lt`/`-ltr` flag handling for sorting by modification time
  - Docker, Git, Kubernetes aliases (only if tools exist)
  - `reload` - Reload shell by unsetting `SPARKDOCK_SHELL_LOADED`
- Added seamless integration with conditional loading:
  - Detects existing oh-my-zsh and starship installations
  - Respects user's existing configurations
  - Double-load protection via `SPARKDOCK_SHELL_LOADED` variable
  - Optional features via environment variables:
    - `SPARKDOCK_ENABLE_STARSHIP=1` (enabled by default in shell-enable)
    - `SPARKDOCK_ENABLE_FZF=1` (enabled by default in shell-enable)
    - `SPARKDOCK_ENABLE_ATUIN=1` (disabled by default)
- Added user customization support via `~/.config/spark/shell.zsh`
- Added local zsh functions directory support (`~/.local/share/zsh/site-functions`)
- Added shell configuration documentation and examples in `config/shell/` directory

#### Other Additions
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
- User configuration directory changed from `~/.sparkdock` to `~/.config/spark` (XDG Base Directory compliant)
- Shell configuration now uses proper load order: oh-my-zsh → starship → atuin
- Simplified Homebrew prefix logic to use `/opt/homebrew` consistently on macOS
- Default terminal changed from Terminal.app to Ghostty

### Fixed
- Fixed `lima-destroy` command to handle VMs that are already stopped, preventing fatal error when VM is not running
- Fixed `docker-desktop-install-version-4412` task to automatically remove incompatible docker-mcp plugin that blocks Docker Desktop 4.41.2 from starting
