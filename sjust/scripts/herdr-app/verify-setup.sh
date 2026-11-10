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

# A stand-in for an open herdr-app window: it serves one request on the home's
# control socket, saves it to request.json and answers ok. Sets FAKE_WINDOW_PID.
FAKE_WINDOW_PID=""
fake_window() {
    local home="$1"
    local reply="${2:-ok}"
    rm -f "${home}/herdr-app.sock" "${home}/request.json"
    python3 -I - "${home}/herdr-app.sock" "${home}/request.json" "${reply}" <<'PY' &
import socket, sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(30)
conn, _ = server.accept()
with conn:
    request = conn.makefile().readline()
    open(sys.argv[2], "w").write(request)
    if sys.argv[3] == "ok":
        conn.sendall(b'{"ok":true}\n')
PY
    FAKE_WINDOW_PID=$!
    local waited=0
    while [[ ! -S "${home}/herdr-app.sock" ]] && (( waited < 50 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
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

    # The mods load assets only from the pack (or the app's own frame/), so an
    # upstream rename in Herdr's mods cannot break them silently.
    local ref
    # shellcheck disable=SC2016 # '${' and backticks are JavaScript template text, not shell.
    while IFS= read -r ref; do
        case "${ref}" in
            mods/sparkfabrik-*) ;;
            frame/*) continue ;;
            *) fail "a mod loads an asset outside the pack: ${ref}" ;;
        esac
        if [[ "${ref}" != *'${'* ]] && [[ ! -e "${PACK_DIR}/${ref}" ]]; then
            fail "a mod loads a missing asset: ${ref}"
        fi
        if [[ "${ref}" == *'${'* ]] && [[ ! -d "${PACK_DIR}/$(dirname "${ref}")" ]]; then
            fail "a mod loads assets from a missing folder: ${ref}"
        fi
    done < <(grep -hoE '["`](mods|frame)/[^"`]+["`]' "${PACK_DIR}"/mods/*/main.js | tr -d '"`' | sort -u)

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
    unset HERDR_APP_HOME XDG_DATA_HOME
    local app_home="${XDG_CONFIG_HOME}/herdr-app"

    # A herdr-app on this machine's PATH would count as an installed app; the
    # tests decide that themselves.
    local dir clean_path=""
    local -a path_dirs
    IFS=: read -ra path_dirs <<< "${PATH}"
    for dir in "${path_dirs[@]}"; do
        if [[ -x "${dir}/herdr-app" ]]; then
            continue
        fi
        clean_path="${clean_path:+${clean_path}:}${dir}"
    done
    export PATH="${clean_path}"
    local setup="${SCRIPT_DIR}/setup.sh"
    local output
    local pinned minimum
    pinned="$(tr -d '[:space:]' < "${PACK_DIR}/HERDR_APP_VERSION")"
    minimum="$(tr -d '[:space:]' < "${PACK_DIR}/HERDR_APP_MIN_VERSION")"
    # A stand-in herdr-app that reports a release: fake_app <version>.
    local fake_bin="${HOME}/fake-bin"
    mkdir -p "${fake_bin}"
    fake_app() {
        printf '#!/usr/bin/env bash\necho "herdr-app %s"\n' "$1" > "${fake_bin}/herdr-app"
        chmod +x "${fake_bin}/herdr-app"
    }

    check_pack

    log_info "Skipping cleanly when herdr-app is not installed..."
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "herdr-app is not installed" "install without herdr-app"
    [[ ! -e "${app_home}" ]] || fail "install created the herdr-app home"

    log_info "Creating the home of an app that is installed but was never opened..."
    # Herdr's Linux installer layout, found without PATH.
    local never_opened="${HOME}/never-opened"
    mkdir -p "${HOME}/.local/share/herdr-app"
    printf '#!/usr/bin/env bash\necho "herdr-app %s"\n' "${pinned}" > "${HOME}/.local/share/herdr-app/herdr-app"
    chmod +x "${HOME}/.local/share/herdr-app/herdr-app"
    output="$(HERDR_APP_HOME="${never_opened}" "${setup}" install 2>&1)"
    assert_contains "${output}" "Created the herdr-app home" "home created for an installed app"
    [[ -f "${never_opened}/layouts/sparkfabrik.json" ]] || fail "layout not installed in the new home"
    [[ "$(shared_layout "${never_opened}")" == "sparkfabrik" ]] || fail "layout not selected in the new home"

    log_info "Installing without selecting when the herdr-app version cannot be read..."
    rm -f "${HOME}/.local/share/herdr-app/herdr-app"
    local unknown="${HOME}/unknown-version"
    output="$(HERDR_APP_HOME="${unknown}" "${setup}" install 2>&1)"
    assert_contains "${output}" "Could not read the herdr-app version" "unknown version"
    [[ -f "${unknown}/layouts/sparkfabrik.json" ]] || fail "layout not installed with an unknown version"
    [[ ! -e "${unknown}/shared.json" ]] || fail "layout selected with an unknown version"
    rm -rf "${HOME}/.local/share/herdr-app"

    log_info "Skipping a herdr-app older than the minimum release..."
    fake_app 0.0.1
    export PATH="${fake_bin}:${clean_path}"
    local old_app="${HOME}/old-app"
    mkdir -p "${old_app}"
    output="$(HERDR_APP_HOME="${old_app}" "${setup}" install 2>&1)"
    assert_contains "${output}" "is older than ${minimum}" "older herdr-app"
    [[ ! -e "${old_app}/layouts/sparkfabrik.json" ]] || fail "layout installed on an older herdr-app"
    [[ ! -e "${old_app}/shared.json" ]] || fail "layout selected on an older herdr-app"

    log_info "Installing and selecting on the minimum release, without a drift warning..."
    fake_app "${minimum}"
    local min_app="${HOME}/min-app"
    mkdir -p "${min_app}"
    output="$(HERDR_APP_HOME="${min_app}" "${setup}" install 2>&1)"
    assert_contains "${output}" "SparkFabrik layout installed" "install on the minimum release"
    assert_not_contains "${output}" "this machine runs" "drift warning on an older release"
    [[ "$(shared_layout "${min_app}")" == "sparkfabrik" ]] || fail "layout not selected on the minimum release"

    log_info "Reading versions with a package revision or a pre-release suffix..."
    local suffix suffixed_app
    for suffix in "${minimum}-1" "${pinned}-beta"; do
        fake_app "${suffix}"
        suffixed_app="${HOME}/suffixed-app-${suffix}"
        mkdir -p "${suffixed_app}"
        output="$(HERDR_APP_HOME="${suffixed_app}" "${setup}" install 2>&1)"
        assert_not_contains "${output}" "is older than" "version ${suffix}"
        assert_contains "${output}" "SparkFabrik layout installed" "install on version ${suffix}"
    done
    fake_app "${pinned}"

    log_info "Accepting a home path with a trailing slash..."
    local slashed="${HOME}/slashed-app"
    mkdir -p "${slashed}"
    output="$(HERDR_APP_HOME="${slashed}/" SPARKDOCK_HERDR_LAYOUT_SELECT=0 "${setup}" install 2>&1)"
    assert_contains "${output}" "SparkFabrik layout installed" "home with a trailing slash"

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

    log_info "Ignoring hidden files and keeping extra files in a mod folder..."
    touch "${app_home}/mods/sparkfabrik-agents/.DS_Store"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "already up to date" "hidden file in a mod folder"
    echo "my notes" > "${app_home}/mods/sparkfabrik-agents/notes.txt"
    echo "// edited" >> "${app_home}/mods/sparkfabrik-agents/main.js"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "had files the pack does not ship" "extra file in a mod folder"
    ls "${app_home}"/.sparkdock-backup/mods/sparkfabrik-agents.*/notes.txt > /dev/null 2>&1 || fail "extra file not kept aside"
    [[ ! -e "${app_home}/mods/sparkfabrik-agents/notes.txt" ]] || fail "extra file left in the reinstalled mod"
    ! ls -d "${app_home}"/mods/sparkfabrik-agents.* > /dev/null 2>&1 || fail "backup left in mods/, where Herdr loads it"
    rm -rf "${app_home}/.sparkdock-backup"

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

    log_info "Not writing through a symlinked folder..."
    local linked="${HOME}/linked-home"
    mkdir -p "${linked}" "${HOME}/shared-mods"
    ln -s "${HOME}/shared-mods" "${linked}/mods"
    output="$(HERDR_APP_HOME="${linked}" "${setup}" install 2>&1)"
    assert_contains "${output}" "mods/sparkfabrik-agents is managed elsewhere" "install through a symlinked folder"
    [[ ! -e "${HOME}/shared-mods/sparkfabrik-agents" ]] || fail "install wrote through a symlinked folder"
    [[ -f "${linked}/layouts/sparkfabrik.json" ]] || fail "install skipped items outside the symlinked folder"

    log_info "Keeping a symlinked shared.json and its mode..."
    local kept="${HOME}/kept-home"
    mkdir -p "${kept}" "${HOME}/dotfiles"
    echo '{"layout":"main"}' > "${HOME}/dotfiles/shared.json"
    chmod 0640 "${HOME}/dotfiles/shared.json"
    ln -s "${HOME}/dotfiles/shared.json" "${kept}/shared.json"
    HERDR_APP_HOME="${kept}" "${setup}" install > /dev/null 2>&1
    [[ -L "${kept}/shared.json" ]] || fail "selection replaced a symlinked shared.json"
    [[ "$(shared_layout "${kept}")" == "sparkfabrik" ]] || fail "selection not written through the symlink"
    [[ "$(python3 -I -c 'import os, stat, sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "${HOME}/dotfiles/shared.json")" == "0o640" ]] || fail "selection changed the mode of shared.json"

    log_info "Warning when herdr-app is newer than the release the mods come from..."
    fake_app 99.0.0
    output="$("${setup}" install 2>&1)"
    assert_not_contains "${output}" "this machine runs" "no version warning when nothing was installed"
    echo '{}' > "${app_home}/layouts/sparkfabrik.json"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "this machine runs 99.0.0" "version warning"
    fake_app "${pinned}"
    echo '{}' > "${app_home}/layouts/sparkfabrik.json"
    output="$("${setup}" install 2>&1)"
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
    fake_window "${window_home}"
    output="$(HERDR_APP_HOME="${window_home}" "${setup}" install 2>&1)"
    wait "${FAKE_WINDOW_PID}" || true
    assert_contains "${output}" "in the open Herdr window" "select over the control socket"
    assert_contains "$(cat "${window_home}/request.json")" '"do": "layout.switch"' "control socket command"
    assert_contains "$(cat "${window_home}/request.json")" '"name": "sparkfabrik"' "control socket layout name"
    [[ ! -e "${window_home}/shared.json" ]] || fail "wrote shared.json while a window was open"
    [[ -e "${window_home}/${MARKER}" ]] || fail "window selection not recorded"

    log_info "Not writing shared.json when an open window fails to answer..."
    local mute="${WINDOW_HOME}-mute"
    mkdir -p "${mute}"
    fake_window "${mute}" silent
    output="$(HERDR_APP_HOME="${mute}" "${setup}" install 2>&1)"
    wait "${FAKE_WINDOW_PID}" || true
    assert_contains "${output}" "Could not select the SparkFabrik layout" "window that does not answer"
    [[ ! -e "${mute}/shared.json" ]] || fail "wrote shared.json behind an open window"
    [[ ! -e "${mute}/${MARKER}" ]] || fail "recorded a selection that failed"
    rm -rf "${mute}"

    log_info "Uninstalling switches an open window back to Herdr's layout..."
    echo '{"layout":"sparkfabrik"}' > "${window_home}/shared.json"
    fake_window "${window_home}"
    output="$(HERDR_APP_HOME="${window_home}" "${setup}" uninstall 2>&1)"
    wait "${FAKE_WINDOW_PID}" || true
    assert_contains "${output}" "Switched the open Herdr window back" "reset over the control socket"
    assert_contains "$(cat "${window_home}/request.json")" '"name": "main"' "reset layout name"

    log_info "Uninstalling keeps a layout the person chose..."
    echo '{"layout":"main"}' > "${quiet}/shared.json"
    output="$(HERDR_APP_HOME="${quiet}" "${setup}" uninstall 2>&1)"
    assert_not_contains "${output}" "its own layout" "uninstall with Herdr's layout chosen"
    [[ "$(shared_layout "${quiet}")" == "main" ]] || fail "uninstall changed the person's layout"

    log_info "Uninstalling removes only the pack and its layout choice..."
    echo '{"layout":"sparkfabrik","sidebar.width":268}' > "${app_home}/shared.json"
    output="$("${setup}" uninstall 2>&1)"
    assert_contains "${output}" "Herdr shows its own layout on the next start" "reset in shared.json"
    [[ -z "$(shared_layout "${app_home}")" ]] || fail "uninstall left the SparkFabrik layout selected"
    grep -q '"sidebar.width": *268' "${app_home}/shared.json" || fail "uninstall lost other shared.json keys"
    assert_contains "${output}" "Removed layouts/sparkfabrik.json" "uninstall"
    [[ ! -e "${app_home}/layouts/sparkfabrik.json" ]] || fail "layout left behind"
    [[ ! -e "${app_home}/themes/sparkfabrik.json" ]] || fail "theme left behind"
    [[ ! -e "${app_home}/mods/sparkfabrik-agents" ]] || fail "mod left behind"
    [[ -L "${app_home}/mods/sparkfabrik-pane" ]] || fail "uninstall removed a symlinked mod"
    [[ -d "${app_home}/mods/agents" ]] || fail "uninstall removed Herdr's own mod"
    [[ -d "${app_home}/mods/my-mod" ]] || fail "uninstall removed a personal mod"
    [[ -f "${app_home}/layouts/main.json" ]] || fail "uninstall removed Herdr's own layout"
    [[ ! -e "${app_home}/${MARKER}" ]] || fail "uninstall kept the selection marker"

    log_info "Keeping provisioning away after an uninstall, until an explicit install..."
    output="$("${setup}" provision 2>&1)"
    assert_contains "${output}" "it was removed with herdr-layout-uninstall" "provision after uninstall"
    [[ ! -e "${app_home}/layouts/sparkfabrik.json" ]] || fail "provisioning added the layout back"
    output="$("${setup}" install 2>&1)"
    assert_contains "${output}" "SparkFabrik layout installed" "explicit install after uninstall"
    output="$("${setup}" provision 2>&1)"
    assert_contains "${output}" "already up to date" "provision after an explicit install"

    log_info "Honoring HERDR_APP_HOME..."
    local other="${HOME}/other-home"
    mkdir -p "${other}"
    HERDR_APP_HOME="${other}" "${setup}" install > /dev/null 2>&1
    [[ -f "${other}/layouts/sparkfabrik.json" ]] || fail "HERDR_APP_HOME ignored"

    rm -rf "${temp_home}"
    log_success "herdr-app layout setup verification passed"
}

main "$@"
