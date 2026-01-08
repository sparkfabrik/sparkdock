# Slack Notification Setup Guide

This guide explains how to set up the automated Slack notifications for Sparkdock feature releases.

## Overview

When significant features are merged to the `master` branch with changes to `CHANGELOG.md`, an automated workflow:
1. Analyzes the changelog changes using Claude AI
2. Determines if the changes warrant a user notification
3. Generates a concise, user-friendly message
4. Sends it to the Sparkfabrik #tech Slack channel

## Prerequisites

- Repository admin access to configure GitHub secrets
- Access to Sparkfabrik Slack workspace
- Permissions to create incoming webhooks in Slack

## Setup Steps

### 1. Create Slack Incoming Webhook

1. Go to https://api.slack.com/apps
2. Click "Create New App" or select existing Sparkfabrik app
3. Navigate to "Incoming Webhooks" in the left sidebar
4. Toggle "Activate Incoming Webhooks" to **On**
5. Click "Add New Webhook to Workspace"
6. Select the **#tech** channel from the dropdown
7. Click "Allow"
8. Copy the webhook URL (format: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`)

### 2. Add Secret to GitHub Repository

1. Go to https://github.com/sparkfabrik/sparkdock/settings/secrets/actions
2. Click "New repository secret"
3. Name: `SLACK_WEBHOOK_URL`
4. Value: Paste the webhook URL from step 1
5. Click "Add secret"

### 3. Verify Existing Secret

The workflow also requires `ANTHROPIC_API_KEY` which should already be configured.

To verify:
1. Go to https://github.com/sparkfabrik/sparkdock/settings/secrets/actions
2. Confirm `ANTHROPIC_API_KEY` is listed

## Testing

### Test the Workflow Structure

Run the included test script to validate the workflow configuration:

```bash
./bin/test-slack-workflow-structure.sh
```

This verifies:
- Workflow file syntax
- Correct triggers and filters
- Required secrets referenced
- JSON parsing logic
- Slack payload structure

### Test with Claude API

If you have an Anthropic API key, you can test the Claude integration:

```bash
export ANTHROPIC_API_KEY="your-key-here"
./bin/test-slack-notification.sh
```

This will:
- Call Claude API with a sample changelog diff
- Generate a notification message
- Display the Slack payload
- Optionally send a test notification (if `SLACK_WEBHOOK_URL` is set)

### Test Live

1. Create a feature branch
2. Add a significant feature to `CHANGELOG.md` under `## [Unreleased]`
3. Commit and push to master (or merge a PR)
4. Check GitHub Actions for workflow run
5. Verify notification in #tech channel

## How It Works

### Trigger Conditions

The workflow only runs when:
- A push happens to the `master` branch
- The push includes changes to `CHANGELOG.md`

### Claude AI Analysis

Claude analyzes the changelog diff and:
- Identifies if changes contain significant new features
- Ignores minor bug fixes or small improvements
- Generates a 2-4 sentence user-friendly message
- Returns JSON: `{"should_notify": true/false, "message": "..."}`

### Message Format

Notifications use Slack's Block Kit for rich formatting:
- Header: "🎉 New Sparkdock Features"
- Message body: Claude's generated summary
- Footer: Commit link and author

Example:
```
🎉 New Sparkdock Features

Sparkdock now includes a modern shell configuration system with smart
aliases, conditional tool loading (eza, bat, fzf, starship), and seamless
oh-my-zsh integration. New sjust commands let you enable/disable features
and view comprehensive shell status with shell-info.

Commit: a1b2c3d by sparkfabrik
```

## Troubleshooting

### Workflow doesn't trigger
- Check that changes include `CHANGELOG.md`
- Verify push is to `master` branch (not `main`)
- Check GitHub Actions tab for workflow runs

### No Slack notification
- Verify `SLACK_WEBHOOK_URL` secret is set correctly
- Check workflow logs for Claude's response
- Claude may have determined changes don't warrant notification
- Verify the webhook hasn't been revoked in Slack

### Claude API errors
- Verify `ANTHROPIC_API_KEY` secret is valid
- Check workflow logs for API response
- Ensure API key has sufficient credits/quota

### Testing locally
Use the test scripts:
```bash
# Test workflow structure (no API key needed)
./bin/test-slack-workflow-structure.sh

# Test Claude integration (requires ANTHROPIC_API_KEY)
export ANTHROPIC_API_KEY="sk-ant-..."
./bin/test-slack-notification.sh

# Test full flow with Slack (requires both secrets)
export ANTHROPIC_API_KEY="sk-ant-..."
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
./bin/test-slack-notification.sh
```

## Maintenance

### Updating the workflow
- Workflow file: `.github/workflows/notify-slack-on-merge.yml`
- Test changes with structure test: `./bin/test-slack-workflow-structure.sh`
- Consider Claude's model version (currently `claude-3-5-sonnet-20241022`)

### Changing notification criteria
Edit the prompt in the workflow file to adjust:
- What qualifies as a "significant feature"
- Message length and tone
- Which changelog sections to include

### Changing Slack channel
1. Create new webhook for different channel
2. Update `SLACK_WEBHOOK_URL` secret with new webhook URL

## Files

- `.github/workflows/notify-slack-on-merge.yml` - Main workflow
- `.github/workflows/README.md` - Workflow documentation
- `bin/test-slack-workflow-structure.sh` - Structure validation tests
- `bin/test-slack-notification.sh` - Integration test with Claude API
- `SETUP_SLACK_NOTIFICATIONS.md` - This file

## Security Notes

- Never commit webhook URLs or API keys to the repository
- Use GitHub Secrets for all sensitive values
- Webhook URLs can be rotated in Slack if compromised
- Limit repository access to trusted collaborators
