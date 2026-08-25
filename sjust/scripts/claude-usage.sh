#!/usr/bin/env bash
# claude-usage — install / upgrade / uninstall the upstream claude-usage tool
# (https://github.com/sparkfabrik/claude-usage). Invoked by the shared sjust/ajust
# recipes (sjust/recipes/shared/08-claude-usage.just); see those for usage.
#
# Install strategy, most-trusted source first:
#   1. Prefer the release-published install.sh asset (v0.6.0+) and verify it
#      against the release checksums.txt when a checksum for install.sh exists.
#   2. Fall back to the raw install.sh from the matching git ref for older
#      releases that do not publish the asset (cannot be verified — warns).
# A checksum MISMATCH always aborts; a missing/unavailable checksum only warns
# and proceeds, so older releases keep working.

set -euo pipefail

REPO="sparkfabrik/claude-usage"
RELEASES_URL="https://github.com/${REPO}/releases"
RAW_URL="https://raw.githubusercontent.com/${REPO}"

usage() {
    echo "Usage: claude-usage.sh {install [version]|uninstall}" >&2
    exit 2
}

# Normalize "1.2.3" -> "v1.2.3" and validate as a v-prefixed semver tag.
# Echoes the normalized tag; exits non-zero on invalid input.
_normalize_version() {
    local v="${1}"
    [[ "${v}" == v* ]] || v="v${v}"
    if [[ ! "${v}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid version: '${1}'. Expected a semver tag like v0.6.0" >&2
        return 1
    fi
    echo "${v}"
}

# Verify install.sh in ${dir} against checksums.txt in ${dir}.
# Returns 0 when verified, 2 when no checksum is available; aborts on mismatch.
_verify_installer() {
    local dir="${1}"
    local -a sha
    [[ -f "${dir}/checksums.txt" ]] || return 2
    grep -qE '[[:space:]]install\.sh$' "${dir}/checksums.txt" || return 2

    if command -v sha256sum >/dev/null 2>&1; then
        sha=(sha256sum)
    elif command -v shasum >/dev/null 2>&1; then
        sha=(shasum -a 256)
    else
        echo "⚠️  Neither sha256sum nor shasum found; cannot verify install.sh." >&2
        return 2
    fi

    if ( cd "${dir}" && "${sha[@]}" --ignore-missing -c checksums.txt >/dev/null 2>&1 ); then
        return 0
    fi
    echo "❌ install.sh checksum verification FAILED — aborting." >&2
    exit 1
}

# Download install.sh (and checksums.txt when present) into ${dir} for ${ref}.
# ${ref} is either "latest" or a v-prefixed tag. Echoes "asset" when the release
# asset was used, "raw" when it fell back to the raw git ref.
_fetch_installer() {
    local ref="${1}" dir="${2}" base raw_ref
    if [[ "${ref}" == "latest" ]]; then
        base="${RELEASES_URL}/latest/download"
    else
        base="${RELEASES_URL}/download/${ref}"
    fi

    if curl -fsSL -L -o "${dir}/install.sh" "${base}/install.sh" 2>/dev/null; then
        curl -fsSL -L -o "${dir}/checksums.txt" "${base}/checksums.txt" 2>/dev/null || true
        echo "asset"
        return 0
    fi

    # Raw fallback for older releases that do not publish the install.sh asset.
    raw_ref="${ref}"
    [[ "${raw_ref}" == "latest" ]] && raw_ref="main"
    if ! curl -fsSL -o "${dir}/install.sh" "${RAW_URL}/${raw_ref}/install.sh" 2>/dev/null; then
        echo "❌ Could not download install.sh from release assets or raw ref '${raw_ref}'." >&2
        exit 1
    fi
    echo "raw"
}

# Resolve the latest release tag from the github.com redirect rather than the
# API. Unauthenticated api.github.com calls are rate limited per IP, and CI
# runners share addresses, so the installer's own lookup answers 403 there and
# aborts the whole run. Echoes the tag; non-zero when it cannot be resolved.
_resolve_latest_tag() {
    local url
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${RELEASES_URL}/latest" 2>/dev/null)" || return 1
    [[ "${url}" =~ /tag/(v[0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}

cmd_install() {
    local version="${1:-}" ref pin_tag tmp src
    if [[ -n "${version}" ]]; then
        version="$(_normalize_version "${version}")"
        ref="${version}"
        pin_tag="${version}"
    else
        # Pin the resolved tag so the installer never has to ask the API, and
        # take the installer from that same release so the script and the
        # binaries it downloads always match. When the redirect cannot be read,
        # fall back to "latest" and let the installer do its own lookup, which
        # still works from an unthrottled address.
        pin_tag="$(_resolve_latest_tag)" || pin_tag=""
        ref="${pin_tag:-latest}"
    fi

    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand ${tmp} now so cleanup uses the real path
    trap "rm -rf '${tmp}'" EXIT

    src="$(_fetch_installer "${ref}" "${tmp}")"

    if [[ "${src}" == "asset" ]]; then
        if _verify_installer "${tmp}"; then
            echo "✅ install.sh checksum verified against checksums.txt."
        else
            echo "⚠️  No install.sh checksum published for this release — proceeding without verification."
        fi
    else
        echo "⚠️  install.sh is not a release asset for this version — using the unverifiable raw script."
    fi

    if [[ -n "${pin_tag}" ]]; then
        CLAUDE_USAGE_VERSION="${pin_tag}" bash "${tmp}/install.sh"
    else
        bash "${tmp}/install.sh"
    fi
}

cmd_uninstall() {
    local tmp src
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand ${tmp} now so cleanup uses the real path
    trap "rm -rf '${tmp}'" EXIT

    src="$(_fetch_installer "latest" "${tmp}")"
    if [[ "${src}" == "asset" ]]; then
        _verify_installer "${tmp}" >/dev/null || true
    fi
    bash "${tmp}/install.sh" --uninstall
}

main() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ curl is required but was not found in PATH" >&2
        exit 1
    fi
    case "${1:-}" in
        install) shift; cmd_install "${1:-}" ;;
        uninstall) cmd_uninstall ;;
        *) usage ;;
    esac
}

main "$@"
