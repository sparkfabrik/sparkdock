# vim: set ft=make :

# Security scanning commands for Sparkdock

# Scan current directory for NPM supply chain attacks
[group('security')]
security-scan-npm dir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" "{{dir}}"

# Scan for specific NPM supply chain attack
[group('security')]
security-scan-npm-attack attack dir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" -a "{{attack}}" "{{dir}}"

# List all available NPM supply chain attacks
[group('security')]
security-list-attacks:
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" --list-attacks

# Update the Shai-Hulud 2.0 attack database from the Wiz IOC repository
[group('security')]
security-update-shai-hulud:
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/scripts/update-shai-hulud.sh"
