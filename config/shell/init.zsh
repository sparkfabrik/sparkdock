#!/usr/bin/env zsh
# Sparkdock Shell Initialization
# This file initializes modern shell tools and their integrations

# Initialize zoxide (smarter cd command)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# Initialize fzf (fuzzy finder) key bindings and completion
if command -v fzf &> /dev/null; then
  # Homebrew prefix on macOS
  HOMEBREW_PREFIX="/opt/homebrew"

  # Source fzf key bindings
  if [[ -f "${HOMEBREW_PREFIX}/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "${HOMEBREW_PREFIX}/opt/fzf/shell/key-bindings.zsh"
  fi

  # Source fzf completion
  if [[ -f "${HOMEBREW_PREFIX}/opt/fzf/shell/completion.zsh" ]]; then
    source "${HOMEBREW_PREFIX}/opt/fzf/shell/completion.zsh"
  fi

  # Configure fzf to use fd for file and directory search if available
  if command -v fd &> /dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi

  # Configure fzf preview with bat if available
  if command -v bat &> /dev/null; then
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
  fi
fi

# Initialize thefuck (command correction)
if command -v thefuck &> /dev/null; then
  eval "$(thefuck --alias)"
fi

# Initialize atuin (shell history search) if available
if command -v atuin &> /dev/null; then
  eval "$(atuin init zsh)"
fi
