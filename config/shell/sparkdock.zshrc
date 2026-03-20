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

# Snapshot fpath before init.zsh may add new directories.
# Using an anonymous function to avoid leaking local variables into the
# user's shell namespace (`local` at top-level is just `typeset` in zsh).
() {
  local fpath_before=("${fpath[@]}")

  # Source shell tool initializations
  if [[ -f "${SPARKDOCK_SHELL_DIR}/init.zsh" ]]; then
    source "${SPARKDOCK_SHELL_DIR}/init.zsh"
  fi

  # Initialize or update the completion system.
  # If compinit has not run yet, run it normally (full scan).
  # If compinit already ran (e.g. oh-my-zsh) and init.zsh added new fpath
  # entries, register only the new completions without a costly full rescan.
  # Respect `#compdef` headers when present, and fall back to `_cmd -> cmd`.
  if ! whence -w _complete >/dev/null 2>&1; then
    autoload -Uz compinit
    compinit
  elif [[ "${fpath[*]}" != "${fpath_before[*]}" ]]; then
    local dir f fname first_line def_line cmd
    local -a commands
    for dir in "${fpath[@]}"; do
      # (I) returns 0 when the element is not found in the array.
      if (( ! ${fpath_before[(I)${dir}]} )); then
        for f in "${dir}"/_*(N); do
          fname="${f:t}"
          autoload -Uz "${fname}"

          IFS= read -r first_line < "${f}" || true
          if [[ "${first_line}" == '#compdef '* ]]; then
            def_line="${first_line#\#compdef }"
            commands=(${=def_line})
          else
            commands=("${fname#_}")
          fi

          for cmd in "${commands[@]}"; do
            [[ "${cmd}" == -* || "${cmd}" == *'='* ]] && continue
            compdef "${fname}" "${cmd}"
          done
        done
      fi
    done
  fi
}

# Source shell aliases
if [[ -f "${SPARKDOCK_SHELL_DIR}/aliases.zsh" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/aliases.zsh"
fi

# Optional: Source user customizations
if [[ -f "${HOME}/.config/spark/shell.zsh" ]]; then
  source "${HOME}/.config/spark/shell.zsh"
fi
