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

# tmate -> upterm transition helper
# tmate is deprecated in Homebrew; upterm is the replacement.
if ! command_exists tmate; then
  tmate() {
    local msg="tmate has been replaced by upterm in Sparkdock.
See: https://upterm.dev/"
    if command_exists gum; then
      gum style --border rounded --border-foreground 214 --foreground 214 \
        --bold --padding "0 1" --margin "0 0 1 0" "${msg}" >&2
    else
      echo "" >&2
      echo "\033[1;33m${msg}\033[0m" >&2
      echo "" >&2
    fi
    if command_exists upterm; then
      echo "Run an authenticated session instead:" >&2
      echo "  sjust upterm-host github <username>" >&2
      return 2
    else
      echo "Install upterm first: brew install --cask owenthereal/upterm/upterm" >&2
      return 127
    fi
  }
fi

# zoxide integration with smart cd replacement
if command_exists zoxide; then
  zd() {
    if [ $# -eq 0 ]; then
      builtin cd ~ && return
    elif [ -d "$1" ]; then
      builtin cd "$1"
    else
      z "$@" && printf "\U000F17A9 " && pwd || echo "Error: Directory not found"
    fi
  }
  # Keep cd literal under AI agents (Claude Code, etc.): zoxide frecency-jumps on a missing
  # relative path instead of erroring, silently teleporting the agent's persistent cwd.
  if [[ -z ${CLAUDECODE:-} && -z ${AI_AGENT:-} ]]; then
    alias cd="zd"
  fi
fi

# Modern replacements for classic commands
# eza - modern replacement for ls with colors and icons
if command_exists eza; then
  # bug on macos: https://github.com/eza-community/eza/issues/1224
  export EZA_CONFIG_DIR=$HOME/.config/eza
  unalias ls 2>/dev/null || true

  function ls() {
    # Only dress up interactive use. Scripts, pipelines, editors and coding
    # agents get the real ls, so `ls -d some/path` returns a path rather than a
    # formatted table with a header row.
    if [[ ! -o interactive || ! -t 1 ]]; then
      command ls "$@"
      return
    fi

    # Inspect options only. Matching against "$*" tested the whole argument
    # string, so any path containing "lt" or "ltr" silently switched to
    # sort-by-modified and revealed hidden files: ls faults/, ls halt.txt,
    # ls results/ all took the wrong branch.
    local -a rest
    local sort_modified=0 reverse=1 arg stripped
    for arg in "$@"; do
      case $arg in
        -[!-]*)
          stripped=$arg
          case $arg in
            *ltr*) sort_modified=1; reverse=0; stripped=${arg//[ltr]/} ;;
            *lt*)  sort_modified=1; reverse=1; stripped=${arg//[lt]/} ;;
          esac
          [[ $stripped != - ]] && rest+=("$stripped")
          ;;
        *) rest+=("$arg") ;;
      esac
    done

    if (( sort_modified )); then
      if (( reverse )); then
        eza -lag --icons=auto --sort=modified --reverse "${rest[@]}"
      else
        eza -lag --icons=auto --sort=modified "${rest[@]}"
      fi
    else
      eza -lhg --group-directories-first --icons=auto "$@"
    fi
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

# glab (GitLab CLI) - disable telemetry
if command_exists glab; then
  export GLAB_SEND_TELEMETRY=false
fi

# gh (GitHub CLI) - disable telemetry
# https://cli.github.com/telemetry
if command_exists gh; then
  export GH_TELEMETRY=false
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

# Google Cloud shortcuts
if command_exists gcloud; then
  alias gcloud-as='gcloud config set auth/impersonate_service_account'
  alias gcloud-me='gcloud config unset auth/impersonate_service_account'
  gcloud-whoami() {
    local impersonated
    impersonated=$(gcloud config get auth/impersonate_service_account 2>/dev/null)
    if [[ -n "${impersonated}" ]]; then
      echo "${impersonated}"
      return
    fi
    gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null
  }
fi

# Add some copilot aliases.
if command_exists copilot; then
  # Ensure ~/.agents is in COPILOT_CUSTOM_INSTRUCTIONS_DIRS (idempotent, preserves existing)
  if [[ ":${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}:" != *":${HOME}/.agents:"* ]]; then
    export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${HOME}/.agents${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:+:${COPILOT_CUSTOM_INSTRUCTIONS_DIRS}}"
  fi

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
  co()  { copilot --allow-all-tools --silent --model gpt-5-mini -p "${@}"; }
  cos() { copilot --allow-all-tools --silent --model claude-sonnet-4.6 -p "${@}"; }
  coh() { copilot --allow-all-tools --silent --model claude-haiku-4.5 -p "${@}"; }
  coc() { copilot --allow-all-tools --silent --model gpt-5.3-codex -p "${@}"; }
  cog() { copilot --allow-all-tools --silent --model gemini-3.1-pro-preview -p "${@}"; }
  coo() { copilot --allow-all-tools --silent --model claude-opus-4.6 -p "${@}"; }

  ## Interactive mode aliases (ico = interactive copilot)
  # ico/icos/icoh/icoc/icog/icoo - Start interactive session, optionally with initial prompt
  # Usage: ico → starts full interactive session
  #        ico "prompt" → starts session with initial prompt
  ico()  { copilot --model gpt-5-mini --allow-all-tools ${1:+-i} "${@}"; }
  icos() { copilot --model claude-sonnet-4.6 --allow-all-tools ${1:+-i} "${@}"; }
  icoh() { copilot --model claude-haiku-4.5 --allow-all-tools ${1:+-i} "${@}"; }
  icoc() { copilot --model gpt-5.3-codex --allow-all-tools ${1:+-i} "${@}"; }
  icog() { copilot --model gemini-3.1-pro-preview --allow-all-tools ${1:+-i} "${@}"; }
  icoo() { copilot --model claude-opus-4.6 --allow-all-tools ${1:+-i} "${@}"; }

  ## Session Management
  # cocon - Resume the last session
  cocon() { copilot --allow-all-tools --continue; }
  # cores - Resume a specific session
  cores() { copilot --allow-all-tools --resume "${@}"; }
fi

# Claude Code with a separate personal profile.
# `claude-personal` runs Claude Code against its own config dir (~/.claude_personal),
# giving it a separate login, usage pool and no org-managed policy.
# The default `claude` command is left untouched and stays on the work/org account.
if command_exists claude; then
  claude-personal() {
    local config_dir="${HOME}/.claude_personal"
    [[ -d "${config_dir}" ]] || mkdir -p "${config_dir}"
    CLAUDE_CONFIG_DIR="${config_dir}" command claude "$@"
  }
fi

# Add some opencode aliases.
if command_exists opencode; then
  alias c='opencode'
fi

# OpenSpec shortcuts
if command_exists openspec; then
  export OPENSPEC_NO_AUTO_CONFIG=1
  alias os='openspec'
  alias osi='openspec init --tools opencode,github-copilot,claude'
  alias osl='openspec list'
  alias oss='openspec status'
  alias osn='openspec new change'
  alias osa='openspec archive'
fi

# Spark HTTP proxy
# Zsh completes through the alias expansion, so 'sproxy sta<TAB>' still works
# wherever 'spark-http-proxy install-completion' has run.
if command_exists spark-http-proxy; then
  alias sproxy='spark-http-proxy'
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
