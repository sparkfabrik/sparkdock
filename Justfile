_default:
    @just --list

run-ansible-playbook TAGS="all":
    #!/usr/bin/env bash
    set -euo pipefail

    # Unset the password on exit
    trap 'unset ANSIBLE_BECOME_PASS' EXIT

    TAGS={{TAGS}}

    # Ensure Python3 is installed and available at the expected location
    if [[ ! -f /opt/homebrew/bin/python3 ]]; then
        echo "Python3 symlink not found at /opt/homebrew/bin/python3"
        
        # Check if python@3 is installed but not linked
        if brew list python@3 &> /dev/null; then
            echo "Python is installed but not linked, fixing symlinks..."
            brew unlink python@3 &> /dev/null || true
            brew link python@3 &> /dev/null || true
        else
            echo "Installing Python3..."
            brew install python3
        fi
        
        # Verify python3 symlink is now available
        if [[ ! -f /opt/homebrew/bin/python3 ]]; then
            echo "Failed to create python3 symlink. Please run: brew link python@3"
            exit 1
        fi
        echo "Python3 is now available at /opt/homebrew/bin/python3"
    fi

    # Read password and save to env ANSIBLE_BECOME_PASS
    # Check if we're running in CI (GitHub Actions sets these variables)
    if [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
        read -rsp "Enter your password (for sudo access): " ANSIBLE_BECOME_PASS
        export ANSIBLE_BECOME_PASS
        echo
    else
        echo "Running in CI mode, skipping sudo password prompt"
        export ANSIBLE_BECOME_PASS=""
    fi

    # Pass the variable to ansible.
    if [ -z "${TAGS}" ]; then
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini -v
    else
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini --tags=${TAGS} -v
    fi

# Create macOS VM with Tart (installs Tart if needed)
# Available VM images: https://tart.run/quick-start/#vm-images
tart-create-vm IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest":
    #!/usr/bin/env bash
    if ! command -v tart >/dev/null 2>&1; then
        echo "Installing Tart via Homebrew..."
        brew install cirruslabs/cli/tart
    fi
    echo "Creating macOS VM with Tart using image: {{IMAGE}}..."
    killall -9 tart &> /dev/null || true
    tart stop sparkdock-test &> /dev/null || true
    tart delete sparkdock-test &> /dev/null || true
    tart pull {{IMAGE}}
    tart clone {{IMAGE}} sparkdock-test

# Start VM and connect via SSH
tart-ssh: tart-create-vm
    #!/usr/bin/env bash
    echo "Starting VM and connecting via SSH..."
    echo "Note: This will start the VM in the background and connect via SSH"
    echo "VM credentials: admin/admin"
    echo "Sparkdock source will be mounted at /Volumes/sparkdock"
    tart run --dir=sparkdock:$PWD sparkdock-test &
    echo "Waiting for VM to boot..."
    VM_IP=$(tart ip sparkdock-test 2>/dev/null || echo "")
    if [ -n "$VM_IP" ]; then
        echo "Connecting to VM at $VM_IP..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$VM_IP
    else
        echo "❌ Could not get VM IP address. Make sure the VM is running."
        echo "You can manually check with: tart list"
        exit 1
    fi

# Delete the Tart VM.
tart-delete-vm:
    #!/usr/bin/env bash
    echo "Deleting Tart VM 'sparkdock-test'..."
    if tart list | grep -q "sparkdock-test"; then
        tart stop sparkdock-test || true
        tart delete sparkdock-test || true
        killall -9 tart &> /dev/null || true
        echo "✅ VM 'sparkdock-test' deleted successfully"
    fi

test-e2e-with-tart: tart-create-vm
    #!/usr/bin/env bash
    tart run --no-graphics --dir=sparkdock:$PWD sparkdock-test &
    sleep 5
    tart exec sparkdock-test bash -c "cd /Volumes/My\ Shared\ Files/sparkdock && ./bin/install.macos --non-interactive"

# Run end-to-end sparkdock test using Cirrus CLI
test-e2e-with-cirrus:
    #!/usr/bin/env bash
    if ! command -v cirrus >/dev/null 2>&1; then
        echo "Installing Cirrus CLI via Homebrew..."
        brew install cirruslabs/cli/cirrus
    fi
    echo "Running sparkdock end-to-end test with Cirrus CLI..."
    cirrus run --output simple
