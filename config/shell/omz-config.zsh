#!/usr/bin/env zsh
# Sparkdock Oh-My-Zsh Configuration
# This file configures oh-my-zsh with Sparkdock defaults
# Source this before initializing starship

# Configure oh-my-zsh paths
export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="$ZSH/custom"

# Disable LS colors to avoid conflict with eza
export DISABLE_LS_COLORS="true"

# Configure zsh-autosuggestions
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
export ZSH_AUTOSUGGEST_USE_ASYNC=1

# Configure completion styles
zstyle ':completion:*:*:make:*' tag-order 'targets'

# Enable plugins
plugins=(zsh-syntax-highlighting zsh-autosuggestions ssh-agent)

# Source oh-my-zsh
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# Initialize completion system
autoload -Uz compinit
compinit

# Add local zsh functions directory to fpath
if [[ -d ~/.local/share/zsh/site-functions ]]; then
  fpath+=~/.local/share/zsh/site-functions
fi
