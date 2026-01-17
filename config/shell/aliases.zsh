#!/usr/bin/env zsh
# Sparkdock Shell Aliases
# This file contains modern command aliases and shortcuts for enhanced shell experience

# Helper function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Initialize thefuck (command correction)
if command_exists thefuck; then
  # Only initialize if 'fuck' alias doesn't already exist
  if ! alias fuck &> /dev/null && ! command_exists fuck; then
    eval "$(thefuck --alias)"
  fi
fi

# Alias to open images from terminal with chafa.
if command_exists chafa; then
  img2terminal() {
    format="ansi"
    if  [[ "${TERM_PROGRAM}" == "iTerm.app" ]] \
        || [[ "${TERM_PROGRAM}" == "ghostty" ]] \
        || [[ "${TERM}" == "xterm-kitty" ]] \
        || [[ -n "${KITTY_WINDOW_ID}" ]]; then
        format="kitty"
    fi
    chafa --format=$format "$@"
  }
fi

# check if fzf is installed for fuzzy finding.
if command_exists fzf; then
  alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
fi

# zoxide integration with smart cd replacement
if command_exists zoxide; then
  alias cd="zd"
  zd() {
    if [ $# -eq 0 ]; then
      builtin cd ~ && return
    elif [ -d "$1" ]; then
      builtin cd "$1"
    else
      z "$@" && printf "\U000F17A9 " && pwd || echo "Error: Directory not found"
    fi
  }
fi

# Modern replacements for classic commands
# eza - modern replacement for ls with colors and icons
if command_exists eza; then
  # bug on macos: https://github.com/eza-community/eza/issues/1224
  export EZA_CONFIG_DIR=$HOME/.config/eza
  unalias ls 2>/dev/null || true

  function ls() {
    local filtered_args=("${@[@]//-ltr/}")
    filtered_args=("${filtered_args[@]//-lt/}")

    case "$*" in
      *ltr*)
        eza -lag --icons=auto --sort=modified ${filtered_args[@]}
        ;;
      *lt*)
        eza -lag --icons=auto --sort=modified --reverse ${filtered_args[@]}
        ;;
      *)
        eza -lhg --group-directories-first --icons=auto "$@"
        ;;
    esac
  }
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

# bat - modern replacement for cat with syntax highlighting
if command_exists bat; then
  alias cat='bat --style=auto'
  alias ccat='/bin/cat'  # Keep original cat available
fi

# Docker shortcuts
if command_exists docker; then
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps'
  alias dpsa='docker ps -a'
  alias di='docker images'
fi

# Git shortcuts
if command_exists git; then
  alias gs='git status'
  alias gp='git pull'
  alias gpush='git push'
  alias gc='git commit'
  alias gco='git checkout'
  alias ga='git add'
  alias gd='git diff'
  alias gl='git log --oneline --graph --decorate'
fi

# Kubernetes shortcuts
if command_exists kubectl; then
  alias k='kubectl'
  alias kgp='kubectl get pods'
  alias kgs='kubectl get services'
  alias kgd='kubectl get deployments'
  alias kga='kubectl get all'
  alias kdp='kubectl describe pod'
  alias kds='kubectl describe service'
  alias kdd='kubectl describe deployment'
  alias kl='kubectl logs'
fi

if command_exists kubectx; then
  alias kx='kubectx'
fi

if command_exists kubens; then
  alias kn='kubens'
fi

# Add some copilot aliases.
if command_exists copilot; then
  # Override copilot function only on macOS for keychain certificate handling
  if [[ "$OSTYPE" == "darwin"* ]]; then
    copilot() {
      # temporary fix for this issue: https://github.com/github/copilot-cli/issues/869#issuecomment-3711278787
      # we want to create a dump of the keychain to a temp file and point copilot to it.
      # we need just to create that one time, to avoid performance issues.
      # save it here ${HOME}/.local/spark/copilot/keychain.pem
      if [ ! -f "${HOME}/.local/spark/copilot/keychain.pem" ]; then
        mkdir -p "${HOME}/.local/spark/copilot"
        security find-certificate -a -p /Library/Keychains/System.keychain > "${HOME}/.local/spark/copilot/keychain.pem" 2>/dev/null || true
        security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain >> "${HOME}/.local/spark/copilot/keychain.pem" 2>/dev/null || true
      fi
      export NODE_EXTRA_CA_CERTS="${HOME}/.local/spark/copilot/keychain.pem"
      command copilot "${@}"
    }
  fi

  ## One-shot mode aliases (co = copilot one-shot)
  # co/cos/coh/coc/cog/coo - Run a single prompt and exit
  co()  { copilot --allow-all-tools --silent --model gpt-4.1 -p "${@}"; }
  cos() { copilot --allow-all-tools --silent --model claude-sonnet-4.5 -p "${@}"; }
  coh() { copilot --allow-all-tools --silent --model claude-haiku-4.5 -p "${@}"; }
  coc() { copilot --allow-all-tools --silent --model gpt-5.1-codex-max -p "${@}"; }
  cog() { copilot --allow-all-tools --silent --model gemini-3-pro -p "${@}"; }
  coo() { copilot --allow-all-tools --silent --model claude-opus-4.5 -p "${@}"; }

  ## Interactive mode aliases (ico = interactive copilot)
  # ico/icos/icoh/icoc/icog/icoo - Start interactive session, optionally with initial prompt
  # Usage: ico → starts full interactive session
  #        ico "prompt" → starts session with initial prompt
  ico()  { copilot --model gpt-4.1 --allow-all-tools ${1:+-i} "${@}"; }
  icos() { copilot --model claude-sonnet-4.5 --allow-all-tools ${1:+-i} "${@}"; }
  icoh() { copilot --model claude-haiku-4.5 --allow-all-tools ${1:+-i} "${@}"; }
  icoc() { copilot --model gpt-5.1-codex-max --allow-all-tools ${1:+-i} "${@}"; }
  icog() { copilot --model gemini-3-pro --allow-all-tools ${1:+-i} "${@}"; }
  icoo() { copilot --model claude-opus-4.5 --allow-all-tools ${1:+-i} "${@}"; }

  ## Session Management
  # cocon - Resume the last session
  cocon() { copilot --allow-all-tools --continue; }
  # cores - Resume a specific session
  cores() { copilot --allow-all-tools --resume "${@}"; }
fi

# Add some opencode aliases.
if command_exists opencode; then
  # Main command with subcommand support
  # Usage: c [args] - runs opencode with args
  #        c web [args] - runs opencode web interface
  #        c serve [args] - runs opencode server
  c() {
    case "${1:-}" in
      web)
        shift
        opencode web "$@"
        ;;
      serve)
        shift
        opencode serve "$@"
        ;;
      *)
        opencode "$@"
        ;;
    esac
  }
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# System shortcuts
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'
alias h='history'
# Note: 'c' alias removed - now used for OpenCode (see OpenCode aliases section above)
# Use 'clear' command directly or ctrl+l for clearing screen

# Reload Sparkdock shell configuration
# This unsets the guard variable and re-sources the main config file
alias reload-sparkdock='unset SPARKDOCK_SHELL_LOADED && [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ] && source /opt/sparkdock/config/shell/sparkdock.zshrc || echo "Sparkdock shell config not found"'
