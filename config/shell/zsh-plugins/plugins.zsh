#!/usr/bin/env zsh
# Sparkdock ZSH Plugins Loader
# This file manages loading of optional zsh plugins

# Plugin directory in user's home
SPARKDOCK_USER_PLUGINS_DIR="${HOME}/.local/spark/sparkdock/zsh-plugins"

# Load ssh-agent plugin if enabled
if [[ -f "${HOME}/.local/spark/sparkdock/plugins-enabled/ssh-agent" ]]; then
  SPARKDOCK_PLUGIN_DIR="${0:A:h}"
  if [[ -f "${SPARKDOCK_PLUGIN_DIR}/ssh-agent.zsh" ]]; then
    source "${SPARKDOCK_PLUGIN_DIR}/ssh-agent.zsh"
  fi
fi

# Load zsh-autosuggestions if installed and enabled
if [[ -f "${HOME}/.local/spark/sparkdock/plugins-enabled/zsh-autosuggestions" ]]; then
  if [[ -f "${SPARKDOCK_USER_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "${SPARKDOCK_USER_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh"
  fi
fi

# Load zsh-syntax-highlighting if installed and enabled (must be loaded last)
if [[ -f "${HOME}/.local/spark/sparkdock/plugins-enabled/zsh-syntax-highlighting" ]]; then
  if [[ -f "${SPARKDOCK_USER_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "${SPARKDOCK_USER_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  fi
fi
