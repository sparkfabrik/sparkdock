# Sparkdock AI Helper

Sparkdock AI is an experimental “living documentation” tool baked into Sparkdock. It uses
GitHub Copilot models to read the repository, answer questions, and point to the exact
files it relied on. You can treat it as an always-fresh handbook that is generated from
Sparkdock’s own source.

## What You Get
- Interactive shell assistant driven by `bin/sparkdock-ai`.
- Automatic GitHub Copilot authentication prompts when required.
- Markdown-formatted answers rendered through Charm Gum.
- Source citations so you can open the referenced files immediately.
- Optional file logging at `~/.config/spark/sparkdock/ai.log` (raise verbosity with `SPARKDOCK_AI_LOG_LEVEL=TRACE`).

## Request Flow

```text
┌────────────────────┐         ┌────────────────────────────┐
│  User question     │         │  github_copilot/gpt-3.5-   │
│  (via gum UI)      ├────────▶│  turbo classifier          │
└────────────────────┘         └──────────────┬─────────────┘
                                              │ YES
                                              ▼
                                 ┌────────────────────────────┐
                                 │ File discovery + selection │
                                 │ (git ls-files + prompts)   │
                                 └──────────────┬─────────────┘
                                              │ context (files, excerpts)
                                              ▼
                                 ┌────────────────────────────┐
                                 │ github_copilot/gpt-4o-mini │
                                 │ contextual answer          │
                                 └──────────────┬─────────────┘
                                              │ answer + sources
                                              ▼
                                         gum format + pager

                        ┌────────────────────────────┐
                        │   NO (classifier says no)  │
                        └──────────────┬─────────────┘
                                      ▼
                        ┌────────────────────────────┐
                        │ github_copilot/gpt-4.1     │
                        │ direct answer (no files)   │
                        └──────────────┬─────────────┘
                                      │ answer only
                                      ▼
                                 gum format + pager
```

## Tips
- Use the “Custom question…” option in the menu to ask anything about Sparkdock.
- Turn on trace logging (`SPARKDOCK_AI_LOG_LEVEL=TRACE`) if you want to inspect the exact
  decisions the engine makes (classifier output, selected files, etc.).
- For repeatable debugging, export `SPARKDOCK_AI_DEBUG=1` to show raw model outputs in the UI.
