#!/usr/bin/env bash
# Test script for Slack notification workflow logic
# This script simulates the workflow steps to validate the integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Slack Notification Workflow Test ==="
echo ""

# Check if ANTHROPIC_API_KEY is set
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo -e "${RED}❌ ANTHROPIC_API_KEY environment variable is not set${NC}"
    echo "Please set it with: export ANTHROPIC_API_KEY='your-api-key'"
    exit 1
fi

echo -e "${GREEN}✅ ANTHROPIC_API_KEY is set${NC}"

# Create a sample changelog diff for testing
SAMPLE_DIFF='--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -8,6 +8,7 @@
 ## [Unreleased]

 ### Added
+- Added automated Slack notifications for significant feature releases merged to master branch (using Claude AI to analyze changelog and generate user-friendly announcements for #tech channel)
 - Added Visual Studio Code Insiders to default package list for early access to new VSCode features

 ### Fixed'

echo ""
echo "Sample changelog diff:"
echo "---"
echo "${SAMPLE_DIFF}"
echo "---"
echo ""

# Create the prompt for Claude
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
${SAMPLE_DIFF}
\`\`\`

Respond ONLY with valid JSON, no other text."

echo -e "${YELLOW}Calling Claude API...${NC}"
echo ""

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

# Check if the API call was successful
if [ -z "${RESPONSE}" ]; then
    echo -e "${RED}❌ Failed to get response from Claude API${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Received response from Claude API${NC}"
echo ""

# Extract the response text
CLAUDE_RESPONSE=$(echo "${RESPONSE}" | jq -r '.content[0].text')

echo "Claude's full response:"
echo "---"
echo "${CLAUDE_RESPONSE}"
echo "---"
echo ""

# Parse the JSON response from Claude
SHOULD_NOTIFY=$(echo "${CLAUDE_RESPONSE}" | jq -r '.should_notify')
MESSAGE=$(echo "${CLAUDE_RESPONSE}" | jq -r '.message // ""')

echo "Parsed results:"
echo "  should_notify: ${SHOULD_NOTIFY}"
echo ""

if [ "${SHOULD_NOTIFY}" = "true" ]; then
    echo -e "${GREEN}✅ Claude determined this should trigger a notification${NC}"
    echo ""
    echo "Generated message:"
    echo "---"
    echo "${MESSAGE}"
    echo "---"
    echo ""

    # Test Slack payload generation (without actually sending)
    COMMIT_SHA="abc1234"
    COMMIT_URL="https://github.com/sparkfabrik/sparkdock/commit/abc1234567890"
    AUTHOR="test-user"

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

    echo "Generated Slack payload:"
    echo "${PAYLOAD}" | jq .
    echo ""

    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        echo -e "${YELLOW}SLACK_WEBHOOK_URL is set. Sending test notification...${NC}"
        HTTP_STATUS=$(curl -s -o /tmp/slack-response.txt -w "%{http_code}" \
          -X POST \
          -H 'Content-Type: application/json' \
          -d "${PAYLOAD}" \
          "${SLACK_WEBHOOK_URL}")

        if [ "${HTTP_STATUS}" = "200" ]; then
            echo -e "${GREEN}✅ Test notification sent successfully to Slack${NC}"
        else
            echo -e "${RED}❌ Failed to send test notification. HTTP status: ${HTTP_STATUS}${NC}"
            cat /tmp/slack-response.txt
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ SLACK_WEBHOOK_URL not set - skipping actual Slack send${NC}"
        echo "To test the actual Slack integration, set SLACK_WEBHOOK_URL environment variable"
    fi
else
    echo -e "${YELLOW}ℹ Claude determined no notification should be sent${NC}"
    echo "This is expected for minor changes or bug fixes only"
fi

echo ""
echo -e "${GREEN}=== Test completed successfully ===${NC}"
