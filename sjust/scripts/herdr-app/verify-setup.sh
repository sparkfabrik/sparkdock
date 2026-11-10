#!/usr/bin/env bash
set -euo pipefail

# Verify the SparkFabrik herdr-app layout setup without herdr-app: the pack is
# checked for consistency, then installed, reinstalled and removed under a
# temporary HOME, with a stubbed `herdr-app` for the version check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

PACK_DIR="${SCRIPT_DIR}/sparkfabrik"
# Mods that ship with herdr-app itself and that the layout may keep using.
HERDR_SHIPPED_MODS=(files changes)

fail() {
    log_error "$1"
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local what="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        fail "${what}: expected output to contain '${needle}'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local what="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        fail "${what}: expected output not to contain '${needle}'"
    fi
}

check_pack() {
    log_info "Checking the pack..."

    local file
    for file in "${PACK_DIR}"/layouts/*.json "${PACK_DIR}"/themes/*.json; do
        python3 -m json.tool "${file}" > /dev/null || fail "invalid JSON: ${file}"
    done

    # Every mod the layout names is in the pack or ships with herdr-app.
    local mod
    while IFS= read -r mod; do
        if [[ -d "${PACK_DIR}/mods/${mod}" ]]; then
            continue
        fi
        local shipped
        local found=false
        for shipped in "${HERDR_SHIPPED_MODS[@]}"; do
            if [[ "${mod}" == "${shipped}" ]]; then
                found=true
            fi
        done
        if [[ "${found}" != true ]]; then
            fail "the layout uses mod '${mod}', which is neither in the pack nor shipped with herdr-app"
        fi
    done < <(python3 - "${PACK_DIR}/layouts/sparkfabrik.json" <<'PY'
import json, sys

def walk(node):
    content = node.get("content")
    if isinstance(content, dict):
        if content.get("mod"):
            yield content["mod"]
        header = (content.get("pane") or {}).get("header") or {}
        mod = (header.get("content") or {}).get("mod")
        if mod:
            yield mod
    for child in node.get("children", []):
        yield from walk(child)

for name in sorted(set(walk(json.load(open(sys.argv[1]))))):
    print(name)
PY
)

    # The layout names the two themes the pack ships.
    local theme
    for theme in sparkfabrik sparkfabrik-light; do
        [[ -f "${PACK_DIR}/themes/${theme}.json" ]] || fail "missing theme: ${theme}"
    done

    # Generated editor files must not be shipped.
    if find "${PACK_DIR}" \( -name gpui-kit.d.ts -o -name jsconfig.json \) | grep -q .; then
        fail "the pack contains files herdr-app generates (gpui-kit.d.ts, jsconfig.json)"
    fi

    # Every bundled font has its license next to it.
    local fonts
    for fonts in "${PACK_DIR}"/mods/*/fonts; do
        if [[ ! -d "${fonts}" ]]; then
            continue
        fi
        ls "${fonts}"/LICENSE-* > /dev/null 2>&1 || fail "fonts without a license: ${fonts}"
    done
}

