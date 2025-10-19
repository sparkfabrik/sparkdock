#!/usr/bin/env zsh
# Sparkdock Shell Aliases
# This file contains modern command aliases and shortcuts for enhanced shell experience

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Initialize thefuck (command correction)
if command_exists thefuck; then
  eval "$(thefuck --alias)"
fi

# check if fzf is installed for fuzzy finding.
if command_exists fzf; then
  alias f='fzf'
  alias fs='fzf --preview "bat --style=numbers --color=always {}"'
fi

# Replace cd with zd if zoxide is installed for smarter directory navigation.
if command_exists zd; then
  alias cd='zd'
  # keep original cd available as ccd
  alias ccd='zd'
fi

# Modern replacements for classic commands
# eza - modern replacement for ls with colors and icons
if command_exists eza; then
  # bug on macos: https://github.com/eza-community/eza/issues/1224
  export EZA_CONFIG_DIR="${HOME}/.config/eza"
  ls() {
    local filtered_args=("${@[@]//-ltr/}")
    filtered_args=("${filtered_args[@]//-lt/}")

    case "$*" in
      *ltr*)
        eza -la --icons=auto --sort=modified "${filtered_args[@]}"
        ;;
      *lt*)
        eza -la --icons=auto --sort=modified --reverse "${filtered_args[@]}"
        ;;
      *)
        eza -lh --group-directories-first --icons=auto "$@"
        ;;
    esac
  }
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

# ripgrep - modern replacement for grep
if command_exists rg; then
  alias grep='rg'
  alias ggrep='grep'
fi

# bat - modern replacement for cat with syntax highlighting
if command_exists bat; then
  alias cat='bat --style=auto'
  alias ccat='/bin/cat'  # Keep original cat available
fi

# Docker shortcuts
if command_exists docker; then
  alias dc='docker-compose'
  alias dps='docker ps'
  alias dpsa='docker ps -a'
  alias di='docker images'
fi

# Git shortcuts
if command_exists git; then
  alias gs='git status'
  alias gp='git pull'
  alias gpush='git push'
  alias gc='git commit'
  alias gco='git checkout'
  alias ga='git add'
  alias gd='git diff'
  alias gl='git log --oneline --graph --decorate'
fi

# Kubernetes shortcuts
if command_exists kubectl; then
  alias k='kubectl'
  alias kgp='kubectl get pods'
  alias kgs='kubectl get services'
  alias kgd='kubectl get deployments'
  alias kga='kubectl get all'
  alias kdp='kubectl describe pod'
  alias kds='kubectl describe service'
  alias kdd='kubectl describe deployment'
  alias kl='kubectl logs'
fi

if command_exists kubectx; then
  alias kx='kubectx'
fi

if command_exists kubens; then
  alias kn='kubens'
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# System shortcuts
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'
alias h='history'
alias c='clear'
