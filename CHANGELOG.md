# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Fixed sjust zsh completion file ownership issue where `_sjust` file could be owned by root, causing Ansible task failures

### Added
- Added modern shell command replacements: ripgrep, zoxide, fd, and bat
- Added Sparkdock shell configuration system with optional sourcing for users
- Added shell configuration files: sparkdock.zshrc, aliases.zsh, and init.zsh
- Added shell management commands: `sjust shell-enable`, `sjust shell-disable`, `sjust shell-info`, and `sjust shell-aliases-help`
- Added oh-my-zsh integration with starship prompt support
- Added zsh plugins via oh-my-zsh: zsh-completions, zsh-autosuggestions, zsh-syntax-highlighting, and ssh-agent (built-in)
- Added plugin setup command: `sjust shell-setup-omz`
- Added starship prompt package to homebrew packages
- Removed custom ssh-agent plugin (using oh-my-zsh built-in instead)
- Added modern command aliases: eza (ls), bat (cat), ripgrep (grep), fd (find), zoxide (cd)
- Added fuzzy file finder function (ff) with preview using fzf, fd, and bat
- Added documentation for shell enhancements in README with setup instructions
- Added maintenance guidelines for shell aliases in copilot-instructions.md
- Added UDP port forwarding support in Lima (see https://github.com/lima-vm/lima/issues/4040)
- Added `docker-desktop-diagnose` task to run Docker Desktop diagnostics with optional upload functionality
- Added `docker-desktop-install-version-4412` task to download Docker Desktop 4.41.2 to work around network issues
- Added Universal Definition of Done link to menubar company links
- Added Lima version display to `lima-quick-setup` task output

### Changed
- Renamed `sparkdock-update-repository` command to `sparkdock-fetch-updates` with improved description and updated output messages
- Lima quick setup now uses dynamic CPU and memory defaults like Docker Desktop: all available processors and 50% of host memory
- Shell aliases now check for command existence before aliasing to avoid breaking standard Unix tools
- Improved `ls` implementation with smart handling of `-lt` and `-ltr` flags for sorting by modification time
- Simplified Homebrew prefix logic to use `/opt/homebrew` consistently on macOS
- User configuration directory changed from `~/.sparkdock` to `~/.local/spark/sparkdock`

### Fixed
- Fixed `lima-destroy` command to handle VMs that are already stopped, preventing fatal error when VM is not running
- Fixed `docker-desktop-install-version-4412` task to automatically remove incompatible docker-mcp plugin that blocks Docker Desktop 4.41.2 from starting
