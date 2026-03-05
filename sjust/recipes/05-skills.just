# vim: set ft=make :

sparkdock_path := "/opt/sparkdock"

# Refresh agent skills from SparkFabrik upstream repository.
[group('skills')]
sf-skills-refresh $force="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Refreshing SparkFabrik agent skills..."
    if [[ "${force}" == "force" ]]; then
        sparkdock-skills-sync --force
    else
        sparkdock-skills-sync
    fi

# Show status of agent skills (managed vs user-owned).
[group('skills')]
sf-skills-status:
    #!/usr/bin/env bash
    set -euo pipefail

    SKILLS_DIR="${HOME}/.agents/skills"
    MANIFEST_PATH="${HOME}/.cache/sparkdock/sf-skills-manifest.json"

    echo "=== Agent Skills Status ==="
    echo ""

    if [[ ! -d "${SKILLS_DIR}" ]]; then
        echo "No skills directory found at ${SKILLS_DIR}"
        exit 0
    fi

    # Get managed skill names from manifest
    managed_skills=""
    if [[ -f "${MANIFEST_PATH}" ]]; then
        managed_skills=$(python3 -c "
import json
with open('${MANIFEST_PATH}') as f:
    data = json.load(f)
for name in sorted(data.get('skills', {}).keys()):
    print(name)
" 2>/dev/null || true)
    fi

    printf "%-25s %-12s %s\n" "SKILL" "TYPE" "STATUS"
    printf "%-25s %-12s %s\n" "-----" "----" "------"

    for skill_dir in "${SKILLS_DIR}"/*/; do
        [[ -d "${skill_dir}" ]] || continue
        skill_name=$(basename "${skill_dir}")

        # Check if SKILL.md exists
        if [[ ! -f "${skill_dir}/SKILL.md" ]]; then
            printf "%-25s %-12s %s\n" "${skill_name}" "incomplete" "no SKILL.md"
            continue
        fi

        # Check if managed
        if echo "${managed_skills}" | grep -qx "${skill_name}"; then
            # Check for local modifications
            if [[ -f "${MANIFEST_PATH}" ]]; then
                manifest_sha=$(python3 -c "
import json
with open('${MANIFEST_PATH}') as f:
    data = json.load(f)
print(data.get('skills', {}).get('${skill_name}', {}).get('sha256', ''))
" 2>/dev/null || true)

                if command -v shasum &>/dev/null; then
                    installed_sha=$(shasum -a 256 "${skill_dir}/SKILL.md" | cut -d' ' -f1)
                else
                    installed_sha=$(sha256sum "${skill_dir}/SKILL.md" | cut -d' ' -f1)
                fi

                if [[ "${manifest_sha}" == "${installed_sha}" ]]; then
                    printf "%-25s %-12s %s\n" "${skill_name}" "managed" "up to date"
                else
                    printf "%-25s %-12s %s\n" "${skill_name}" "managed" "locally modified"
                fi
            fi
        else
            printf "%-25s %-12s %s\n" "${skill_name}" "user" ""
        fi
    done

    echo ""
    if [[ -f "${MANIFEST_PATH}" ]]; then
        echo "Manifest: ${MANIFEST_PATH}"
    else
        echo "No manifest found. Run 'sjust sf-skills-refresh' to sync."
    fi
