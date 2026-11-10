#!/usr/bin/env bash
set -euo pipefail

# Verify the SparkFabrik herdr-app layout setup without herdr-app: the pack is
# checked for consistency, then installed, reinstalled and removed under a
# temporary HOME, with a stubbed `herdr-app` for the version check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

PACK_DIR="${SCRIPT_DIR}/sparkfabrik"
MARKER=".sparkdock-layout-selected"
# The fake window's home sits under /tmp (socket paths are short); removed on exit.
WINDOW_HOME=""
trap 'if [[ -n "${WINDOW_HOME}" ]]; then rm -rf "${WINDOW_HOME}"; fi' EXIT
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

# The layout herdr-app will show, as recorded in a home's shared.json.
shared_layout() {
    python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1])).get("layout", ""))' "$1/shared.json"
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
    echo '{"layout":"main","sidebar.width":268}' > "${app_home}/shared.json"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "SparkFabrik layout installed" "first install"
    assert_contains "${output}" "for the next Herdr start" "first install selects the layout"
    [[ "$(shared_layout "${app_home}")" == "sparkfabrik" ]] || fail "first install did not select the layout"
    grep -q '"sidebar.width": *268' "${app_home}/shared.json" || fail "selecting the layout lost other shared.json keys"
    [[ -e "${app_home}/${MARKER}" ]] || fail "selection not recorded"
    local item
    while IFS= read -r item; do
        [[ -e "${app_home}/${item}" ]] || fail "not installed: ${item}"
    done < <(cd "${PACK_DIR}" && find layouts themes -type f && find mods -mindepth 1 -maxdepth 1 -type d)

    log_info "Reinstalling is a no-op, even with the files herdr-app generates..."
    touch "${app_home}/mods/sparkfabrik-agents/gpui-kit.d.ts" "${app_home}/mods/sparkfabrik-agents/jsconfig.json"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "already up to date" "second install"

    log_info "Restoring files changed by hand, keeping the person's layout choice..."
    echo '{"layout":"main"}' > "${app_home}/shared.json"
    echo '{}' > "${app_home}/layouts/sparkfabrik.json"
    echo "// edited" >> "${app_home}/mods/sparkfabrik-tabs/main.js"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "Installed layouts/sparkfabrik.json" "restore layout"
    assert_contains "${output}" "Installed mods/sparkfabrik-tabs" "restore mod"
    cmp -s "${PACK_DIR}/layouts/sparkfabrik.json" "${app_home}/layouts/sparkfabrik.json" || fail "layout not restored"
    [[ "$(shared_layout "${app_home}")" == "main" ]] || fail "a later run overrode the person's layout choice"

    log_info "Selecting the layout once on an existing install..."
    rm -f "${app_home}/${MARKER}"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "Selected the SparkFabrik layout" "existing install gets selected"
    [[ "$(shared_layout "${app_home}")" == "sparkfabrik" ]] || fail "existing install not selected"
    echo '{"layout":"main"}' > "${app_home}/shared.json"
    output="$("${setup}" install 2>&1)"
    assert_not_contains "${output}" "Selected the SparkFabrik layout" "existing install selected twice"
    [[ "$(shared_layout "${app_home}")" == "main" ]] || fail "existing install selected twice"

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

    log_info "Not selecting the layout with SPARKDOCK_HERDR_LAYOUT_SELECT=0..."
    local quiet="${HOME}/quiet-home"
    mkdir -p "${quiet}"
    HERDR_APP_HOME="${quiet}" SPARKDOCK_HERDR_LAYOUT_SELECT=0 "${setup}" install > /dev/null 2>&1
    [[ -f "${quiet}/layouts/sparkfabrik.json" ]] || fail "layout not installed with the selection off"
    [[ ! -e "${quiet}/shared.json" ]] || fail "layout selected with SPARKDOCK_HERDR_LAYOUT_SELECT=0"
    [[ ! -e "${quiet}/${MARKER}" ]] || fail "selection recorded with SPARKDOCK_HERDR_LAYOUT_SELECT=0"

    log_info "Selecting the layout in an open window over its control socket..."
    # A short path: Unix socket paths are limited to about 100 bytes.
    WINDOW_HOME="$(mktemp -d /tmp/sdh.XXXXXX)"
    local window_home="${WINDOW_HOME}"
    python3 -I - "${window_home}/herdr-app.sock" "${window_home}/request.json" <<'PY' &
import socket, sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(30)
conn, _ = server.accept()
with conn:
    request = conn.makefile().readline()
    open(sys.argv[2], "w").write(request)
    conn.sendall(b'{"ok":true}\n')
PY
    local server_pid=$!
    local waited=0
    while [[ ! -S "${window_home}/herdr-app.sock" ]] && (( waited < 50 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    output="$(HERDR_APP_HOME="${window_home}" "${setup}" install 2>&1)"
    wait "${server_pid}" || true
    assert_contains "${output}" "in the open Herdr window" "select over the control socket"
    assert_contains "$(cat "${window_home}/request.json")" '"do": "layout.switch"' "control socket command"
    assert_contains "$(cat "${window_home}/request.json")" '"name": "sparkfabrik"' "control socket layout name"
    [[ ! -e "${window_home}/shared.json" ]] || fail "wrote shared.json while a window was open"
    [[ -e "${window_home}/${MARKER}" ]] || fail "window selection not recorded"

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
    [[ ! -e "${app_home}/${MARKER}" ]] || fail "uninstall kept the selection marker"

    log_info "Honoring HERDR_APP_HOME..."
    local other="${HOME}/other-home"
    mkdir -p "${other}"
    HERDR_APP_HOME="${other}" "${setup}" install > /dev/null 2>&1
    [[ -f "${other}/layouts/sparkfabrik.json" ]] || fail "HERDR_APP_HOME ignored"

    rm -rf "${temp_home}"
    log_success "herdr-app layout setup verification passed"
}

main "$@"
