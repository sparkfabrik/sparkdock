#!/usr/bin/env bash
# drupalorg-cli — install, update and remove the Drupal.org CLI (drupalorg)
# and the agent skill it ships. Invoked by sjust/recipes/shared/19-drupalorg.just
# on macOS (sjust) and Linux (ajust), so it sticks to bash, curl, python3 and
# PHP, which behave the same on BSD and GNU userlands.
#
# Usage: drupalorg-cli.sh [help|install|status|uninstall|mcp|mcp-remove]
#
# Releases are taken from GitHub, verified against the sha256 digest GitHub
# publishes for the release asset, and skipped until they are
# DRUPALORG_MIN_AGE_DAYS old (default 7, 0 disables the cooldown).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../libs/libshell.sh
source "${SCRIPT_DIR}/../libs/libshell.sh"
# Tool registry: TOOL_SKILLS_DIR, TOOL_LABEL, TOOLS_NATIVE_DISCOVERY.
# shellcheck source=../../bin/common/skills-symlink-shim.sh
source "${SPARKDOCK_ROOT}/bin/common/skills-symlink-shim.sh"
# bold, print_label, print_faint.
# shellcheck source=../../bin/common/utils.sh
source "${SPARKDOCK_ROOT}/bin/common/utils.sh"

readonly REPO="mglaman/drupalorg-cli"
readonly TARGET="${HOME}/.local/bin/drupalorg"
readonly SKILL_NAME="drupalorg-cli"
readonly SKILL_DIR="${HOME}/.agents/skills/${SKILL_NAME}"
readonly MCP_NAME="drupalorg-cli"
readonly MIN_AGE_DAYS="${DRUPALORG_MIN_AGE_DAYS:-7}"
if [[ "$(uname -s)" == "Darwin" ]]; then
    readonly CMD="sjust drupal-org-cli"
else
    readonly CMD="ajust drupal-org-cli"
fi

# --- Output ---

# Shorten a path under HOME to ~/...
tilde() {
    echo "${1/#${HOME}/\~}"
}

# --- PHP ---

php_hint() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "Install PHP with: brew install php"
        return 0
    fi
    if command -v pacman >/dev/null 2>&1; then
        echo "Install PHP with: sudo pacman -S php"
        echo "Then enable the iconv extension: uncomment ';extension=iconv' in /etc/php/php.ini"
        return 0
    fi
    if command -v apt-get >/dev/null 2>&1; then
        echo "Install PHP with: sudo apt install php-cli php-xml php-curl php-mbstring"
        return 0
    fi
    echo "Install PHP 8.1 or later with your package manager."
}

require_php() {
    if ! command -v php >/dev/null 2>&1; then
        log_error "PHP 8.1 or later is required and was not found on PATH."
        php_hint >&2
        exit 1
    fi
    if ! php -r 'exit(PHP_VERSION_ID >= 80100 ? 0 : 1);' 2>/dev/null; then
        log_error "PHP 8.1 or later is required, found $(php -r 'echo PHP_VERSION;')."
        php_hint >&2
        exit 1
    fi
}

# --- Releases ---

# Print "<eligible tag> <sha256> <url> <newest tag> <newest date>" for the
# newest stable release with a drupalorg.phar asset that is at least
# MIN_AGE_DAYS old. Fields are "-" when no release qualifies.
resolve_release() {
    local releases
    releases="$(curl -fsSL -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO}/releases?per_page=30")"
    python3 -I -c '
import json, sys
from datetime import datetime, timedelta, timezone

min_age = timedelta(days=int(sys.argv[1]))
now = datetime.now(timezone.utc)
candidates = []
for release in json.loads(sys.stdin.read()):
    if release["draft"] or release["prerelease"] or not release["published_at"]:
        continue
    asset = next((a for a in release["assets"] if a["name"] == "drupalorg.phar"), None)
    if asset is None:
        continue
    published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    candidates.append((published, release["tag_name"], asset))
candidates.sort(key=lambda c: c[0], reverse=True)

