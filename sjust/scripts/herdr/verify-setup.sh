#!/usr/bin/env bash
set -euo pipefail

# Verify the herdr skill setup against a stubbed `herdr` binary, so the
# integration refresh logic runs in CI without herdr, OpenCode, or a herdr
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
codex: current (v8) (/tmp/home/.codex/herdr-agent-state.sh)
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

    PATH="${fake_bin}:${PATH}" "${SCRIPT_DIR}/setup.sh" install > /dev/null

    if [[ ! -f "${HOME}/.agents/skills/herdr/SKILL.md" ]]; then
        log_error "herdr skill was not installed"
        exit 1
    fi

    local installed
    installed="$(tr '\n' ' ' < "${install_log}")"
    assert_equals "claude opencode letta " "${installed}" "refreshed integrations"

    log_success "herdr setup verification passed"
}

main "$@"
