# vim: set ft=make :

# Opt-in helper: sparkdock never installs or configures the CLI.
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
        if engram update --check >/dev/null 2>&1; then
            echo "  ${bold}An update is available:${normal} engram update --apply"
            echo ""
        fi
        echo "  Check the installation with:  ${bold}engram doctor${normal}"
        echo "  Update the CLI with:          ${bold}engram update --apply${normal}"
    else
        echo "  ❌ Not installed."
        echo ""
        echo "  The CLI is distributed internally, so sparkdock cannot install it"
        echo "  for you. Follow the setup instructions at"
        echo "  https://docs.firestarter.sparkfabrik.cloud/packages/engram/docs/install_and_update/"
    fi

    echo ""
    echo "  Engram is the shared agent memory: agents recall what colleagues"
    echo "  already learned and store what they find out."
