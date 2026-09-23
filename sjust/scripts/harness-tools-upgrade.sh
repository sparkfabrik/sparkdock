#!/usr/bin/env bash
# harness-tools-upgrade — upgrade Claude Code and Codex through whichever
# channel installed each one: the Homebrew casks (macOS, Debian/Ubuntu), the
# native Claude installer and the `openai-codex` pacman package (Arch). Tools
# behind an Omarchy mise wrapper are left to `omarchy update`. Invoked by
# sjust/recipes/shared/17-harness-tools-upgrade.just.

set -euo pipefail

failed=0

has_cask() {
    command -v brew >/dev/null 2>&1 && brew list --cask "$1" >/dev/null 2>&1
}

# Omarchy generates ~/.local/bin wrappers that run `mise use -g`; the same
# signal sf-toolbox uses in omarchy-detect.yml.
is_mise_wrapper() {
    local bin
    bin="$(command -v "$1" 2>/dev/null)" || return 1
    grep -qs 'mise use -g' "${bin}"
}

run() {
    echo "==> $*"
    "$@" || failed=1
}

upgrade_claude() {
    if has_cask claude-code@latest; then
        run brew upgrade --cask claude-code@latest
        return
    fi
    if is_mise_wrapper claude; then
        echo "==> claude is managed by Omarchy (mise); run 'omarchy update' instead."
        return
    fi
    if command -v claude >/dev/null 2>&1; then
        run claude update
        return
    fi
    echo "==> claude is not installed; skipping."
}

upgrade_codex() {
    if has_cask codex; then
        run brew upgrade --cask codex
        return
    fi
    if is_mise_wrapper codex; then
        echo "==> codex is managed by Omarchy (mise); run 'omarchy update' instead."
        return
    fi
    if command -v pacman >/dev/null 2>&1 && pacman -Q openai-codex >/dev/null 2>&1; then
        run sudo pacman -Sy --needed --noconfirm openai-codex
        return
    fi
    if command -v codex >/dev/null 2>&1; then
        echo "==> codex at $(command -v codex) comes from an unmanaged source; skipping." >&2
        failed=1
        return
    fi
    echo "==> codex is not installed; skipping."
}

upgrade_claude
upgrade_codex

echo
command -v claude >/dev/null 2>&1 && echo "claude: $(claude --version 2>/dev/null || echo unknown)"
command -v codex >/dev/null 2>&1 && echo "codex:  $(codex --version 2>/dev/null || echo unknown)"

exit "${failed}"
