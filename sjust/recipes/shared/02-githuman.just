# vim: set ft=make :

# GitHuman - Review AI agent code changes before commit
# https://githuman.dev/
githuman_version := "0.9.0"
githuman_label := "com.sparkfabrik.githuman"
githuman_cache_volume := "githuman-npm-cache"
githuman_data_volume := "githuman-data"

# Start a GitHuman code review container for a project directory.
[group('githuman')]
[no-cd]
githuman-start $directory=".":
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -d "${directory}" ]]; then
        echo "❌ Directory not found: ${directory}"
        exit 1
    fi

    target_dir=$(cd -P "${directory}" && pwd -P)
    basename_raw=$(basename "${target_dir}")

    # Sanitize basename for DNS-compatible hostname (RFC 952)
    sanitized=$(echo "${basename_raw}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')

    # Query running GitHuman containers for duplicate detection
    # Note: {{ "{{" }} and {{ "}}" }} are Just escape sequences producing literal Go template delimiters
    existing=$(docker ps --filter "label={{githuman_label}}=true" \
        --format '{{ "{{" }}.Label "{{githuman_label}}.directory"{{ "}}" }}|{{ "{{" }}.Names{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.fqdn"{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.token"{{ "}}" }}' 2>/dev/null || true)

    # Check for exact path duplicate
    if [[ -n "${existing}" ]]; then
        while IFS='|' read -r dir name fqdn_existing token_existing; do
            if [[ "${dir}" == "${target_dir}" ]]; then
                url="https://${fqdn_existing}?token=${token_existing}"
                echo "⚠️  GitHuman is already running for ${target_dir}"
                echo "   Container: ${name}"
                echo "   URL: ${url}"
                echo "🌐 Opening ${url}"
                if [[ "$(uname)" == "Darwin" ]]; then
                    open "${url}"
                else
                    xdg-open "${url}"
                fi
                exit 0
            fi
        done <<< "${existing}"
    fi

    # Determine container name and FQDN, handling basename collisions with numeric suffixes
    container_name="githuman-${sanitized}"
    fqdn="${sanitized}.githuman.sparkfabrik.loc"

    name_taken=false
    if [[ -n "${existing}" ]]; then
        while IFS='|' read -r _dir name _fqdn _token; do
            if [[ "${name}" == "githuman-${sanitized}" ]]; then
                name_taken=true
                break
            fi
        done <<< "${existing}"
    fi

    if [[ "${name_taken}" == "true" ]]; then
        suffix=1
        while true; do
            suffix_str=$(printf "%02d" "${suffix}")
            candidate="githuman-${sanitized}-${suffix_str}"
            candidate_taken=false
            if [[ -n "${existing}" ]]; then
                while IFS='|' read -r _dir name _fqdn _token; do
                    if [[ "${name}" == "${candidate}" ]]; then
                        candidate_taken=true
                        break
                    fi
                done <<< "${existing}"
            fi
            if [[ "${candidate_taken}" == "false" ]]; then
                container_name="${candidate}"
                fqdn="${sanitized}-${suffix_str}.githuman.sparkfabrik.loc"
                break
            fi
            suffix=$((suffix + 1))
        done
    fi

    # Generate random token (32 hex chars = 16 bytes, minimum required by GitHuman)
    token=$(openssl rand -hex 16)

    echo "🚀 Starting GitHuman for ${target_dir}"
    echo "   Container: ${container_name}"
    echo "   FQDN: ${fqdn}"

    # Ensure data volume subdirectory and home dir exist, owned by current user
    docker run --rm \
        -v {{githuman_data_volume}}:/data/githuman \
        -v {{githuman_cache_volume}}:/cache/npm \
        node:lts \
        bash -c "mkdir -p /data/githuman/${container_name}/home && chown -R $(id -u):$(id -g) /data/githuman/${container_name} /cache/npm" \
        > /dev/null

    docker run -d --rm \
        --name "${container_name}" \
        --user "$(id -u):$(id -g)" \
        -e HOME=/data/githuman/${container_name}/home \
        -e VIRTUAL_HOST="${fqdn}" \
        -e VIRTUAL_PORT=3847 \
        -e GITHUMAN_DB_PATH="/data/githuman/${container_name}/home/reviews.db" \
        -e npm_config_cache=/cache/npm \
        -v "${target_dir}:${target_dir}" \
        -v {{githuman_cache_volume}}:/cache/npm \
        -v {{githuman_data_volume}}:/data/githuman \
        -w "${target_dir}" \
        --label "{{githuman_label}}=true" \
        --label "{{githuman_label}}.directory=${target_dir}" \
        --label "{{githuman_label}}.fqdn=${fqdn}" \
        --label "{{githuman_label}}.token=${token}" \
        node:lts \
        bash -c "git config --global --add safe.directory '${target_dir}' && npx githuman@{{githuman_version}} serve --host 0.0.0.0 --no-open --no-https --auth '${token}'" \
        > /dev/null

    echo "✅ GitHuman container started"

    # TLS certificate management
    if command -v spark-http-proxy >/dev/null 2>&1; then
        cert_path="${HOME}/.local/spark/http-proxy/certs/${fqdn}.pem"
        if [[ ! -f "${cert_path}" ]]; then
            echo "🔒 Generating TLS certificate for ${fqdn}..."
            spark-http-proxy generate-mkcert "${fqdn}"
            echo "✅ Certificate generated"
        else
            echo "🔒 TLS certificate already installed for ${fqdn}"
        fi
    else
        echo "⚠️  spark-http-proxy is not installed — you may need to accept the invalid certificate in the browser"
    fi

    # Wait for GitHuman to be ready via the FQDN URL
    url="https://${fqdn}?token=${token}"
    echo "⏳ Waiting for GitHuman to be ready..."
    ready=false
    for _i in $(seq 1 60); do
        if curl -sfk "${url}" > /dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 1
    done

    if [[ "${ready}" == "false" ]]; then
        echo "⚠️  GitHuman did not become ready within 60s — opening browser anyway"
        echo "💡 Run 'sjust githuman-logs ${container_name}' to check for errors"
    fi

    # Open browser (cross-platform)
    echo "🌐 Opening ${url}"
    if [[ "$(uname)" == "Darwin" ]]; then
        open "${url}"
    else
        xdg-open "${url}"
    fi

# Open the browser for a running GitHuman instance, or start a new one.
[group('githuman')]
[no-cd]
githuman-open $directory=".":
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -d "${directory}" ]]; then
        echo "❌ Directory not found: ${directory}"
        exit 1
    fi

    target_dir=$(cd -P "${directory}" && pwd -P)

    match=$(docker ps --filter "label={{githuman_label}}=true" \
        --format '{{ "{{" }}.Label "{{githuman_label}}.directory"{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.fqdn"{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.token"{{ "}}" }}' 2>/dev/null \
        | awk -F'|' -v dir="${target_dir}" '$1 == dir' || true)

    if [[ -z "${match}" ]]; then
        just --justfile "{{justfile()}}" githuman-start "${directory}"
        exit 0
    fi

    IFS='|' read -r _dir fqdn token <<< "${match}"
    url="https://${fqdn}?token=${token}"
    echo "🌐 Opening ${url}"
    if [[ "$(uname)" == "Darwin" ]]; then
        open "${url}"
    else
        xdg-open "${url}"
    fi

