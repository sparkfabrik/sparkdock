#!/usr/bin/env bash
#
# Slack Notification Script for Sparkdock Feature Releases
#
# This script analyzes CHANGELOG.md changes using Claude AI and sends
# notifications to Slack for significant feature releases.
#
# Usage:
#   Production mode:
#     notify-slack-on-merge.sh <changelog_file> <commit_sha> <commit_url> <author>
#
#   Test mode (uses sample diff, doesn't send to Slack):
#     notify-slack-on-merge.sh --test
#
# Environment variables required:
#   ANTHROPIC_API_KEY - API key for Claude AI
#   SLACK_WEBHOOK_URL - Slack webhook URL (not required in test mode)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
TEST_MODE=false
if [ $# -eq 1 ] && [ "$1" = "--test" ]; then
    TEST_MODE=true
    echo "=== Slack Notification Test Mode ==="
    echo ""
elif [ $# -ne 4 ]; then
    echo "Usage: $0 <changelog_file> <commit_sha> <commit_url> <author>"
    echo "   or: $0 --test"
    exit 1
fi

# Check required environment variables
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo -e "${RED}Error: ANTHROPIC_API_KEY environment variable is required${NC}"
    exit 1
fi

if [ "${TEST_MODE}" = "false" ]; then
    # Production mode - check all requirements
    CHANGELOG_FILE="$1"
    COMMIT_SHA="$2"
    COMMIT_URL="$3"
    AUTHOR="$4"

    if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
        echo -e "${RED}Error: SLACK_WEBHOOK_URL environment variable is required${NC}"
        exit 1
    fi

    # Check if changelog file exists
    if [ ! -f "${CHANGELOG_FILE}" ]; then
        echo -e "${RED}Error: Changelog file not found: ${CHANGELOG_FILE}${NC}"
        exit 1
    fi

    # Get the changelog diff from the previous commit
    DIFF=$(git diff HEAD~1 HEAD -- "${CHANGELOG_FILE}")

    # Check if there are any changes
    if [ -z "${DIFF}" ]; then
        echo "No changelog changes detected"
        exit 0
    fi

    echo "Changelog changes detected, analyzing with Claude AI..."
else
    # Test mode - use sample data
    echo -e "${GREEN}✅ ANTHROPIC_API_KEY is set${NC}"
    echo ""

    COMMIT_SHA="abc1234"
    COMMIT_URL="https://github.com/sparkfabrik/sparkdock/commit/abc1234567890"
    AUTHOR="test-user"

    # Sample changelog diff for testing
    DIFF='--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -8,6 +8,7 @@
 ## [Unreleased]

 ### Added
+- Added automated Slack notifications for significant feature releases merged to master branch (using Claude AI to analyze changelog and generate user-friendly announcements for #tech channel)
 - Added Visual Studio Code Insiders to default package list for early access to new VSCode features

 ### Fixed'

    echo "Sample changelog diff:"
    echo "---"
    echo "${DIFF}"
    echo "---"
    echo ""
    echo -e "${YELLOW}Calling Claude API...${NC}"
    echo ""
fi

# Create a prompt for Claude to analyze the changelog
PROMPT="You are analyzing a CHANGELOG.md diff for a macOS development environment provisioner called Sparkdock.

Your task is to:
1. Determine if the changes contain significant NEW FEATURES that would be valuable to announce to users
2. Ignore minor bug fixes, small improvements, or internal changes
3. If there ARE significant features worth announcing, respond with JSON: {\"should_notify\": true, \"message\": \"<your message>\"}
4. If there are NO significant features, respond with JSON: {\"should_notify\": false}

Guidelines for the message (if should_notify is true):
- Keep it concise (2-4 sentences maximum)
- Focus on user-facing benefits
- Use friendly, conversational tone
- Highlight the most impactful features
- Mention this is merged into the master branch
- Do NOT include markdown formatting or headers

Here is the CHANGELOG.md diff:

\`\`\`diff
${DIFF}
\`\`\`

Respond ONLY with valid JSON, no other text."

# Call Claude API
RESPONSE=$(curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -d @- << EOF
{
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 1024,
  "messages": [
    {
      "role": "user",
      "content": $(echo "${PROMPT}" | jq -Rs .)
    }
  ]
}
EOF
)

# Verify the Claude API response has the expected structure
if ! echo "${RESPONSE}" | jq -e '.content and .content[0].text' >/dev/null 2>&1; then
    echo "Error: Unexpected response from Claude API"
    echo "${RESPONSE}"
    exit 1
fi

# Extract the response text
CLAUDE_RESPONSE=$(echo "${RESPONSE}" | jq -r '.content[0].text')

# Ensure the extracted text is valid JSON with the expected fields
if ! echo "${CLAUDE_RESPONSE}" | jq -e '.should_notify' >/dev/null 2>&1; then
    echo "Error: Claude response does not contain expected JSON structure"
    echo "${CLAUDE_RESPONSE}"
    exit 1
fi

# Parse the JSON response from Claude
SHOULD_NOTIFY=$(echo "${CLAUDE_RESPONSE}" | jq -r '.should_notify')
MESSAGE=$(echo "${CLAUDE_RESPONSE}" | jq -r '.message // ""')

if [ "${SHOULD_NOTIFY}" != "true" ]; then
    if [ "${TEST_MODE}" = "true" ]; then
        echo -e "${YELLOW}ℹ  Claude determined no notification should be sent${NC}"
        echo "This is expected for minor changes or bug fixes only"
    else
        echo "No significant features detected - skipping notification"
    fi
    exit 0
fi

if [ "${TEST_MODE}" = "true" ]; then
    echo -e "${GREEN}✅ Claude determined this should trigger a notification${NC}"
    echo ""
    echo "Generated message:"
    echo "---"
    echo "${MESSAGE}"
    echo "---"
    echo ""
else
    echo "Significant features detected, sending Slack notification..."
    echo "Message: ${MESSAGE}"
fi

# Create Slack message payload with blocks for better formatting
PAYLOAD=$(jq -n \
    --arg text "🎉 New Sparkdock features merged to master!" \
    --arg message "${MESSAGE}" \
    --arg commit_url "${COMMIT_URL}" \
    --arg commit_sha "${COMMIT_SHA}" \
    --arg author "${AUTHOR}" \
    '{
      "text": $text,
      "blocks": [
        {
          "type": "header",
          "text": {
            "type": "plain_text",
            "text": "🎉 New Sparkdock Features",
            "emoji": true
          }
        },
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": $message
          }
        },
        {
          "type": "context",
          "elements": [
            {
              "type": "mrkdwn",
              "text": ("*Commit:* <" + $commit_url + "|" + $commit_sha + "> by " + $author)
            }
          ]
        }
      ]
    }')

if [ "${TEST_MODE}" = "true" ]; then
    echo "Generated Slack payload:"
    echo "${PAYLOAD}" | jq .
    echo ""
    echo -e "${YELLOW}⚠  Test mode - not sending to Slack${NC}"
    echo "To test actual Slack integration, set SLACK_WEBHOOK_URL and run in production mode"
    echo ""
    echo -e "${GREEN}=== Test completed successfully ===${NC}"
else
    # Send to Slack
    HTTP_STATUS=$(curl -s -o /tmp/slack-response.txt -w "%{http_code}" \
        -X POST \
        -H 'Content-Type: application/json' \
        -d "${PAYLOAD}" \
        "${SLACK_WEBHOOK_URL}")

    if [ "${HTTP_STATUS}" = "200" ]; then
        echo "✅ Slack notification sent successfully"
    else
        echo "❌ Failed to send Slack notification. HTTP status: ${HTTP_STATUS}"
        cat /tmp/slack-response.txt
        exit 1
    fi
fi