newest = candidates[0] if candidates else None
eligible = next((c for c in candidates if now - c[0] >= min_age), None)
fields = ["-", "-", "-"]
if eligible is not None:
    digest = eligible[2].get("digest") or ""
    fields = [eligible[1], digest.removeprefix("sha256:") or "-", eligible[2]["browser_download_url"]]
fields += [newest[1], newest[0].date().isoformat()] if newest else ["-", "-"]
print(" ".join(fields))
' "${MIN_AGE_DAYS}" <<<"${releases}"
}

installed_version() {
    if [[ ! -x "${TARGET}" ]]; then
        return 0
    fi
    "${TARGET}" --version 2>/dev/null | awk '{ print $NF }'
}

# True when version $1 is lower than version $2 (dotted numeric versions).
version_lt() {
    python3 -I -c '
import sys
def key(v):
    return [int(p) if p.isdigit() else 0 for p in v.lstrip("v").split(".")]
sys.exit(0 if key(sys.argv[1]) < key(sys.argv[2]) else 1)
' "$1" "$2"
}

# --- Skill ---

# Copy skills/drupalorg-cli/ out of a phar into a directory. The phar path must
# end in .phar for PHP's phar:// stream to open it.
extract_skill() {
    local phar="$1" dest="$2"
    # shellcheck disable=SC2016 # PHP code, expanded by PHP.
    php -r '
$src = "phar://" . $argv[1] . "/skills/drupalorg-cli";
$dst = $argv[2];
$it = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($src, FilesystemIterator::SKIP_DOTS),
    RecursiveIteratorIterator::SELF_FIRST
);
foreach ($it as $file) {
    $target = $dst . "/" . substr($file->getPathname(), strlen($src) + 1);
    if ($file->isDir()) {
        is_dir($target) || mkdir($target, 0755, true) || exit(1);
        continue;
    }
    copy($file->getPathname(), $target) || exit(1);
}
' "${phar}" "${dest}"
}

is_native_discovery() {
    local tool_id="$1" native
    for native in "${TOOLS_NATIVE_DISCOVERY[@]}"; do
        if [[ "${tool_id}" == "${native}" ]]; then
            return 0
        fi
    done
    return 1
}

link_skill() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        if is_native_discovery "${tool_id}"; then
            continue
        fi

        local tool_dir="${TOOL_SKILLS_DIR[${tool_id}]}"
        local link="${tool_dir}/${SKILL_NAME}"
        mkdir -p "${tool_dir}"

        if [[ -L "${link}" ]] && [[ "$(readlink "${link}")" == "${SKILL_DIR}" ]]; then
            continue
        fi
        if [[ -e "${link}" ]] || [[ -L "${link}" ]]; then
            log_warn "${TOOL_LABEL[${tool_id}]}: skipped ${SKILL_NAME} (other content exists at ${link})"
            continue
        fi

        ln -s "${SKILL_DIR}" "${link}"
        log_success "${TOOL_LABEL[${tool_id}]}: linked ${SKILL_NAME} skill"
    done
}

# Install the skill bundled in a phar, replacing the previous copy.
install_skill() {
    local phar="$1"

    # A symlinked skill directory is managed elsewhere (a checkout, dotfiles).
    if [[ -L "${SKILL_DIR}" ]]; then
        log_warn "${SKILL_NAME} skill is managed elsewhere (${SKILL_DIR} -> $(readlink "${SKILL_DIR}")), skipping"
        return 0
    fi

    local staging
    staging="$(mktemp -d "${TMPDIR:-/tmp}/drupalorg-skill.XXXXXX")"
    if ! extract_skill "${phar}" "${staging}" || [[ "$(head -n 1 "${staging}/SKILL.md" 2>/dev/null)" != "---" ]]; then
        rm -rf "${staging}"
        log_warn "drupalorg ships no usable agent skill, skipping it"
        return 0
    fi

    mkdir -p "$(dirname "${SKILL_DIR}")"
    rm -rf "${SKILL_DIR}"
    mv "${staging}" "${SKILL_DIR}"
    chmod 0755 "${SKILL_DIR}"
    log_success "Agent skill installed: $(tilde "${SKILL_DIR}")"
    link_skill
}

