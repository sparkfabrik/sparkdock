# Sparkdock AI Assistant Specification

## Overview
- Introduce a `sparkdock-ai` CLI helper that gives interactive, up-to-date answers about the local Sparkdock repository.
- Build on [simonw/llm](https://github.com/simonw/llm) using OpenAI models (requires OPENAI_API_KEY environment variable).
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
2. Script checks prerequisites (`llm`, `gum`, OPENAI_API_KEY environment variable).
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
- Check for OPENAI_API_KEY environment variable.
- Surface actionable guidance when key is missing: show instructions to export OPENAI_API_KEY and contact internal support.
- Never prompt user to paste credentials inside the tool; rely on `llm`’s own auth flow.

## Error Handling / Edge Cases
- Missing dependencies → clear message suggesting `brew install gum` or `pipx install llm` (if needed).
- LLM JSON parsing failure → show diagnostic, allow retry or manual override (e.g., use entire candidate list or `--files` CLI flag).
- Large repository contexts → limit candidate files by directory whitelist plus `.md`, `.yml`, `.zsh`, `.swift` patterns relevant to Sparkdock.
- Non-zero `llm` exit status → surface stderr output and allow the user to retry.

## Implementation Plan
1. **Binary**: Keep `bin/sparkdock-ai` as a Bash orchestrator that handles terminal UX via gum and delegates heavy lifting to Python utilities in `src/sparkdock-ai/`.
2. **Python Module**: Implement the core logic (question triage, file discovery, prompt building, LLM calls) in `src/sparkdock-ai/engine.py`, emitting Markdown answers plus a sources list so the Bash layer never needs to parse JSON.
3. **Question Classifier**: Before any repo work, ask a lightweight model (`gpt-3.5-turbo`) whether the user’s question needs repository context. Provide it with the candidate file paths (no contents) and require a `YES` or `NO` response. If the answer is `NO`, skip file selection entirely and answer the question with a general-purpose OpenAI model (`gpt-4o`).
4. **Contextual Answers**: Only when the classifier returns `YES` do we run the existing contextual pipeline (file selection + contextual answer) backed by `gpt-4o-mini`.
5. **Dependency Checks**: Bash handles gum/llm presence, ensures the `llm-github-copilot` plugin is installed (prompting to install if missing), and manages OpenAI API key check; Python validates that `llm` is available before executing.
6. **Provisioning**: Extend Ansible roles to install `gum`, ensure `llm` is available (via Homebrew), and run `check for OPENAI_API_KEY` during setup.
7. **File Discovery**: Use `git ls-files` when repo accessible; fallback to curated globs if `.git` missing. Always include `README.md` (if present) in the candidate list and append its content to the final answer context even when not selected, so the assistant retains awareness of Sparkdock’s overview.
8. **Prompts**: Keep template strings under `src/sparkdock-ai/prompts/` so they stay scoped to the assistant feature. Add dedicated prompts for the classifier (`needs-files-*.txt`) and direct-answer flow.
9. **Answer Formatting**: Instruct the models to answer in Markdown suitable for `gum format`, render responses through `gum pager`, and gracefully degrade to plain stdout if gum is missing.
10. **Tests / Validation**: Provide manual test instructions (since tool integrates with live LLM).
11. **Docs**: Update `.github/README` or main `README.md` with usage instructions and auth notes, including the fact that authentication is handled interactively at runtime (`bin/sparkdock-ai` checks and guides the user through `export OPENAI_API_KEY` as needed). Document the new “quick answer” path.
12. **Logging**: Record key engine events to `~/.config/spark/sparkdock/ai.log` (configurable via `SPARKDOCK_AI_LOG_FILE`) with INFO vs TRACE levels controlled by `SPARKDOCK_AI_LOG_LEVEL`.
13. **Help UX**: Ship a static Markdown help sheet (`src/sparkdock-ai/help.md`) detailing the architecture diagram and usage tips; expose it via a “Help” option in the gum front-end.

## Open Questions
- Should we cache LLM-selected files per question to speed re-asks? (Nice-to-have; optional.)
- Do we log interactions locally for auditing? Default to `--no-log` to avoid storing content; mention privacy trade-offs.
- Model choices are fixed per stage: classifier (`gpt-3.5-turbo`), contextual reasoning (`gpt-4o-mini`), and quick answers (`gpt-4o`). No environment overrides for now.
