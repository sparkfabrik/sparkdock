#!/usr/bin/env zsh
# Sparkdock Shell — bashcompinit-based completions
#
# Tools like gcloud and aws use bash-style `complete -F` via bashcompinit
# rather than native zsh completions. These must be sourced explicitly —
# autoload won't work. This file is sourced AFTER the site-functions
# autoload loop in sparkdock.zshrc to avoid compinit wipes.

# Google Cloud SDK
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
