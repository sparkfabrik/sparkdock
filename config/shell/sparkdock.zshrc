#!/usr/bin/env zsh
# Sparkdock ZSH Configuration
# Add this line to your ~/.zshrc to enable Sparkdock shell enhancements:
#   source /opt/sparkdock/config/shell/sparkdock.zshrc

# Determine the directory where this script is located (works when sourced)
if [[ -n "${(%):-%N}" && "${(%):-%N}" != "zsh" ]]; then
  SPARKDOCK_SHELL_SOURCE="${(%):-%N}"
else
  SPARKDOCK_SHELL_SOURCE="${0}"
fi
SPARKDOCK_SHELL_DIR="${SPARKDOCK_SHELL_SOURCE:A:h}"

# Save fpath before init.zsh (which may add new entries like ~/.local/share/zsh/site-functions)
local _sparkdock_fpath_before="${fpath[*]}"

# Source shell tool initializations
if [[ -f "${SPARKDOCK_SHELL_DIR}/init.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/init.zsh"
fi

# Initialize completion system
# If init.zsh extended fpath (e.g. added site-functions), we must run compinit
# so completions in the new paths (sjust, ajust, opencode, etc.) are discovered.
# If fpath is unchanged and compinit already ran (e.g. via oh-my-zsh), skip it.
if [[ "${fpath[*]}" != "${_sparkdock_fpath_before}" ]] || ! whence -w _complete >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit
fi
unset _sparkdock_fpath_before

# Source shell aliases
if [[ -f "${SPARKDOCK_SHELL_DIR}/aliases.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/aliases.zsh"
fi

# Source tool completions (optional, can be disabled via SPARKDOCK_ENABLE_COMPLETIONS)
: "${SPARKDOCK_ENABLE_COMPLETIONS:=1}" # Enabled by default
if [[ "$SPARKDOCK_ENABLE_COMPLETIONS" == "1" && -f "${SPARKDOCK_SHELL_DIR}/completions.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/completions.zsh"
fi

# Optional: Source user customizations
if [[ -f "${HOME}/.config/spark/shell.zsh" ]]; then
  source "${HOME}/.config/spark/shell.zsh"
fi
