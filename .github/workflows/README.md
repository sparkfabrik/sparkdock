# GitHub Workflows

This directory contains GitHub Actions workflows for the Sparkdock project.

## Workflows

### Claude Code (`claude.yml`)
AI-assisted code reviews and issue handling using Claude Code action.
- Triggers on issue comments, PR comments, and new issues with `@claude` mentions
- Uses Anthropic API key from repository secrets

### Test Ansible Playbook (`test-ansible-playbook.yml`)
Continuous integration tests for the Ansible provisioning playbook.
- Runs on push to master/main branches and pull requests
- Tests installation on macOS 15 and 26
- Validates idempotency of the installer

### Test Menubar App (`test-menubar-app.yml`)
Tests for the Swift menubar application.

### Test sjust (`test-sjust.yml`)
Tests for the SparkJust task runner.

### Slack Notifications (`notify-slack-on-merge.yml`)
Automated Slack notifications for significant feature releases.

#### How It Works
1. **Trigger**: Runs when changes to `CHANGELOG.md` are pushed to the `master` branch
2. **Analysis**: Uses Claude AI to analyze the changelog diff and determine if changes contain significant new features (vs. minor bug fixes)
3. **Notification**: If significant features are detected, sends a concise, user-friendly message to the Sparkfabrik #tech Slack channel

#### Requirements
- `ANTHROPIC_API_KEY` - Already configured in repository secrets (used by Claude workflow)
- `SLACK_WEBHOOK_URL` - Required - Slack incoming webhook URL for the #tech channel

#### Setting Up Slack Webhook
1. Go to https://api.slack.com/apps
2. Create or select your Slack app
3. Enable "Incoming Webhooks"
4. Add new webhook to workspace and select #tech channel
5. Copy the webhook URL
6. Add it as a repository secret named `SLACK_WEBHOOK_URL`

#### Testing the Notification Script

**Dry run validation** (no API keys required):
```bash
# Validates script syntax and structure without calling APIs
python3 src/slack-notify/notify-slack-on-merge.py --dry-run
```

**Test mode** (requires API keys, sends actual notifications):
```bash
# Test mode uses sample diffs and sends to Slack
export ANTHROPIC_API_KEY="your-key"
export SLACK_WEBHOOK_URL="your-webhook-url"
python3 src/slack-notify/notify-slack-on-merge.py --test
```

This allows you to:
- Verify Claude AI integration
- Test message generation
- Validate end-to-end Slack notification delivery
- Use sample diffs without needing git history

#### Message Format
The workflow generates messages using Claude AI to:
- Focus on user-facing benefits
- Keep messages concise (2-4 sentences)
- Use friendly, conversational tone
- Highlight the most impactful features
- Include commit information and author

#### Example Notification
```
🎉 New Sparkdock Features

Sparkdock now includes a modern shell configuration system with smart aliases,
conditional tool loading (eza, bat, fzf, starship), and seamless oh-my-zsh
integration. New sjust commands let you enable/disable features and view
comprehensive shell status with shell-info.

Commit: a1b2c3d by sparkfabrik
```

### Test Slack Notification Script (`test-slack-notification.yml`)
Validates the Slack notification Python script on pull requests and pushes.

#### What It Tests
1. **Python syntax validation** - Ensures the script has no syntax errors
2. **Dry-run validation** - Validates script structure and configuration without API calls
3. **File existence** - Verifies prompt files and dependencies exist
4. **JSON schema validation** - Ensures Slack payload structure is correct

This workflow ensures the notification script is ready to deploy without requiring API keys or secrets.

## Secret Management

Repository secrets are managed in GitHub Settings → Secrets and variables → Actions.

Current secrets:
- `ANTHROPIC_API_KEY` - For Claude AI features
- `SLACK_WEBHOOK_URL` - For Slack notifications (to be added)
