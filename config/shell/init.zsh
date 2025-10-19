#!/usr/bin/env zsh
# Sparkdock Shell Initialization
# This file initializes modern shell tools and their integrations

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Add local zsh functions directory to fpath.
if [[ -d ~/.local/share/zsh/site-functions ]]; then
  fpath+=~/.local/share/zsh/site-functions
fi

# Load oh-my-zsh configuration FIRST (it calls compinit)
# Only load if:
# 1. oh-my-zsh is installed
# 2. oh-my-zsh has NOT been loaded already by user's .zshrc
# This allows users to keep their existing oh-my-zsh configuration
if [[ -d "$HOME/.oh-my-zsh" ]] && [[ -z "$ZSH" ]] && [[ -f "${SPARKDOCK_SHELL_DIR}/omz-init.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/omz-init.zsh"
fi

# Initialize fzf AFTER oh-my-zsh (which calls compinit)
# Skip if atuin is enabled to avoid conflicts with history search
if command_exists fzf && [[ -z "$SPARKDOCK_ENABLE_ATUIN" ]]; then
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

  # Configure fzf to use fd for file and directory search
  if command_exists fd; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi

  # Configure fzf preview with bat
  if command_exists bat; then
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
  fi
fi

# Initialize zoxide (smarter cd command)
if command_exists zoxide; then
  eval "$(zoxide init zsh)"
fi

# Starship prompt (opt-in via SPARKDOCK_ENABLE_STARSHIP)
if [[ -n "$SPARKDOCK_ENABLE_STARSHIP" ]] && command_exists starship; then
  eval "$(starship init zsh)"
fi

# Atuin history sync (opt-in via SPARKDOCK_ENABLE_ATUIN)
if [[ -n "$SPARKDOCK_ENABLE_ATUIN" ]] && command_exists atuin; then
  eval "$(atuin init zsh --disable-up-arrow)"
fi