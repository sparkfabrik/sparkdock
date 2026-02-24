#!/usr/bin/env zsh
# Sparkdock Shell Completions
# This file configures modern shell command completions for an enhanced, discoverable CLI experience

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# AI tool completions
# Use cached completion files to avoid running external binaries on every shell startup.
_spark_site_functions="${HOME}/.local/spark/site-functions"
mkdir -p "${_spark_site_functions}"

if command_exists opencode; then
  _opencode_completion_file="${_spark_site_functions}/_opencode"
  if [[ ! -f "${_opencode_completion_file}" ]]; then
    opencode completion > "${_opencode_completion_file}" 2>/dev/null || rm -f "${_opencode_completion_file}"
  fi
  if [[ -f "${_opencode_completion_file}" ]]; then
    source "${_opencode_completion_file}"
  fi
fi

if command_exists openspec; then
  _openspec_completion_file="${_spark_site_functions}/_openspec"
  if [[ ! -f "${_openspec_completion_file}" ]]; then
    openspec completion generate zsh > "${_openspec_completion_file}" 2>/dev/null || rm -f "${_openspec_completion_file}"
  fi
  if [[ -f "${_openspec_completion_file}" ]]; then
    source "${_openspec_completion_file}"
  fi
fi
