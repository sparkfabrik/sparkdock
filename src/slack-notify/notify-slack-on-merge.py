#!/usr/bin/env python3
"""
Slack Notification Script for Sparkdock Feature Releases

Analyzes CHANGELOG.md changes using Claude AI and sends notifications
to Slack for significant feature releases.

Usage:
  Production: notify-slack-on-merge.py <changelog_file> <commit_sha> <commit_url> <author>
  Test mode:  notify-slack-on-merge.py --test
  Dry run:    notify-slack-on-merge.py --dry-run

Environment variables:
  ANTHROPIC_API_KEY - API key for Claude AI (not required for --dry-run)
  SLACK_WEBHOOK_URL - Slack webhook URL (not required for --dry-run)
"""

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

# Constants
DEBUG = os.environ.get("DEBUG", "") == "1"
CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
CLAUDE_MODEL = "claude-haiku-4-5"
CLAUDE_MODEL_TEMPERATURE = 0.3
CLAUDE_MAX_TOKENS = 4096
HTTP_TIMEOUT = 120

# Colors (only apply if output is a TTY)
if sys.stdout.isatty():
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC = "\033[0m"
else:
    RED = ""
    GREEN = ""
    YELLOW = ""
    NC = ""

# Paths
SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
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


def check_env(require_slack=True):
    """Check required environment variables. Exits if missing."""
    missing = []
    if not os.environ.get("ANTHROPIC_API_KEY"):
        missing.append("ANTHROPIC_API_KEY")
    if require_slack and not os.environ.get("SLACK_WEBHOOK_URL"):
        missing.append("SLACK_WEBHOOK_URL")

    if missing:
        for var in missing:
            print(f"{RED}Error: {var} environment variable is required{NC}")
        sys.exit(1)


def call_claude_api(prompt, schema, max_tokens=CLAUDE_MAX_TOKENS, temperature=CLAUDE_MODEL_TEMPERATURE):
    """Call Claude API with structured output."""
    if DEBUG:
        print(f"Prompt:\n---\n{prompt[:2000]}...\n---\n")
        print(f"Temperature: {temperature}")

    payload = json.dumps({
        "model": CLAUDE_MODEL,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "messages": [{"role": "user", "content": prompt}],
        "output_format": {
            "type": "json_schema",
            "schema": schema
        }
    }).encode()

    if DEBUG:
        print(f"Payload size: {len(payload)} bytes")

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

    content = data["content"][0]
    if content["type"] == "text":
        return json.loads(content["text"])
    raise ValueError(f"Unexpected content type: {content['type']}")


def call_claude(diff):
    """Analyze changelog diff."""
    prompt = PROMPT_FILE.read_text().format(diff=diff)
    if DEBUG:
        print(f"Prompt length: {len(prompt)} chars")
    return call_claude_api(prompt, OUTPUT_SCHEMA)


