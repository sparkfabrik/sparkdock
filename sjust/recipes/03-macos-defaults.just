# vim: set ft=make :
#
# macOS system defaults — declarative, idempotent application of curated
# developer defaults. See config/macos/defaults.yml for the data, README for
# user-facing usage. Recipes use positional arguments per AGENTS.md.

# `sparkdock_path` is shared across recipes and defined in 00-default.just.
config_file := sparkdock_path + "/config/macos/defaults.yml"
user_overrides := "${HOME}/.local/spark/macos-defaults/overrides.yml"
snapshots_root := "${HOME}/.local/spark/macos-defaults/snapshots"

# Apply or preview macOS defaults.
#   macos-defaults                       # apply (default)
#   macos-defaults dry-run               # preview, never exits non-zero on drift
#   macos-defaults dry-run strict        # preview, exit 2 if any drift exists
#   macos-defaults dry-run "" verbose    # preview, also print unchanged settings
[group('macos')]
[doc('Apply or preview the curated macOS defaults. Modes: apply (default), dry-run [strict] [verbose].')]
macos-defaults $mode="apply" $strict="" $verbose="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ sparkdock_path }}/sjust/libs/libcolors.sh"

    config_file="{{ config_file }}"
    user_overrides="{{ user_overrides }}"
    snapshots_root="{{ snapshots_root }}"

    case "${mode}" in
        apply|dry-run) ;;
        *)
            echo "${red}Error:${normal} unknown mode '${mode}'. Valid: apply, dry-run." >&2
            exit 2
            ;;
    esac

    if ! command -v yq >/dev/null 2>&1; then
        echo "${red}Error:${normal} yq is required. Install with: brew install yq" >&2
        exit 1
    fi

    if [[ ! -f "${config_file}" ]]; then
        echo "${red}Error:${normal} curated defaults missing at ${config_file}" >&2
        exit 1
    fi

    merged="$(mktemp -t macos-defaults.XXXXXX)"
    trap 'rm -f "${merged}"' EXIT

    if [[ -f "${user_overrides}" ]]; then
        if ! yq eval '.' "${user_overrides}" >/dev/null 2>&1; then
            echo "${red}Error:${normal} ${user_overrides} is not valid YAML." >&2
            yq eval '.' "${user_overrides}" 2>&1 | head -n 5 >&2 || true
            exit 1
        fi
        # shellcheck disable=SC2016 # $i is a yq variable, not bash
        yq eval-all '. as $i ireduce ({}; . *+ $i)' "${config_file}" "${user_overrides}" > "${merged}"
    else
        cp "${config_file}" "${merged}"
    fi

    # Render every entry as one TSV row: id\tdomain\tkey\ttype\tvalue\trequires_csv
    mapfile -t rows < <(yq eval '
        . | to_entries | .[] |
        [.key, .value.domain, .value.key, .value.type, .value.value, ((.value.requires // []) | join(","))]
        | @tsv
    ' "${merged}")

    declare -a to_write
    declare -A touched_domains
    drift_count=0

    expand_home() {
        local v="$1"
        v="${v//\$\{HOME\}/${HOME}}"
        v="${v//\$HOME/${HOME}}"
        printf '%s' "${v}"
    }

    normalize_desired() {
        local type="$1" value="$2"
        case "${type}" in
            bool) [[ "${value}" == "true" ]] && printf '1' || printf '0' ;;
            *)    printf '%s' "${value}" ;;
        esac
    }

    for row in "${rows[@]}"; do
        IFS=$'\t' read -r id domain key type desired_raw requires_csv <<<"${row}"

        if [[ "${type}" == "string" ]]; then
            desired="$(expand_home "${desired_raw}")"
        else
            desired="${desired_raw}"
        fi
        desired_norm="$(normalize_desired "${type}" "${desired}")"

        current="$(defaults read "${domain}" "${key}" 2>/dev/null || printf '__UNSET__')"

        if [[ "${current}" == "__UNSET__" ]]; then
            relation="+"
            drift_count=$((drift_count + 1))
            to_write+=("${id}")
            touched_domains["${domain}"]=1
        elif [[ "${current}" == "${desired_norm}" || "${current}" == "${desired}" ]]; then
            relation="="
        else
            relation="±"
            drift_count=$((drift_count + 1))
            to_write+=("${id}")
            touched_domains["${domain}"]=1
        fi

        case "${relation}" in
            "=")
                if [[ "${verbose}" == "verbose" ]]; then
                    echo "${dim}= ${id}: ${current}${normal}"
                fi
                ;;
            "+")
                echo "${green}+${normal} ${id}: ${dim}<unset>${normal} → ${green}${desired_norm}${normal}"
                ;;
            "±")
                echo "${yellow}±${normal} ${id}: ${red}${current}${normal} → ${green}${desired_norm}${normal}"
                ;;
        esac
    done

    echo
    if [[ ${drift_count} -eq 0 ]]; then
        echo "${green}No drift — nothing to do.${normal}"
        exit 0
    fi
    echo "${bold}${drift_count} setting(s) drifted from desired.${normal}"

    if [[ "${mode}" == "dry-run" ]]; then
        [[ "${strict}" == "strict" ]] && exit 2
        exit 0
    fi

    # Apply path: snapshot, write, restart, prune.
    ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    snapshot_dir="${snapshots_root}/${ts}"
    mkdir -p "${snapshot_dir}"
    : > "${snapshot_dir}/manifest.txt"
    for d in "${!touched_domains[@]}"; do
        defaults export "${d}" "${snapshot_dir}/${d}.plist" 2>/dev/null || true
        echo "${d}" >> "${snapshot_dir}/manifest.txt"
    done
    ln -sfn "${ts}" "${snapshots_root}/latest"
    echo "${dim}Snapshot: ${snapshot_dir}${normal}"

    declare -A restart_apps
    declare -A row_lookup
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r id _rest <<<"${row}"
        row_lookup["${id}"]="${row}"
    done

    for id in "${to_write[@]}"; do
        IFS=$'\t' read -r _id domain key type desired_raw requires_csv <<<"${row_lookup[${id}]}"
        if [[ "${type}" == "string" ]]; then
            desired="$(expand_home "${desired_raw}")"
        else
            desired="${desired_raw}"
        fi
        case "${type}" in
            bool)
                if [[ "${desired}" == "true" ]]; then
                    defaults write "${domain}" "${key}" -bool true
                else
                    defaults write "${domain}" "${key}" -bool false
                fi
                ;;
            int)    defaults write "${domain}" "${key}" -int "${desired}" ;;
            float)  defaults write "${domain}" "${key}" -float "${desired}" ;;
            string) defaults write "${domain}" "${key}" -string "${desired}" ;;
            *)
                echo "${yellow}Warning:${normal} skipping ${id}: unknown type '${type}'" >&2
                continue
                ;;
        esac
        readback="$(defaults read "${domain}" "${key}" 2>/dev/null || printf '__UNSET__')"
        expected_norm="$(normalize_desired "${type}" "${desired}")"
        if [[ "${readback}" != "${expected_norm}" && "${readback}" != "${desired}" ]]; then
            echo "${yellow}⚠${normal}  ${id}: write succeeded but readback returned '${readback}' (key may be deprecated)" >&2
        fi
        if [[ -n "${requires_csv}" ]]; then
            IFS=',' read -ra apps <<<"${requires_csv}"
            for app in "${apps[@]}"; do
                [[ -n "${app}" ]] && restart_apps["${app}"]=1
            done
        fi
    done

    if [[ ${#restart_apps[@]} -gt 0 ]]; then
        echo
        echo "${dim}Restarting affected applications:${normal}"
        for app in "${!restart_apps[@]}"; do
            if pgrep -x "${app}" >/dev/null 2>&1; then
                echo "  • ${app}"
                killall "${app}" 2>/dev/null || true
            fi
        done
    fi

    # Retain only the 10 newest snapshot directories.
    if [[ -d "${snapshots_root}" ]]; then
        mapfile -t old_snapshots < <(
            find "${snapshots_root}" -mindepth 1 -maxdepth 1 -type d -not -name "latest" \
                | sort -r | tail -n +11
        )
        for old in "${old_snapshots[@]}"; do
            [[ -n "${old}" ]] && rm -rf "${old}"
        done
    fi

    echo
    echo "${green}✅ Applied ${drift_count} setting(s).${normal}"
    echo "${dim}Some settings may require logout/restart to fully take effect.${normal}"

# Restore the latest snapshot, list snapshots, or restore a specific one.
#   macos-defaults-undo                  # restore latest
#   macos-defaults-undo list             # list snapshots, no mutation
#   macos-defaults-undo <timestamp>      # restore a specific snapshot directory name
[group('macos')]
[doc('Restore a snapshot from a previous macos-defaults apply.')]
macos-defaults-undo $action="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ sparkdock_path }}/sjust/libs/libcolors.sh"

    snapshots_root="{{ snapshots_root }}"

    if [[ ! -d "${snapshots_root}" ]]; then
        echo "${red}Error:${normal} no snapshots directory at ${snapshots_root}" >&2
        exit 1
    fi

    mapfile -t snapshots < <(
        find "${snapshots_root}" -mindepth 1 -maxdepth 1 -type d -not -name "latest" \
            | sort
    )

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        echo "${red}Error:${normal} no snapshots available." >&2
        exit 1
    fi

    if [[ "${action}" == "list" ]]; then
        echo "${bold}Available snapshots (oldest → newest):${normal}"
        for s in "${snapshots[@]}"; do
            ts="$(basename "${s}")"
            domains_count="$(wc -l < "${s}/manifest.txt" 2>/dev/null | tr -d ' ' || printf '?')"
            echo "  ${ts}  (${domains_count} domain(s))"
        done
        latest="$(readlink "${snapshots_root}/latest" 2>/dev/null || true)"
        [[ -n "${latest}" ]] && echo "${dim}latest →${normal} ${latest}"
        exit 0
    fi

    if [[ -n "${action}" ]]; then
        target="${snapshots_root}/${action}"
        if [[ ! -d "${target}" ]]; then
            echo "${red}Error:${normal} no snapshot directory named '${action}' under ${snapshots_root}" >&2
            exit 1
        fi
    else
        target="${snapshots[-1]}"
    fi

    target_name="$(basename "${target}")"
    echo "${bold}Restoring snapshot:${normal} ${target_name}"

    if [[ ! -f "${target}/manifest.txt" ]]; then
        echo "${red}Error:${normal} snapshot ${target_name} is missing manifest.txt" >&2
        exit 1
    fi

    declare -A restart_apps
    while IFS= read -r domain; do
        [[ -z "${domain}" ]] && continue
        plist="${target}/${domain}.plist"
        if [[ ! -f "${plist}" ]]; then
            echo "${yellow}⚠${normal}  domain ${domain} listed in manifest but plist missing; skipping" >&2
            continue
        fi
        if defaults import "${domain}" "${plist}" 2>/dev/null; then
            echo "  ${green}✓${normal} restored ${domain}"
        else
            echo "  ${red}✗${normal} failed to restore ${domain}" >&2
            continue
        fi
        # Restart any apps the curated YAML associates with this domain
        if [[ -f "{{ config_file }}" ]] && command -v yq >/dev/null 2>&1; then
            while IFS= read -r app; do
                [[ -z "${app}" || "${app}" == "null" ]] && continue
                restart_apps["${app}"]=1
            done < <(
                yq eval ". | to_entries | .[] | select(.value.domain == \"${domain}\") | .value.requires // [] | .[]" \
                    "{{ config_file }}" 2>/dev/null
            )
        fi
    done < "${target}/manifest.txt"

    if [[ ${#restart_apps[@]} -gt 0 ]]; then
        echo
        echo "${dim}Restarting affected applications:${normal}"
        for app in "${!restart_apps[@]}"; do
            if pgrep -x "${app}" >/dev/null 2>&1; then
                echo "  • ${app}"
                killall "${app}" 2>/dev/null || true
            fi
        done
    fi

    echo
    echo "${green}✅ Restored snapshot ${target_name}.${normal}"

# Print, check, or write the macOS defaults docs table.
#   macos-defaults-docs                  # print Markdown table to stdout (default 'print')
#   macos-defaults-docs check            # exit non-zero if README block is stale
#   macos-defaults-docs write            # rewrite README block with fresh table
[group('macos')]
[doc('Generate / verify the macOS defaults Markdown table embedded in README.md.')]
macos-defaults-docs $mode="print":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ sparkdock_path }}/sjust/libs/libcolors.sh"

    config_file="{{ config_file }}"
    readme="{{ sparkdock_path }}/README.md"
    start_marker="<!-- macos-defaults:start -->"
    end_marker="<!-- macos-defaults:end -->"

    case "${mode}" in
        print|check|write) ;;
        *)
            echo "${red}Error:${normal} unknown mode '${mode}'. Valid: print, check, write." >&2
            exit 2
            ;;
    esac

    if ! command -v yq >/dev/null 2>&1; then
        echo "${red}Error:${normal} yq is required. Install with: brew install yq" >&2
        exit 1
    fi

    render_table() {
        printf '%s\n' "${start_marker}"
        printf '\n<!-- prettier-ignore-start -->\n\n'
        # shellcheck disable=SC2016 # backticks are literal Markdown
        printf '_This table is generated from `config/macos/defaults.yml` by `sjust macos-defaults-docs write`. Do not edit by hand._\n\n'
        printf '| Category | Domain | Key | Type | Default | Description | Restarts |\n'
        printf '| --- | --- | --- | --- | --- | --- | --- |\n'
        yq eval '
            . | to_entries
            | sort_by(.value.category, .value.key) | .[]
            | [
                .value.category,
                .value.domain,
                .value.key,
                .value.type,
                (.value.value | tostring),
                .value.description,
                ((.value.requires // []) | join(", "))
              ]
            | @tsv
        ' "${config_file}" | while IFS=$'\t' read -r category domain key type value description requires; do
            # shellcheck disable=SC2016 # backticks are literal Markdown
            printf '| %s | `%s` | `%s` | %s | `%s` | %s | %s |\n' \
                "${category}" "${domain}" "${key}" "${type}" "${value}" "${description}" "${requires}"
        done
        printf '\n<!-- prettier-ignore-end -->\n\n%s\n' "${end_marker}"
    }

    fresh="$(mktemp -t macos-defaults-docs.XXXXXX)"
    trap 'rm -f "${fresh}"' EXIT
    render_table > "${fresh}"

    if [[ "${mode}" == "print" ]]; then
        cat "${fresh}"
        exit 0
    fi

    if [[ ! -f "${readme}" ]]; then
        echo "${red}Error:${normal} ${readme} not found" >&2
        exit 1
    fi

    if ! grep -qF "${start_marker}" "${readme}" || ! grep -qF "${end_marker}" "${readme}"; then
        echo "${red}Error:${normal} README is missing the macos-defaults markers." >&2
        echo "${dim}Add a block bracketed by:${normal}" >&2
        echo "  ${start_marker}" >&2
        echo "  ${end_marker}" >&2
        exit 1
    fi

    current="$(awk -v start="${start_marker}" -v end="${end_marker}" '
        $0 == start { in_block = 1; print; next }
        $0 == end   { in_block = 0; print; next }
        in_block    { print }
    ' "${readme}")"
    fresh_content="$(cat "${fresh}")"

    if [[ "${current}" == "${fresh_content}" ]]; then
        if [[ "${mode}" == "check" ]]; then
            echo "${green}✓${normal} README macos-defaults block is up to date."
        else
            echo "${dim}(no change)${normal}"
        fi
        exit 0
    fi

    if [[ "${mode}" == "check" ]]; then
        echo "${red}✗${normal} README macos-defaults block is stale. Run: sjust macos-defaults-docs write" >&2
        exit 1
    fi

    # mode == write
    out="$(mktemp -t macos-defaults-readme.XXXXXX)"
    awk -v start="${start_marker}" -v end="${end_marker}" -v fresh="${fresh}" '
        $0 == start { in_block = 1; while ((getline line < fresh) > 0) print line; close(fresh); next }
        $0 == end   { in_block = 0; next }
        !in_block   { print }
    ' "${readme}" > "${out}"
    mv "${out}" "${readme}"
    echo "${green}✓${normal} README macos-defaults block updated."
