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

# Source shell aliases
if [[ -f "${SPARKDOCK_SHELL_DIR}/aliases.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/aliases.zsh"
fi

# Load optional plugins
if [[ -f "${SPARKDOCK_SHELL_DIR}/zsh-plugins/plugins.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/zsh-plugins/plugins.zsh"
fi

# Add custom functions
# ff - Fuzzy find files with fzf and preview
if command -v fzf &> /dev/null && command -v fd &> /dev/null; then
  ff() {
    local file
    file=$(fd --type f --hidden --follow --exclude .git | fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}' --preview-window=right:60%:wrap)
    if [[ -n "$file" ]]; then
      ${EDITOR:-vim} "$file"
    fi
  }
fi

# Optional: Source user customizations
if [[ -f "${HOME}/.local/spark/sparkdock/shell.zsh" ]]; then
  source "${HOME}/.local/spark/sparkdock/shell.zsh"
fi
