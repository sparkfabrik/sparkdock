# Sparkdock AI Assistant Specification

## Overview
- Introduce a `sparkdock-ai` CLI helper that gives interactive, up-to-date answers about the local Sparkdock repository.
- Build on [simonw/llm](https://github.com/simonw/llm) with the [llm-github-copilot](https://github.com/jmdaly/llm-github-copilot) plugin to reuse the Sparkfabrik GitHub Copilot subscription (`github_copilot/gpt-5-mini` model).
- Wrap all interactions in a lightweight terminal UI powered by [charmbracelet/gum](https://github.com/charmbracelet/gum).

## Goals
- Provide a curated menu of common Sparkdock questions plus a “custom question” option.
- Ask the LLM which repository files are relevant to the selected question, then feed those files into a second LLM call that produces the answer.
- Allow follow-up questions reusing previously selected files when it makes sense, to avoid re-querying the files-selection step unless the user chooses otherwise.
- Handle both installed (`/opt/sparkdock`) and local-repo execution.
- Produce clean terminal output that highlights LLM commands run and resulting answer.

## Non-Goals
- No autonomous agent loop or long-running conversations.
- No network calls outside of those performed by `llm` with the GitHub Copilot backend.
- No file modifications or code generation beyond question answering.
- No Windows/Linux support; macOS only is acceptable.

## User Workflow
1. User runs `bin/sparkdock-ai` (installed via existing provisioning flow).
2. Script checks prerequisites (`llm`, `gum`, `github_copilot/gpt-5-mini` availability, auth status).
3. `gum choose` displays:
   - Predefined FAQ-style questions (e.g., “What packages are installed?”, “What aliases are defined?”, “What is sjust?”).
   - `Custom question…` entry that opens a `gum input`.
   - `Quit`.
4. Once a question is chosen:
   1. Gather candidate files (default: repository git-tracked files + key config paths when running from `/opt/sparkdock`).
   2. Prompt LLM with question + candidate file inventory (filenames only, maybe grouped by directories) asking it to pick relevant files (JSON list response).
   3. Validate LLM output (JSON array of up to N files). If invalid, fall back to the whole candidate set or display an error.
   4. Concatenate the contents of selected files, trimming large files (>N KB) or first/last chunk policy if needed.
   5. Send final prompt to LLM with question + inlined file excerpts (include filename headers).
   6. Display the formatted answer (plain markdown rendered as text).
5. Offer the user options after each answer via `gum choose`:
   - Ask another question (reset flow).
   - Re-ask with different files (skip initial question selection).
   - Exit.

## Data & Prompt Design
- **Step 1 Prompt (File Selection)**: Provide question + candidate file list. Ask for JSON array of filenames limited to, e.g., 10 entries. Include explicit instruction to respond with JSON only to ease parsing.
- **Step 2 Prompt (Answer)**: Provide question, cite selected filenames, embed contents under fenced blocks or triple backtick sections labelled by filepath.
- Apply system prompts to set assistant persona (“You are Sparkdock’s assistant…”) and to discourage hallucinations by requesting citations like `config/shell/aliases.zsh`.
- Add size guards (e.g., skip files over ~20KB or truncate using `head/tail` to stay within Copilot’s smaller token limit).

## Authentication Handling
- Delegate to `llm github_copilot auth status` and `llm keys`.
- Surface actionable guidance when authentication missing: show README link + instructions (`llm github_copilot auth login`).
- Never prompt user to paste credentials inside the tool; rely on `llm`’s own auth flow.

## Error Handling / Edge Cases
- Missing dependencies → clear message suggesting `brew install gum` or `pipx install llm` (if needed).
- LLM JSON parsing failure → show diagnostic, allow retry or manual override (e.g., use entire candidate list or `--files` CLI flag).
- Large repository contexts → limit candidate files by directory whitelist plus `.md`, `.yml`, `.zsh`, `.swift` patterns relevant to Sparkdock.
- Non-zero `llm` exit status → surface stderr output and allow the user to retry.

## Implementation Plan
1. **Binary**: Keep `bin/sparkdock-ai` as a Bash orchestrator that handles terminal UX via gum and delegates heavy lifting to Python utilities in `src/sparkdock-ai/`.
2. **Python Module**: Implement the core logic (file discovery, prompt building, LLM calls) in `src/sparkdock-ai/cli.py`, exposing a simple `--format text` output that includes the answer and cited sources so the Bash layer never needs to parse JSON. Default the model to `github_copilot/gpt-4o-mini`—it is the fastest Copilot variant available to us—and only allow overrides within the `github_copilot/` namespace so we stay on the Copilot subscription.
3. **Dependency Checks**: Bash handles gum/llm presence and Copilot auth prompts; Python validates that `llm` is available before executing.
4. **Provisioning**: Extend Ansible roles to install `gum`, ensure `llm` is available (via Homebrew), and run `llm install llm-github-copilot` during setup.
5. **File Discovery**: Use `git ls-files` when repo accessible; fallback to curated globs if `.git` missing. Always include `README.md` (if present) in the candidate list and append its content to the final answer context even when not selected, so the assistant retains awareness of Sparkdock’s overview.
6. **Prompts**: Keep template strings under `src/sparkdock-ai/prompts/` so they stay scoped to the assistant feature.
7. **Answer Formatting**: Instruct the model to answer in Markdown suitable for `gum format`, render responses through `gum pager`, and gracefully degrade to plain stdout if gum is missing.
8. **Tests / Validation**: Provide manual test instructions (since tool integrates with live LLM).
9. **Docs**: Update `.github/README` or main `README.md` with usage instructions and auth notes, including the fact that authentication is handled interactively at runtime (`bin/sparkdock-ai` checks and guides the user through `llm github_copilot auth login` as needed).

## Open Questions
- Should we cache LLM-selected files per question to speed re-asks? (Nice-to-have; optional.)
- Do we log interactions locally for auditing? Default to `--no-log` to avoid storing content; mention privacy trade-offs.
- Model selection stays fixed to `github_copilot/gpt-4o-mini`; no environment override.
