#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable, List, Optional

MODEL = "github_copilot/gpt-4o-mini"
MAX_FILE_CHARS = int(os.getenv("SPARKDOCK_AI_MAX_FILE_CHARS", "30000"))
MAX_CANDIDATES = int(os.getenv("SPARKDOCK_AI_MAX_CANDIDATES", "50"))
PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"

CURATED_FALLBACK = [
    "README.md",
    "config/packages/all-packages.yml",
    "config/shell/aliases.zsh",
    "config/shell/init.zsh",
    "config/shell/README.md",
    "sjust/00-default.just",
    "sjust/sjust.sh",
]


class SparkdockAIError(RuntimeError):
    """Domain-specific error reported to the calling script."""


def determine_root(explicit: Optional[str] = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()

    script_path = Path(__file__).resolve()
    if str(script_path).startswith("/opt/sparkdock/"):
        return Path("/opt/sparkdock")
    # cli.py -> sparkdock-ai -> src -> repo root
    return script_path.parent.parent.parent


def ensure_dependency(command: str) -> None:
    if shutil.which(command) is None:
        raise SparkdockAIError(
            f"Missing dependency: {command}. Please install it and retry."
        )


def run_subprocess(
    args: List[str],
    *,
    cwd: Optional[Path] = None,
    input_text: Optional[str] = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        input=input_text,
        text=True,
        capture_output=True,
    )


def load_prompt(name: str) -> str:
    path = PROMPTS_DIR / name
    return path.read_text(encoding="utf-8")


def gather_candidate_files(root: Path) -> List[str]:
    candidates: List[str] = []
    git_dir = root / ".git"
    if git_dir.exists():
        result = run_subprocess(["git", "ls-files"], cwd=root)
        if result.returncode == 0:
            candidates = [
                line.strip() for line in result.stdout.splitlines() if line.strip()
            ]
    if not candidates:
        exts = (".md", ".yml", ".yaml", ".zsh", ".sh", ".swift", ".just")
        for path in root.rglob("*"):
            if path.is_file() and path.suffix in exts:
                candidates.append(str(path.relative_to(root)))
    if "README.md" not in candidates and (root / "README.md").exists():
        candidates.append("README.md")
    return candidates[:MAX_CANDIDATES]


def render_candidate_block(files: Iterable[str]) -> str:
    return "\n".join(f"- {path}" for path in files)


def select_files(
    *,
    question: str,
    candidates: List[str],
    system_prompt: str,
    prompt_template: str,
) -> List[str]:
    block = render_candidate_block(candidates)
    prompt_body = (
        prompt_template.replace("{{QUESTION}}", question).replace("{{FILES}}", block)
    )
    result = run_subprocess(
        ["llm", "prompt", "--no-log", "--no-stream", "-m", MODEL, "-s", system_prompt, prompt_body]
    )

    tmp_dir = Path(tempfile.gettempdir())
    tmp_dir.joinpath("sparkdock-ai-file-selection.raw").write_text(
        result.stdout.strip(), encoding="utf-8"
    )
    if result.returncode != 0:
        tmp_dir.joinpath("sparkdock-ai-file-selection.err").write_text(
            result.stderr, encoding="utf-8"
        )
        raise SparkdockAIError(
            "Unable to select files. See /tmp/sparkdock-ai-file-selection.err for details."
        )

    return parse_file_selection(result.stdout, candidates)


def ask_with_context(
    *,
    question: str,
    context: str,
    system_prompt: str,
    prompt_template: str,
) -> str:
    prompt_body = (
        prompt_template.replace("{{QUESTION}}", question).replace("{{CONTEXT}}", context)
    )
    result = run_subprocess(
        ["llm", "prompt", "--no-log", "--no-stream", "-m", MODEL, "-s", system_prompt, prompt_body]
    )
    if result.returncode != 0:
        raise SparkdockAIError(result.stderr or "Unable to obtain answer from llm.")
    return result.stdout.strip()


def parse_file_selection(response: str, candidates: List[str]) -> List[str]:
    cleaned: List[str] = []
    try:
        cleaned = _extract_json_array(response)
    except ValueError:
        cleaned = []

    if not cleaned:
        cleaned = _fallback_from_lines(response)

    candidate_set = set(candidates)
    normalized: List[str] = []
    for entry in cleaned:
        if not isinstance(entry, str):
            continue
        item = entry.strip()
        if item.startswith("./"):
            item = item[2:]
        if item in candidate_set and item not in normalized:
            normalized.append(item)
        if len(normalized) >= 10:
            break

    if not normalized:
        for fallback in CURATED_FALLBACK:
            if fallback in candidate_set and fallback not in normalized:
                normalized.append(fallback)
            if len(normalized) >= 10:
                break

    if not normalized and "README.md" in candidate_set:
        normalized.append("README.md")

    return normalized


def _extract_json_array(response: str) -> List[str]:
    text = response.strip()
    if not text:
        return []
    try:
        data = json.loads(text)
        if isinstance(data, list):
            return data
    except json.JSONDecodeError:
        pass

    match = re.search(r"\[[\s\S]*\]", text)
    if match:
        try:
            parsed = json.loads(match.group(0))
            if isinstance(parsed, list):
                return parsed
        except json.JSONDecodeError:
            pass

    raise ValueError("No JSON array found")


def _fallback_from_lines(response: str) -> List[str]:
    lines = []
    for line in response.splitlines():
        stripped = line.strip().strip("`\"'")
        if not stripped:
            continue
        stripped = stripped.lstrip("-*0123456789. ").strip()
        if not stripped:
            continue
        token = stripped.split()[0].strip('",')
        if token:
            lines.append(token)
    return lines


def read_file_excerpt(path: Path) -> str:
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        content = path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return "[file not found]"
    if len(content) > MAX_FILE_CHARS:
        return f"{content[:MAX_FILE_CHARS]}\n...[truncated]..."
    return content


def build_context(root: Path, selected: List[str]) -> str:
    parts = []
    readme_seen = False
    for relative in selected:
        file_path = root / relative
        if relative == "README.md":
            readme_seen = True
        if not file_path.is_file():
            continue
        parts.append(f"File: {relative}\n```\n{read_file_excerpt(file_path)}\n```\n")

    readme_path = root / "README.md"
    if readme_path.is_file() and not readme_seen:
        parts.append(f"File: README.md\n```\n{read_file_excerpt(readme_path)}\n```\n")
    return "\n".join(parts)


def generate_answer(question: str, root: Path) -> dict:
    ensure_dependency("llm")

    file_selection_system = load_prompt("file-selection-system.txt")
    file_selection_template = load_prompt("file-selection-template.txt")
    answer_system = load_prompt("answer-system.txt")
    answer_template = load_prompt("answer-template.txt")

    candidates = gather_candidate_files(root)

    selected_files = select_files(
        question=question,
        candidates=candidates,
        system_prompt=file_selection_system,
        prompt_template=file_selection_template,
    )
    if not selected_files:
        selected_files = ["README.md"] if "README.md" in candidates else []

    context = build_context(root, selected_files)
    answer = ask_with_context(
        question=question,
        context=context,
        system_prompt=answer_system,
        prompt_template=answer_template,
    )
    return {
        "question": question,
        "answer": answer,
        "selected_files": selected_files,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Sparkdock AI assistant backend")
    parser.add_argument("--question", required=True, help="Question to ask the assistant")
    parser.add_argument(
        "--format",
        choices=("json", "text"),
        default="json",
        help="Output format (default: json)",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="Root directory of the Sparkdock repository (defaults to auto-detect)",
    )
    args = parser.parse_args()

    try:
        root = determine_root(args.root)
        os.chdir(root)
        result = generate_answer(args.question, root)
    except SparkdockAIError as err:
        print(err, file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps(result))
    else:
        answer = result["answer"].strip()
        if answer:
            print(answer)
        if result["selected_files"]:
            print("\n## Sources\n")
            for item in result["selected_files"]:
                print(f"- {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
