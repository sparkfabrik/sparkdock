# Sparkdock Shell Enhancements - Usage Examples

This document provides practical examples of using Sparkdock's modern shell tools.

## Installation and Setup

### Quick Setup

```bash
# Enable shell enhancements
sjust shell-enable

# Reload your shell
source ~/.zshrc

# Check what's installed
sjust shell-info
```

## Modern ls with eza

### Basic Usage

```bash
# Instead of: ls
# You get colorful output with icons
ls

# Detailed listing
ll

# Show all files including hidden
la

# Tree view (2 levels deep)
lt
```

### Example Output

```
$ ls
 Documents  Downloads  Pictures  Projects  Videos

$ ll
drwxr-xr-x  user  staff  128 B  Mon Oct 13 10:00:00 2025  Documents
drwxr-xr-x  user  staff  256 B  Mon Oct 13 09:30:00 2025  Downloads
drwxr-xr-x  user  staff   96 B  Mon Oct 13 08:00:00 2025  Pictures
drwxr-xr-x  user  staff  512 B  Mon Oct 13 11:00:00 2025  Projects

$ lt
 Projects
├──  sparkdock
│  ├──  config
│  └──  sjust
└──  myapp
   ├──  src
   └──  tests
```

## Smart Directory Navigation with zoxide

### Basic Usage

```bash
# First time: use cd normally
cd ~/projects/sparkfabrik/sparkdock

# Later: just type 'z' with a fragment of the path
z sparkdock
# Or even shorter
z spar

# Jump to a frequently used directory
z proj

# List your directory history
z -l
```

### Example Workflow

```bash
$ cd ~/projects/client-a/backend
$ cd ~/documents/notes
$ cd ~/projects/client-b/frontend

# Now you can jump directly
$ z backend
# Takes you to ~/projects/client-a/backend

$ z frontend
# Takes you to ~/projects/client-b/frontend

$ z notes
# Takes you to ~/documents/notes
```

## Fuzzy File Finding

### Interactive File Search (ff)

```bash
# From any directory, type ff to search for files
ff

# This opens an interactive fuzzy finder with:
# - File list on the left
# - Live preview on the right (with syntax highlighting)
# - Type to filter
# - Enter to open in your editor
```

### Command History Search (Ctrl+R)

```bash
# Press Ctrl+R in your terminal
# Start typing any part of a previous command
# Fuzzy match shows matching commands
# Enter to execute, Ctrl+C to cancel
```

### Find Files with fd

```bash
# Find files by name
fd config

# Find in specific directory
fd config ~/projects

# Find and execute command
fd .jpg | xargs -I {} cp {} ~/Pictures/

# Find only directories
fd --type d test

# Include hidden files
fd --hidden .env
```

## Better File Viewing with bat

### Basic Usage

```bash
# View file with syntax highlighting
cat README.md

# Use original cat if needed
ccat README.md

# View with line numbers
bat -n script.sh

# View multiple files
bat file1.js file2.js

# Pipe output
curl -s https://example.com/api | bat --language json
```

## Fast Text Search with ripgrep

### Basic Usage

```bash
# Search in current directory
grep "function" .

# Search in specific directory
rg "TODO" ~/projects

# Case-insensitive search
rg -i "error"

# Show context (3 lines before and after)
rg -C 3 "import"

# Search only in specific file types
rg "class" --type js
rg "class" --type-add 'web:*.{html,css,js}' --type web

# Exclude directories
rg "secret" --glob '!node_modules'
```

## Combined Workflows

### Find and Edit Files

```bash
# Find a file and edit it
fd config | fzf | xargs $EDITOR

# Or use the ff alias
ff
# (type to filter, Enter to open)
```

### Search and Review Code

```bash
# Find all TODO comments
rg "TODO|FIXME" --color always | less -R

# Find function definitions
rg "^function\s+\w+" --type js

# Search with file preview
rg "useState" --files-with-matches | fzf --preview 'bat --color=always {}'
```

### Directory Navigation Patterns

