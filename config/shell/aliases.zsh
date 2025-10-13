#!/usr/bin/env zsh
# Sparkdock Shell Aliases
# This file contains modern command aliases and shortcuts for enhanced shell experience

# Modern replacements for classic commands
# eza - modern replacement for ls with colors and icons
alias ls='eza --color=auto --icons'
alias ll='eza -l --color=auto --icons'
alias la='eza -la --color=auto --icons'
alias lt='eza --tree --level=2 --color=auto --icons'
alias lta='eza --tree --level=2 -a --color=auto --icons'
alias lsa='eza -la --color=auto --icons'

# fd - modern replacement for find
alias ff='fd'

# ripgrep - modern replacement for grep
alias grep='rg'

# bat - modern replacement for cat with syntax highlighting
if command -v bat &> /dev/null; then
  alias cat='bat --style=auto'
  alias ccat='/bin/cat'  # Keep original cat available
fi

# Docker shortcuts
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'

# Git shortcuts
alias gs='git status'
alias gp='git pull'
alias gpush='git push'
alias gc='git commit'
alias gco='git checkout'
alias ga='git add'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'

# Kubernetes shortcuts
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kga='kubectl get all'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdd='kubectl describe deployment'
alias kl='kubectl logs'
alias kx='kubectx'
alias kn='kubens'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# System shortcuts
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'
alias h='history'
alias c='clear'
