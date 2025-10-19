#!/usr/bin/env zsh
# Sparkdock ZSH Configuration
# Add this line to your ~/.zshrc to enable Sparkdock shell enhancements:
#   source /opt/sparkdock/config/shell/sparkdock.zshrc

# Guard against multiple sourcing
if [[ -n "${SPARKDOCK_SHELL_LOADED}" ]]; then
  return
fi
export SPARKDOCK_SHELL_LOADED=1

# Determine the directory where this script is located
SPARKDOCK_SHELL_DIR="${0:A:h}"

# Source shell tool initializations
if [[ -f "${SPARKDOCK_SHELL_DIR}/init.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/init.zsh"
fi

# Initialize completion system
autoload -Uz compinit
compinit

# Add local zsh functions directory to fpath
if [[ -d ~/.local/share/zsh/site-functions ]]; then
  fpath+=~/.local/share/zsh/site-functions
fi

# Source shell aliases
if [[ -f "${SPARKDOCK_SHELL_DIR}/aliases.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/aliases.zsh"
fi

# Optional: Source user customizations
if [[ -f "${HOME}/.config/spark/shell.zsh" ]]; then
  source "${HOME}/.config/spark/shell.zsh"
fi