# Print the container ID for a running GitHuman instance.
[group('githuman')]
[no-cd]
githuman-id $directory=".":
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -d "${directory}" ]]; then
        echo "❌ Directory not found: ${directory}"
        exit 1
    fi

    target_dir=$(cd -P "${directory}" && pwd -P)

    container_id=$(docker ps --filter "label={{githuman_label}}=true" \
        --format '{{ "{{" }}.Label "{{githuman_label}}.directory"{{ "}}" }}|{{ "{{" }}.ID{{ "}}" }}' 2>/dev/null \
        | awk -F'|' -v dir="${target_dir}" '$1 == dir {print $2}' || true)

    if [[ -z "${container_id}" ]]; then
        echo "No GitHuman instance running for this directory. Use 'githuman-start' to start one."
        exit 1
    fi

    echo "${container_id}"

# Run a GitHuman CLI command inside a running container for the current directory.
[group('githuman')]
[no-cd]
githuman-exec *args='':
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -z "{{args}}" ]]; then
        echo "Usage: sjust githuman-exec <githuman-command...>"
        echo "Example: sjust githuman-exec review list"
        exit 1
    fi

    target_dir=$(pwd -P)

    container_name=$(docker ps --filter "label={{githuman_label}}=true" \
        --format '{{ "{{" }}.Label "{{githuman_label}}.directory"{{ "}}" }}|{{ "{{" }}.Names{{ "}}" }}' 2>/dev/null \
        | awk -F'|' -v dir="${target_dir}" '$1 == dir {print $2}' || true)

    if [[ -z "${container_name}" ]]; then
        echo "❌ No GitHuman instance running for ${target_dir}"
        echo "💡 Run 'sjust githuman-start' first to start an instance."
        exit 1
    fi

    exec_flags="-i"
    if [ -t 0 ]; then
        exec_flags="-it"
    fi

    docker exec ${exec_flags} "${container_name}" npx githuman@{{githuman_version}} {{args}}

