#!/usr/bin/env python3
"""
Daily Slack digest script for Sparkdock changelog updates.

Usage:
  notify-slack-on-merge.py daily [--date YYYY-MM-DD] [--timezone Europe/Rome] [--preview]
  notify-slack-on-merge.py --dry-run
  notify-slack-on-merge.py --test

Environment variables:
  ANTHROPIC_API_KEY - API key for Claude AI (required for daily runs)
  SLACK_WEBHOOK_URL - Slack webhook URL (required unless --preview is used)
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Iterable
from zoneinfo import ZoneInfo

# Constants
DEBUG = os.environ.get("DEBUG", "") == "1"
CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
CLAUDE_MODEL = "claude-haiku-4-5"
CLAUDE_MODEL_TEMPERATURE = 0.2
CLAUDE_MAX_TOKENS = 4096
HTTP_TIMEOUT = 180
DEFAULT_TIMEZONE = "Europe/Rome"
CHANGELOG_PATH = "CHANGELOG.md"
SUMMARY_PATH = os.environ.get("GITHUB_STEP_SUMMARY")
DEFAULT_DIGEST_REF = "origin/master"
ENTRY_SIMILARITY_THRESHOLD = 0.65

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
            "description": "Whether to send a Slack notification",
        },
        "message": {
            "type": "string",
            "description": "The Slack message body, or empty string if should_notify is false",
        },
        "reason": {
            "type": "string",
            "description": "Short explanation for why the digest should or should not be sent",
        },
    },
    "required": ["should_notify", "message", "reason"],
    "additionalProperties": False,
}


@dataclass
class CommitInfo:
    sha: str
    author: str
    committed_at: str
    subject: str
    url: str

    @property
    def short_sha(self) -> str:
        return self.sha[:7]


TEST_CASES = [
    {
        "name": "No new entries when snapshots match",
        "before": """# Changelog

## [Unreleased]

### Added
- Added previous feature
""",
        "after": """# Changelog

## [Unreleased]

### Added
- Added previous feature
""",
        "expected": {},
    },
    {
        "name": "Prepended Added entry is detected",
        "before": """# Changelog

## [Unreleased]

### Added
- Added previous feature

### Fixed
- Fixed older bug
""",
        "after": """# Changelog

## [Unreleased]

### Added
- Added daily digest notifications for meaningful changelog updates
- Added previous feature

### Fixed
- Fixed older bug
""",
        "expected": {
            "Added": [
                "- Added daily digest notifications for meaningful changelog updates"
            ]
        },
    },
    {
        "name": "Multiple sections are preserved",
        "before": """# Changelog

## [Unreleased]

### Added
- Added previous feature

### Changed
- Changed older workflow
""",
        "after": """# Changelog

## [Unreleased]

### Added
- Added scheduled daily digest notifications
- Added previous feature

### Changed
- Changed Slack workflow to use Europe/Rome daily scheduling
- Changed older workflow
""",
        "expected": {
            "Added": ["- Added scheduled daily digest notifications"],
            "Changed": ["- Changed Slack workflow to use Europe/Rome daily scheduling"],
        },
    },
    {
        "name": "Edited existing entry is not treated as new",
        "before": """# Changelog

## [Unreleased]

### Added
- Added previous feature

### Fixed
- Fixed older bug
""",
        "after": """# Changelog

## [Unreleased]

### Added
- Added previous feature with clarified wording

### Fixed
- Fixed older bug
""",
        "expected": {},
    },
    {
        "name": "New prepended entry survives alongside edited older entry",
        "before": """# Changelog

## [Unreleased]

### Added
- Added previous feature

### Fixed
- Fixed older bug
""",
        "after": """# Changelog

## [Unreleased]

### Added
- Added scheduled daily digest notifications
- Added previous feature with clarified wording

