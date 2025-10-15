# Sparkdock Shell Configuration

This directory contains Sparkdock's modern shell enhancements for zsh.

## Files

- **`sparkdock.zshrc`** - Main entry point that users source in their `~/.zshrc`
- **`aliases.zsh`** - Modern command aliases and shortcuts
- **`init.zsh`** - Initialization scripts for shell tools (zoxide, fzf, etc.)
- **`zsh-plugins/`** - Optional zsh plugins (ssh-agent, autosuggestions, syntax-highlighting)

## Quick Start

### Enable Shell Enhancements

The easiest way to enable shell enhancements:

```bash
sjust shell-enable
```

Or manually add to your `~/.zshrc`:

```bash
source /opt/sparkdock/config/shell/sparkdock.zshrc
```

Then reload your shell:

```bash
source ~/.zshrc
```

### Check Status

```bash
sjust shell-info
```

### Disable Shell Enhancements

```bash
sjust shell-disable
```

### Optional Plugins

Sparkdock provides optional zsh plugins that can be enabled:

```bash
# Install external plugins
sjust shell-plugins-install

# Enable plugins
sjust shell-plugins-enable ssh-agent
sjust shell-plugins-enable zsh-autosuggestions
sjust shell-plugins-enable zsh-syntax-highlighting

# List plugins
sjust shell-plugins-list
```

Available plugins:
- **ssh-agent** - Manages SSH keys and agent lifecycle
- **zsh-autosuggestions** - Command suggestions as you type
- **zsh-syntax-highlighting** - Syntax highlighting for commands

See [`zsh-plugins/README.md`](zsh-plugins/README.md) for detailed plugin documentation.

## Features

### Modern Command Replacements

When enabled, the following modern tools are aliased to replace traditional commands:

| Traditional | Modern | Description |
|------------|--------|-------------|
| `ls` | `eza` | Colorful file listings with icons |
| `cat` | `bat` | Syntax highlighting for file contents |
| `grep` | `ripgrep` (rg) | Faster, smarter text search |
| `find` | `fd` | Simpler, faster file finding |
| `cd` | `zoxide` (z) | Smart directory jumping |

### Enhanced Aliases

Common shortcuts provided:

```bash
# File listing
ls, ll, la     # eza with various options
lt, lta        # tree view (2 levels deep)

# File operations
cat            # bat with syntax highlighting
ccat           # original cat (if you need it)

# Docker
dc             # docker-compose
dps, dpsa      # docker ps variants
di             # docker images

# Git
gs, gp, gpush  # git status, pull, push
gc, gco, ga    # git commit, checkout, add
gd, gl         # git diff, log

# Kubernetes
k              # kubectl
kgp, kgs, kgd  # kubectl get pods/services/deployments
```

### Custom Functions

- **`ff`** - Fuzzy file finder with preview
  - Uses fd + fzf + bat to search and open files
  - Press Enter to edit in your default editor

### Key Bindings

- **`Ctrl+R`** - Fuzzy search through command history (fzf)
- **`Alt+C`** - Change directory using fuzzy finder (fzf)
- **`Ctrl+T`** - Insert file path from fuzzy finder (fzf)

## Tool Documentation

Each tool has comprehensive manual pages:

```bash
man eza        # Modern ls
man fd         # Modern find
man rg         # ripgrep
man bat        # Modern cat
man fzf        # Fuzzy finder
man zoxide     # Smart cd
```

## Customization

### User Custom Configuration

Create `~/.local/spark/sparkdock/shell.zsh` for your personal customizations:

```bash
mkdir -p ~/.local/spark/sparkdock
cat > ~/.local/spark/sparkdock/shell.zsh << 'EOF'
# My custom aliases
alias myproject='cd ~/projects/myproject'

# My custom functions
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Custom environment variables
export MY_CUSTOM_VAR="value"
EOF
```

This file is automatically sourced if it exists.

### Overriding Default Aliases

If you prefer the traditional commands, you can override the aliases in your custom config:

```bash
# In ~/.local/spark/sparkdock/shell.zsh
unalias ls
unalias cat
unalias grep

# Or create your own variants
alias ls='eza --no-icons'
alias cat='bat --plain'
```

## Examples

### Using Zoxide

```bash
# Navigate to a directory once
cd ~/projects/sparkdock

# Later, jump there from anywhere
z sparkdock
# or even shorter
z spar

# View your directory history
z -l
```

### Using Fuzzy Finder

```bash
# Search command history
Ctrl+R

# Find and open a file
ff

# Find files with specific pattern
fd pattern

# Search file contents
rg "search term"
```

### Using Modern ls (eza)

```bash
# Basic listing with icons
ls

# Detailed listing
ll

# Show hidden files
la

# Tree view (2 levels)
lt

# Tree with hidden files
lta
```

## Troubleshooting

### Tools Not Working

Check if tools are installed:

```bash
sjust shell-info
```

If any tools are missing, run:

```bash
sparkdock  # Full provisioning
# or
sjust sparkdock-install-tags "brew_packages"  # Just update packages
```

### Aliases Not Active

Make sure you've sourced your `.zshrc`:

```bash
source ~/.zshrc
```

Or restart your terminal.

### Conflicts with Other Tools

If you have conflicts with other shell frameworks (oh-my-zsh, prezto, etc.),
you may need to adjust the load order in your `~/.zshrc`.

Load Sparkdock configuration **after** your shell framework:

```bash
# Load oh-my-zsh or other framework first
source ~/.oh-my-zsh/oh-my-zsh.sh

# Then load Sparkdock (which can override if desired)
source /opt/sparkdock/config/shell/sparkdock.zshrc
```

## Architecture

### Load Order

1. Guard check prevents double-loading
2. `init.zsh` - Initialize shell tools (zoxide, fzf)
3. `aliases.zsh` - Set up command aliases
4. `~/.local/spark/sparkdock/shell.zsh` - User customizations (if exists)

### Environment Variables

The configuration sets these environment variables:

- `SPARKDOCK_SHELL_LOADED=1` - Prevents double-loading
- `FZF_DEFAULT_COMMAND` - Uses fd for file search
- `FZF_CTRL_T_COMMAND` - Uses fd for Ctrl+T
- `FZF_ALT_C_COMMAND` - Uses fd for Alt+C
- `FZF_CTRL_T_OPTS` - Uses bat for preview

## Contributing

To modify the shell configuration:

1. Edit files in `/opt/sparkdock/config/shell/`
2. Test changes by sourcing: `source /opt/sparkdock/config/shell/sparkdock.zshrc`
3. Submit a pull request

## References

- [eza](https://eza.rocks/) - Modern ls replacement
- [fd](https://github.com/sharkdp/fd) - Modern find replacement
- [ripgrep](https://github.com/BurntSushi/ripgrep) - Modern grep replacement
- [bat](https://github.com/sharkdp/bat) - Modern cat replacement
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder
- [zoxide](https://github.com/ajeetdsouza/zoxide) - Smarter cd
