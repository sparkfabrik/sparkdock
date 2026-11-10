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
# userlands, and python3 for JSON and the app's control socket.
#
# Usage: setup.sh install|provision|uninstall
#   install    add or update the layout (what `sjust herdr-layout-install` runs);
#              it also undoes an earlier uninstall
#   provision  the same for provisioning runs, except after an uninstall
#   uninstall  remove the layout and keep provisioning from adding it back

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

PACK_DIR="${SCRIPT_DIR}/sparkfabrik"
LAYOUT_NAME="sparkfabrik"
# The layout Herdr ships and shows by default.
HERDR_DEFAULT_LAYOUT="main"
# Written in the app home once the layout has been selected, so the selection
# happens once per home, existing installs included, and never again after.
SELECTED_MARKER=".sparkdock-layout-selected"
# Written by uninstall, so provisioning does not add the layout back. An
# explicit install removes it.
REMOVED_MARKER=".sparkdock-layout-removed"
# The herdr-app release the sparkfabrik-* mods were copied from (they are forks
# of Herdr's own mods, see README.md next to this script). Older releases lack
# APIs the mods use, so the layout needs this release or a later one.
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

# The herdr-app executable, whether or not it is on PATH: the macOS cask's
# bundle, Herdr's Linux installer, a distribution package. Prints nothing when
# none is found.
app_executable() {
    local path
    if command -v herdr-app &> /dev/null; then
        command -v herdr-app
        return 0
    fi
    for path in \
        "/Applications/Herdr.app/Contents/MacOS/Herdr" \
        "${HOME}/Applications/Herdr.app/Contents/MacOS/Herdr" \
        "${XDG_DATA_HOME:-${HOME}/.local/share}/herdr-app/herdr-app" \
        "/usr/bin/herdr-app"; do
        if [[ -x "${path}" ]]; then
            echo "${path}"
            return 0
        fi
    done
}

# True when herdr-app is installed, whether or not it has been opened yet.
app_installed() {
    [[ -n "$(app_executable)" ]] \
        || [[ -d "/Applications/Herdr.app" ]] \
        || [[ -d "${HOME}/Applications/Herdr.app" ]] \
        || [[ -d "${XDG_DATA_HOME:-${HOME}/.local/share}/herdr-app" ]]
}

# The installed herdr-app release ("0.1.15"), or nothing when it cannot be read.
app_version() {
    local executable
    executable="$(app_executable)"
    if [[ -z "${executable}" ]]; then
        return 0
    fi
    "${executable}" --version 2> /dev/null | awk '{ print $2 }' || true
}

forked_version() {
    tr -d '[:space:]' < "${FORKED_FROM_FILE}"
}

