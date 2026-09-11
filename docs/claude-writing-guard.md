# Claude and Codex writing guards

The guards request writing guidance before supported publishing calls. They confirm skill loads, then give one short publishing reminder per user turn. They do not score or rewrite the text.

## Install and inspect

Sparkdock provisioning installs both guards. The companion sf-toolbox change installs them on Linux. For an existing installation:

```bash
sjust writing-guard-enable
sjust writing-guard-info
```

Use `ajust` on Linux. Start a new Claude session after installation. In Codex, open `/hooks` and review/trust the new definitions. Registration alone does not activate untrusted hooks. The installer never changes trust, approval or sandbox settings.

Remove both registrations with `sjust writing-guard-disable`. Provisioning can reinstall them. For a persistent runtime opt-out, set an environment variable before starting the agent:

- `SPARKDOCK_WRITING_GUARD=0`: skip writing guidance and reminders; retain CLI platform requirements.
- `SPARKDOCK_GH_GATE=0`: skip the entire guard in either agent.

Both accept `0`, `off`, `false` and `no`, ignoring case and whitespace. They do not prevent the agent from loading skills independently.

The `claude-gh-gate-enable`, `claude-gh-gate-disable` and `claude-gh-gate-info` commands manage Claude alone. Corresponding Codex commands are `codex-writing-guard-enable`, `codex-writing-guard-disable` and `codex-writing-guard-info`.

## Coverage

| Transport                                                                    | Requirement                      |
| ---------------------------------------------------------------------------- | -------------------------------- |
| Recognized `gh` / `glab` shell commands                                      | Corresponding CLI skill          |
| CLI issue, PR/MR, comment, review and release authoring                      | CLI skill and `sf-writing-style` |
| Explicit CLI API writes                                                      | CLI skill and `sf-writing-style` |
| Supported Slack message sends, replies, updates and scheduling               | `sf-writing-style`               |
| Supported GitHub/GitLab MCP issue, PR/MR, comment, review and release writes | `sf-writing-style`               |

Connector reads do not require writing guidance. MCP coverage uses explicit operation names in `writing_guard.requirements`, including Claude Slack names and prefixed Codex app names. Unknown operations are not classified by guessing whether their arguments look like prose.

Shell coverage includes direct commands, absolute executable paths, simple chains, assignments, `env`, `command`, `rtk`, `rtk proxy` and `rtk-run`. API requests with fields or a non-GET/HEAD method conservatively count as writes.

## Loading and reminders

Claude confirms successful `Skill` calls through `PostToolUse`. A failed call never counts as a load.

Codex confirms a load when a Bash tool result contains the complete installed skill text. The command must mention `SKILL.md`; mentioning a path or returning truncated text is insufficient. Read the requested file with enough output allowance. Native loaders and partial reads are not tracked.

The first supported write requests any missing available skills and asks the agent to revise its prepared text before retrying. If the skill was already loaded, the guard instead gives a short review reminder. Later writes in the same user turn proceed without another reminder. A new user prompt resets only the reminder; it does not force a full reload.

Resume preserves confirmations. Startup, clear and compaction reset them. State is separate for each engine and session, and also uses `agent_id` when supplied. Codex does not document an agent identifier on every tool event, so isolation of Codex subagents is not guaranteed by this adapter.

The hooks run local Python and never call a model or inject full skill bodies. Reminders and retries still consume some tokens. Loading a skill does not guarantee that the model follows it.

## Missing skills and failures

Claude discovery checks personal and ancestor project `.claude/skills` locations, honoring `CLAUDE_CONFIG_DIR` and local skill overrides. Codex discovery checks `CODEX_HOME/skills` and ancestor `.codex/skills` locations. It honors disabled entries in those `config.toml` files and requires Python 3.11 or newer to parse them. Other discovery locations, profile overrides and plugin-only skills are not resolved.

Unavailable, empty, unreadable, broken-link and manual-only skills are skipped. Each skill gets at most one load request per context. If the load is not confirmed, the next attempt proceeds with a notice. Invalid input, corrupt state and inaccessible storage also fail open. This is a workflow aid, not a security boundary.

Installation preserves unrelated hooks and backs up existing JSON files. Re-running enable repairs partial registrations. The shared installer reports a change when either registration changes. Malformed Codex settings and malformed Claude hook objects are not overwritten.

## Diagnostics and limits

`writing-guard-info` reports registrations, bypasses and coverage. In Codex, `/hooks` remains the authority for trust and activation.

State lives under `${XDG_CACHE_HOME:-~/.cache}/sparkdock/{claude,codex}-skill-gate/`. Each private JSON file records confirmed/requested/skipped skills and the last matched tool decision. It does not record message bodies. Read this state together with hook events to distinguish a skipped check from a confirmed load.

Chat-only drafts, arbitrary scripts, aliases, dynamic shell syntax, heredocs, unknown connector tools and hosted tools are outside coverage. Nested tool execution depends on the host emitting hook events; only direct fixture MCP and shell paths have live coverage tests. Sending input to an existing Codex shell session does not trigger a new `PreToolUse` check.

## Validation and references

Run `just test-python` for classifier, runtime, installer and lifecycle tests. Live tests use isolated settings, fixture skills, an inert CLI and a local Slack MCP server. No real messages or PRs are published by those tests.

- [Codex hooks and tool coverage](https://learn.chatgpt.com/docs/hooks#tool-coverage)
- [Codex hook trust](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks)
- [Claude skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle)
- [Shared guard live test results](shared-writing-guard-results.json)
- [Earlier Claude-only test results](claude-writing-guard-results.json)
