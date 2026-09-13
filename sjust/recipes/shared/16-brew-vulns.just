# vim: set ft=make :

# Check installed Homebrew formulae for known vulnerabilities (OSV.dev). Optional severity: low, medium, high, critical.
[group('system')]
brew-vulns $severity="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is not installed; brew vulns needs Homebrew 7 or later." >&2
        exit 127
    fi

    if [[ -z "${severity}" ]]; then
        exec brew vulns
    fi

    case "${severity}" in
        low|medium|high|critical) ;;
        *)
            echo "Unknown severity '${severity}'; use one of: low, medium, high, critical." >&2
            exit 2
            ;;
    esac

    exec brew vulns --severity "${severity}"
