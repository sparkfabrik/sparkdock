# Testing the sparkfabrik-harness plugin

The `sparkfabrik-harness` Claude Code plugin has three layers of tests: unit tests in CI, a live smoke run, and a manual check of the confirmation dialogs.

## Unit tests

```bash
just test-claude-harness
```

The recipe runs `claude plugin validate` and `claude plugin test`. The tests cover the guard rules and run the hooks against a mocked engine. They make no model calls and need no login. The `Test Claude Harness Plugin` workflow runs them on pull requests that touch the plugin or the shared writing guard classifier, pinned to the Claude Code version in the workflow.

## Live smoke run

```bash
just test-claude-harness-live
```

The recipe runs real `claude -p` sessions with the plugin loaded in a throwaway git repository. It checks that the plugin denies an unattended `rm -rf`, a secret file read and a commit subject outside the repository format. Each check needs the plugin's denial in the transcript and no side effect on the repository.

The run needs a logged-in Claude Code or `ANTHROPIC_API_KEY` and makes one model call per check. `CLAUDE_SMOKE_MODEL` picks the model (default `haiku`). Run it before a release and after a Claude Code upgrade. A failed check keeps its transcript and prints the path.

## Manual dialog check

`claude -p` has nobody to answer a dialog, so the smoke run cannot reach the confirmation paths. Check them once in an interactive session started with `claude --plugin-dir config/claude/plugins/sparkfabrik-harness` in a scratch repository:

1. Ask Claude to run `rm -rf build`. The **Guard** dialog appears. **Cancel** stops the command; **Run it** runs it.
2. Ask Claude to open a pull request with `gh pr create`. After the skills load, the **Publish** dialog shows the whole command. **Cancel** stops it.
3. Ask Claude to commit with a conventional subject and no `Refs:` footer. The **Commit** dialog asks before committing. **Commit anyway** commits.
