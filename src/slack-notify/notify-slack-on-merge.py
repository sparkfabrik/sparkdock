#!/usr/bin/env python3
"""
Slack Notification Script for Sparkdock Feature Releases

Analyzes CHANGELOG.md changes using Claude AI and sends notifications
to Slack for significant feature releases.

Usage:
  Production: notify-slack-on-merge.py <changelog_file> <commit_sha> <commit_url> <author>
  Test mode:  notify-slack-on-merge.py --test

Environment variables:
  ANTHROPIC_API_KEY - API key for Claude AI
  SLACK_WEBHOOK_URL - Slack webhook URL
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

# Constants
CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
CLAUDE_MODEL = "claude-haiku-4-5"
CLAUDE_MAX_TOKENS = 4096
HTTP_TIMEOUT = 30

# Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
NC = "\033[0m"

# Paths
SCRIPT_DIR = Path(__file__).parent
PROMPT_FILE = SCRIPT_DIR / "prompts" / "analyze-changelog.txt"

# JSON Schema for structured output
OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "should_notify": {
            "type": "boolean",
            "description": "Whether to send a Slack notification"
        },
        "message": {
            "type": "string",
            "description": "The notification message, or empty string if should_notify is false"
        }
    },
    "required": ["should_notify", "message"],
    "additionalProperties": False
}

# Test cases
TEST_CASES = [
    {
        "name": "Static: No significant updates (bug fix only)",
        "expected": False,
        "diff": """--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -10,6 +10,7 @@
 ### Added

 ### Fixed
+- Fixed trailing whitespace in shell configuration files
 - Fixed keyboard layout installation path"""
    },
    {
        "name": "Static: Multiple features (list formatting)",
        "expected": True,
        "diff": """--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -8,6 +8,10 @@
 ## [Unreleased]

 ### Added
+- Added automated Slack notifications for significant feature releases merged to master branch
+- Integrated Lima container environment with full Docker Desktop replacement support
+- Added new shell enhancement system with eza, starship, and fzf integration
 - Added Visual Studio Code Insiders to default package list

 ### Fixed"""
    },
]


def check_env():
    """Check required environment variables. Exits if missing."""
    missing = []
    if not os.environ.get("ANTHROPIC_API_KEY"):
        missing.append("ANTHROPIC_API_KEY")
    if not os.environ.get("SLACK_WEBHOOK_URL"):
        missing.append("SLACK_WEBHOOK_URL")

    if missing:
        for var in missing:
            print(f"{RED}Error: {var} environment variable is required{NC}")
        sys.exit(1)


def call_claude(diff):
    """Call Claude API with structured output to analyze the changelog diff."""
    prompt = PROMPT_FILE.read_text().format(diff=diff)

    payload = json.dumps({
        "model": CLAUDE_MODEL,
        "max_tokens": CLAUDE_MAX_TOKENS,
        "messages": [{"role": "user", "content": prompt}],
        "output_format": {
            "type": "json_schema",
            "schema": OUTPUT_SCHEMA
        }
    }).encode()

    req = urllib.request.Request(
        CLAUDE_API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": os.environ["ANTHROPIC_API_KEY"],
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "structured-outputs-2025-11-13"
        }
    )

    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        raise RuntimeError(f"HTTP {e.code}: {error_body}")

    # Handle the response - structured outputs returns JSON directly in text
    content = data["content"][0]
    if content["type"] == "text":
        return json.loads(content["text"])
    else:
        raise ValueError(f"Unexpected content type: {content['type']}")


def create_slack_payload(message, commit_url, commit_sha, author):
    """Create Slack message payload."""
    return {
        "text": "🚀 New Sparkdock Release!",
        "blocks": [
            {
                "type": "header",
                "text": {"type": "plain_text", "text": "🚀 New Sparkdock Release", "emoji": True}
            },
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": message}
            },
            {
                "type": "context",
                "elements": [{
                    "type": "mrkdwn",
                    "text": f"*Commit:* <{commit_url}|{commit_sha}> by {author}"
                }]
            }
        ]
    }