main() {
    local temp_home
    temp_home=$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-herdr-app-verify.XXXXXX")
    export HOME="${temp_home}"
    export XDG_CONFIG_HOME="${HOME}/.config"
    unset HERDR_APP_HOME
    local app_home="${XDG_CONFIG_HOME}/herdr-app"
    local setup="${SCRIPT_DIR}/setup.sh"
    local output

    check_pack

    log_info "Skipping cleanly when herdr-app is not installed..."
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "herdr-app home not found" "install without herdr-app"
    [[ ! -e "${app_home}" ]] || fail "install created the herdr-app home"

    log_info "Installing into a herdr-app home..."
    mkdir -p "${app_home}/mods/agents" "${app_home}/mods/my-mod" "${app_home}/layouts"
    echo '{"id":"root"}' > "${app_home}/layouts/main.json"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "SparkFabrik layout installed" "first install"
    local item
    while IFS= read -r item; do
        [[ -e "${app_home}/${item}" ]] || fail "not installed: ${item}"
    done < <(cd "${PACK_DIR}" && find layouts themes -type f && find mods -mindepth 1 -maxdepth 1 -type d)

    log_info "Reinstalling is a no-op, even with the files herdr-app generates..."
    touch "${app_home}/mods/sparkfabrik-agents/gpui-kit.d.ts" "${app_home}/mods/sparkfabrik-agents/jsconfig.json"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "already up to date" "second install"

    log_info "Restoring files changed by hand..."
    echo '{}' > "${app_home}/layouts/sparkfabrik.json"
    echo "// edited" >> "${app_home}/mods/sparkfabrik-tabs/main.js"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "Installed layouts/sparkfabrik.json" "restore layout"
    assert_contains "${output}" "Installed mods/sparkfabrik-tabs" "restore mod"
    cmp -s "${PACK_DIR}/layouts/sparkfabrik.json" "${app_home}/layouts/sparkfabrik.json" || fail "layout not restored"

    log_info "Leaving symlinked items alone..."
    local elsewhere="${HOME}/elsewhere-pane"
    mkdir -p "${elsewhere}"
    rm -rf "${app_home}/mods/sparkfabrik-pane"
    ln -s "${elsewhere}" "${app_home}/mods/sparkfabrik-pane"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "managed elsewhere" "install over a symlink"
    [[ -L "${app_home}/mods/sparkfabrik-pane" ]] || fail "install replaced a symlinked mod"

    log_info "Warning when herdr-app is not the release the mods come from..."
    local fake_bin="${HOME}/fake-bin"
    mkdir -p "${fake_bin}"
    printf '#!/usr/bin/env bash\necho "herdr-app 99.0.0"\n' > "${fake_bin}/herdr-app"
    chmod +x "${fake_bin}/herdr-app"
    output="$(PATH="${fake_bin}:${PATH}" "${setup}" install 2>&1)"
    assert_contains "${output}" "this machine runs 99.0.0" "version warning"
    printf '#!/usr/bin/env bash\necho "herdr-app %s"\n' "$(tr -d '[:space:]' < "${PACK_DIR}/HERDR_APP_VERSION")" > "${fake_bin}/herdr-app"
    output="$(PATH="${fake_bin}:${PATH}" "${setup}" install 2>&1)"
    assert_not_contains "${output}" "this machine runs" "no version warning on the pinned release"

    log_info "Uninstalling removes only the pack..."
    output="$("${setup}" uninstall 2>&1)"
    assert_contains "${output}" "Removed layouts/sparkfabrik.json" "uninstall"
    [[ ! -e "${app_home}/layouts/sparkfabrik.json" ]] || fail "layout left behind"
    [[ ! -e "${app_home}/themes/sparkfabrik.json" ]] || fail "theme left behind"
    [[ ! -e "${app_home}/mods/sparkfabrik-agents" ]] || fail "mod left behind"
    [[ -L "${app_home}/mods/sparkfabrik-pane" ]] || fail "uninstall removed a symlinked mod"
    [[ -d "${app_home}/mods/agents" ]] || fail "uninstall removed Herdr's own mod"
    [[ -d "${app_home}/mods/my-mod" ]] || fail "uninstall removed a personal mod"
    [[ -f "${app_home}/layouts/main.json" ]] || fail "uninstall removed Herdr's own layout"

    log_info "Honoring HERDR_APP_HOME..."
    local other="${HOME}/other-home"
    mkdir -p "${other}"
    HERDR_APP_HOME="${other}" "${setup}" install > /dev/null 2>&1
    [[ -f "${other}/layouts/sparkfabrik.json" ]] || fail "HERDR_APP_HOME ignored"

    rm -rf "${temp_home}"
    log_success "herdr-app layout setup verification passed"
}

main "$@"
