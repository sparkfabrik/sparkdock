#!/usr/bin/env bash
# Test script to verify Sparkdock shell configuration
set -euo pipefail

echo "Testing Sparkdock Shell Configuration..."
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

FAILURES=0

# Determine sparkdock directory
if [[ -d "/opt/sparkdock" ]]; then
    SPARKDOCK_DIR="/opt/sparkdock"
else
    # Assume we're running from the repo
    SPARKDOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

echo "Using Sparkdock directory: ${SPARKDOCK_DIR}"
echo ""

# Test function
test_file() {
    local file="$1"
    local description="$2"

    if [[ -f "${file}" ]]; then
        echo -e "${GREEN}✓${NC} ${description}"
    else
        echo -e "${RED}✗${NC} ${description}"
        FAILURES=$((FAILURES + 1))
    fi
}

test_content() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -q "${pattern}" "${file}"; then
        echo -e "${GREEN}✓${NC} ${description}"
    else
        echo -e "${RED}✗${NC} ${description}"
        FAILURES=$((FAILURES + 1))
    fi
}

# Test file existence
echo "1. Testing file structure..."
test_file "${SPARKDOCK_DIR}/config/shell/sparkdock.zshrc" "Main config file exists"
test_file "${SPARKDOCK_DIR}/config/shell/aliases.zsh" "Aliases file exists"
test_file "${SPARKDOCK_DIR}/config/shell/init.zsh" "Init file exists"
test_file "${SPARKDOCK_DIR}/config/shell/README.md" "Documentation exists"

echo ""
echo "2. Testing package configuration..."
test_content "${SPARKDOCK_DIR}/config/packages/all-packages.yml" "ripgrep" "ripgrep in package list"
test_content "${SPARKDOCK_DIR}/config/packages/all-packages.yml" "zoxide" "zoxide in package list"
test_content "${SPARKDOCK_DIR}/config/packages/all-packages.yml" "fd" "fd in package list"
test_content "${SPARKDOCK_DIR}/config/packages/all-packages.yml" "bat" "bat in package list"

echo ""
echo "3. Testing configuration content..."
test_content "${SPARKDOCK_DIR}/config/shell/aliases.zsh" "eza" "eza aliases present"
test_content "${SPARKDOCK_DIR}/config/shell/aliases.zsh" "ls()" "ls function defined"
test_content "${SPARKDOCK_DIR}/config/shell/init.zsh" "zoxide" "zoxide initialization"
test_content "${SPARKDOCK_DIR}/config/shell/init.zsh" "fzf" "fzf initialization"
echo ""
echo "4. Testing sjust recipes..."
test_content "${SPARKDOCK_DIR}/sjust/recipes/03-shell.just" "shell-enable" "shell-enable recipe exists"
test_content "${SPARKDOCK_DIR}/sjust/recipes/03-shell.just" "shell-disable" "shell-disable recipe exists"
test_content "${SPARKDOCK_DIR}/sjust/recipes/03-shell.just" "shell-info" "shell-info recipe exists"

echo ""
echo "5. Testing installer hook..."
test_content "${SPARKDOCK_DIR}/bin/sparkdock.macos" "sjust shell-enable" "shell configuration triggered after provisioning"

echo ""
if [[ ${FAILURES} -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ ${FAILURES} test(s) failed${NC}"
    exit 1
fi
