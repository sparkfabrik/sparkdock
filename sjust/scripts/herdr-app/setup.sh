#!/usr/bin/env bash
set -euo pipefail

# Install the SparkFabrik layout for the Herdr desktop app (herdr-app).
#
# The layout ships as files herdr-app reads from its home: a layout, a light and
# a dark theme (the person's Appearance setting picks one), and the mods the
# layout draws with, named sparkfabrik-*. It also selects the layout, once per
# app home and existing installs included; later runs only keep the files
# current, so a person who switches back to Herdr's own layout keeps that
# choice. Both provisioners call this script (sparkdock on macOS, sf-toolbox on
# Linux), so it sticks to bash plus tools that behave the same on BSD and GNU
# userlands.
#
# Usage: setup.sh [install|uninstall]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

PACK_DIR="${SCRIPT_DIR}/sparkfabrik"
LAYOUT_NAME="sparkfabrik"
# Written in the app home once the layout has been selected, so the selection
# happens once per home, existing installs included, and never again after.
SELECTED_MARKER=".sparkdock-layout-selected"
# The herdr-app release the sparkfabrik-* mods were copied from (they are forks
# of Herdr's own mods, see README.md next to this script).
FORKED_FROM_FILE="${PACK_DIR}/HERDR_APP_VERSION"
# Files herdr-app writes into every mod folder for editors. They are not part of
# the pack, so they neither count as a change nor get shipped.
GENERATED_FILES=(gpui-kit.d.ts jsconfig.json)

# --- Helpers ---

# herdr-app's home, resolved the way the app does on every OS: $HERDR_APP_HOME,
# else $XDG_CONFIG_HOME/herdr-app, else ~/.config/herdr-app.
app_home() {
    if [[ -n "${HERDR_APP_HOME:-}" ]]; then
        echo "${HERDR_APP_HOME}"
        return 0
    fi
    echo "${XDG_CONFIG_HOME:-${HOME}/.config}/herdr-app"
}

