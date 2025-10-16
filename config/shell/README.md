# Sparkdock Shell Configuration

This directory contains Sparkdock's modern shell enhancements for zsh with oh-my-zsh and starship integration.

## Quick Start

```bash
sjust shell-setup-omz    # Install oh-my-zsh and plugins
sjust shell-enable       # Enable shell enhancements
sjust shell-info         # View status
```

## Files

- **`sparkdock.zshrc`** - Main entry point
- **`omz-config.zsh`** - Oh-my-zsh configuration
- **`aliases.zsh`** - Modern command aliases
- **`init.zsh`** - Tool initializations (zoxide, fzf, etc.)
- **`zsh-plugins/`** - Plugin documentation

## Features

**Modern Tools:** eza, fd, ripgrep, bat, fzf, zoxide, starship
**Oh-My-Zsh Plugins:** zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, ssh-agent

**View all aliases:** `sjust shell-aliases-help`

**Key Bindings:**
- `Ctrl+R` - Fuzzy history search
- `Alt+C` - Change directory with fuzzy finder
- `Ctrl+T` - Insert file path from fuzzy finder
- `ff` - Fuzzy file finder with preview

## Customization

Create `~/.config/spark/shell.zsh` for personal customizations:

```bash
# Custom aliases
alias myproject='cd ~/projects/myproject'

# Custom functions
function mkcd() { mkdir -p "$1" && cd "$1"; }

# Override defaults if needed
unalias ls  # Use traditional ls

# Configure oh-my-zsh plugins
zstyle :omz:plugins:ssh-agent lifetime 4h
```

This file is automatically sourced by sparkdock.zshrc.

## Usage Examples

See [EXAMPLES.md](EXAMPLES.md) for comprehensive usage examples.

## Troubleshooting

**Tools not working:** Run `sjust shell-info` to check installation status
**Reload shell:** `source ~/.zshrc` or restart terminal
**Missing packages:** Run `sparkdock` to provision all tools

## Architecture

**Load Order:**
1. omz-config.zsh (oh-my-zsh with plugins)
2. init.zsh (initialize tools)
3. aliases.zsh (command aliases)
4. Custom functions (ff)
5. Starship prompt
6. Atuin history
7. ~/.config/spark/shell.zsh (user customizations)

**Environment Variables:**
- `SPARKDOCK_SHELL_LOADED=1` - Prevents double-loading
- `FZF_*` variables - Configure fzf with fd and bat integration
- `DISABLE_LS_COLORS=true` - Avoid conflicts with eza
