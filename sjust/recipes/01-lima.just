# Default values
lima_default_name := "sf-docker-dev"
lima_default_cpus := "4"
lima_default_memory := "8"
lima_default_disk := "100"

[group('lima')]
lima-quick-setup cpus=lima_default_cpus memory=lima_default_memory disk=lima_default_disk:
    #!/usr/bin/env bash
    set -euo pipefail

    if limactl list | grep -q "{{ lima_default_name }}"; then
        echo "❌ A Lima VM named '{{ lima_default_name }}' already exists. Please remove it first with 'sjust lima-destroy'."
        exit 1
    fi
    echo "🚀 Lima VM Quick Setup"
    echo "======================"
    echo ""
    echo "📋 VM Configuration:"
    echo "   • Name: {{ lima_default_name }}"
    echo "   • CPUs: {{ cpus }}"
    echo "   • Memory: {{ memory }}GB"
    echo "   • Disk: {{ disk }}GB"
    echo ""
    echo "🔧 Additional Setup:"
    echo "   • Docker context configuration"
    echo "   • Auto-start at login"
    echo ""
    echo "💡 Want different specs? Use:"
    echo "   sjust lima-quick-setup cpus=6 memory=16 disk=200"
    echo ""
    just _confirm_action "Proceed with quick setup?"

    # Create the VM using lima-create-vm with default values
    echo "Creating Lima VM..."
    sjust lima-create-vm {{ cpus }} {{ memory }} {{ disk }}

    echo "Setting up Docker context..."
    sjust lima-set-docker-context

    echo "Enabling auto-start at login..."
    sjust lima-enable-autostart

    echo "✅ Quick setup completed! You can now use the Lima VM with Docker."

# Create Lima VM with optional custom settings
[group('lima')]
lima-create-vm cpus=lima_default_cpus memory=lima_default_memory disk=lima_default_disk:
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if VM already exists
    if limactl list | grep -q "{{ lima_default_name }}"; then
        echo "❌ A Lima VM named '{{ lima_default_name }}' already exists!"
        echo ""
        echo "Current Lima VMs:"
        limactl list --format 'table'
        echo ""
        echo "💡 To remove the existing VM, use: sjust lima-destroy"
        echo "💡 To use a different name, edit the lima_default_name variable"
        exit 1
    fi

    echo "Creating Lima VM '{{ lima_default_name }}' with {{ cpus }} CPUs, {{ memory }}GB RAM, {{ disk }}GB disk..."
    limactl create --name={{ lima_default_name }} \
      -y \
      --vm-type=vz \
      --mount-type=virtiofs \
      --mount-writable \
      --memory={{ memory }} \
      --cpus={{ cpus }} \
      --disk={{ disk }} \
      template://docker

    echo "Starting Lima VM..."
    limactl start {{ lima_default_name }} -y
    echo "✅ Lima VM '{{ lima_default_name }}' created and started successfully!"

# Remove Lima VM and its Docker context.
[group('lima')]
lima-destroy:
    #!/usr/bin/env bash
    set -euo pipefail

    just _confirm_action "Are you sure you want to remove the Lima VM '{{ lima_default_name }}'? This action cannot be undone."

    echo "Stopping Lima VM..."
    limactl stop {{ lima_default_name }}
    echo "Removing Lima VM '{{ lima_default_name }}'..."
    limactl delete {{ lima_default_name }}
    echo "✅ Lima VM '{{ lima_default_name }}' removed successfully!"

    echo "Removing Docker context for Lima VM '{{ lima_default_name }}'..."
    docker context rm -f lima-{{ lima_default_name }} >/dev/null || true

    echo "Disabling auto-start for Lima VM '{{ lima_default_name }}'..."
    limactl start-at-login {{ lima_default_name }} --enabled=false || true

    echo "Cleaning up Docker socket symlink..."
    just _lima-cleanup-docker-socket

    echo "✅ Docker context for Lima VM '{{ lima_default_name }}' removed successfully!"

# Configure Docker context for Lima VM
[group('lima')]
lima-set-docker-context:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Configuring Docker context for Lima VM '{{ lima_default_name }}'..."
    docker context rm -f lima-{{ lima_default_name }} >/dev/null || true

    echo "Creating Docker context..."
    docker context create lima-{{ lima_default_name }} \
      --docker "host=unix://$HOME/.lima/{{ lima_default_name }}/sock/docker.sock" >/dev/null

    echo "Switching to Lima Docker context..."
    docker context use lima-{{ lima_default_name }} >/dev/null

    echo "Setting up Docker socket symlink..."
    just _lima-setup-docker-socket

    echo ""
    docker context ls
    echo ""
    echo "✅ Docker context set to Lima VM '{{ lima_default_name }}'!"

# Enable auto-start at login
[group('lima')]
lima-enable-autostart:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Enabling auto-start for Lima VM '{{ lima_default_name }}'..."
    limactl start-at-login {{ lima_default_name }} --enabled
    echo "✅ Lima VM '{{ lima_default_name }}' will start automatically at login!"

# Disable auto-start at login
[group('lima')]
lima-disable-autostart:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Disabling auto-start for Lima VM '{{ lima_default_name }}'..."
    limactl start-at-login {{ lima_default_name }} --enabled=false
    echo "✅ Lima VM '{{ lima_default_name }}' auto-start disabled!"

