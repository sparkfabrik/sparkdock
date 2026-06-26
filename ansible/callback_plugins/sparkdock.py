"""Sparkdock stdout callback: emit the line protocol the sparkdock TUI parses.

It interleaves human-readable content lines with machine-readable markers so the
terminal hub (src/tui) can render a streaming view with a pinned statusline:

    @@PHASE <play name>
    @@TASK  <task name>
    @@STAT  ok=.. changed=.. failed=.. skipped=..
    @@DONE
    ✓ / ~ / ✗ / »  <task name>   (ok / changed / failed / skipped)

Enable per invocation (the TUI does this automatically):

    ANSIBLE_STDOUT_CALLBACK=sparkdock
    ANSIBLE_CALLBACK_PLUGINS=<repo>/ansible/callback_plugins
"""

from __future__ import annotations

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "sparkdock"

    def __init__(self):
        super().__init__()
        self.ok = 0
        self.changed = 0
        self.failed = 0
        self.skipped = 0

    def _emit(self, line):
        self._display.display(line)

    def _stat(self):
        self._emit(
            "@@STAT ok=%d changed=%d failed=%d skipped=%d"
            % (self.ok, self.changed, self.failed, self.skipped)
        )

    def v2_playbook_on_play_start(self, play):
        self._emit("@@PHASE " + (play.get_name().strip() or "play"))

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._emit("@@TASK " + task.get_name().strip())

    def v2_runner_on_ok(self, result):
        name = result._task.get_name().strip()
        if result._result.get("changed", False):
            self.changed += 1
            self._emit("~ " + name)
        else:
            self.ok += 1
            self._emit("✓ " + name)
        self._stat()

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self.failed += 1
        name = result._task.get_name().strip()
        msg = result._result.get("msg", "")
        suffix = (" (ignored)" if ignore_errors else "") + (": " + msg if msg else "")
        self._emit("✗ " + name + suffix)
        self._stat()

    def v2_runner_on_skipped(self, result):
        self.skipped += 1
        self._emit("» " + result._task.get_name().strip())
        self._stat()

    def v2_runner_on_unreachable(self, result):
        self.failed += 1
        self._emit("✗ " + result._task.get_name().strip() + " (unreachable)")
        self._stat()

    def v2_playbook_on_stats(self, stats):
        self._emit("@@DONE")