```bash
# Navigate to project
z myproject

# Check what's there
ll

# Find specific file
fd middleware

# Search file contents
rg "express"

# Open file in editor
ff
```

## Kubernetes Workflows

```bash
# Quick kubectl alias
k get pods

# Get all resources
kga

# View pod logs
kl my-pod-name

# Describe a pod with preview
kgp | fzf --preview 'kubectl describe pod {1}'

# Switch context
kx production
```

## Docker Workflows

```bash
# Docker compose shortcut
dc up -d

# View running containers
dps

# View all containers
dpsa

# Find container and view logs
docker ps | fzf --preview 'docker logs --tail 50 {1}' | awk '{print $1}' | xargs docker logs -f
```

## Git Workflows

```bash
# Quick status
gs

# Fuzzy search through commits
gl | fzf --preview 'git show --color=always {1}'

# Interactive staging
ga -p

# Search git history
git log --oneline | fzf --preview 'git show --color=always {1}'
```

## Customization Examples

### Custom Aliases in ~/.config/spark/shell.zsh

```bash
# Project shortcuts
alias proj='cd ~/projects'
alias work='cd ~/work'

# Git shortcuts
alias gac='git add -A && git commit -m'
alias gp='git pull --rebase'

# Docker shortcuts
alias dclean='docker system prune -af --volumes'

# Custom functions
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

function extract() {
  case "$1" in
    *.tar.gz) tar -xzf "$1" ;;
    *.zip)    unzip "$1" ;;
    *)        echo "Unknown archive format" ;;
  esac
}
```

### Environment Variables

```bash
# In ~/.config/spark/shell.zsh

# Preferred editor
export EDITOR="code"

# Custom paths
export PATH="$HOME/bin:$PATH"

# FZF customization
export FZF_DEFAULT_OPTS="--height 60% --border --color=16"
```

## Tips and Tricks

### Search Command History by Context

```bash
# Press Ctrl+R
# Type: docker ps
# See all docker ps commands you've run
# Arrow keys to select, Enter to run
```

### Quick Project Switcher

```bash
# Create this function in ~/.config/spark/shell.zsh
function proj() {
  local project
  project=$(fd . ~/projects --type d --max-depth 2 | fzf)
  if [[ -n "$project" ]]; then
    cd "$project"
  fi
}

# Usage: just type 'proj' and fuzzy find your project
```

### Find Large Files

```bash
# Find files larger than 100MB
fd . --size +100m

# With human-readable sizes
fd . --size +100m --exec ls -lh {}
```

### Search and Replace

```bash
# Find files containing a pattern
rg "oldFunction" --files-with-matches

# Preview and edit
rg "oldFunction" --files-with-matches | fzf --preview 'bat {}' | xargs $EDITOR
```

## Performance Comparisons

### Speed Examples (typical results)

```bash
# Traditional find vs fd
time find . -name "*.js"     # ~2.5 seconds
time fd ".js$"               # ~0.1 seconds

# Traditional grep vs ripgrep
time grep -r "import" .      # ~5 seconds
time rg "import"             # ~0.3 seconds

# ls vs eza (similar speed, better output)
ls -la                       # Plain output
eza -la                      # Colorful, with icons
```

## Troubleshooting

### Aliases Not Working

```bash
# Check if tools are installed
which eza fd rg bat fzf zoxide

# Check if configuration is loaded
echo $SPARKDOCK_SHELL_LOADED

# Reload configuration
source ~/.zshrc
```

### Zoxide Not Finding Directories

```bash
# Zoxide learns over time
# Visit directories with cd first
cd ~/projects/myproject

# Then use z
z myproject

# View learned directories
zoxide query --list
```

### FZF Preview Not Showing

```bash
# Make sure bat is installed
brew install bat

# Check FZF environment variables
echo $FZF_CTRL_T_OPTS
```

## Further Reading

- Run `man <tool>` for detailed documentation
- `sjust shell-info` for current configuration status
- `/opt/sparkdock/config/shell/README.md` for architecture details
