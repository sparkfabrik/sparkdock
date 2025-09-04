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
    echo "=== FIRST RUN: Fresh installation ==="
    tart exec sparkdock-test bash -c "cd /Volumes/My\ Shared\ Files/sparkdock && ./bin/install.macos --non-interactive"
    echo "=== Validating first installation ==="
    tart exec sparkdock-test bash -c "test -d '/opt/sparkdock' && echo '✅ /opt/sparkdock exists' || (echo '❌ /opt/sparkdock missing' && exit 1)"
    tart exec sparkdock-test bash -c "test -L '/usr/local/bin/sparkdock' && echo '✅ sparkdock symlink exists' || (echo '❌ sparkdock symlink missing' && exit 1)"
    tart exec sparkdock-test bash -c "command -v sjust >/dev/null 2>&1 && echo '✅ sjust available' || (echo '❌ sjust missing' && exit 1)"
    echo "=== SECOND RUN: Already provisioned machine ==="
    tart exec sparkdock-test bash -c "cd /Volumes/My\ Shared\ Files/sparkdock && ./bin/install.macos --non-interactive"
    echo "=== Validating second installation (idempotency) ==="
    tart exec sparkdock-test bash -c "test -d '/opt/sparkdock' && echo '✅ /opt/sparkdock still exists' || (echo '❌ /opt/sparkdock missing after second run' && exit 1)"
    tart exec sparkdock-test bash -c "test -L '/usr/local/bin/sparkdock' && echo '✅ sparkdock symlink still exists' || (echo '❌ sparkdock symlink missing after second run' && exit 1)"
    tart exec sparkdock-test bash -c "command -v sjust >/dev/null 2>&1 && echo '✅ sjust still available' || (echo '❌ sjust missing after second run' && exit 1)"
    tart exec sparkdock-test bash -c "sjust --list > /dev/null && echo '✅ sjust functionality verified' || (echo '❌ sjust not working after second run' && exit 1)"
    echo "✅ Both installation runs completed successfully"

# Run end-to-end sparkdock test using Cirrus CLI
test-e2e-with-cirrus:
    #!/usr/bin/env bash
    if ! command -v cirrus >/dev/null 2>&1; then
        echo "Installing Cirrus CLI via Homebrew..."
        brew install cirruslabs/cli/cirrus
    fi
    echo "Running sparkdock end-to-end test with Cirrus CLI..."
    cirrus run --output simple
