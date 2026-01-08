#!/usr/bin/env bash
#
# Slack Notification Script for Sparkdock Feature Releases
#
# This script analyzes CHANGELOG.md changes using Claude AI and sends
# notifications to Slack for significant feature releases.
#
# Usage:
#   notify-slack-on-merge.sh <changelog_file> <commit_sha> <commit_url> <author>
#
# Environment variables required:
#   ANTHROPIC_API_KEY - API key for Claude AI
#   SLACK_WEBHOOK_URL - Slack webhook URL for notifications
#

set -euo pipefail

# Check required arguments
if [ $# -ne 4 ]; then
    echo "Usage: $0 <changelog_file> <commit_sha> <commit_url> <author>"
    exit 1
fi

CHANGELOG_FILE="$1"
COMMIT_SHA="$2"
COMMIT_URL="$3"
AUTHOR="$4"

# Check required environment variables
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "Error: ANTHROPIC_API_KEY environment variable is required"
    exit 1
fi

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "Error: SLACK_WEBHOOK_URL environment variable is required"
    exit 1
fi

# Check if changelog file exists
if [ ! -f "${CHANGELOG_FILE}" ]; then
    echo "Error: Changelog file not found: ${CHANGELOG_FILE}"
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
    echo "No significant features detected - skipping notification"
    exit 0
fi

echo "Significant features detected, sending Slack notification..."
echo "Message: ${MESSAGE}"

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
