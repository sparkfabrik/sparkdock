# Sparkdock AI Helper

Sparkdock AI is an experimental “living documentation” tool baked into Sparkdock. It uses
OpenAI models to read the repository, answer questions, and point to the exact files it
relied on. You can treat it as an always-fresh handbook that is generated from
Sparkdock’s own source.

## What You Get
- Interactive shell assistant driven by `bin/sparkdock-ai`.
- Environment validation to ensure `OPENAI_API_KEY` is available before starting.
- Markdown-formatted answers rendered through Charm Gum.
- Source citations so you can open the referenced files immediately.
- Optional file logging at `~/.config/spark/sparkdock/ai.log` (raise verbosity with `SPARKDOCK_AI_LOG_LEVEL=TRACE`).

## Request Flow

```text
┌────────────────────┐         ┌────────────────────────────┐
│  User question     │         │  gpt-3.5-turbo classifier  │
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
                                 │ gpt-4.1-nano contextual    │
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
                        │ gpt-5-nano direct answer   │
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

## Need Support?
- Post in Slack `#support-tech` with a short description and any relevant logs (for example `~/.config/spark/sparkdock/ai.log`).
- If it looks like a product issue, open an issue in the Sparkdock repository so the team can follow up.
