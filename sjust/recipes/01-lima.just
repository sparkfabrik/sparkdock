# Default values
lima_default_name := "sf-docker-dev"
lima_default_cpus := "4"
lima_default_memory := "8"
lima_default_disk := "100"

[group('lima')]
lima-quick-setup cpus=lima_default_cpus memory=lima_default_memory disk=lima_default_disk:
    #!/usr/bin/env bash
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
    read -p "Proceed with quick setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Setup cancelled."
        exit 0
    fi

    # Create the VM using lima-create-vm with default values
    echo "Creating Lima VM..."
    if sjust lima-create-vm {{ cpus }} {{ memory }} {{ disk }}; then
        echo "Setting up Docker context..."
        sjust lima-set-docker-context

        echo "Enabling auto-start at login..."
        sjust lima-enable-autostart

        echo "✅ Quick setup completed! You can now use the Lima VM with Docker."
    else
        echo "❌ Quick setup failed during VM creation!"
        exit 1
    fi

# Create Lima VM with optional custom settings
[group('lima')]
lima-create-vm cpus=lima_default_cpus memory=lima_default_memory disk=lima_default_disk:
    #!/usr/bin/env bash
    echo "Creating Lima VM '{{ lima_default_name }}' with {{ cpus }} CPUs, {{ memory }}GB RAM, {{ disk }}GB disk..."
    if limactl create --name={{ lima_default_name }} \
      -y \
      --vm-type=vz \
      --mount-type=virtiofs \
      --mount-writable \
      --memory={{ memory }} \
      --cpus={{ cpus }} \
      --disk={{ disk }} \
      template://docker; then
        limactl start {{ lima_default_name }} -y
        echo "✅ Lima VM '{{ lima_default_name }}' created and started successfully!"
    else
        echo "❌ Failed to create Lima VM '{{ lima_default_name }}'!"
        echo "💡 Check if the VM name already exists or if Lima is properly installed."
        exit 1
    fi

# Remove Lima VM and its Docker context.
[group('lima')]
lima-destroy:
    #!/usr/bin/env bash
    read -p "Are you sure you want to remove the Lima VM '{{ lima_default_name }}'? This action cannot be undone. (y/N): " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Removal cancelled."
        exit 0
    fi
    echo "Removing Lima VM '{{ lima_default_name }}'..."
    limactl stop {{ lima_default_name }}
    if limactl delete {{ lima_default_name }}; then
        echo "✅ Lima VM '{{ lima_default_name }}' removed successfully!"
    else
        echo "❌ Failed to remove Lima VM '{{ lima_default_name }}'!"
        echo "💡 Check if the VM exists with: sjust lima-status"
        exit 1
    fi
    echo "Removing Docker context for Lima VM '{{ lima_default_name }}'..."
    if docker context rm -f lima-{{ lima_default_name }} 1>/dev/null; then
        echo "✅ Docker context for Lima VM '{{ lima_default_name }}' removed successfully!"
    fi

# Configure Docker context for Lima VM
[group('lima')]
lima-set-docker-context:
    #!/usr/bin/env bash
    echo "Configuring Docker context for Lima VM '{{ lima_default_name }}'..."
    docker context rm -f lima-{{ lima_default_name }} 1>/dev/null

    if docker context create lima-{{ lima_default_name }} \
      --docker "host=unix://$HOME/.lima/{{ lima_default_name }}/sock/docker.sock" 1> /dev/null; then
        if docker context use lima-{{ lima_default_name }} 1> /dev/null; then
            echo ""
            docker context ls
            echo ""
            echo "✅ Docker context set to Lima VM '{{ lima_default_name }}'!"
        else
            echo "❌ Failed to switch to Docker context lima-{{ lima_default_name }}!"
            exit 1
        fi
    else
        echo "❌ Failed to create Docker context for Lima VM '{{ lima_default_name }}'!"
        echo "💡 Make sure the VM is running and Docker socket is available."
        exit 1
    fi

