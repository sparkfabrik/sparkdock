# vim: set ft=make :

# Opt-in helper: sparkdock never installs or configures the CLI.
# Show timetracker CLI status and where to find the installation instructions.
[group('timetracker')]
sf-timetracker-info:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{source_directory()}}/../../libs/libformatting.sh"
    source "{{source_directory()}}/../../libs/libcolors.sh"

    echo "${bold}Timetracker CLI${normal}"
    echo ""

    if command -v timetracker >/dev/null 2>&1; then
        echo "  ✅ Installed: $(command -v timetracker)"
        echo "     Version:   $(timetracker version 2>/dev/null || echo "unknown")"
        echo ""
        echo "  Start the terminal UI with: ${bold}timetracker tui${normal}"
        echo "  Update the CLI with:        ${bold}timetracker update --apply${normal}"
    else
        echo "  ❌ Not installed."
        echo ""
        echo "  The CLI is distributed internally, so sparkdock cannot install it"
        echo "  for you. Follow the setup instructions in the internal knowledge base."
    fi

    echo ""
    echo "  The sparkdock menu bar app reports timetracker updates once the CLI"
    echo "  is on your PATH."