# Compare two dotted releases. Prints older, same or newer for $1 against $2.
compare_versions() {
    python3 -I -c '
import sys
def parts(v):
    return [int(p) for p in v.split(".") if p.isdigit()]
a, b = parts(sys.argv[1]), parts(sys.argv[2])
print("older" if a < b else "newer" if a > b else "same")
' "$1" "$2"
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

# Print the first symlink on the way from the app home to an item (the item
# itself or a folder above it), or nothing. A symlink means the content is
# managed elsewhere (a checkout, a dotfiles repo), so the script must not write
# through it.
symlink_on_path() {
    local home="$1"
    local item="$2"
    local path="${home}/${item}"
    while [[ "${path}" != "${home}" ]]; do
        if [[ -L "${path}" ]]; then
            echo "${path}"
            return 0
        fi
        path="$(dirname "${path}")"
    done
}

# The differences between a pack mod and its installed copy, ignoring hidden
# files (.DS_Store, editor state) and the files herdr-app generates. One line
# per difference, as `diff -rq` prints them.
mod_dir_differences() {
    local src="$1"
    local dest="$2"
    local excludes=(-x '.*')
    local name
    for name in "${GENERATED_FILES[@]}"; do
        excludes+=(-x "${name}")
    done
    diff -rq "${excludes[@]}" "${src}" "${dest}" 2>&1 || true
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
    local link
    link="$(symlink_on_path "${home}" "${item}")"
    if [[ -n "${link}" ]]; then
        log_warn "${item} is managed elsewhere (${link} -> $(readlink "${link}")), skipping"
        return 0
    fi

    mkdir -p "$(dirname "${dest}")"

    if [[ -d "${src}" ]]; then
        local differences=""
        if [[ -d "${dest}" ]]; then
            differences="$(mod_dir_differences "${src}" "${dest}")"
            if [[ -z "${differences}" ]]; then
                return 0
            fi
        fi
        # Files the pack does not have are someone's work: keep them aside.
        if [[ "${differences}" == *"Only in ${dest}"* ]]; then
            local aside
            aside="${dest}.sparkdock-$(date +%Y%m%d%H%M%S)"
            mv "${dest}" "${aside}"
            log_warn "${item} had files the pack does not ship; moved it to ${aside}"
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

# Switch the layout herdr-app shows. A running window owns its state, so it
# gets the switch over its control socket (herdr-app.sock in the home, one JSON
# line each way: the protocol of `herdr-app do`), which works even where the
# herdr-app CLI is not on PATH; the window saves the choice itself. Only when
# no window answers the connection does the choice go where herdr-app keeps it:
# key "layout" of shared.json, written through any symlink with its mode kept.
#
# Usage: switch_layout <home> select|reset. "select" shows the SparkFabrik
# layout; "reset" goes back to Herdr's own, and only when SparkFabrik is the one
# recorded. Prints window, file, none or failed.
switch_layout() {
    local home="$1"
    local mode="$2"
    if ! command -v python3 &> /dev/null; then
        echo "failed"
        return 0
    fi
    python3 -I - "${home}" "${mode}" "${LAYOUT_NAME}" "${HERDR_DEFAULT_LAYOUT}" <<'PY' || echo "failed"
import json, os, socket, stat, sys, tempfile

home, mode, ours, default = sys.argv[1:5]
path = os.path.join(home, "shared.json")

try:
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError
except (OSError, ValueError):
    print("failed")
    sys.exit(0)

if mode == "reset" and data.get("layout") != ours:
    print("none")
    sys.exit(0)

target = ours if mode == "select" else default
conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
conn.settimeout(10)
try:
    conn.connect(os.path.join(home, "herdr-app.sock"))
except OSError:
    conn.close()
    conn = None

if conn is not None:
    # A window answered: it owns the choice. Any error from here on is a
    # failure, never a reason to write a file the window would overwrite.
    try:
        with conn:
            request = {"do": "layout.switch", "args": {"name": target}}
            conn.sendall((json.dumps(request) + "\n").encode())
            reply = conn.makefile().readline()
        print("window" if json.loads(reply or "{}").get("ok") else "failed")
    except (OSError, ValueError):
        print("failed")
    sys.exit(0)

if mode == "select":
    data["layout"] = ours
else:
    # Without the key Herdr shows its own layout.
    data.pop("layout", None)
try:
    real = os.path.realpath(path)
    mode_bits = stat.S_IMODE(os.stat(real).st_mode) if os.path.exists(real) else 0o644
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real), prefix=".sparkdock.")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.chmod(tmp, mode_bits)
    os.replace(tmp, real)
    print("file")
except OSError:
    print("failed")
PY
}

