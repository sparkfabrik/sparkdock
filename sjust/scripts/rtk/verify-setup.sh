#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../libs/libshell.sh"

rtk_config_dir() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "${HOME}/Library/Application Support/rtk"
    else
        echo "${XDG_CONFIG_HOME:-${HOME}/.config}/rtk"
    fi
}

assert_file_exists() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        log_error "Missing expected file: ${file}"
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"

    if ! grep -Fq -- "${needle}" "${file}"; then
        log_error "Expected '${needle}' in ${file}"
        exit 1
    fi
}

main() {
    if ! command -v rtk > /dev/null 2>&1; then
        log_error "rtk is not installed"
        exit 1
    fi

    local temp_home
    temp_home=$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-rtk-verify.XXXXXX")
    export HOME="${temp_home}"
    export XDG_CONFIG_HOME="${HOME}/.config"

    local rtk_dir
    rtk_dir="$(rtk_config_dir)"
    local rtk_config="${rtk_dir}/config.toml"
    local filters_file="${rtk_dir}/filters.toml"
    local claude_settings="${HOME}/.claude/settings.json"
    local claude_md="${HOME}/.claude/CLAUDE.md"
    local rtk_md="${HOME}/.claude/RTK.md"
    local vscode_instructions="${HOME}/.github/copilot-instructions.md"
    local cli_instructions="${HOME}/.copilot/copilot-instructions.md"
    local opencode_plugin="${HOME}/.config/opencode/plugins/rtk.ts"
    local rtk_run="${HOME}/.local/bin/rtk-run"

    log_info "Bootstrapping RTK base config in ${HOME}..."
    mkdir -p "${HOME}/.claude" "${HOME}/.github" "${HOME}/.copilot"
    rtk config --create > /dev/null 2>&1
    assert_file_exists "${rtk_config}"

    perl -0pi -e 's/\[hooks\]\nexclude_commands = \[\]/[hooks]\ntransparent_prefixes = ["direnv exec ."]\nexclude_commands = ["curl"]/' "${rtk_config}"

    log_info "Running Sparkdock RTK setup..."
    "${SPARKDOCK_ROOT}/sjust/scripts/rtk/setup.sh"

    log_info "Checking installed files..."
    assert_file_exists "${rtk_config}"
    assert_file_exists "${filters_file}"
    assert_file_exists "${claude_settings}"
    assert_file_exists "${claude_md}"
    assert_file_exists "${rtk_md}"
    assert_file_exists "${vscode_instructions}"
    assert_file_exists "${cli_instructions}"
    assert_file_exists "${opencode_plugin}"
    assert_file_exists "${rtk_run}"

    assert_file_contains "${claude_settings}" "rtk hook claude"
    assert_file_contains "${claude_md}" "@RTK.md"
    assert_file_contains "${vscode_instructions}" "Use \`rtk-run\` for high-output local development commands"
    assert_file_contains "${cli_instructions}" "Do not use \`rtk-run\` for destructive commands"

    log_info "Checking merged RTK config..."
    assert_file_contains "${rtk_config}" 'transparent_prefixes = ["direnv exec ."]'
    assert_file_contains "${rtk_config}" '^git push(?: .*)?(?: --force| -f)(?:$| )'
    assert_file_contains "${rtk_config}" '^(?:kubectl|k)(?: .*)? (?:apply|delete|patch|replace)(?:$| )'
    assert_file_contains "${rtk_config}" '^(?:terraform|tf)(?: .*)? destroy(?:$| )'
    assert_file_contains "${rtk_config}" '^(?:gh|glab)(?: .*)? (?:merge|close|delete|destroy|cancel|disable)(?:$| )'

    if grep -Fq 'exclude_commands = ["curl"]' "${rtk_config}"; then
        log_error "Old exclude_commands value was not replaced"
        exit 1
    fi

    log_info "Running RTK smoke tests..."
    rtk git status > /dev/null
    "${rtk_run}" git status > /dev/null

    local raw_output
    raw_output=$("${rtk_run}" printf hello)
    if [[ "${raw_output}" != "hello" ]]; then
        log_error "Unexpected rtk-run raw output: ${raw_output}"
        exit 1
    fi

    local pipe_output
    pipe_output=$("${rtk_run}" 'printf hello | tr a-z A-Z')
    if [[ "${pipe_output}" != "HELLO" ]]; then
        log_error "Unexpected rtk-run quoted command output: ${pipe_output}"
        exit 1
    fi

    local rewrite_output
    local rewrite_rc
    set +e
    rewrite_output=$(rtk rewrite "git status" 2> /dev/null)
    rewrite_rc=$?
    set -e

    if [[ "${rewrite_output}" != "rtk git status" ]]; then
        log_error "Unexpected rewrite output: ${rewrite_output}"
        exit 1
    fi

    if [[ "${rewrite_rc}" -ne 0 && "${rewrite_rc}" -ne 3 ]]; then
        log_error "Unexpected rewrite exit code: ${rewrite_rc}"
        exit 1
    fi

    local excluded_output
    local excluded_rc
    set +e
    excluded_output=$(rtk rewrite "terraform destroy" 2> /dev/null)
    excluded_rc=$?
    set -e

    if [[ -n "${excluded_output}" ]]; then
        log_error "Excluded command was rewritten: ${excluded_output}"
        exit 1
    fi

    if [[ "${excluded_rc}" -ne 1 ]]; then
        log_error "Expected excluded command to exit 1, got ${excluded_rc}"
        exit 1
    fi

    local gh_output
    local gh_rc
    set +e
    gh_output=$(rtk rewrite "gh pr merge 123" 2> /dev/null)
    gh_rc=$?
    set -e

    if [[ -n "${gh_output}" ]]; then
        log_error "Excluded gh command was rewritten: ${gh_output}"
        exit 1
    fi

    if [[ "${gh_rc}" -ne 1 ]]; then
        log_error "Expected gh exclusion to exit 1, got ${gh_rc}"
        exit 1
    fi

    log_success "RTK setup verification passed"
}

main "$@"
