# vim: set ft=make :

# Configure OpenSpec with custom profile and all workflows.
# Pass 'force' to overwrite existing config without prompting.
[group('ai-coding-agents')]
sf-openspec-configure $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{source_directory()}}/../../libs/libshell.sh"

    CONFIG_DIR="${HOME}/.config/openspec"
    CONFIG_FILE="${CONFIG_DIR}/config.json"
    SOURCE_FILE="{{sparkdock_path}}/config/macos/openspec.json"

    if [[ ! -f "${SOURCE_FILE}" ]]; then
        log_error "Source config not found at ${SOURCE_FILE}"
        exit 1
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        if [[ "${force}" == "force" ]]; then
            log_info "Overwriting existing OpenSpec config (force mode)"
        else
            log_warn "OpenSpec config already exists at ${CONFIG_FILE}"
            read -p "Overwrite with Sparkdock defaults? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Keeping existing configuration."
                exit 0
            fi
        fi
    fi

    mkdir -p "${CONFIG_DIR}"
    cp "${SOURCE_FILE}" "${CONFIG_FILE}"
    chmod 644 "${CONFIG_FILE}"
    log_success "OpenSpec configured with custom profile (all 11 workflows enabled)"
