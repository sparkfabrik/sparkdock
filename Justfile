_default:
    @just --list

run-ansible-macos TAGS="all":
    #!/usr/bin/env bash
    TAGS={{TAGS}}
    if [ -z "${TAGS}" ]; then
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini --ask-become-pass -v
    else
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini --ask-become-pass --tags=${TAGS} -v
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
    if ! tart list | grep -q "sparkdock-test"; then
        tart clone {{IMAGE}} sparkdock-test
        echo "✅ VM 'sparkdock-test' created successfully"
    fi

# Start VM and connect via SSH
tart-ssh: tart-create-vm
    #!/usr/bin/env bash
    echo "Starting VM and connecting via SSH..."
    echo "Note: This will start the VM in the background and connect via SSH"
    echo "VM credentials: admin/admin"
    echo "Sparkdock source will be mounted at /opt/sparkdock-src"
    tart run  --dir=sparkdock-src:$PWD sparkdock-test &
    echo "Waiting for VM to boot..."
    sleep 30
    VM_IP=$(tart ip sparkdock-test 2>/dev/null || echo "")
    if [ -n "$VM_IP" ]; then
        echo "Connecting to VM at $VM_IP..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$VM_IP
    else
        echo "❌ Could not get VM IP address. Make sure the VM is running."
        echo "You can manually check with: tart list"
        exit 1
    fi

# Run end-to-end sparkdock test using Cirrus CLI
test-e2e-with-cirrus:
    #!/usr/bin/env bash
    if ! command -v cirrus >/dev/null 2>&1; then
        echo "Installing Cirrus CLI via Homebrew..."
        brew install cirruslabs/cli/cirrus
    fi
    echo "Running sparkdock end-to-end test with Cirrus CLI..."
    cirrus run --output simple
