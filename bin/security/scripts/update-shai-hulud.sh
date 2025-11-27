#!/usr/bin/env bash
# Update the Shai-Hulud 2.0 attack database from the Wiz IOC repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTACKS_DIR="${SCRIPT_DIR}/../attacks"
LOCAL_FILE="${ATTACKS_DIR}/shai-hulud-2.txt"
REMOTE_CSV="https://raw.githubusercontent.com/wiz-sec-public/wiz-research-iocs/main/reports/shai-hulud-2-packages.csv"

echo "🔄 Updating Shai-Hulud 2.0 attack database..."
echo "📥 Fetching from: ${REMOTE_CSV}"

# Create header
cat > "${LOCAL_FILE}" << 'HEADER'
# Shai-Hulud 2.0 Attack - Compromised NPM Packages
# Date: November 21-23, 2025
# Source: https://www.wiz.io/blog/shai-hulud-2-0-ongoing-supply-chain-attack
# Data: https://github.com/wiz-sec-public/wiz-research-iocs/blob/main/reports/shai-hulud-2-packages.csv
# Format: ["package-name"]="version"

HEADER

# Fetch and convert CSV to expected format
curl -sL "${REMOTE_CSV}" | tail -n +2 | awk -F',' '{
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
}' >> "${LOCAL_FILE}"

count=$(grep -c '^\["' "${LOCAL_FILE}" || echo "0")
echo "✅ Updated shai-hulud-2.txt with ${count} package entries"
