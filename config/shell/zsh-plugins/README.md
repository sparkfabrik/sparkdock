# Sparkdock ZSH Plugins

This directory contains optional zsh plugins that can be enabled by users.

## Available Plugins

### Built-in Plugins

#### ssh-agent

Manages ssh-agent lifecycle and automatically loads SSH identities.

**Features:**
- Automatically starts ssh-agent if not running
- Loads SSH keys from `~/.ssh/`
- Caches agent environment between sessions
- Supports agent forwarding for screen/tmux

**Enable:**
```bash
sjust shell-plugins-enable ssh-agent
```

### External Plugins

These plugins are downloaded from GitHub and stored in `~/.local/spark/sparkdock/zsh-plugins/`.

#### zsh-autosuggestions

Suggests commands as you type based on history and completions.

**Repository:** https://github.com/zsh-users/zsh-autosuggestions

**Install and enable:**
```bash
sjust shell-plugins-install
sjust shell-plugins-enable zsh-autosuggestions
```

#### zsh-syntax-highlighting

Provides syntax highlighting for commands as you type.

**Repository:** https://github.com/zsh-users/zsh-syntax-highlighting

**Install and enable:**
```bash
sjust shell-plugins-install
sjust shell-plugins-enable zsh-syntax-highlighting
```

**Note:** This plugin should be loaded last, which is handled automatically.

## Management Commands

### Install External Plugins

```bash
sjust shell-plugins-install
```

Downloads zsh-autosuggestions and zsh-syntax-highlighting to `~/.local/spark/sparkdock/zsh-plugins/`.

### Enable a Plugin

```bash
sjust shell-plugins-enable <plugin-name>
```

Available plugin names:
- `ssh-agent`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`

### Disable a Plugin

```bash
sjust shell-plugins-disable <plugin-name>
```

### List Plugins

```bash
sjust shell-plugins-list
```

Shows installation and enabled status for all plugins.

## Plugin Storage

- **System plugins:** `/opt/sparkdock/config/shell/zsh-plugins/`
- **User-installed plugins:** `~/.local/spark/sparkdock/zsh-plugins/`
- **Enabled plugins marker:** `~/.local/spark/sparkdock/plugins-enabled/`

## Configuration

### ssh-agent Configuration

You can configure ssh-agent behavior using zstyle:

```bash
# In ~/.local/spark/sparkdock/shell.zsh

# Set key lifetime (in seconds)
zstyle :omz:plugins:ssh-agent lifetime 4h

# Specify which identities to load
zstyle :omz:plugins:ssh-agent identities id_rsa id_ed25519

# Run in quiet mode
zstyle :omz:plugins:ssh-agent quiet yes

# Enable lazy loading (don't add identities on shell start)
zstyle :omz:plugins:ssh-agent lazy yes

# Enable agent forwarding for screen/tmux
zstyle :omz:plugins:ssh-agent agent-forwarding yes

# Use a helper program for password prompts
zstyle :omz:plugins:ssh-agent helper ksshaskpass
```

### zsh-autosuggestions Configuration

```bash
# In ~/.local/spark/sparkdock/shell.zsh

# Change suggestion color
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# Change suggestion strategy
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
```

### zsh-syntax-highlighting Configuration

```bash
# In ~/.local/spark/sparkdock/shell.zsh

# Customize highlighters
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)

# Customize colors
ZSH_HIGHLIGHT_STYLES[command]='fg=green,bold'
```

## How It Works

1. Plugins are loaded by `config/shell/zsh-plugins/plugins.zsh`
2. Each plugin is only loaded if there's a marker file in `~/.local/spark/sparkdock/plugins-enabled/`
3. External plugins are cloned to `~/.local/spark/sparkdock/zsh-plugins/`
4. The main `sparkdock.zshrc` sources `plugins.zsh` after aliases

## Troubleshooting

### Plugin Not Loading

1. Check if plugin is enabled:
   ```bash
   sjust shell-plugins-list
   ```

2. Verify plugin files exist:
   ```bash
   ls -la ~/.local/spark/sparkdock/zsh-plugins/
   ls -la ~/.local/spark/sparkdock/plugins-enabled/
   ```

3. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

### ssh-agent Issues

If ssh-agent isn't working:

1. Check if `~/.ssh/` directory exists
2. Verify SSH keys are present in `~/.ssh/`
3. Check cache file: `~/.ssh/environment-$SHORT_HOST`
4. Manually test ssh-agent: `ssh-add -l`

## Adding New Plugins

To add a new built-in plugin:

1. Create plugin file in `/opt/sparkdock/config/shell/zsh-plugins/<name>.zsh`
2. Add loading logic to `plugins.zsh`
3. Update enable/disable commands in sjust recipe
4. Update this README

To add a new external plugin:

1. Update `shell-plugins-install` command in sjust recipe
2. Add loading logic to `plugins.zsh`
3. Update valid plugins list in sjust commands
4. Update this README
