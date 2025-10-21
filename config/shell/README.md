# Sparkdock Shell Configuration

This directory contains Sparkdock's modern shell enhancements for zsh with oh-my-zsh and starship integration.

## Quick Start

```bash
sjust shell-omz-setup           # Install oh-my-zsh and plugins
sjust shell-omz-update-plugins  # Update oh-my-zsh plugins
sjust shell-enable              # Enable shell enhancements
sjust shell-info                # Inspect detected configuration and the zshrc snippet Sparkdock adds
```

## Seamless Integration Philosophy

Sparkdock shell configuration is designed to **respect your existing setup**:

- ✅ **Non-intrusive**: Won't override your existing oh-my-zsh configuration
- ✅ **Configurable**: Control starship, fzf, and atuin via environment variables
- ✅ **Plugin-safe**: Won't override your oh-my-zsh plugins array if already configured
- ✅ **Detection-first**: Checks what's already loaded before initializing
- ✅ **Profile-aware**: Only symlinks terminal profiles when no existing file is present

### How It Works

When you source `sparkdock.zshrc`, it intelligently detects your existing configuration:

1. **oh-my-zsh**: Only loads if `$ZSH` is not already set (meaning you haven't loaded it in your `.zshrc`)
2. **starship**: Enabled by default. Disable by setting `SPARKDOCK_ENABLE_STARSHIP=0` or remove the variable
3. **fzf**: Enabled by default. Disable by setting `SPARKDOCK_ENABLE_FZF=0` or remove the variable
4. **atuin**: Disabled by default. Enable by setting `SPARKDOCK_ENABLE_ATUIN=1`
5. **Plugins**: Only sets default plugins if `$plugins` array is empty

### Controlling Optional Features

The default configuration (`sjust shell-enable`) enables starship and fzf by default, while atuin is disabled. You can customize this in your `.zshrc` **before** sourcing sparkdock:

```bash
# Starship prompt (modern, fast, cross-shell prompt) - ENABLED BY DEFAULT
export SPARKDOCK_ENABLE_STARSHIP=1  # Set to 0 to disable

# fzf fuzzy finder (file search, history, etc.) - ENABLED BY DEFAULT
export SPARKDOCK_ENABLE_FZF=1        # Set to 0 to disable

# Atuin history sync (encrypted cloud sync, advanced search) - DISABLED BY DEFAULT
export SPARKDOCK_ENABLE_ATUIN=1      # Set to 1 to enable

source /opt/sparkdock/config/shell/sparkdock.zshrc
```

> `sjust shell-enable` adds the exports above with their default values. Set each `SPARKDOCK_ENABLE_*` before the `source` line (or in `~/.config/spark/shell.zsh`) if you want different behavior.

**Default States Explained:**

- **Starship**: Enabled by default - provides a modern, fast prompt that works well for most users
- **fzf**: Enabled by default - essential for fuzzy file finding and history search
- **Atuin**: Disabled by default - requires account setup, encryption keys, and cloud sync configuration

## Files

- **`sparkdock.zshrc`** - Main entry point (source this from your .zshrc)
- **`omz-init.zsh`** - Oh-my-zsh configuration (only loaded if needed)
- **`aliases.zsh`** - Modern command aliases
- **`init.zsh`** - Tool initializations (zoxide, starship, fzf, atuin)

## Features

**Core Tools (always enabled):** eza, fd, ripgrep, bat, zoxide
**Enabled by Default:** starship, fzf
**Disabled by Default:** atuin
**Oh-My-Zsh Plugins:** zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, ssh-agent

**Inspect your setup:** `sjust shell-info` (shows detected state and the exact block added to `~/.zshrc`)

**Key Bindings:**

- `Ctrl+R` - Fuzzy history search (fzf or atuin)
- `Alt+C` - Change directory with fuzzy finder
- `Ctrl+T` - Insert file path from fuzzy finder
- `ff` - Fuzzy file finder with preview

## Customization

Create `~/.config/spark/shell.zsh` for personal customizations (Sparkdock sources this file after its own defaults, so it’s safe to override aliases and exports here):

```bash
# Control optional features (set before sourcing sparkdock in .zshrc)
export SPARKDOCK_ENABLE_STARSHIP=1  # Enabled by default
export SPARKDOCK_ENABLE_FZF=1       # Enabled by default
export SPARKDOCK_ENABLE_ATUIN=1     # Disabled by default - set to 1 to enable

# Custom aliases
alias myproject='cd ~/projects/myproject'

# Custom functions
function mkcd() { mkdir -p "$1" && cd "$1"; }

# Override defaults if needed
unalias ls  # Use traditional ls

# Configure oh-my-zsh plugins (only if you're using Sparkdock's oh-my-zsh init)
zstyle :omz:plugins:ssh-agent lifetime 4h
```

Sparkdock sources this file after its own defaults, so keep personal aliases, exports, and overrides here.

## Usage Examples

See [EXAMPLES.md](EXAMPLES.md) for comprehensive usage examples.

## Troubleshooting

**Tools not working:** Run `sjust shell-info` to check installation status
**Reload shell:** `source ~/.zshrc` or restart terminal
**Missing packages:** Run `sparkdock` to provision all tools
**Starship not loading:** Check if `SPARKDOCK_ENABLE_STARSHIP=1` is set (enabled by default with shell-enable)
**fzf not loading:** Check if `SPARKDOCK_ENABLE_FZF=1` is set (enabled by default with shell-enable)
**Atuin not loading:** Atuin is disabled by default, set `SPARKDOCK_ENABLE_ATUIN=1` to enable
**oh-my-zsh conflicts:** Sparkdock uses your existing oh-my-zsh configuration by default

## Architecture

**Load Order:**

1. Guard against double-loading (SPARKDOCK_SHELL_LOADED)
2. init.zsh:
   - fpath setup
   - **oh-my-zsh** (calls compinit - must be first!)
   - **fzf** (requires compinit - ENABLED BY DEFAULT via SPARKDOCK_ENABLE_FZF=1)
   - **zoxide** (directory navigation)
   - **starship** (prompt - ENABLED BY DEFAULT via SPARKDOCK_ENABLE_STARSHIP=1)
   - **atuin** (history - DISABLED BY DEFAULT, requires SPARKDOCK_ENABLE_ATUIN=1)
3. aliases.zsh (command aliases)
4. ~/.config/spark/shell.zsh (user customizations)

**Why This Order Matters:**

- **oh-my-zsh first**: Initializes the completion system (compinit)
- **fzf after oh-my-zsh**: Requires completion system to be ready
- **Prompts before history**: Starship sets up prompt before atuin hooks history
- **atuin last**: Uses `--disable-up-arrow` to work with fzf's Ctrl+R

**Conditional Loading Logic:**

- **oh-my-zsh**: Loaded only if `$ZSH` is not set (not already initialized)
- **fzf**: Loaded only if `SPARKDOCK_ENABLE_FZF` is set (enabled by default in shell-enable)
- **starship**: Loaded only if `SPARKDOCK_ENABLE_STARSHIP` is set (enabled by default in shell-enable)
- **atuin**: Loaded only if `SPARKDOCK_ENABLE_ATUIN=1` is set (disabled by default)
- **plugins**: Set only if `$plugins` array is empty (respects user configuration)

**Environment Variables:**

- `SPARKDOCK_SHELL_LOADED=1` - Prevents double-loading
- `SPARKDOCK_ENABLE_STARSHIP=1` - Enable starship prompt (enabled by default)
- `SPARKDOCK_ENABLE_FZF=1` - Enable fzf fuzzy finder (enabled by default)
- `SPARKDOCK_ENABLE_ATUIN=1` - Enable atuin history sync (disabled by default)
- `FZF_*` variables - Configure fzf with fd and bat integration
- `DISABLE_LS_COLORS=true` - Avoid conflicts with eza
