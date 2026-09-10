# Claude writing guard

Sparkdock's Claude guard requests the platform and writing skills before recognized GitHub or GitLab publishing commands. It skips unavailable skills and remembers successful loads.

## Enable and bypass

Provisioning installs the guard. To upgrade an existing registration, run:

```bash
sjust claude-gh-gate-enable
```

On Linux, use `ajust` instead of `sjust`. Start a new Claude session afterward. The existing command names remain available:

- **Inspect:** `sjust claude-gh-gate-info`
- **Disable persistently:** `sjust claude-gh-gate-disable`
- **Skip writing enforcement:** `SPARKDOCK_WRITING_GUARD=0 claude`
- **Skip the entire gate:** `SPARKDOCK_GH_GATE=0 claude`

Both variables accept `0`, `off`, `false` and `no`, ignoring case and surrounding whitespace. Set them before starting Claude. An assignment inside a proposed Bash command does not change the hook's environment.

The writing bypass leaves the `gh` and `glab` requirements active. Neither bypass hides skills from Claude or prevents it from loading them independently.

## Required skills

| Command                                             | Required skills                       |
| --------------------------------------------------- | ------------------------------------- |
| `gh` commands                                       | `gh`                                  |
| `glab` commands                                     | `glab`                                |
| Issue, PR/MR, comment, review and release authoring | Platform skill and `sf-writing-style` |
| Explicit API writes                                 | Platform skill and `sf-writing-style` |

Authoring includes `create`, `edit`, `update`, `comment`, `note` and `review` for issues, PRs, MRs, releases, discussions, gists and snippets. API calls with fields, input or a non-GET/HEAD method conservatively require writing guidance, including GraphQL queries submitted as POST requests.

The guard recognizes direct commands, absolute executable paths, simple shell chains, environment assignments, `env`, `command`, `rtk`, `rtk proxy` and `rtk-run`. It does not execute shell text or open description files.

## Missing skills and failures

The guard checks personal Claude skills and project `.claude/skills` directories from the working directory through its ancestors. Personal skills honor `CLAUDE_CONFIG_DIR`. Linked skills work; unlinked copies under `~/.agents/skills` do not count. Empty, unreadable, broken-link and manual-only skills are skipped, as are skills marked `off` or `user-invocable-only` in those settings files.

A successful `PostToolUse` event confirms a load. A failed load never counts as success. Each required skill gets at most one load request per context: if Claude does not confirm it, the next command proceeds with a notice. This also handles validation or permission failures that do not emit a failure hook.

Unavailable or unconfirmed skills produce one short notice per skill per session. Available requirements still apply. Malformed input, corrupt state and inaccessible storage allow the command without a traceback.

This is a workflow aid, not a security control. An agent that ignores the first load request can proceed on retry.

## Repeated calls and compaction

After successful loads, the guard stays silent. It runs local Python only and never injects full skill bodies or calls a model.

State is isolated by session and subagent under `${XDG_CACHE_HOME:-~/.cache}/sparkdock/claude-skill-gate/`. Resume preserves confirmations. Startup, clear and compaction reset them, so the next relevant command requests fresh confirmation. Notice history survives compaction.

Claude itself [deduplicates unchanged skill invocations](https://code.claude.com/docs/en/skills#skill-content-lifecycle). A re-invocation after compaction can restore content that Claude dropped. The guard does not guarantee fewer billed tokens.

## Limits

The guard acts before recognized Bash commands. It cannot enforce style in chat-only drafts, aliases, arbitrary scripts, dynamic shell syntax, heredocs or MCP connectors. Plugin-only skills and additional discovery locations are not resolved; a successful tracked load still counts.

Loading guidance does not guarantee concise or factual text. When the guard stops a command, it asks Claude to apply the loaded guidance to any prepared text before retrying. It does not inspect or rewrite the body itself.

## Tests

Run the runtime and installer tests with:

```bash
python3 -m unittest discover -s sjust/scripts/lib -p test_claude_gh_gate.py
just test-python
```

Tests use fixture skills, private cache directories and inert CLI stubs. They cover both platforms, bypasses, missing skills, failed loads, repeated calls, session lifecycle, shell parsing, storage failures and migration from the old hook registration.

The [recorded Claude results](claude-writing-guard-results.json) cover six isolated sessions on Linux with Claude Code 2.1.266 and Opus 5. All six completed two fixture publications without repeated skill loads. The writing bypass requested only the platform skill; Claude could still load writing guidance independently. Compaction and subagent behavior were covered by hook-payload tests.