def create_slack_payload(message, commit_url, commit_sha, author):
    """Create Slack message payload."""
    blocks = [
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

    return {"text": "🚀 New Sparkdock Release!", "blocks": blocks}


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
    try:
        result = subprocess.run(
            ["git", "diff", "HEAD~1", "HEAD", "--", changelog_file],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        if DEBUG:
            print(f"{RED}Git diff failed for {changelog_file}: {e}{NC}")
            if e.stderr:
                print(f"{RED}stderr: {e.stderr}{NC}")
        return ""
    return result.stdout


def get_real_diff():
    """Get real diff from current repository (last 5 commits)."""
    try:
        result = subprocess.run(
            ["git", "diff", "HEAD~5", "HEAD", "--", "CHANGELOG.md"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        if DEBUG:
            print(f"{RED}Git diff failed for CHANGELOG.md: {e}{NC}")
            if e.stderr:
                print(f"{RED}stderr: {e.stderr}{NC}")
        return "No changes in CHANGELOG.md"
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

    if DEBUG:
        print(f"Claude response:\n{json.dumps(result, indent=2)}\n")

    if should_notify:
        if DEBUG:
            print(f"\nGenerated message:\n---\n{message}\n---\n")
        payload = create_slack_payload(message, commit_url, commit_sha, author)
        
        print(f"{YELLOW}Test mode: Sending notification to Slack...{NC}")
        try:
            if send_slack(payload):
                print(f"{GREEN}✅ Notification sent successfully{NC}")
            else:
                print(f"{RED}❌ Failed to send notification{NC}")
        except Exception as e:
            print(f"{RED}❌ Error sending notification: {e}{NC}")

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
    print("Significant features detected, sending notification...")
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


def dry_run_mode():
    """Dry run mode - validates script without calling APIs or sending notifications."""
    print(f"{GREEN}=== Dry Run Mode ==={NC}")
    print("Validating script configuration and structure...")
    
    # Check script structure
    print("\n1. Checking script components...")
    print(f"   ✓ Script directory: {SCRIPT_DIR}")
    print(f"   ✓ Repository root: {REPO_ROOT}")
    
    # Check prompt file
    if PROMPT_FILE.exists():
        print(f"   ✓ Prompt file exists: {PROMPT_FILE}")
        with open(PROMPT_FILE, "r", encoding="utf-8") as f:
            prompt_content = f.read()
            print(f"   ✓ Prompt file size: {len(prompt_content)} characters")
    else:
        print(f"   ✗ Prompt file missing: {PROMPT_FILE}")
        sys.exit(1)
    
    # Validate output schema
    print("\n2. Validating JSON schema...")
    try:
        schema_str = json.dumps(OUTPUT_SCHEMA, indent=2)
        print(f"   ✓ JSON schema is valid ({len(schema_str)} bytes)")
    except Exception as e:
        print(f"   ✗ JSON schema error: {e}")
        sys.exit(1)
    
    # Test sample diffs
    print("\n3. Testing sample changelog diffs...")
    for i, test_case in enumerate(TEST_CASES, 1):
        diff = test_case.get("diff", "")
        name = test_case.get("name", f"Test #{i}")
        print(f"   ✓ {name} ({len(diff)} characters)")
    
    # Validate Slack payload structure
    print("\n4. Validating Slack payload structure...")
    try:
        test_payload = create_slack_payload(
            "Test message for dry run validation",
            "https://github.com/test/repo/commit/abc123",
            "abc1234",
            "test-user"
        )
        payload_str = json.dumps(test_payload, indent=2)
        print(f"   ✓ Slack payload structure is valid ({len(payload_str)} bytes)")
    except Exception as e:
        print(f"   ✗ Slack payload error: {e}")
        sys.exit(1)
    
    # Check environment (optional in dry run)
    print("\n5. Checking environment variables (optional)...")
    has_anthropic = bool(os.environ.get("ANTHROPIC_API_KEY"))
    has_slack = bool(os.environ.get("SLACK_WEBHOOK_URL"))
    print(f"   {'✓' if has_anthropic else '○'} ANTHROPIC_API_KEY {'set' if has_anthropic else 'not set'}")
    print(f"   {'✓' if has_slack else '○'} SLACK_WEBHOOK_URL {'set' if has_slack else 'not set'}")
    
    print(f"\n{GREEN}✅ Dry run validation passed - script is ready to use{NC}")
    print("\nNext steps:")
    if not has_anthropic or not has_slack:
        print("  - Set required environment variables:")
        if not has_anthropic:
            print("    export ANTHROPIC_API_KEY='your-key'")
        if not has_slack:
            print("    export SLACK_WEBHOOK_URL='your-webhook-url'")
    print("  - Run in test mode: python3 src/slack-notify/notify-slack-on-merge.py --test")


def main():
    """Main entry point."""
    if len(sys.argv) == 2 and sys.argv[1] == "--test":
        check_env(require_slack=True)
        test_mode()
    elif len(sys.argv) == 2 and sys.argv[1] == "--dry-run":
        # Dry run doesn't require environment variables
        dry_run_mode()
    elif len(sys.argv) == 5:
        check_env(require_slack=True)
        production_mode(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
