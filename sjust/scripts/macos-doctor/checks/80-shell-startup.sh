#!/usr/bin/env bash
# shellcheck shell=bash
#
# checks/80-shell-startup.sh — interactive shell startup time.
#
# Sparkdock owns part of the zsh configuration, so a regression here is something
# we can cause. Slow shell startup is felt on every new terminal tab, which makes
# it one of the most noticeable forms of slowness on a dev machine.
#
# Three runs, best time taken. The first run pays for cold caches and would
# otherwise dominate; the minimum is the closest thing to the steady-state cost.

# Milliseconds. Under 300 is comfortable; over 800 is felt on every new tab.
_SS_WARN_MS=800
_SS_INFO_MS=300
_SS_RUNS=3

doctor_meta() {
    printf 'shell-startup\tShell startup time\tinteractive zsh startup time, best of three runs\tno\tno\tno\n'
}

# Print the best wall-clock time in milliseconds for `zsh -i -c exit`.
_ss_best_ms() {
    command -v zsh >/dev/null 2>&1 || return 0

    local i best="" ms
    for ((i = 0; i < _SS_RUNS; i++)); do
        ms="$(
            python3 -c '
import subprocess, sys, time
start = time.monotonic()
subprocess.run(["zsh", "-i", "-c", "exit"],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(int((time.monotonic() - start) * 1000))
'
        )" || continue
        [[ -n "${ms}" ]] || continue
        if [[ -z "${best}" || "${ms}" -lt "${best}" ]]; then
            best="${ms}"
        fi
    done
    [[ -n "${best}" ]] && printf '%s' "${best}"
}

doctor_detect() {
    local ms
    ms="$(_ss_best_ms)"
    [[ -n "${ms}" ]] || return 0

    if [[ "${ms}" -ge "${_SS_WARN_MS}" ]]; then
        doctor_finding warn "zsh -i" \
            "${ms} ms to start (best of ${_SS_RUNS} runs)" \
            "profile with: zsh -i -c 'zmodload zsh/zprof; exit' or zsh -xv"
    elif [[ "${ms}" -ge "${_SS_INFO_MS}" ]]; then
        doctor_finding info "zsh -i" "${ms} ms to start (best of ${_SS_RUNS} runs)" ""
    fi
}

doctor_explain() {
    cat <<'MD'
Times `zsh -i -c exit` three times and reports the best result. Sparkdock manages
part of the zsh configuration, so a regression here is something we can introduce,
and the cost is paid on every new terminal tab.

Thresholds:

- Under 300 ms is comfortable and produces no finding.
- 300 to 800 ms is reported as `info`.
- 800 ms or more is a `warn`.

The best of three runs is used rather than the first or the average. A first run
pays for cold caches and would dominate any average, so the minimum is the closest
honest estimate of the steady-state cost.

To find where the time goes, `zprof` is the practical tool:

```bash
zsh -i -c 'zmodload zsh/zprof; zprof | head -20'
```

Common causes on a provisioned machine are version manager initialisation (nvm,
rbenv, pyenv) running eagerly instead of lazily, completion caches being rebuilt
on every start, and network calls in the prompt.
MD
}
