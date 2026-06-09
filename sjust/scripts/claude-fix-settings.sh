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

# Resolve the most stable node path for the caveman hook commands. The caveman
# installer bakes an absolute, version-pinned path (process.execPath) that
# vanishes when node is upgraded. Prefer a version-independent value, in order:
#
#   1. Homebrew symlink ($(brew --prefix)/bin/node) — covers macOS Homebrew and
#      Linux linuxbrew (e.g. .../Cellar/node/X/bin/node -> .../bin/node); stable
#      across node bumps.
#   2. A non-versioned absolute path already on PATH (e.g. /usr/bin/node from a
#      distro package) — already stable, so keep it.
#   3. Otherwise the path is version-pinned with no stable symlink (nvm,
#      .../.nvm/versions/node/vX/bin/node, or a bare Cellar path) — fall back to
#      the bare `node` command so the hook resolves via PATH instead of a path
#      that disappears on the next upgrade.
#
# We deliberately do NOT readlink the result, so we never re-bake a version dir.
_stable_node_path() {
    local prefix n
    if command -v brew >/dev/null 2>&1; then
        prefix="$(brew --prefix 2>/dev/null || true)"
        if [[ -n "${prefix}" && -x "${prefix}/bin/node" ]]; then
            printf '%s\n' "${prefix}/bin/node"
            return 0
        fi
    fi
    n="$(command -v node 2>/dev/null || true)"
    if [[ -z "${n}" ]]; then
        return 1
    fi
    case "${n}" in
        */Cellar/* | */.nvm/* | */versions/node/*)
            # Version-pinned with no stable symlink — use PATH-relative `node`.
            printf 'node\n'
            ;;
        *)
            printf '%s\n' "${n}"
            ;;
    esac
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