# Switch between Docker contexts
[group('lima')]
switch-to-docker-desktop-context:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Switching to Docker Desktop context..."
    desktop_context=$(docker context ls --format '{{{{.Name}}}}' | grep -E '^desktop-' || true)
    if [ -z "$desktop_context" ]; then
        echo "❌ No Docker Desktop context found. Please ensure Docker Desktop is installed and configured."
        exit 1
    fi
    docker context use "$desktop_context"

    echo "Cleaning up Lima Docker socket symlink..."
    just _lima-cleanup-docker-socket

    echo "✅ Now using Docker Desktop context '$desktop_context'!"

# Switch to Lima Docker context
[group('lima')]
switch-to-lima-docker-context:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Switching to Lima context..."
    docker context use lima-{{ lima_default_name }}

    echo "Setting up Docker socket symlink..."
    just _lima-setup-docker-socket

    echo "✅ Now using Lima VM '{{ lima_default_name }}'!"

# Internal helper: Ask for user confirmation
_confirm_action message:
    #!/usr/bin/env bash
    set -euo pipefail

    read -p "{{ message }} (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled."
        exit 0
    fi

# Internal helper: Update Lima VM configuration (stops, edits, starts VM)
_lima-update-config config_type value unit="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Determine the display unit
    display_unit="{{ unit }}"

    echo "Setting {{ config_type }} for VM '{{ lima_default_name }}' to {{ value }}${display_unit}..."

    # Check VM status and stop if running
    vm_status=$(limactl list {{ lima_default_name }} --format 'json' | jq -r '.status' 2>/dev/null || echo "NotFound")

    if [ "$vm_status" = "NotFound" ]; then
        echo "❌ VM '{{ lima_default_name }}' does not exist!"
        exit 1
    fi

    if [ "$vm_status" = "Running" ]; then
        echo "Stopping VM..."
        limactl stop {{ lima_default_name }}
    fi

    # Update configuration
    echo "Updating {{ config_type }} configuration..."
    limactl edit {{ lima_default_name }} --{{ config_type }} {{ value }} >/dev/null
    echo "✅ {{ config_type }} updated to {{ value }}${display_unit}"

    # Start the VM
    echo "Starting VM..."
    limactl start {{ lima_default_name }} -y

    echo "✅ VM '{{ lima_default_name }}' is now running with updated {{ config_type }}!"

# Set CPU count for Lima VM (stops, edits, starts VM)
[group('lima')]
lima-set-cpus cpus:
    @just _lima-update-config "cpus" "{{ cpus }}" " cores"

# Set memory size for Lima VM (stops, edits, starts VM)
[group('lima')]
lima-set-memory memory:
    @just _lima-update-config "memory" "{{ memory }}" "GB"

# Set disk size for Lima VM (stops, edits, starts VM)
[group('lima')]
lima-set-disk disk:
    @just _lima-update-config "disk" "{{ disk }}" "GB"

# Show current VM configuration
[group('lima')]
lima-show-config name=lima_default_name:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Configuration for Lima VM '{{ name }}':"
    if limactl list {{ name }} >/dev/null 2>&1; then
        limactl list {{ name }} --format 'table'
        echo ""
        echo "Detailed configuration:"
        echo "Run 'limactl info {{ name }}' for full details"
    else
        echo "❌ VM '{{ name }}' does not exist."
        echo "💡 Use 'sjust lima-create-vm' to create it first."
    fi

# Start the default Lima VM
[group('lima')]
lima-start:
    limactl start {{ lima_default_name }} -y

# Stop the default Lima VM
[group('lima')]
lima-stop:
    limactl stop {{ lima_default_name }}

# Show status of the default Lima VM
[group('lima')]
lima-status:
    limactl list {{ lima_default_name }} --format table

# List the lima vms.
[group('lima')]
lima-list:
    #!/usr/bin/env bash
    set -euo pipefail

    limactl list --format 'table'

# Internal helper: Setup Docker socket symlink for Lima
_lima-setup-docker-socket:
    #!/usr/bin/env bash
    set -euo pipefail

    lima_socket="$HOME/.lima/{{ lima_default_name }}/sock/docker.sock"
    system_socket="/var/run/docker.sock"

    # Check if Lima socket exists
    if [ ! -S "${lima_socket}" ]; then
        echo "⚠️  Lima Docker socket not found at ${lima_socket}"
        echo "💡 Make sure Lima VM '{{ lima_default_name }}' is running"
        return 0
    fi

    # Remove existing symlink if it exists
    if [ -L "${system_socket}" ]; then
        sudo rm "${system_socket}"
    fi

    # Create symlink to Lima socket
    sudo ln -sf "${lima_socket}" "${system_socket}"
    echo "✅ Docker socket symlinked: ${system_socket} → ${lima_socket}"

# Internal helper: Cleanup Lima Docker socket symlink
_lima-cleanup-docker-socket:
    #!/usr/bin/env bash
    set -euo pipefail

    system_socket="/var/run/docker.sock"
    lima_socket="$HOME/.lima/{{ lima_default_name }}/sock/docker.sock"

    # Only remove the symlink if it points to our Lima socket
    if [ -L "${system_socket}" ]; then
        current_target=$(readlink "${system_socket}" || true)
        if [ "${current_target}" = "${lima_socket}" ]; then
            sudo rm "${system_socket}"
            echo "✅ Lima Docker socket symlink removed"
        fi
    fi
