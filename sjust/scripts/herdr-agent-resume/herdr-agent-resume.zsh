# sparkdock herdr-agent-resume: resume Claude Code / Codex in recovered herdr-core
# terminals. Stopgap until herdr-core does it (herdrdev/herdr-core#13, #15).
# Managed by `sjust herdr-agent-resume-enable`; see README.md next to this file.
#
# Cost: nothing unless this terminal has a marker file. Then one python3 call.

# All top-level work runs in functions under `emulate -L zsh`, so the person's
# options (KSH_ARRAYS, ERR_EXIT, ...) never change how this file behaves.
_sf_har_init() {
  emulate -L zsh
  [[ -o interactive ]] || return 1
  [[ -n ${HC_TERMINAL_ID-} && ${HERDR_ENV-} != 1 ]] || return 1
  typeset -g _sf_har_dir=${HOME}/.config/spark/herdr-agent-resume
  [[ -e $_sf_har_dir/enabled ]] || return 1
  (( ${+commands[python3]} )) || return 1  # without it the snippet does nothing at all
  typeset -g _sf_har_py=${1:A:h}/herdr-agent-resume.py
  [[ $HC_TERMINAL_SOCKET == /* ]] || return 1
  # The core's folder: its full socket path with `%` and `/` encoded (core_key).
  local core=${HC_TERMINAL_SOCKET//\%/%25}
  core=${core//\//%2F}
  typeset -g _sf_har_marker=$_sf_har_dir/markers/$core/${HC_TERMINAL_ID//\//_}
  # _sf_har_top: is this the terminal's own shell (parent is the herdr-core
  # holder), not one nested in a running agent? Checked once, lazily.
  typeset -g _sf_har_cmd= _sf_har_msg= _sf_har_top=
  zmodload zsh/parameter 2>/dev/null  # $jobstates, read before each command
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _sf_har_preexec
  _sf_har_startup
  return 0
}

_sf_har_top_level() {
  emulate -L zsh
  if [[ -z $_sf_har_top ]]; then
    local comm=
    if [[ -r /proc/$PPID/comm ]]; then
      read -r comm 2>/dev/null </proc/$PPID/comm
    else
      comm=$(ps -o comm= -p $PPID 2>/dev/null)
    fi
    [[ ${comm:t} == herdr-core ]] && _sf_har_top=1 || _sf_har_top=0
  fi
  (( _sf_har_top ))
}

# Before each command: an agent recorded here has ended. Skipped while jobs exist
# (a suspended agent is still alive). Nobody types during a shutdown, so a reboot
# never gets here. Builtins first write the ended record (the session token), so a
# recovery racing the cleanup still sees the session as closed; then the cleanup
# runs in the background, so a slow core never delays the shell.
_sf_har_preexec() {
  emulate -L zsh
  [[ -e $_sf_har_dir/enabled && -e $_sf_har_marker ]] || return 0
  (( ${+jobstates} && ${#jobstates} == 0 )) || return 0
  _sf_har_top_level || return 0
  local token=
  read -r token 2>/dev/null <$_sf_har_marker
  [[ $token =~ '^[0-9a-f]{16}$' ]] || token=
  if [[ -z $token ]] || ! print -r -- "$token" 2>/dev/null >|$_sf_har_marker.ended.$token; then
    # No ended record (unreadable marker, full or read-only filesystem): without
    # a marker a recovery resumes nothing, and deleting works on a full disk.
    command rm -f -- $_sf_har_marker 2>/dev/null
    return 0
  fi
  python3 $_sf_har_py --shell-cleanup $$ $token </dev/null >/dev/null 2>&1 &!
  return 0
}

# First prompt of a recovered terminal: show the message and run the resume once.
_sf_har_line_init() {
  emulate -L zsh
  add-zle-hook-widget -d line-init _sf_har_line_init
  [[ -e $_sf_har_dir/enabled ]] || return 0
  zle -I
  print -r -- "herdr-agent-resume: ${_sf_har_msg}"
  if [[ -n $_sf_har_cmd ]]; then
    BUFFER=$_sf_har_cmd
    _sf_har_cmd=
    zle accept-line
  fi
}

_sf_har_startup() {
  emulate -L zsh
  local records=( $_sf_har_marker.ended.*(N) )
  [[ -e $_sf_har_marker ]] || (( $#records )) || return 0
  local kind agent id cwd
  local plan=$(python3 $_sf_har_py --shell-startup $$ </dev/null 2>/dev/null)
  [[ -n $plan ]] || return 0
  IFS=$'\t' read -r kind agent id cwd <<<"${plan%%$'\n'*}"
  if [[ $kind == msg ]]; then
    _sf_har_msg="$agent${id:+ $id}${cwd:+ $cwd}"
  elif [[ $kind == resume && $id =~ '^[A-Za-z0-9][A-Za-z0-9-]{7,127}$' && -d $cwd ]]; then
    case $agent in
      claude) _sf_har_cmd="claude --resume $id" ;;
      codex) _sf_har_cmd="codex resume $id" ;;
      *) return 0 ;;
    esac
    # cd now, so direnv/mise load the folder's environment at the first prompt.
    builtin cd -- "$cwd" 2>/dev/null || return 0
    _sf_har_msg="resuming $agent $id"
  else
    return 0
  fi
  # zle must be loaded, or add-zle-hook-widget silently registers nothing.
  zmodload zsh/zle 2>/dev/null || return 0
  autoload -Uz add-zle-hook-widget 2>/dev/null || return 0
  add-zle-hook-widget line-init _sf_har_line_init
}

if _sf_har_init "${(%):-%x}"; then
  unfunction _sf_har_init _sf_har_startup
else
  unfunction _sf_har_init _sf_har_startup _sf_har_top_level _sf_har_preexec _sf_har_line_init
fi