remove_skill() {
    local tool_id
    for tool_id in "${!TOOL_SKILLS_DIR[@]}"; do
        local link="${TOOL_SKILLS_DIR[${tool_id}]}/${SKILL_NAME}"
        if [[ -L "${link}" ]] && [[ "$(readlink "${link}")" == "${SKILL_DIR}" ]]; then
            rm -f "${link}"
            log_success "${TOOL_LABEL[${tool_id}]}: removed ${SKILL_NAME} skill link"
        fi
    done

    if [[ -L "${SKILL_DIR}" ]]; then
        log_warn "${SKILL_NAME} skill is managed elsewhere (${SKILL_DIR} -> $(readlink "${SKILL_DIR}")), leaving it in place"
        return 0
    fi
    if [[ -d "${SKILL_DIR}" ]]; then
        rm -rf "${SKILL_DIR}"
        log_success "Removed agent skill: $(tilde "${SKILL_DIR}")"
    fi
}

# --- MCP ---

mcp_registered() {
    command -v claude >/dev/null 2>&1 || return 1
    python3 -I -c '
import json, sys
try:
    with open(sys.argv[1]) as fh:
        servers = json.load(fh).get("mcpServers") or {}
except (OSError, ValueError):
    sys.exit(1)
sys.exit(0 if sys.argv[2] in servers else 1)
' "${HOME}/.claude.json" "${MCP_NAME}"
}

add_mcp() {
    if ! command -v claude >/dev/null 2>&1; then
        log_error "Claude Code (claude) is not installed."
        exit 1
    fi
    if [[ ! -x "${TARGET}" ]]; then
        log_error "drupalorg is not installed. Run: ${CMD} install"
        exit 1
    fi
    if mcp_registered; then
        log_info "MCP server ${MCP_NAME} is already registered in Claude Code"
        return 0
    fi
    claude mcp add --scope user "${MCP_NAME}" -- "${TARGET}" mcp:serve >/dev/null
    log_success "Registered MCP server ${MCP_NAME} in Claude Code (user scope)"
}

remove_mcp() {
    if ! mcp_registered; then
        return 0
    fi
    claude mcp remove --scope user "${MCP_NAME}" >/dev/null
    log_success "Removed MCP server ${MCP_NAME} from Claude Code"
}

# --- Actions ---

install_latest() {
    local release tag digest url newest newest_date
    release="$(resolve_release)"
    read -r tag digest url newest newest_date <<<"${release}"

    if [[ "${tag}" == "-" ]]; then
        log_error "No drupalorg release is at least ${MIN_AGE_DAYS} days old yet (newest: ${newest}, ${newest_date})."
        exit 1
    fi
    if [[ "${digest}" == "-" ]]; then
        log_error "GitHub publishes no checksum for drupalorg ${tag}; refusing to install it."
        exit 1
    fi
    if [[ "${newest}" != "${tag}" ]]; then
        log_info "drupalorg ${newest} (${newest_date}) is newer than ${MIN_AGE_DAYS} days and is held back."
    fi

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/drupalorg.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT
    local phar="${tmpdir}/drupalorg.phar"

    local installed
    installed="$(installed_version)"
    if [[ -n "${installed}" ]] && ! version_lt "${installed}" "${tag}"; then
        log_success "drupalorg ${installed} is already up to date"
        if [[ ! -d "${SKILL_DIR}" ]]; then
            cp "${TARGET}" "${phar}"
            install_skill "${phar}"
        fi
        return 0
    fi

    log_info "Downloading drupalorg ${tag}"
    curl -fsSL -o "${phar}" "${url}"
    if ! python3 -I -c '
import hashlib, sys
with open(sys.argv[1], "rb") as fh:
    sys.exit(hashlib.sha256(fh.read()).hexdigest() != sys.argv[2])
' "${phar}" "${digest}"; then
        log_error "Checksum mismatch for drupalorg ${tag}; nothing installed."
        exit 1
    fi

    # The phar's requirement checker reports missing PHP extensions here.
    if ! php "${phar}" --version >/dev/null 2>&1; then
        php "${phar}" --version >&2 || true
        log_error "Your PHP cannot run drupalorg ${tag}; nothing installed."
        php_hint >&2
        exit 1
    fi

    mkdir -p "$(dirname "${TARGET}")"
    chmod 0755 "${phar}"
    install_skill "${phar}"
    mv -f "${phar}" "${TARGET}"
    log_success "drupalorg ${tag} installed: $(tilde "${TARGET}")"

    echo
    print_label "Next steps"
    print_faint "$(printf '  %-30s %s\n' \
        "drupalorg list" "Show the available commands" \
        "Restart your AI coding tools" "Load the drupalorg-cli agent skill" \
        "${CMD} mcp" "Optional: add the MCP server to Claude Code")"
}

