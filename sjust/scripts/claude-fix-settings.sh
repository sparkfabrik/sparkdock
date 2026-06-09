#!/usr/bin/env bash
# claude-fix-settings — repair sparkdock-managed Claude Code hooks in the user's
# ~/.claude/settings.json. Invoked by the shared sjust/ajust recipe
# (sjust/recipes/shared/09-claude-fix-settings.just) and by caveman/setup.sh so
# the repair self-heals on every provisioning pass (macOS and Linux, since both
# provisioners run the caveman setup script).
#
# Two idempotent fixes:
#   1. Caveman hook node path — the caveman installer bakes the *resolved* node
#      binary (e.g. /opt/homebrew/Cellar/node/26.0.0/bin/node) into the
#      SessionStart/UserPromptSubmit hook commands, which breaks on every node
#      version bump. Rewrite it to the stable Homebrew symlink
#      (/opt/homebrew/bin/node on macOS, /home/linuxbrew/.linuxbrew/bin/node on
#      Linux) — still absolute, but version-independent.
#   2. claude-usage hooks — remove the SessionStart/SessionEnd hooks that the
#      upstream claude-usage installer wires in.
#
# python3 does all JSON work (no jq dependency); writes are atomic (temp file +
# os.replace) with a timestamped backup, and a missing/corrupt/non-object
# settings file is a clean no-op.

set -euo pipefail

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

_run() {
    local mode="$1" node="$2"
    python3 - "${SETTINGS}" "${mode}" "${node}" <<'PY'
import json, os, re, shutil, sys, tempfile, time

path, mode, node = sys.argv[1], sys.argv[2], sys.argv[3]
dry = mode == "info"

if not os.path.exists(path):
    print(f"ℹ️  {path} does not exist — nothing to do.")
    sys.exit(0)
try:
    with open(path) as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    print(f"⚠️  {path} is missing or not valid JSON — skipping.")
    sys.exit(0)
if not isinstance(data, dict):
    print(f"⚠️  {path} is not a JSON object — skipping.")
    sys.exit(0)

changes = []
CAVEMAN_SCRIPTS = ("caveman-activate.js", "caveman-mode-tracker.js")
# Leading command token: a quoted "..." path or a bare \S+ run, then the rest.
_node_token = re.compile(r'^("(?P<q>[^"]*)"|(?P<b>\S+))(?P<rest>\s.*)$', re.DOTALL)


def normalize_node_path(cmd):
    # Op 1: only touch caveman-managed hook commands, and only when a stable
    # node path is known and differs from the baked-in one.
    if not node or not any(s in cmd for s in CAVEMAN_SCRIPTS):
        return cmd, False
    m = _node_token.match(cmd)
    if not m:
        return cmd, False
    current = m.group("q") if m.group("q") is not None else m.group("b")
    if current == node:
        return cmd, False
    return f'"{node}"{m.group("rest")}', True


hooks = data.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks.keys()):
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                kept_groups.append(group)
                continue
            kept_entries = []
            for entry in group["hooks"]:
                if isinstance(entry, dict) and isinstance(entry.get("command"), str):
                    cmd = entry["command"]
                    # Op 2: drop claude-usage hooks entirely.
                    if "claude-usage" in cmd:
                        changes.append(f"removed claude-usage hook from {event}")
                        continue
                    # Op 1: normalize the caveman hook node path.
                    new_cmd, changed = normalize_node_path(cmd)
                    if changed:
                        entry["command"] = new_cmd
                        changes.append(f"normalized caveman node path in {event} -> {node}")
                kept_entries.append(entry)
            if kept_entries:
                group["hooks"] = kept_entries
                kept_groups.append(group)
            else:
                changes.append(f"removed empty hook group from {event}")
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
            changes.append(f"removed empty event '{event}'")
    if not hooks:
        data.pop("hooks", None)

if not changes:
    print("✅ Already clean — no changes needed.")
    sys.exit(0)

for c in changes:
    print(("would fix: " if dry else "fixed: ") + c)

if dry:
    print(f"\nℹ️  {len(changes)} change(s) pending. Run 'claude-fix-settings' to apply.")
    sys.exit(0)

backup = f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}"
shutil.copy2(path, backup)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings.", suffix=".json")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
except BaseException:
    os.path.exists(tmp) and os.unlink(tmp)
    raise

print(f"\n✅ Applied {len(changes)} change(s) to {path}")
print(f"💡 Backup saved to {backup}")
PY
}

main() {
    local mode="${1:-fix}"
    case "${mode}" in
        fix | info) ;;
        *) usage ;;
    esac

    local node=""
    if ! node="$(_stable_node_path)"; then
        node=""
        echo "⚠️  node not found on PATH — skipping caveman node-path normalization."
    fi

    _run "${mode}" "${node}"
}

main "$@"
