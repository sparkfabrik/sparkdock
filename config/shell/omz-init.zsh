#!/usr/bin/env zsh
# Sparkdock Oh-My-Zsh Configuration
# This file configures oh-my-zsh with Sparkdock defaults
# Only sourced if oh-my-zsh is not already initialized by user's .zshrc

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

# Only set plugins if they haven't been configured by the user already
# This respects user's existing plugin configuration
if [[ -z "$plugins" ]]; then
  plugins=(zsh-syntax-highlighting zsh-autosuggestions ssh-agent)
fi

# Source oh-my-zsh
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

