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

Triggers when `CHANGELOG.md` changes are pushed to `master`. Uses Claude AI to analyze changes and send user-friendly announcements to the #tech Slack channel for significant features.

**Requirements:**
- `ANTHROPIC_API_KEY` - Already configured
- `SLACK_WEBHOOK_URL` - Required (see setup instructions below)

**Setup Slack Webhook:**
1. Go to https://api.slack.com/apps
2. Create/select your Slack app → Enable "Incoming Webhooks"
3. Add webhook to #tech channel and copy the URL
4. Add as repository secret: `SLACK_WEBHOOK_URL`

**Testing:**
```bash
# Dry-run validation (no API keys)
python3 src/slack-notify/notify-slack-on-merge.py --dry-run

# End-to-end test (requires API keys)
python3 src/slack-notify/notify-slack-on-merge.py --test
```

📖 **Full documentation:** See [docs/SLACK_NOTIFICATION_EXAMPLES.md](../../docs/SLACK_NOTIFICATION_EXAMPLES.md) for examples, customization, and detailed testing instructions.

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