# Every path the pack installs, relative to the app home: the layout and theme
# files, and one directory per mod.
pack_items() {
    local path
    for path in "${PACK_DIR}"/layouts/* "${PACK_DIR}"/themes/*; do
        if [[ -f "${path}" ]]; then
            echo "${path#"${PACK_DIR}/"}"
        fi
    done
    for path in "${PACK_DIR}"/mods/*; do
        if [[ -d "${path}" ]]; then
            echo "${path#"${PACK_DIR}/"}"
        fi
    done
}

# True when the installed mod directory matches the pack, ignoring the files
# herdr-app generates in it.
same_mod_dir() {
    local src="$1"
    local dest="$2"
    local excludes=()
    local name
    for name in "${GENERATED_FILES[@]}"; do
        excludes+=(-x "${name}")
    done
    diff -rq "${excludes[@]}" "${src}" "${dest}" > /dev/null 2>&1
}

# How many pack items the last install wrote.
INSTALL_CHANGED=0

# Copy one pack item into the app home, counting it in INSTALL_CHANGED when it
# wrote something.
install_item() {
    local item="$1"
    local home="$2"
    local src="${PACK_DIR}/${item}"
    local dest="${home}/${item}"

    # A symlink means the item is managed elsewhere (a checkout, a dotfiles
    # repo). Writing through it would overwrite content this script does not own.
    if [[ -L "${dest}" ]]; then
        log_warn "${item} is managed elsewhere (${dest} -> $(readlink "${dest}")), skipping"
        return 0
    fi

    mkdir -p "$(dirname "${dest}")"

    if [[ -d "${src}" ]]; then
        if [[ -d "${dest}" ]] && same_mod_dir "${src}" "${dest}"; then
            return 0
        fi
        rm -rf "${dest}"
        cp -R "${src}" "${dest}"
        INSTALL_CHANGED=$((INSTALL_CHANGED + 1))
        log_success "Installed ${item}"
        return 0
    fi

    if [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
        return 0
    fi
    local tmpfile
    tmpfile="$(mktemp "$(dirname "${dest}")/.sparkdock.XXXXXX")"
    cp "${src}" "${tmpfile}"
    chmod 0644 "${tmpfile}"
    mv "${tmpfile}" "${dest}"
    INSTALL_CHANGED=$((INSTALL_CHANGED + 1))
    log_success "Installed ${item}"
}

# Warn when the installed herdr-app is not the release the mods were copied
# from: Herdr's own mods may have changed since, and the forks need a look.
check_forked_version() {
    local forked installed
    if [[ ! -f "${FORKED_FROM_FILE}" ]] || ! command -v herdr-app &> /dev/null; then
        return 0
    fi
    forked="$(tr -d '[:space:]' < "${FORKED_FROM_FILE}")"
    installed="$(herdr-app --version 2> /dev/null | awk '{ print $2 }')" || true
    if [[ -z "${installed}" ]] || [[ "${installed}" == "${forked}" ]]; then
        return 0
    fi
    log_warn "The SparkFabrik mods come from herdr-app ${forked}, this machine runs ${installed}."
    log_warn "If a Herdr panel looks or behaves wrong, report it to the sparkdock maintainers."
}

# Make the SparkFabrik layout the one Herdr shows, once per app home: the marker
# file records it, so a person who switches back to Herdr's own layout keeps
# that choice on later runs. SPARKDOCK_HERDR_LAYOUT_SELECT=0 turns it off.
#
# A running window owns its state, so it gets the switch over its control
# socket (herdr-app.sock in the home, one JSON line each way: the protocol of
# `herdr-app do`), which works even where the herdr-app CLI is not on PATH. The
# window saves the choice itself; the new mods load on its next start. With no
# window, the choice goes where herdr-app keeps it: key "layout" of shared.json.
select_layout() {
    local home="$1"
    if [[ "${SPARKDOCK_HERDR_LAYOUT_SELECT:-1}" == "0" ]] || [[ -e "${home}/${SELECTED_MARKER}" ]]; then
        return 0
    fi
    if ! command -v python3 &> /dev/null; then
        log_warn "python3 not found; pick the SparkFabrik layout in Herdr's Settings"
        return 0
    fi

    local outcome
    outcome="$(python3 -I - "${home}" "${LAYOUT_NAME}" <<'PY'
import json, os, socket, sys, tempfile

home, name = sys.argv[1], sys.argv[2]

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(10)
        conn.connect(os.path.join(home, "herdr-app.sock"))
        request = {"do": "layout.switch", "args": {"name": name}}
        conn.sendall((json.dumps(request) + "\n").encode())
        reply = conn.makefile().readline()
    print("window" if json.loads(reply or "{}").get("ok") else "window-failed")
    sys.exit(0)
except (OSError, ValueError):
    pass

path = os.path.join(home, "shared.json")
data = {}
try:
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError
    data["layout"] = name
    fd, tmp = tempfile.mkstemp(dir=home, prefix=".sparkdock.")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, path)
    print("file")
except (OSError, ValueError):
    print("file-failed")
PY
)" || outcome="failed"

    case "${outcome}" in
        window) log_success "Selected the SparkFabrik layout in the open Herdr window" ;;
        file) log_success "Selected the SparkFabrik layout for the next Herdr start" ;;
        *)
            # No marker: the next run tries again.
            log_warn "Could not select the SparkFabrik layout; pick it in Herdr's Settings"
            return 0
            ;;
    esac
    touch "${home}/${SELECTED_MARKER}"
}

# --- Install ---

install() {
    local home
    home="$(app_home)"

    # herdr-app creates its home on first launch. Without it the app is not
    # installed (or never opened), which is fine: there is nothing to style.
    if [[ ! -d "${home}" ]]; then
        log_warn "herdr-app home not found (${home}), skipping the SparkFabrik layout"
        return 0
    fi

    local item
    INSTALL_CHANGED=0
    while IFS= read -r item; do
        install_item "${item}" "${home}"
    done < <(pack_items)

    check_forked_version

    select_layout "${home}"

    if (( INSTALL_CHANGED == 0 )); then
        log_info "SparkFabrik layout already up to date in ${home}"
        return 0
    fi
    log_success "SparkFabrik layout installed in ${home}"
    log_info "Restart Herdr to load it. The SparkFabrik layout is in Settings, where Appearance chooses light or dark."
}

# --- Uninstall ---

uninstall() {
    local home
    home="$(app_home)"
    if [[ ! -d "${home}" ]]; then
        log_info "herdr-app home not found (${home}), nothing to remove"
        return 0
    fi

    local item dest
    while IFS= read -r item; do
        dest="${home}/${item}"
        if [[ -L "${dest}" ]]; then
            log_warn "${item} is managed elsewhere (${dest} -> $(readlink "${dest}")), leaving it in place"
            continue
        fi
        if [[ -e "${dest}" ]]; then
            rm -rf "${dest}"
            log_success "Removed ${item}"
        fi
    done < <(pack_items)

    # A later install selects the layout again.
    rm -f "${home}/${SELECTED_MARKER}"

    # herdr-app falls back to its own layout when the selected one is gone.
    log_info "SparkFabrik layout removed. Herdr switches back to its own layout on the next start."
}

# --- Main ---

main() {
    local action="${1:-install}"

    case "${action}" in
        install)
            install
            ;;
        uninstall)
            uninstall
            ;;
        *)
            log_error "Unknown action: ${action}. Use install or uninstall."
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
