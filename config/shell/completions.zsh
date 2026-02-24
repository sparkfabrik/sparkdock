#!/usr/bin/env zsh
# Sparkdock Shell Completions
# This file configures modern shell command completions for an enhanced, discoverable CLI experience

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# AI tool completions
# Use cached completion files in ~/.local/share/zsh/site-functions to avoid
# running external binaries on every shell startup.
if command_exists opencode; then
  _opencode_completion_file="${HOME}/.local/share/zsh/site-functions/_opencode"
  if [[ ! -f "${_opencode_completion_file}" ]]; then
    mkdir -p "${HOME}/.local/share/zsh/site-functions"
    opencode completion > "${_opencode_completion_file}" 2>/dev/null || rm -f "${_opencode_completion_file}"
  fi
  if [[ -f "${_opencode_completion_file}" ]]; then
    source "${_opencode_completion_file}"
  fi
fi

if command_exists openspec; then
  _openspec_completion_file="${HOME}/.local/share/zsh/site-functions/_openspec"
  if [[ ! -f "${_openspec_completion_file}" ]]; then
    mkdir -p "${HOME}/.local/share/zsh/site-functions"
    openspec completion generate zsh > "${_openspec_completion_file}" 2>/dev/null || rm -f "${_openspec_completion_file}"
  fi
  if [[ -f "${_openspec_completion_file}" ]]; then
    source "${_openspec_completion_file}"
  fi
fi