# List all running GitHuman instances.
[group('githuman')]
githuman-list:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{source_directory()}}/../../libs/libformatting.sh"
    source "{{source_directory()}}/../../libs/libcolors.sh"

    containers=$(docker ps --filter "label={{githuman_label}}=true" \
        --format '{{ "{{" }}.Names{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.directory"{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.fqdn"{{ "}}" }}|{{ "{{" }}.Label "{{githuman_label}}.token"{{ "}}" }}' 2>/dev/null || true)

    if [[ -z "${containers}" ]]; then
        echo "No GitHuman instances running."
        exit 0
    fi

    echo "${bold}GitHuman Instances${normal}"
    echo ""
    while IFS='|' read -r name dir fqdn_val token_val; do
        url="https://${fqdn_val}?token=${token_val}"
        echo "  📦 ${bold}${name}${normal}"
        echo "     📁 ${dir}"
        echo "     🌐 $(Urllink "${url}" "${fqdn_val}")"
        echo ""
    done <<< "${containers}"

# Show logs for a GitHuman instance (interactive selection if no name given).
[group('githuman')]
githuman-logs $name="":
    #!/usr/bin/env bash
    set -euo pipefail

    selected="${name}"
    if [[ -z "${selected}" ]]; then
        mapfile -t names < <(docker ps --filter "label={{githuman_label}}=true" --format '{{ "{{" }}.Names{{ "}}" }}' 2>/dev/null)
        if [[ ${#names[@]} -eq 0 ]]; then
            echo "No GitHuman instances running."
            exit 0
        fi
        echo "Select a GitHuman instance:"
        select choice in "${names[@]}"; do
            if [[ -n "${choice}" ]]; then
                selected="${choice}"
                break
            fi
            echo "Invalid selection, try again."
        done
    fi

    if ! docker ps -q --filter "name=^${selected}$" --filter "label={{githuman_label}}=true" 2>/dev/null | grep -q .; then
        echo "⚠️  No GitHuman instance found with name '${selected}'"
        exit 1
    fi

    docker logs -f "${selected}"

# Stop a GitHuman instance (interactive selection if no name given, with stop-all option).
[group('githuman')]
githuman-stop $name="":
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -n "${name}" ]]; then
        if docker ps -q --filter "name=^${name}$" --filter "label={{githuman_label}}=true" 2>/dev/null | grep -q .; then
            docker stop "${name}" > /dev/null
            echo "✅ Stopped ${name}"
        else
            echo "⚠️  No GitHuman instance found with name '${name}'"
        fi
        exit 0
    fi

    mapfile -t names < <(docker ps --filter "label={{githuman_label}}=true" --format '{{ "{{" }}.Names{{ "}}" }}' 2>/dev/null)
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "No GitHuman instances running."
        exit 0
    fi

    echo "Select a GitHuman instance to stop:"
    select choice in "${names[@]}" "Stop all"; do
        if [[ "${choice}" == "Stop all" ]]; then
            for cname in "${names[@]}"; do
                docker stop "${cname}" > /dev/null
                echo "✅ Stopped ${cname}"
            done
            break
        elif [[ -n "${choice}" ]]; then
            docker stop "${choice}" > /dev/null
            echo "✅ Stopped ${choice}"
            break
        fi
        echo "Invalid selection, try again."
    done

# Stop all GitHuman instances and remove the shared npm cache volume.
[group('githuman')]
githuman-purge:
    #!/usr/bin/env bash
    set -euo pipefail

    container_ids=$(docker ps -q --filter "label={{githuman_label}}=true" 2>/dev/null || true)
    if [[ -n "${container_ids}" ]]; then
        for cid in ${container_ids}; do
            cname=$(docker inspect --format '{{ "{{" }}.Name{{ "}}" }}' "${cid}" | sed 's/^\///')
            docker stop "${cid}" > /dev/null
            echo "✅ Stopped ${cname}"
        done
    fi

    if docker volume inspect {{githuman_cache_volume}} > /dev/null 2>&1; then
        docker volume rm {{githuman_cache_volume}} > /dev/null
        echo "✅ Removed npm cache volume ({{githuman_cache_volume}})"
    fi

    if docker volume inspect {{githuman_data_volume}} > /dev/null 2>&1; then
        docker volume rm {{githuman_data_volume}} > /dev/null
        echo "✅ Removed data volume ({{githuman_data_volume}})"
    fi

    echo "🧹 GitHuman purge complete"
