#!/usr/bin/env bash
# Unit test for Slack notification workflow structure
# Tests the workflow without requiring API keys

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW_FILE="${REPO_ROOT}/.github/workflows/notify-slack-on-merge.yml"

echo "=== Slack Notification Workflow Structure Test ==="
echo ""

# Test 1: Check if workflow file exists
echo "Test 1: Workflow file exists"
if [ -f "${WORKFLOW_FILE}" ]; then
    echo -e "${GREEN}✅ Workflow file found${NC}"
else
    echo -e "${RED}❌ Workflow file not found: ${WORKFLOW_FILE}${NC}"
    exit 1
fi

# Test 2: Validate YAML syntax
echo ""
echo "Test 2: YAML syntax validation"
if python3 -c "import yaml; yaml.safe_load(open('${WORKFLOW_FILE}'))" 2>/dev/null; then
    echo -e "${GREEN}✅ YAML syntax is valid${NC}"
else
    echo -e "${RED}❌ YAML syntax is invalid${NC}"
    exit 1
fi

# Test 3: Check workflow triggers
echo ""
echo "Test 3: Workflow triggers"
# Check directly in file since YAML parser may interpret 'on' as boolean
if grep -A 3 "^on:" "${WORKFLOW_FILE}" | grep -q "master"; then
    echo -e "${GREEN}✅ Workflow triggers on master branch${NC}"
else
    echo -e "${RED}❌ Workflow doesn't trigger on master branch${NC}"
    exit 1
fi

# Test 4: Check CHANGELOG.md path filter
echo ""
echo "Test 4: CHANGELOG.md path filter"
# Check directly in file
if grep -A 5 "^on:" "${WORKFLOW_FILE}" | grep -q "CHANGELOG.md"; then
    echo -e "${GREEN}✅ Workflow filters on CHANGELOG.md changes${NC}"
else
    echo -e "${RED}❌ Workflow doesn't filter on CHANGELOG.md${NC}"
    exit 1
fi

# Test 5: Check required secrets are referenced
echo ""
echo "Test 5: Required secrets referenced"
if grep -q "ANTHROPIC_API_KEY" "${WORKFLOW_FILE}"; then
    echo -e "${GREEN}✅ ANTHROPIC_API_KEY secret is referenced${NC}"
else
    echo -e "${RED}❌ ANTHROPIC_API_KEY secret not found${NC}"
    exit 1
fi

if grep -q "SLACK_WEBHOOK_URL" "${WORKFLOW_FILE}"; then
    echo -e "${GREEN}✅ SLACK_WEBHOOK_URL secret is referenced${NC}"
else
    echo -e "${RED}❌ SLACK_WEBHOOK_URL secret not found${NC}"
    exit 1
fi

# Test 6: Check for proper step structure
echo ""
echo "Test 6: Workflow steps structure"
# Count steps by looking for "- name:" entries under steps
STEP_COUNT=$(grep -c "^      - name:" "${WORKFLOW_FILE}" || echo "0")
if [ "${STEP_COUNT}" -ge 2 ]; then
    echo -e "${GREEN}✅ Workflow has ${STEP_COUNT} steps (expected at least 2)${NC}"
else
    echo -e "${RED}❌ Workflow has only ${STEP_COUNT} steps${NC}"
    exit 1
fi

# Test 7: Check that script is called
echo ""
echo "Test 7: Script execution"
if grep -q "notify-slack-on-merge.sh" "${WORKFLOW_FILE}"; then
    echo -e "${GREEN}✅ Workflow calls notification script${NC}"
else
    echo -e "${RED}❌ Script call not found in workflow${NC}"
    exit 1
fi

# Test 8: Check that notification script exists
echo ""
echo "Test 8: Notification script exists"
SCRIPT_FILE="${REPO_ROOT}/bin/notify-slack-on-merge.sh"
if [ -f "${SCRIPT_FILE}" ] && [ -x "${SCRIPT_FILE}" ]; then
    echo -e "${GREEN}✅ Notification script exists and is executable${NC}"
else
    echo -e "${RED}❌ Notification script not found or not executable${NC}"
    exit 1
fi

# Test 9: Check script contains required logic
echo ""
echo "Test 9: Script contains required logic"
if grep -q "jq -n" "${SCRIPT_FILE}" && grep -q "ANTHROPIC_API_KEY" "${SCRIPT_FILE}"; then
    echo -e "${GREEN}✅ Script contains JSON payload generation and Claude API logic${NC}"
else
    echo -e "${RED}❌ Script missing required logic${NC}"
    exit 1
fi

# Test 10: Check README documentation exists
echo ""
echo "Test 10: Documentation exists"
README_FILE="${REPO_ROOT}/.github/workflows/README.md"
if [ -f "${README_FILE}" ] && grep -q "Slack Notifications" "${README_FILE}"; then
    echo -e "${GREEN}✅ Workflow documentation found${NC}"
else
    echo -e "${RED}❌ Workflow documentation not found${NC}"
    exit 1
fi

# Summary
echo ""
echo -e "${GREEN}=== All tests passed successfully ===${NC}"
echo ""
echo "Next steps:"
echo "1. Add SLACK_WEBHOOK_URL secret to GitHub repository settings"
echo "2. Test the workflow by merging a significant feature to master"
echo "3. Verify notification appears in #tech channel"
