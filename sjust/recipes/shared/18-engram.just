# vim: set ft=make :

# Opt-in helpers: sparkdock never installs the engram CLI. It is distributed
# internally through a private carrier image, like the timetracker CLI.
# Show engram CLI status and where to find the installation instructions.
[group('engram')]
sf-engram-info:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{source_directory()}}/../../libs/libformatting.sh"
    source "{{source_directory()}}/../../libs/libcolors.sh"

    echo "${bold}Engram CLI${normal}"
    echo ""

    if command -v engram >/dev/null 2>&1; then
        echo "  ✅ Installed: $(command -v engram)"
        echo "     Version:   $(engram version 2>/dev/null || echo "unknown")"
        echo ""
        echo "  Log in to the hub with: ${bold}sjust sf-engram-auth${normal}"
        echo "  Update the CLI with:    ${bold}engram update --apply${normal}"
    else
        echo "  ❌ Not installed."
        echo ""
        echo "  The CLI is distributed internally, so sparkdock cannot install it"
        echo "  for you. Follow \"Install and update\" in the Engram section of the"
        echo "  Firestarter documentation."
    fi

    echo ""
    echo "  The sparkdock menu bar app reports engram updates once the CLI"
    echo "  is on your PATH."

# Log the engram CLI in to the hub through the GitLab device flow.
[group('engram')]
sf-engram-auth:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{source_directory()}}/../../libs/libformatting.sh"
    source "{{source_directory()}}/../../libs/libcolors.sh"

    if ! command -v engram >/dev/null 2>&1; then
        echo "  ❌ engram is not installed. Run ${bold}sjust sf-engram-info${normal} for the setup steps."
        exit 1
    fi
    engram login
