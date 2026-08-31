# vim: set ft=make :

# Host an authenticated Upterm shell.
# Providers: github, gitlab, keys. Modes: shell, forward.
# Examples:
#   sjust upterm-host github paolomainardi
#   sjust upterm-host github paolomainardi forward
# ajust upterm-host keys ~/.ssh/authorized_keys
[group('terminal-sharing')]
upterm-host $provider $identity $mode="shell":
    #!/usr/bin/env bash
    # Just exports provider, identity, and mode into the recipe environment.
    # shellcheck disable=SC2154
    set -euo pipefail

    if ! command -v upterm >/dev/null 2>&1; then
        echo "upterm is not installed." >&2
        exit 127
    fi

    auth_args=()
    case "${provider}" in
        github) auth_args=(--github-user "${identity}") ;;
        gitlab) auth_args=(--gitlab-user "${identity}") ;;
        keys) auth_args=(--authorized-keys "${identity}") ;;
        *)
            echo "Unsupported provider '${provider}'. Use github, gitlab, or keys." >&2
            exit 2
            ;;
    esac

    mode_args=()
    case "${mode}" in
        shell) ;;
        forward) mode_args=(--allow-local-tcp-forwarding --no-sftp) ;;
        *)
            echo "Unsupported mode '${mode}'. Use shell or forward." >&2
            exit 2
            ;;
    esac

    exec upterm host "${auth_args[@]}" "${mode_args[@]}" -- "${SHELL:-/bin/sh}"

# Show connection and SFTP/SCP commands for the active Upterm session.
[group('terminal-sharing')]
upterm-session:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v upterm >/dev/null 2>&1; then
        echo "upterm is not installed." >&2
        exit 127
    fi

    exec upterm session current
