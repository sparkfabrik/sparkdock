#!/usr/bin/env bash
# Test script for launchctl-helper.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SCRIPT="${SCRIPT_DIR}/../bin/launchctl-helper.sh"

echo "Testing launchctl-helper.sh functionality..."

# Test 1: Help output
echo "Test 1: Help output"
if "${HELPER_SCRIPT}" --help | grep -q "Usage:"; then
    echo "✅ Help output works"
else
    echo "❌ Help output failed"
    exit 1
fi

# Test 2: Invalid command
echo "Test 2: Invalid command handling"
if "${HELPER_SCRIPT}" invalid-command 2>/dev/null; then
    echo "❌ Should have failed on invalid command"
    exit 1
else
    echo "✅ Invalid command properly rejected"
fi

# Test 3: Missing plist path
echo "Test 3: Missing plist path"
if "${HELPER_SCRIPT}" load 2>/dev/null; then
    echo "❌ Should have failed on missing plist path"
    exit 1
else
    echo "✅ Missing plist path properly rejected"
fi

# Test 4: Non-existent plist file (for load)
echo "Test 4: Non-existent plist file"
if "${HELPER_SCRIPT}" load "/nonexistent/file.plist" 2>/dev/null; then
    echo "❌ Should have failed on non-existent plist"
    exit 1
else
    echo "✅ Non-existent plist properly rejected"
fi

# Test 5: Shell check validation
echo "Test 5: Shell check validation"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "${HELPER_SCRIPT}"; then
        echo "✅ Shell check passed"
    else
        echo "❌ Shell check failed"
        exit 1
    fi
else
    echo "⚠️  shellcheck not available, skipping validation"
fi

echo "All tests passed! ✅"