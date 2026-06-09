#!/usr/bin/env bash
# claude-fix-settings — repair sparkdock-managed Claude Code hooks in the user's
# ~/.claude/settings.json. Invoked by the shared sjust/ajust recipe
# (sjust/recipes/shared/09-claude-fix-settings.just) and by caveman/setup.sh so
# the repair self-heals on every provisioning pass (macOS and Linux, since both
# provisioners run the caveman setup script).
#
# This wrapper resolves a stable node path and the settings location, then
# delegates all JSON work to claude-fix-settings.py (same directory).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PYSCRIPT="${SCRIPT_DIR}/claude-fix-settings.py"
SETTINGS="${HOME}/.claude/settings.json"

usage() {
    echo "Usage: claude-fix-settings.sh {fix|info}" >&2
    exit 2
}

# Resolve a stable node path: prefer the Homebrew prefix symlink (survives node
# version bumps), fall back to the PATH entry. We deliberately do NOT readlink
# the result, so we never re-bake a version-pinned Cellar path.
_stable_node_path() {
    local prefix
    if command -v brew >/dev/null 2>&1; then
        prefix="$(brew --prefix 2>/dev/null || true)"
        if [[ -n "${prefix}" && -x "${prefix}/bin/node" ]]; then
            printf '%s\n' "${prefix}/bin/node"
            return 0
        fi
    fi
    if command -v node >/dev/null 2>&1; then
        command -v node
        return 0
    fi
    return 1
}

main() {
    local mode="${1:-fix}"
    case "${mode}" in
        fix | info) ;;
        *) usage ;;
    esac
    shift || true

    local node=""
    if ! node="$(_stable_node_path)"; then
        node=""
        echo "⚠️  node not found on PATH — skipping caveman node-path normalization."
    fi

    # Any extra args (e.g. --remove-claude-usage) are forwarded to the python
    # script. The automatic caveman setup omits them; the sjust recipe opts in.
    python3 "${PYSCRIPT}" "${SETTINGS}" --mode "${mode}" --node "${node}" "$@"
}

main "$@"