show_status() {
    local release tag digest url newest newest_date
    release="$(resolve_release)"
    read -r tag digest url newest newest_date <<<"${release}"

    local installed rows
    installed="$(installed_version)"
    rows="Field\tValue"
    rows+="\nInstalled\t${installed:-not installed}"
    rows+="\nAvailable\t${tag} (releases at least ${MIN_AGE_DAYS} days old)"
    if [[ "${newest}" != "${tag}" ]]; then
        rows+="\nHeld back\t${newest} (published ${newest_date})"
    fi
    rows+="\nPHP\t$(php -r 'echo PHP_VERSION;') ($(command -v php))"
    if [[ -f "${SKILL_DIR}/SKILL.md" ]]; then
        rows+="\nAgent skill\t$(tilde "${SKILL_DIR}")"
    else
        rows+="\nAgent skill\tnot installed"
    fi
    if mcp_registered; then
        rows+="\nMCP server\tregistered in Claude Code"
    else
        rows+="\nMCP server\tnot registered"
    fi

    print_label "Drupal.org CLI"
    printf '%b\n' "${rows}" | render_table
    if [[ -z "${installed}" ]]; then
        print_faint "Install it with: ${CMD} install"
    fi
}

uninstall() {
    remove_mcp
    remove_skill
    if [[ -e "${TARGET}" ]]; then
        rm -f "${TARGET}"
        log_success "Removed $(tilde "${TARGET}")"
    fi
}

usage() {
    print_label "Drupal.org CLI"
    print_faint "Install and manage drupalorg, its agent skill and its Claude Code MCP server."
    echo
    printf '%s %s\n\n' "$(bold "Usage:")" "${CMD} <action>"
    printf '%b\n' "Action\tWhat it does" \
        "install\tInstall or update drupalorg and its agent skill" \
        "status\tShow versions, PHP, agent skill and MCP server state" \
        "uninstall\tRemove drupalorg, its agent skill and the MCP server" \
        "mcp\tAdd the drupalorg MCP server to Claude Code" \
        "mcp-remove\tRemove the drupalorg MCP server from Claude Code" | render_table
    print_faint "Requires PHP 8.1 or later. Releases younger than ${MIN_AGE_DAYS} days are skipped;
set DRUPALORG_MIN_AGE_DAYS=0 to install the newest one."
}

main() {
    local action="${1:-help}"

    case "${action}" in
        "" | help | -h | --help)
            usage
            return 0
            ;;
        install | status | uninstall | mcp | mcp-remove) ;;
        *)
            log_error "Unknown action '${action}'. Run '${CMD}' to list the actions."
            exit 2
            ;;
    esac

    if ! [[ "${MIN_AGE_DAYS}" =~ ^[0-9]+$ ]]; then
        log_error "DRUPALORG_MIN_AGE_DAYS must be a whole number of days, got '${MIN_AGE_DAYS}'."
        exit 2
    fi

    case "${action}" in
        uninstall)
            uninstall
            return 0
            ;;
        mcp-remove)
            remove_mcp
            return 0
            ;;
    esac

    require_php

    case "${action}" in
        install) install_latest ;;
        status) show_status ;;
        mcp) add_mcp ;;
    esac
}

main "$@"