# Enable auto-start at login
[group('lima')]
lima-enable-autostart:
    #!/usr/bin/env bash
    echo "Enabling auto-start for Lima VM '{{ lima_default_name }}'..."
    if limactl start-at-login {{ lima_default_name }} --enabled; then
        echo "✅ Lima VM '{{ lima_default_name }}' will start automatically at login!"
    else
        echo "❌ Failed to enable auto-start for Lima VM '{{ lima_default_name }}'!"
        echo "💡 Check if the VM exists with: sjust lima-status"
        exit 1
    fi

# Disable auto-start at login
[group('lima')]
lima-disable-autostart name=lima_default_name:
    #!/usr/bin/env bash
    echo "Disabling auto-start for Lima VM '{{ name }}'..."
    if limactl start-at-login {{ name }} --enabled=false; then
        echo "✅ Lima VM '{{ name }}' auto-start disabled!"
    else
        echo "❌ Failed to disable auto-start for Lima VM '{{ name }}'!"
        echo "💡 Check if the VM exists with: sjust lima-status"
        exit 1
    fi

# Switch between Docker contexts
[group('lima')]
switch-to-docker-desktop:
    #!/usr/bin/env bash
    echo "Switching to Docker Desktop context..."
    if docker context use desktop-linux; then
        echo "✅ Now using Docker Desktop!"
    else
        echo "❌ Failed to switch to Docker Desktop context!"
        echo "💡 Make sure Docker Desktop is installed and running."
        exit 1
    fi

# Switch to Lima Docker context
[group('lima')]
switch-to-lima name=lima_default_name:
    #!/usr/bin/env bash
    echo "Switching to Lima context..."
    if docker context use lima-{{ lima_default_name }}; then
        echo "✅ Now using Lima VM '{{ lima_default_name }}'!"
    else
        echo "❌ Failed to switch to Lima context lima-{{ lima_default_name }}!"
        echo "💡 Make sure the Docker context exists. Use: sjust lima-set-docker-context {{ lima_default_name }}"
        exit 1
    fi

# Internal helper: Update Lima VM configuration (stops, edits, starts VM)
_lima-update-config config_type value unit="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Determine the display unit
    display_unit="{{ if unit == "" { "" } else { unit } }}"

    echo "Setting {{ config_type }} for VM '{{ lima_default_name }}' to {{ value }}${display_unit}..."

    # Check VM status and stop if running
    vm_status=$(limactl list {{ lima_default_name }} --format 'json' | jq -r '.status' 2>/dev/null || echo "NotFound")

    if [ "$vm_status" = "Running" ]; then
        echo "Stopping VM..."
        stop_output=$(limactl stop {{ lima_default_name }} 2>&1)
        if [ $? -ne 0 ]; then
            echo "❌ Failed to stop VM '{{ lima_default_name }}'!"
            echo "$stop_output"
            exit 1
        fi
    elif [ "$vm_status" = "NotFound" ]; then
        echo "❌ VM '{{ lima_default_name }}' does not exist!"
        exit 1
    fi

    # Update configuration
    if limactl edit {{ lima_default_name }} --{{ config_type }} {{ value }} >/dev/null; then
        echo "✅ {{ config_type }} updated to {{ value }}${display_unit}"
    else
        echo "❌ Failed to update {{ config_type }} configuration!"
        exit 1
    fi

    # Start the VM
    echo "Starting VM..."
    start_output=$(limactl start {{ lima_default_name }} -y 2>&1)
    if [ $? -ne 0 ]; then
        echo "❌ Failed to start VM '{{ lima_default_name }}'!"
        echo "$start_output"
        exit 1
    fi

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
    echo "Configuration for Lima VM '{{ lima_default_name }}':"
    if limactl list {{ lima_default_name }} >/dev/null 2>&1; then
        limactl list {{ lima_default_name }} --format 'table'
        echo ""
        echo "Detailed configuration:"
        echo "Run 'limactl info {{ lima_default_name }}' for full details"
    else
        echo "❌ VM '{{ lima_default_name }}' does not exist."
        echo "💡 Use 'sjust lima-create {{ lima_default_name }}' to create it first."
    fi

# List the lima vms.
[group('lima')]
lima-list:
    #!/usr/bin/env bash
    limactl list --format 'table'