def send_slack(payload):
    """Send message to Slack webhook."""
    req = urllib.request.Request(
        os.environ["SLACK_WEBHOOK_URL"],
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
        return resp.status == 200


def get_git_diff(changelog_file):
    """Get changelog diff from previous commit."""
    result = subprocess.run(
        ["git", "diff", "HEAD~1", "HEAD", "--", changelog_file],
        capture_output=True,
        text=True,
    )
    return result.stdout


def get_real_diff():
    """Get real diff from current repository (last 5 commits)."""
    result = subprocess.run(
        ["git", "diff", "HEAD~5", "HEAD", "--", "CHANGELOG.md"],
        capture_output=True,
        text=True,
    )
    return result.stdout or "No changes in CHANGELOG.md"


def run_test(test, commit_sha, commit_url, author):
    """Run a single test case. Returns True if passed."""
    print(f"{YELLOW}{'━' * 55}{NC}")
    print(f"{YELLOW}Test: {test['name']}{NC}")
    print(f"{YELLOW}{'━' * 55}{NC}\n")

    if test.get("expected") is not None:
        print(f"Expected: should_notify = {test['expected']}\n")

    print(f"Diff:\n---\n{test['diff']}\n---\n")
    print(f"{YELLOW}Calling Claude API...{NC}")

    try:
        result = call_claude(test["diff"])
    except Exception as e:
        print(f"{RED}✗ API Error: {e}{NC}\n")
        return False

    should_notify = result.get("should_notify", False)
    message = result.get("message", "")

    print(f"Claude response:\n{json.dumps(result, indent=2)}\n")

    if should_notify:
        print(f"\nGenerated message:\n---\n{message}\n---\n")
        payload = create_slack_payload(message, commit_url, commit_sha, author)
        print(f"Slack payload:\n{json.dumps(payload, indent=2)}\n")

        try:
            if send_slack(payload):
                print(f"{GREEN}✅ Slack notification sent{NC}\n")
            else:
                print(f"{RED}✗ Failed to send Slack notification{NC}\n")
        except Exception as e:
            print(f"{RED}✗ Slack error: {e}{NC}\n")

    # Validate result
    expected = test.get("expected")
    if expected is None:
        print(f"{GREEN}✅ Completed (no expected result){NC}\n")
        return True

    if should_notify == expected:
        print(f"{GREEN}✅ PASSED{NC}\n")
        return True

    print(f"{RED}✗ FAILED (expected {expected}, got {should_notify}){NC}\n")
    return False


def test_mode():
    """Run all test cases."""
    print("=== Slack Notification Test Mode ===\n")
    print("Test cases:")
    print("  1. Static changelog: no significant updates (bug fix only)")
    print("  2. Static changelog: multiple features (list formatting)")
    print("  3. Real changelog: git diff HEAD~5..HEAD on CHANGELOG.md")
    print("")

    commit_sha = "abc1234"
    commit_url = "https://github.com/sparkfabrik/sparkdock/commit/abc1234"
    author = "test-user"

    # Run static test cases
    results = []
    for test in TEST_CASES:
        results.append(run_test(test, commit_sha, commit_url, author))

    # Run real diff test
    real_test = {"name": "Real: git diff HEAD~5..HEAD", "expected": None, "diff": get_real_diff()}
    results.append(run_test(real_test, commit_sha, commit_url, author))

    # Summary
    print(f"{YELLOW}{'━' * 55}{NC}")
    print(f"{YELLOW}Test Summary{NC}")
    print(f"{YELLOW}{'━' * 55}{NC}")

    for i, test in enumerate(TEST_CASES):
        status = f"{GREEN}✅ PASSED{NC}" if results[i] else f"{RED}✗ FAILED{NC}"
        print(f"Test {i + 1} ({test['name']}): {status}")
    print(f"Test {len(TEST_CASES) + 1} (Real: git diff HEAD~5..HEAD): {GREEN}✅ COMPLETED{NC}")

    all_passed = all(results)
    color = GREEN if all_passed else RED
    message = "All tests passed" if all_passed else "Some tests failed"
    print(f"\n{color}=== {message} ==={NC}")

    sys.exit(0 if all_passed else 1)


def production_mode(changelog_file, commit_sha, commit_url, author):
    """Run in production mode."""
    if not os.path.exists(changelog_file):
        print(f"{RED}Error: Changelog file not found: {changelog_file}{NC}")
        sys.exit(1)

    diff = get_git_diff(changelog_file)
    if not diff:
        print("No changelog changes detected")
        sys.exit(0)

    print("Changelog changes detected, analyzing with Claude AI...")

    try:
        result = call_claude(diff)
    except Exception as e:
        print(f"{RED}Error: {e}{NC}")
        sys.exit(1)

    if not result.get("should_notify"):
        print("No significant features detected - skipping notification")
        sys.exit(0)

    message = result.get("message", "")
    print("Significant features detected, sending Slack notification...")
    print(f"Message: {message}")

    payload = create_slack_payload(message, commit_url, commit_sha, author)

    try:
        if send_slack(payload):
            print("✅ Slack notification sent successfully")
        else:
            print("❌ Failed to send Slack notification")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Failed to send Slack notification: {e}")
        sys.exit(1)


def main():
    """Main entry point."""
    check_env()

    if len(sys.argv) == 2 and sys.argv[1] == "--test":
        test_mode()
    elif len(sys.argv) == 5:
        production_mode(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
