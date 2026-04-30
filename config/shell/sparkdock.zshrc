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

# Source shell tool initializations
if [[ -f "${SPARKDOCK_SHELL_DIR}/init.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/init.zsh"
fi

# Ensure base completion system exists (only if never initialized).
if ! whence -w compdef >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit
fi

# Source shell aliases
if [[ -f "${SPARKDOCK_SHELL_DIR}/aliases.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/aliases.zsh"
fi

# Generate any missing completion files (fallback for non-Ansible installs).
# This must run BEFORE the autoload loop so freshly generated files are picked up.
: "${SPARKDOCK_ENABLE_COMPLETIONS:=1}" # Enabled by default
if [[ "$SPARKDOCK_ENABLE_COMPLETIONS" == "1" && -f "${SPARKDOCK_SHELL_DIR}/completions.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/completions.zsh"
fi

# Register site-functions completions directly via autoload + compdef.
# This avoids re-running compinit (which wipes bashcompinit registrations
# like aws, gcloud) and works regardless of whether the user added
# site-functions to fpath before or after their own compinit call.
# Runs AFTER completions.zsh so freshly generated files are included.
_sparkdock_site_dir="${HOME}/.local/share/zsh/site-functions"
if [[ -d "${_sparkdock_site_dir}" ]]; then
  for _f in "${_sparkdock_site_dir}"/_*(N); do
    autoload -Uz "${_f:t}"
    compdef "${_f:t}" "${${_f:t}#_}" 2>/dev/null
  done
  unset _f
fi
unset _sparkdock_site_dir

# Source bashcompinit-based completions.
# Tools like gcloud use bash-style `complete -F` via bashcompinit rather than
# native zsh completions. These must be sourced explicitly — autoload won't work.
if command_exists gcloud; then
  local _gcloud_comp
  for _gcloud_comp in \
    /opt/google-cloud-sdk/completion.zsh.inc \
    /opt/google-cloud-cli/completion.zsh.inc \
    /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc; do
    if [[ -f "${_gcloud_comp}" ]]; then
      source "${_gcloud_comp}"
      break
    fi
  done
  unset _gcloud_comp
fi

# Optional: Source user customizations
if [[ -f "${HOME}/.config/spark/shell.zsh" ]]; then
  source "${HOME}/.config/spark/shell.zsh"
fi