# Make the SparkFabrik layout the one Herdr shows, once per app home: the marker
# file records it, so a person who switches back to Herdr's own layout keeps
# that choice on later runs. SPARKDOCK_HERDR_LAYOUT_SELECT=0 turns it off. The
# window takes the switch at once; the new mods load on its next start.
select_layout() {
    local home="$1"
    if [[ "${SPARKDOCK_HERDR_LAYOUT_SELECT:-1}" == "0" ]] || [[ -e "${home}/${SELECTED_MARKER}" ]]; then
        return 0
    fi

    case "$(switch_layout "${home}" select)" in
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
    local reason="$1"
    local home
    home="$(app_home)"

    if [[ "${reason}" == "provision" ]] && [[ -e "${home}/${REMOVED_MARKER}" ]]; then
        log_info "SparkFabrik layout skipped: it was removed with herdr-layout-uninstall"
        return 0
    fi

    # herdr-app creates its home on first launch, but provisioning installs the
    # app without opening it. Create the home for an installed app, so its first
    # start already shows the layout; skip only when the app is not there.
    if [[ ! -d "${home}" ]]; then
        if ! app_installed; then
            log_warn "herdr-app is not installed (no ${home}), skipping the SparkFabrik layout"
            return 0
        fi
        mkdir -p "${home}"
        log_info "Created the herdr-app home ${home} for its first start"
    fi

    # The mods use APIs of the release they were copied from: an older Herdr
    # would load the layout without some of its panels.
    local installed forked comparison=""
    installed="$(app_version)"
    forked="$(forked_version)"
    if [[ -n "${installed}" ]]; then
        comparison="$(compare_versions "${installed}" "${forked}")"
    fi
    if [[ "${comparison}" == "older" ]]; then
        log_warn "herdr-app ${installed} is older than ${forked}, which the SparkFabrik layout needs; update Herdr and a later run adds the layout"
        return 0
    fi

    rm -f "${home}/${REMOVED_MARKER}"

    local item
    INSTALL_CHANGED=0
    while IFS= read -r item; do
        install_item "${item}" "${home}"
    done < <(pack_items)

    if [[ -n "${comparison}" ]]; then
        select_layout "${home}"
    else
        log_warn "Could not read the herdr-app version, so the SparkFabrik layout was not selected; pick it in Herdr's Settings (Herdr ${forked} or later)"
    fi

    if (( INSTALL_CHANGED == 0 )); then
        log_info "SparkFabrik layout already up to date in ${home}"
        return 0
    fi
    log_success "SparkFabrik layout installed in ${home}"
    # Only when files changed, so routine provisioning runs stay quiet.
    if [[ "${comparison}" == "newer" ]]; then
        log_warn "The SparkFabrik mods come from herdr-app ${forked}, this machine runs ${installed}."
        log_warn "If a Herdr panel looks or behaves wrong, report it to the sparkdock maintainers."
    fi
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

    # Back to Herdr's own layout first, when SparkFabrik is the one shown.
    case "$(switch_layout "${home}" reset)" in
        window) log_success "Switched the open Herdr window back to its own layout" ;;
        file) log_success "Herdr shows its own layout on the next start" ;;
        none) ;;
        *) log_warn "Could not switch Herdr back to its own layout; pick it in Herdr's Settings" ;;
    esac

    local item dest link
    while IFS= read -r item; do
        dest="${home}/${item}"
        link="$(symlink_on_path "${home}" "${item}")"
        if [[ -n "${link}" ]]; then
            log_warn "${item} is managed elsewhere (${link} -> $(readlink "${link}")), leaving it in place"
            continue
        fi
        if [[ -e "${dest}" ]]; then
            rm -rf "${dest}"
            log_success "Removed ${item}"
        fi
    done < <(pack_items)

    # Provisioning keeps away until an explicit install; that install selects
    # the layout again.
    rm -f "${home}/${SELECTED_MARKER}"
    touch "${home}/${REMOVED_MARKER}"

    log_info "SparkFabrik layout removed from ${home}. Provisioning will not add it back; run herdr-layout-install to restore it."
}

# --- Main ---

main() {
    local action="${1:-install}"

    case "${action}" in
        install | provision)
            install "${action}"
            ;;
        uninstall)
            uninstall
            ;;
        *)
            log_error "Unknown action: ${action}. Use install, provision or uninstall."
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
