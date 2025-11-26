# vim: set ft=make :

# Security scanning commands for Sparkdock

# Scan current directory for NPM supply chain attacks
[group('security')]
security-scan-npm dir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" "{{dir}}"

# Scan for specific NPM supply chain attack
[group('security')]
security-scan-npm-attack attack dir=".":
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" -a "{{attack}}" "{{dir}}"

# List all available NPM supply chain attacks
[group('security')]
security-list-attacks:
    #!/usr/bin/env bash
    set -euo pipefail
    "{{sparkdock_path}}/bin/security/npm-supply-chain-detector" --list-attacks

# Update the Shai-Hulud 2.0 attack database from the Wiz IOC repository
[group('security')]
security-update-shai-hulud:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{sparkdock_path}}/sjust/libs/libshell.sh"

    local_file="{{sparkdock_path}}/bin/security/attacks/shai-hulud-2.txt"
    remote_csv="https://raw.githubusercontent.com/wiz-sec-public/wiz-research-iocs/main/reports/shai-hulud-2-packages.csv"

    echo "🔄 Updating Shai-Hulud 2.0 attack database..."
    echo "📥 Fetching from: ${remote_csv}"

    # Create header
    cat > "${local_file}" << 'HEADER'
# Shai-Hulud 2.0 Attack - Compromised NPM Packages
# Date: November 21-23, 2025
# Source: https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack
# Data: https://github.com/wiz-sec-public/wiz-research-iocs/blob/main/reports/shai-hulud-2-packages.csv
# Format: ["package-name"]="version"

HEADER

    # Fetch and convert CSV to expected format
    curl -sL "${remote_csv}" | tail -n +2 | awk -F',' '{
      # Remove "= " prefix from version
      gsub(/^= /, "", $2);
      # Handle multiple versions separated by " || "
      split($2, versions, " \\|\\| ");
      for (i in versions) {
        gsub(/^= /, "", versions[i]);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", versions[i]);
        if (versions[i] != "") {
          print "[\"" $1 "\"]=\"" versions[i] "\""
        }
      }
    }' >> "${local_file}"

    count=$(grep -c '^\["' "${local_file}" || echo "0")
    echo "✅ Updated shai-hulud-2.txt with ${count} package entries"

# Run security scanner tests against test fixtures
[group('security')]
security-test:
    #!/usr/bin/env bash
    set -euo pipefail

    test_dir="{{sparkdock_path}}/bin/security/test"
    scanner="{{sparkdock_path}}/bin/security/npm-supply-chain-detector"
    failed=0

    echo "🧪 Running security scanner tests..."
    echo ""

    # Test 1: Safe directory should have 0 issues
    echo "Test 1: Safe directory (expecting 0 issues)..."
    result=$("${scanner}" "${test_dir}/safe" 2>&1 || true)
    if echo "${result}" | grep -q "Issues found: 0"; then
        echo "  ✅ PASSED: Safe directory correctly detected as clean"
    else
        echo "  ❌ FAILED: Safe directory was not detected as clean"
        failed=$((failed + 1))
    fi

    # Test 2: Shai-Hulud compromised directory should have issues
    echo "Test 2: Shai-Hulud 2.0 compromised directory (expecting issues)..."
    result=$("${scanner}" "${test_dir}/compromised/shai-hulud-2" 2>&1 || true)
    if echo "${result}" | grep -q "COMPROMISED VERSION FOUND"; then
        echo "  ✅ PASSED: Shai-Hulud compromised packages detected"
    else
        echo "  ❌ FAILED: Shai-Hulud compromised packages not detected"
        failed=$((failed + 1))
    fi

    # Test 3: September 2025 qix compromised directory should have issues
    echo "Test 3: September 2025 qix- compromised directory (expecting issues)..."
    result=$("${scanner}" "${test_dir}/compromised/september-2025-qix" 2>&1 || true)
    if echo "${result}" | grep -q "COMPROMISED VERSION FOUND"; then
        echo "  ✅ PASSED: September 2025 qix- compromised packages detected"
    else
        echo "  ❌ FAILED: September 2025 qix- compromised packages not detected"
        failed=$((failed + 1))
    fi

    echo ""
    if [ ${failed} -eq 0 ]; then
        echo "🎉 All tests passed!"
    else
        echo "❌ ${failed} test(s) failed"
        exit 1
    fi
