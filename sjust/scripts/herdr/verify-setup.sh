#!/usr/bin/env bash
set -euo pipefail

# Verify the herdr skill setup against stubbed `herdr`, `hc` and `herdr-app`
# binaries, so the router, the generated manuals and the integration refresh
# logic run in CI without herdr, herdr-core, OpenCode, or a herdr
# server. Everything is written under a temporary HOME.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../libs/libshell.sh
source "${SCRIPT_DIR}/../../libs/libshell.sh"

assert_equals() {
    local expected="$1"
    local actual="$2"
    local what="$3"

    if [[ "${expected}" != "${actual}" ]]; then
        log_error "${what}: expected '${expected}', got '${actual}'"
        exit 1
    fi
}

assert_file() {
    local path="$1"
    local what="$2"

    if [[ ! -f "${path}" ]]; then
        log_error "${what}: ${path} is missing"
        exit 1
    fi
}

assert_no_file() {
    local path="$1"
    local what="$2"

    if [[ -e "${path}" ]]; then
        log_error "${what}: ${path} should not exist"
        exit 1
    fi
}

# PATH without any directory holding a real herdr, hc, herdr-core or herdr-app,
# so the stubs below are the only Herdr binaries the setup can find.
path_without_herdr() {
    local dir clean=""
    local IFS=":"
    for dir in ${PATH}; do
        if [[ -x "${dir}/herdr" || -x "${dir}/hc" || -x "${dir}/herdr-core" || -x "${dir}/herdr-app" ]]; then
            continue
        fi
        clean="${clean:+${clean}:}${dir}"
    done
    echo "${clean}"
}

main() {
    local temp_home
    temp_home=$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-herdr-verify.XXXXXX")
    export HOME="${temp_home}"
    export XDG_CONFIG_HOME="${HOME}/.config"

    log_info "Checking the outdated-integration parser..."
    # shellcheck source=./setup.sh
    source "${SCRIPT_DIR}/setup.sh"

    local fixture
    fixture="$(cat <<'STATUS'
pi: not installed (/tmp/home/.pi/agent/extensions/herdr-agent-state.ts)
claude: outdated (v9 < v10) (/tmp/home/.claude/hooks/herdr-agent-state.sh)
codex: not installed (/tmp/home/.codex/herdr-agent-state.sh)
copilot: current (v8) (/tmp/home/.copilot/hooks/herdr-agent-state.sh)
opencode: outdated (v11 < v12) (/tmp/home/.config/opencode/plugins/herdr-agent-state.js)
kilo: not installed (/tmp/home/outdated/kilo/plugin/herdr-agent-state.js)
letta (experimental): outdated (v1 < v2) (/tmp/home/.letta/hooks/herdr-agent-session.sh)
STATUS
)"
    local parsed
    parsed="$(outdated_integrations <<< "${fixture}" | tr '\n' ' ')"
    assert_equals "claude opencode letta " "${parsed}" "outdated integrations"

    parsed="$(outdated_integrations <<< "" | tr '\n' ' ')"
    assert_equals "" "${parsed}" "outdated integrations on empty status"

    log_info "Checking the missing default integrations..."
    # Codex counts as present through its config directory, whatever PATH holds.
    # Pi and kilo are missing too, but they are not default integrations.
    mkdir -p "${HOME}/.codex"
    parsed="$(missing_default_integrations <<< "${fixture}" | tr '\n' ' ')"
    assert_equals "codex " "${parsed}" "missing default integrations"

    parsed="$(SPARKDOCK_HERDR_DEFAULT_INTEGRATIONS=0 missing_default_integrations <<< "${fixture}" | tr '\n' ' ')"
    assert_equals "" "${parsed}" "missing default integrations when turned off"

    log_info "Running the herdr skill setup against a stubbed herdr..."
    local fake_bin="${HOME}/fake-bin"
    local install_log="${HOME}/herdr-install.log"
    mkdir -p "${fake_bin}"
    cat > "${fake_bin}/herdr" <<STUB
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in
    "--skill ")
        printf -- '---\nname: herdr\ndescription: stub\n---\n# herdr\n'
        ;;
    "integration status")
        cat <<'STATUS'
${fixture}
STATUS
        ;;
    "integration install")
        echo "\${3}" >> "${install_log}"
        ;;
    *)
        echo "unexpected herdr call: \$*" >&2
        exit 1
        ;;
