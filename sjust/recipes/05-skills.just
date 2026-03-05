# vim: set ft=make :

# Refresh agent skills from SparkFabrik upstream repository.
[group('skills')]
sf-skills-refresh $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${force}" == "force" ]]; then
        {{sparkdock_path}}/bin/sparkdock-skills-sync --force
    else
        {{sparkdock_path}}/bin/sparkdock-skills-sync
    fi

# Show status of agent skills (managed vs user-owned).
[group('skills')]
sf-skills-status:
    @{{sparkdock_path}}/bin/sparkdock-skills-status
