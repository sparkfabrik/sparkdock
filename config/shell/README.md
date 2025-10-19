# Sparkdock Shell Configuration

This directory contains Sparkdock's modern shell enhancements for zsh with oh-my-zsh and starship integration.

## Quick Start

```bash
sjust shell-setup-omz    # Install oh-my-zsh and plugins
sjust shell-enable       # Enable shell enhancements
sjust shell-info         # View status, features, and aliases
```

## Seamless Integration Philosophy

Sparkdock shell configuration is designed to **respect your existing setup**:

- ✅ **Non-intrusive**: Won't override your existing oh-my-zsh configuration
- ✅ **Prompt-agnostic**: Starship and atuin are opt-in, disabled by default
- ✅ **Plugin-safe**: Won't override your oh-my-zsh plugins array if already configured
- ✅ **Detection-first**: Checks what's already loaded before initializing

### How It Works

When you source `sparkdock.zshrc`, it intelligently detects your existing configuration:

1. **oh-my-zsh**: Only loads if `$ZSH` is not already set (meaning you haven't loaded it in your `.zshrc`)
2. **starship**: Disabled by default. Enable by setting `SPARKDOCK_ENABLE_STARSHIP=1` before sourcing sparkdock
3. **atuin**: Disabled by default. Enable by setting `SPARKDOCK_ENABLE_ATUIN=1` before sourcing sparkdock
4. **Plugins**: Only sets default plugins if `$plugins` array is empty

### Enabling Optional Features

Advanced tools like starship and atuin are opt-in. Add these to your `.zshrc` **before** sourcing sparkdock:

```bash
# Enable starship prompt (modern, fast, cross-shell prompt)
export SPARKDOCK_ENABLE_STARSHIP=1

# Enable atuin history sync (encrypted cloud sync, advanced search, statistics)
export SPARKDOCK_ENABLE_ATUIN=1

source /opt/sparkdock/config/shell/sparkdock.zshrc
```

**Why Opt-In?**

- **Starship**: You may prefer your existing prompt (powerlevel10k, pure, default zsh, etc.)
- **Atuin**: Requires account setup, encryption keys, and cloud sync configuration - more complex than basic fzf history search

## Files

- **`sparkdock.zshrc`** - Main entry point (source this from your .zshrc)
- **`omz-init.zsh`** - Oh-my-zsh configuration (only loaded if needed)
- **`aliases.zsh`** - Modern command aliases
- **`init.zsh`** - Tool initializations (zoxide, fzf, starship, atuin)

## Features

**Core Tools (auto-enabled):** eza, fd, ripgrep, bat, fzf, zoxide
**Optional Tools (opt-in):** starship, atuin
**Oh-My-Zsh Plugins:** zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, ssh-agent

**View all information:** `sjust shell-info`

**Key Bindings:**

- `Ctrl+R` - Fuzzy history search (fzf or atuin)
- `Alt+C` - Change directory with fuzzy finder
- `Ctrl+T` - Insert file path from fuzzy finder
- `ff` - Fuzzy file finder with preview

## Customization

Create `~/.config/spark/shell.zsh` for personal customizations:

```bash
# Enable optional features (set before sourcing sparkdock in .zshrc)
export SPARKDOCK_ENABLE_STARSHIP=1
export SPARKDOCK_ENABLE_ATUIN=1

# Custom aliases
alias myproject='cd ~/projects/myproject'

# Custom functions
function mkcd() { mkdir -p "$1" && cd "$1"; }

# Override defaults if needed
unalias ls  # Use traditional ls

# Configure oh-my-zsh plugins (only if you're using Sparkdock's oh-my-zsh init)
zstyle :omz:plugins:ssh-agent lifetime 4h
```

This file is automatically sourced by sparkdock.zshrc.

## Usage Examples

See [EXAMPLES.md](EXAMPLES.md) for comprehensive usage examples.

## Troubleshooting

**Tools not working:** Run `sjust shell-info` to check installation status
**Reload shell:** `source ~/.zshrc` or restart terminal
**Missing packages:** Run `sparkdock` to provision all tools
**Starship not loading:** Starship is disabled by default, set `SPARKDOCK_ENABLE_STARSHIP=1` to enable
**Atuin not loading:** Atuin is disabled by default, set `SPARKDOCK_ENABLE_ATUIN=1` to enable
**oh-my-zsh conflicts:** Sparkdock uses your existing oh-my-zsh configuration by default

## Architecture

**Load Order:**

1. Guard against double-loading (SPARKDOCK_SHELL_LOADED)
2. init.zsh:
   - fpath setup
   - **oh-my-zsh** (calls compinit - must be first!)
   - **fzf** (requires compinit to be initialized)
   - **zoxide** (directory navigation)
   - **starship** (prompt - OPTIONAL, requires SPARKDOCK_ENABLE_STARSHIP=1)
   - **atuin** (history - OPTIONAL, requires SPARKDOCK_ENABLE_ATUIN=1)
3. aliases.zsh (command aliases)
4. ~/.config/spark/shell.zsh (user customizations)

**Why This Order Matters:**

- **oh-my-zsh first**: Initializes the completion system (compinit)
- **fzf after oh-my-zsh**: Requires completion system to be ready
- **Prompts before history**: Starship sets up prompt before atuin hooks history
- **atuin last**: Uses `--disable-up-arrow` to work with fzf's Ctrl+R

**Conditional Loading Logic:**

- **oh-my-zsh**: Loaded only if `$ZSH` is not set (not already initialized)
- **starship**: Loaded only if `SPARKDOCK_ENABLE_STARSHIP=1` is set
- **atuin**: Loaded only if `SPARKDOCK_ENABLE_ATUIN=1` is set
- **plugins**: Set only if `$plugins` array is empty (respects user configuration)

**Environment Variables:**

- `SPARKDOCK_SHELL_LOADED=1` - Prevents double-loading
- `SPARKDOCK_ENABLE_STARSHIP=1` - Enable starship prompt (opt-in)
- `SPARKDOCK_ENABLE_ATUIN=1` - Enable atuin history sync (opt-in)
- `FZF_*` variables - Configure fzf with fd and bat integration
- `DISABLE_LS_COLORS=true` - Avoid conflicts with eza