esac
STUB
    chmod +x "${fake_bin}/herdr"

    cat > "${fake_bin}/hc" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --version) echo "hc 0.1.19" ;;
    --skill) printf '# hc manual (herdr-core)\n' ;;
    *) echo "unexpected hc call: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "${fake_bin}/hc"

    cat > "${fake_bin}/herdr-app" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --skill) printf "# herdr-app: drive the person's window\n" ;;
    *) echo "unexpected herdr-app call: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "${fake_bin}/herdr-app"

    # On a provisioned Mac, Homebrew's bin holds both herdr and bash 5, so the
    # filtered PATH below would fall back to macOS bash 3.2. Keep the running
    # bash reachable through the stub directory.
    ln -sf "${BASH}" "${fake_bin}/bash"

    local clean_path skill_dir
    clean_path="$(path_without_herdr)"
    skill_dir="${HOME}/.agents/skills/herdr"

    local output
    output="$(PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install 2>&1)"

    log_info "Checking the router and the three manuals..."
    if [[ "${output}" == *"sf-herdr-skill-install"* ]]; then
        log_error "missing herdr-core warning printed although hc is installed"
        exit 1
    fi
    assert_file "${skill_dir}/SKILL.md" "router"
    if ! cmp -s "${SCRIPT_DIR}/skill-router.md" "${skill_dir}/SKILL.md"; then
        log_error "router: SKILL.md does not match skill-router.md"
        exit 1
    fi
    assert_file "${skill_dir}/references/herdr-tui.md" "herdr TUI manual"
    assert_equals "# herdr" "$(head -n 1 "${skill_dir}/references/herdr-tui.md")" "herdr TUI manual without front matter"
    assert_file "${skill_dir}/references/hc.md" "herdr-core manual"
    assert_equals "# hc manual (herdr-core)" "$(head -n 1 "${skill_dir}/references/hc.md")" "herdr-core manual"
    assert_file "${skill_dir}/references/herdr-app.md" "herdr-app manual"

    local installed
    installed="$(tr '\n' ' ' < "${install_log}")"
    assert_equals "claude opencode letta codex " "${installed}" "refreshed and installed integrations"

    log_info "Checking that manuals of removed runtimes are dropped..."
    rm -f "${fake_bin}/hc" "${fake_bin}/herdr-app"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null
    assert_file "${skill_dir}/references/herdr-tui.md" "herdr TUI manual after rerun"
    assert_no_file "${skill_dir}/references/hc.md" "stale herdr-core manual"
    assert_no_file "${skill_dir}/references/herdr-app.md" "stale herdr-app manual"

    log_info "Checking an hc-only machine (no herdr TUI)..."
    rm -f "${fake_bin}/herdr" "${install_log}"
    cat > "${fake_bin}/hc" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    --version) echo "hc 0.1.19" ;;
    --skill) printf '# hc manual (herdr-core)\n' ;;
    *) echo "unexpected hc call: $*" >&2; exit 1 ;;
esac
STUB
    chmod +x "${fake_bin}/hc"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null
    assert_file "${skill_dir}/references/hc.md" "herdr-core manual on an hc-only machine"
    assert_no_file "${skill_dir}/references/herdr-tui.md" "stale herdr TUI manual"
    assert_no_file "${install_log}" "integrations touched without the herdr TUI"

    log_info "Checking that an unrelated hc is ignored and herdr-core is reported missing..."
    printf '#!/usr/bin/env bash\necho "unrelated-tool 1.0"\n' > "${fake_bin}/hc"
    printf '#!/usr/bin/env bash\nprintf "# herdr-app\\n"\n' > "${fake_bin}/herdr-app"
    chmod +x "${fake_bin}/hc" "${fake_bin}/herdr-app"
    output="$(PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install 2>&1)"
    assert_no_file "${skill_dir}/references/hc.md" "manual from an unrelated hc"
    if [[ "${output}" != *"sf-herdr-skill-install"* ]]; then
        log_error "no herdr-core warning although the Herdr app is installed without hc"
        exit 1
    fi
    assert_file "${skill_dir}/references/herdr-app.md" "herdr-app manual"

    log_info "Checking that a TUI manual with an unclosed front matter is dropped, not fatal..."
    printf '#!/usr/bin/env bash\nprintf -- "---\\nname: herdr\\n# herdr\\n"\n' > "${fake_bin}/herdr"
    chmod +x "${fake_bin}/herdr"
    if ! PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null 2>&1; then
        log_error "setup failed on an unusable herdr manual instead of skipping it"
        exit 1
    fi
    assert_no_file "${skill_dir}/references/herdr-tui.md" "TUI manual from an unclosed front matter"
    assert_file "${skill_dir}/SKILL.md" "router written when the TUI manual is unusable"
    rm -f "${fake_bin}/herdr"

    log_info "Checking that user files survive a run with no Herdr runtime..."
    rm -f "${fake_bin}/hc" "${fake_bin}/herdr-app"
    echo "user notes" > "${skill_dir}/notes.md"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null
    assert_file "${skill_dir}/notes.md" "user file in the skill directory"
    assert_no_file "${skill_dir}/SKILL.md" "router with no runtime installed"
    assert_no_file "${skill_dir}/references" "generated manuals with no runtime installed"
    if [[ -L "${HOME}/.claude/skills/herdr" ]]; then
        log_error "Claude Code herdr skill link left behind after its router was removed"
        exit 1
    fi
    rm -f "${skill_dir}/notes.md"

    log_info "Checking that the skill is removed when no Herdr runtime is left..."
    printf '#!/usr/bin/env bash\nprintf "# herdr-app\\n"\n' > "${fake_bin}/herdr-app"
    chmod +x "${fake_bin}/herdr-app"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null 2>&1
    assert_file "${skill_dir}/SKILL.md" "router reinstalled before the removal check"
    rm -f "${fake_bin}/herdr-app"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null
    assert_no_file "${skill_dir}" "herdr skill with no runtime installed"
    if [[ -L "${HOME}/.claude/skills/herdr" ]]; then
        log_error "Claude Code herdr skill link left behind with no runtime installed"
        exit 1
    fi

    log_info "Checking that a custom herdr skill survives a run with no Herdr runtime..."
    mkdir -p "${skill_dir}/references"
    printf -- '---\nname: herdr\ndescription: my own\n---\n# custom\n' > "${skill_dir}/SKILL.md"
    echo "custom manual" > "${skill_dir}/references/hc.md"
    PATH="${fake_bin}:${clean_path}" "${SCRIPT_DIR}/setup.sh" install > /dev/null 2>&1
    assert_equals "# custom" "$(tail -n 1 "${skill_dir}/SKILL.md")" "custom SKILL.md"
    assert_file "${skill_dir}/references/hc.md" "custom reference"

    log_success "herdr setup verification passed"
}

main "$@"