### Fixed
- Fixed older bug
""",
        "expected": {"Added": ["- Added scheduled daily digest notifications"]},
    },
]


def debug(message: str) -> None:
    if DEBUG:
        print(f"{YELLOW}[debug]{NC} {message}")


def append_summary(lines: Iterable[str]) -> None:
    if not SUMMARY_PATH:
        return
    with open(SUMMARY_PATH, "a", encoding="utf-8") as summary_file:
        summary_file.write("\n".join(lines) + "\n")


def check_env(require_anthropic: bool, require_slack: bool) -> None:
    missing = []
    if require_anthropic and not os.environ.get("ANTHROPIC_API_KEY"):
        missing.append("ANTHROPIC_API_KEY")
    if require_slack and not os.environ.get("SLACK_WEBHOOK_URL"):
        missing.append("SLACK_WEBHOOK_URL")

    if missing:
        for var in missing:
            print(f"{RED}Error: {var} environment variable is required{NC}")
        sys.exit(1)


def run_git(args: list[str], check: bool = True) -> str:
    debug(f"git {' '.join(args)}")
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {stderr}")
    return result.stdout


def git_ref_exists(ref_name: str) -> bool:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref_name}^{{commit}}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def resolve_digest_ref(requested_ref: str | None) -> str:
    if requested_ref:
        if not git_ref_exists(requested_ref):
            raise ValueError(f"Git ref not found: {requested_ref}")
        return requested_ref

    if git_ref_exists(DEFAULT_DIGEST_REF):
        return DEFAULT_DIGEST_REF
    return "HEAD"


def build_repo_url() -> str:
    if os.environ.get("GITHUB_SERVER_URL") and os.environ.get("GITHUB_REPOSITORY"):
        return f"{os.environ['GITHUB_SERVER_URL'].rstrip('/')}/{os.environ['GITHUB_REPOSITORY']}"

    remote_url = run_git(["config", "--get", "remote.origin.url"]).strip()
    if remote_url.startswith("git@"):
        host_and_path = remote_url.split("@", maxsplit=1)[1]
        host, path = host_and_path.split(":", maxsplit=1)
        remote_url = f"https://{host}/{path}"
    if remote_url.endswith(".git"):
        remote_url = remote_url[:-4]
    return remote_url.rstrip("/")


def call_claude_api(prompt: str, schema: dict) -> dict:
    if DEBUG:
        debug(f"Prompt length: {len(prompt)} chars")

    payload = json.dumps(
        {
            "model": CLAUDE_MODEL,
            "max_tokens": CLAUDE_MAX_TOKENS,
            "temperature": CLAUDE_MODEL_TEMPERATURE,
            "messages": [{"role": "user", "content": prompt}],
            "output_format": {"type": "json_schema", "schema": schema},
        }
    ).encode()

    request = urllib.request.Request(
        CLAUDE_API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "x-api-key": os.environ["ANTHROPIC_API_KEY"],
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "structured-outputs-2025-11-13",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        body = error.read().decode()
        raise RuntimeError(f"HTTP {error.code}: {body}") from error

    content = data["content"][0]
    if content["type"] != "text":
        raise ValueError(f"Unexpected content type: {content['type']}")
    return json.loads(content["text"])


def extract_unreleased_section(changelog_text: str) -> list[str]:
    lines = changelog_text.splitlines()
    start_index = None
    end_index = len(lines)

    for index, line in enumerate(lines):
        if line.strip() == "## [Unreleased]":
            start_index = index + 1
            break

    if start_index is None:
        return []

    for index in range(start_index, len(lines)):
        if lines[index].startswith("## "):
            end_index = index
            break

    return lines[start_index:end_index]


def parse_unreleased_entries(changelog_text: str) -> dict[str, list[str]]:
    entries: dict[str, list[str]] = {}
    current_section = None

    for raw_line in extract_unreleased_section(changelog_text):
        line = raw_line.rstrip()
        if line.startswith("### "):
            current_section = line[4:].strip()
            entries.setdefault(current_section, [])
            continue

        if current_section is None:
            continue

        if line.startswith("- "):
            entries[current_section].append(line)

    return {section: values for section, values in entries.items() if values}


def fallback_added_entries(before: list[str], after: list[str]) -> list[str]:
    matcher = difflib.SequenceMatcher(a=before, b=after, autojunk=False)
    additions: list[str] = []
    for (
        tag,
        _before_start,
        _before_end,
        after_start,
        after_end,
    ) in matcher.get_opcodes():
        if tag == "insert":
            additions.extend(after[after_start:after_end])
    return additions


def entries_equivalent(before_entry: str, after_entry: str) -> bool:
    if before_entry == after_entry:
        return True
    similarity = difflib.SequenceMatcher(
        a=before_entry, b=after_entry, autojunk=False
    ).ratio()
    return similarity >= ENTRY_SIMILARITY_THRESHOLD


def find_new_entries(before: list[str], after: list[str]) -> list[str]:
    if not after or after == before:
        return []
    if not before:
        return list(after)
    if len(after) < len(before):
        return []

    delta = len(after) - len(before)
    suffix = after[delta:]
    if len(suffix) == len(before) and all(
        entries_equivalent(before_entry, after_entry)
        for before_entry, after_entry in zip(before, suffix)
    ):
        return after[:delta]

    return fallback_added_entries(before, after)


def extract_daily_entries(
    before_sections: dict[str, list[str]], after_sections: dict[str, list[str]]
) -> dict[str, list[str]]:
    additions: dict[str, list[str]] = {}
    for section, after_entries in after_sections.items():
        new_entries = find_new_entries(before_sections.get(section, []), after_entries)
        if new_entries:
            additions[section] = new_entries
    return additions


def parse_target_date(raw_date: str | None, timezone_name: str) -> date:
    if raw_date:
        parsed = date.fromisoformat(raw_date)
        if parsed > datetime.now(ZoneInfo(timezone_name)).date():
            raise ValueError("Target date cannot be in the future")
        return parsed
    now_local = datetime.now(ZoneInfo(timezone_name))
    return now_local.date() - timedelta(days=1)


def get_day_window(target_date: date, timezone_name: str) -> tuple[datetime, datetime]:
    timezone = ZoneInfo(timezone_name)
    start = datetime.combine(target_date, time.min, tzinfo=timezone)
    end = start + timedelta(days=1)
    return start, end


def get_last_commit_before(cutoff: datetime, digest_ref: str) -> str:
    output = run_git(
        [
            "rev-list",
            "--first-parent",
            "-n",
            "1",
            f"--before={cutoff.isoformat()}",
            digest_ref,
        ],
        check=False,
    )
    return output.strip()


def get_file_at_commit(commit_sha: str, path: str) -> str:
    if not commit_sha:
        return ""
    result = subprocess.run(
        ["git", "show", f"{commit_sha}:{path}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def get_commits_for_window(
    start: datetime, end: datetime, repo_url: str, digest_ref: str
) -> list[CommitInfo]:
    inclusive_end = end - timedelta(seconds=1)
    log_format = "%H%x1f%an%x1f%cI%x1f%s%x1e"
    output = run_git(
        [
            "log",
            "--first-parent",
            f"--since={start.isoformat()}",
            f"--until={inclusive_end.isoformat()}",
            f"--pretty=format:{log_format}",
            digest_ref,
        ],
        check=False,
    )

    commits: list[CommitInfo] = []
    for record in output.strip("\x1e\n").split("\x1e"):
        record = record.strip()
        if not record:
            continue
        sha, author, committed_at, subject = record.split("\x1f")
        commits.append(
            CommitInfo(
                sha=sha,
                author=author,
                committed_at=committed_at,
                subject=subject,
                url=f"{repo_url}/commit/{sha}",
            )
        )
    return commits


def format_entries_block(entries_by_section: dict[str, list[str]]) -> str:
    blocks = []
    for section, entries in entries_by_section.items():
        blocks.append(f"### {section}")
        blocks.extend(entries)
        blocks.append("")
    return "\n".join(blocks).strip()


def format_commits_block(commits: list[CommitInfo]) -> str:
    if not commits:
        return "- No commits in this window"
    return "\n".join(
        f"- {commit.short_sha} by {commit.author} at {commit.committed_at}: {commit.subject}"
        for commit in commits
    )


def build_prompt(
    target_date: date,
    timezone_name: str,
    entries_by_section: dict[str, list[str]],
    commits: list[CommitInfo],
) -> str:
    return PROMPT_FILE.read_text(encoding="utf-8").format(
        target_date=target_date.isoformat(),
        timezone_name=timezone_name,
        commit_block=format_commits_block(commits),
        entries_block=format_entries_block(entries_by_section),
    )


def create_digest_title(target_date: date, timezone_name: str) -> str:
    expected_yesterday = datetime.now(ZoneInfo(timezone_name)).date() - timedelta(
        days=1
    )
    if target_date == expected_yesterday:
        return "What shipped yesterday in Sparkdock"
    return f"What shipped in Sparkdock on {target_date.isoformat()}"


def build_commit_context(commits: list[CommitInfo], limit: int = 3) -> str:
    if not commits:
        return "No commits in this window"

    preview = commits[:limit]
    parts = [f"<{commit.url}|{commit.short_sha}>" for commit in preview]
    if len(commits) > limit:
        parts.append(f"+{len(commits) - limit} more")
    return ", ".join(parts)


def create_slack_payload(
    title: str, message: str, target_date: date, commits: list[CommitInfo]
) -> dict:
    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": title,
                "emoji": True,
            },
        },
        {"type": "section", "text": {"type": "mrkdwn", "text": message}},
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": (
                        f"*Date:* {target_date.isoformat()}  |  "
                        f"*Commits:* {build_commit_context(commits)}"
                    ),
                }
            ],
        },
    ]
    return {"text": title, "blocks": blocks}


def send_slack(payload: dict) -> bool:
    request = urllib.request.Request(
        os.environ["SLACK_WEBHOOK_URL"],
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
        return response.status == 200


def write_digest_summary(
    *,
    target_date: date,
    timezone_name: str,
    digest_ref: str,
    commits: list[CommitInfo],
    entries_by_section: dict[str, list[str]],
    decision: str,
    reason: str,
    message: str = "",
) -> None:
    entry_block = format_entries_block(entries_by_section) or "_None_"
    lines = [
        "## Daily Slack digest",
        "",
        f"- **Target date:** `{target_date.isoformat()}`",
        f"- **Time zone:** `{timezone_name}`",
        f"- **Git ref:** `{digest_ref}`",
        f"- **Commits considered:** {len(commits)}",
        f"- **Decision:** {decision}",
        f"- **Reason:** {reason}",
        "",
        "### Commits",
        format_commits_block(commits),
        "",
        "### Changelog additions",
        entry_block,
    ]

    if message:
        lines.extend(["", "### Claude message", message])

    append_summary(lines)


def analyze_digest(
    target_date: date,
    timezone_name: str,
    entries_by_section: dict[str, list[str]],
    commits: list[CommitInfo],
) -> dict:
    prompt = build_prompt(target_date, timezone_name, entries_by_section, commits)
    result = call_claude_api(prompt, OUTPUT_SCHEMA)
    debug(f"Claude response: {json.dumps(result, indent=2)}")
    return result


def dry_run_mode() -> int:
    print(f"{GREEN}=== Dry Run Mode ==={NC}")
    print("Validating daily Slack digest configuration and structure...")

    print("\n1. Checking script components...")
    print(f"   ✓ Script directory: {SCRIPT_DIR}")
    print(f"   ✓ Repository root: {REPO_ROOT}")

    print("\n2. Checking prompt and schema...")
    if not PROMPT_FILE.exists():
        print(f"   ✗ Prompt file missing: {PROMPT_FILE}")
        return 1
    prompt_text = PROMPT_FILE.read_text(encoding="utf-8")
    print(f"   ✓ Prompt file exists ({len(prompt_text)} characters)")
    json.dumps(OUTPUT_SCHEMA)
    print("   ✓ Structured output schema is valid")

    print("\n3. Checking repository context...")
    repo_url = build_repo_url()
    try:
        digest_ref = resolve_digest_ref(DEFAULT_DIGEST_REF)
    except ValueError:
        print(f"   ⚠ {DEFAULT_DIGEST_REF} not found, falling back to HEAD")
        digest_ref = resolve_digest_ref(None)
    print(f"   ✓ Repository URL: {repo_url}")
    target_date = parse_target_date(None, DEFAULT_TIMEZONE)
    start, end = get_day_window(target_date, DEFAULT_TIMEZONE)
    commits = get_commits_for_window(start, end, repo_url, digest_ref)
    print(
        f"   ✓ Default digest window: {target_date.isoformat()} ({DEFAULT_TIMEZONE}) on {digest_ref} with {len(commits)} commit(s)"
    )

    print("\n4. Parsing current changelog structure...")
    changelog_text = (REPO_ROOT / CHANGELOG_PATH).read_text(encoding="utf-8")
    sections = parse_unreleased_entries(changelog_text)
    print(f"   ✓ Parsed {len(sections)} unreleased section(s)")

    print("\n5. Checking environment variables (optional)...")
    has_anthropic = bool(os.environ.get("ANTHROPIC_API_KEY"))
    has_slack = bool(os.environ.get("SLACK_WEBHOOK_URL"))
    print(
        f"   {'✓' if has_anthropic else '○'} ANTHROPIC_API_KEY {'set' if has_anthropic else 'not set'}"
    )
    print(
        f"   {'✓' if has_slack else '○'} SLACK_WEBHOOK_URL {'set' if has_slack else 'not set'}"
    )

    print(f"\n{GREEN}✅ Dry run validation passed{NC}")
    print(
        "  - Preview a date: python3 src/slack-notify/notify-slack-on-merge.py daily --date 2026-03-11 --preview"
    )
    return 0


def test_mode() -> int:
    print("=== Slack Notification Test Mode ===\n")
    all_passed = True
    for test_case in TEST_CASES:
        before_sections = parse_unreleased_entries(test_case["before"])
        after_sections = parse_unreleased_entries(test_case["after"])
        result = extract_daily_entries(before_sections, after_sections)
        passed = result == test_case["expected"]
        color = GREEN if passed else RED
        status = "PASSED" if passed else "FAILED"
        print(f"{color}{status}{NC}: {test_case['name']}")
        if not passed:
            all_passed = False
            print(f"  Expected: {json.dumps(test_case['expected'], indent=2)}")
            print(f"  Got:      {json.dumps(result, indent=2)}")
    return 0 if all_passed else 1


def daily_mode(
    target_date_raw: str | None,
    timezone_name: str,
    preview: bool,
    requested_ref: str | None,
) -> int:
    repo_url = build_repo_url()
    digest_ref = resolve_digest_ref(requested_ref)
    target_date = parse_target_date(target_date_raw, timezone_name)
    start, end = get_day_window(target_date, timezone_name)
    commits = get_commits_for_window(start, end, repo_url, digest_ref)

    if not commits:
        reason = f"No commits landed on {digest_ref} during the selected day"
        print(reason)
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section={},
            decision="skipped",
            reason=reason,
        )
        return 0

    before_commit = get_last_commit_before(start, digest_ref)
    after_commit = get_last_commit_before(end, digest_ref)
    before_text = get_file_at_commit(before_commit, CHANGELOG_PATH)
    after_text = get_file_at_commit(after_commit, CHANGELOG_PATH)

    before_sections = parse_unreleased_entries(before_text)
    after_sections = parse_unreleased_entries(after_text)
    entries_by_section = extract_daily_entries(before_sections, after_sections)

    if not entries_by_section:
        reason = (
            "CHANGELOG.md has no net additions in [Unreleased] for the selected day"
        )
        print(reason)
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="skipped",
            reason=reason,
        )
        return 0

    check_env(require_anthropic=True, require_slack=not preview)

    print("Changelog additions detected, analyzing daily digest with Claude AI...")
    try:
        result = analyze_digest(target_date, timezone_name, entries_by_section, commits)
    except Exception as error:
        reason = f"Claude analysis failed: {error}"
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="failed",
            reason=reason,
        )
        raise

    if not result.get("should_notify"):
        reason = result.get(
            "reason",
            "Claude judged the daily digest as not meaningful enough to announce",
        )
        print(reason)
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="skipped",
            reason=reason,
        )
        return 0

    message = result.get("message", "").strip()
    reason = result.get("reason", "Claude approved the daily digest")
    if not message:
        reason = "Claude approved the digest but returned an empty message"
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="failed",
            reason=reason,
        )
        print(f"{RED}{reason}{NC}")
        return 1

    title = create_digest_title(target_date, timezone_name)
    payload = create_slack_payload(title, message, target_date, commits)

    if preview:
        print(f"{YELLOW}Preview mode enabled - Slack delivery skipped{NC}")
        print(f"Title: {title}")
        print(f"Message:\n{message}")
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="previewed",
            reason=reason,
            message=message,
        )
        return 0

    print("Meaningful daily digest detected, sending Slack notification...")
    try:
        send_slack(payload)
        print("✅ Slack notification sent successfully")
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="sent",
            reason=reason,
            message=message,
        )
        return 0
    except Exception as error:
        write_digest_summary(
            target_date=target_date,
            timezone_name=timezone_name,
            digest_ref=digest_ref,
            commits=commits,
            entries_by_section=entries_by_section,
            decision="failed",
            reason=f"Slack delivery failed: {error}",
            message=message,
        )
        print(f"❌ Failed to send Slack notification: {error}")
        return 1


def normalize_legacy_args(argv: list[str]) -> list[str]:
    if len(argv) == 2 and argv[1] == "--dry-run":
        return [argv[0], "dry-run"]
    if len(argv) == 2 and argv[1] == "--test":
        return [argv[0], "test"]
    return argv


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate Sparkdock Slack digests")
    subparsers = parser.add_subparsers(dest="command", required=True)

    daily_parser = subparsers.add_parser(
        "daily",
        help="Generate the daily changelog digest and optionally send it to Slack",
    )
    daily_parser.add_argument(
        "--date",
        dest="target_date",
        help="Digest date in YYYY-MM-DD format. Defaults to yesterday in the configured time zone.",
    )
    daily_parser.add_argument(
        "--timezone",
        default=DEFAULT_TIMEZONE,
        help=f"Digest time zone (default: {DEFAULT_TIMEZONE})",
    )
    daily_parser.add_argument(
        "--preview",
        action="store_true",
        help="Generate the digest and workflow summary without posting to Slack",
    )
    daily_parser.add_argument(
        "--ref",
        dest="git_ref",
        help="Git ref to analyze. Defaults to origin/master when available, otherwise HEAD.",
    )

    subparsers.add_parser("dry-run", help="Validate script structure without API calls")
    subparsers.add_parser("test", help="Run offline changelog extraction tests")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args(normalize_legacy_args(sys.argv)[1:])

    try:
        if args.command == "dry-run":
            sys.exit(dry_run_mode())
        if args.command == "test":
            sys.exit(test_mode())
        if args.command == "daily":
            sys.exit(
                daily_mode(
                    args.target_date,
                    args.timezone,
                    args.preview,
                    args.git_ref,
                )
            )
    except ValueError as error:
        print(f"{RED}Error: {error}{NC}")
        sys.exit(1)
    except RuntimeError as error:
        print(f"{RED}Error: {error}{NC}")
        sys.exit(1)


if __name__ == "__main__":
    main()
