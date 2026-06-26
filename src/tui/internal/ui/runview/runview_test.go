package runview

import (
	"strings"
	"testing"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
)

// feedEvents drives the reducer with a sequence of parsed lines.
func feedEvents(m Model, lines ...string) Model {
	for _, l := range lines {
		m, _ = m.Update(eventMsg(feed.Parse(l)))
	}
	return m
}

func TestApply_CapturesContentAndStats(t *testing.T) {
	m := New(runner.New())
	m.running = true
	m = feedEvents(m,
		"@@PHASE Packages",
		"✓ docker present",
		"~ orbstack upgraded",
		"@@STAT ok=1 changed=1 failed=0 skipped=0",
		"PLAY RECAP noise",
	)
	if m.stats.OK != 1 || m.stats.Changed != 1 {
		t.Errorf("stats = %+v", m.stats)
	}
	// raw log keeps content lines but not control markers
	joined := strings.Join(m.raw, "\n")
	if !strings.Contains(joined, "docker present") || !strings.Contains(joined, "PLAY RECAP noise") {
		t.Errorf("raw missing content: %q", joined)
	}
	if strings.Contains(joined, "@@PHASE") || strings.Contains(joined, "@@STAT") {
		t.Errorf("raw should not contain control markers: %q", joined)
	}
}

func TestFinish_Success(t *testing.T) {
	m := New(runner.New())
	m.running = true
	m = feedEvents(m, "@@STAT ok=3 changed=1 failed=0 skipped=0")
	m, _ = m.Update(doneMsg(runner.Result{}))
	if m.running || m.failed || m.canceled {
		t.Errorf("want completed-success state, got running=%v failed=%v canceled=%v", m.running, m.failed, m.canceled)
	}
	if !strings.Contains(strings.Join(m.lines, "\n"), "Summary") {
		t.Error("summary line missing")
	}
}

func TestFinish_NonZeroExitFails(t *testing.T) {
	m := New(runner.New())
	m.running = true
	m, _ = m.Update(doneMsg(runner.Result{Err: errBoom{}}))
	if !m.failed {
		t.Error("failed = false, want true on non-zero exit")
	}
}

func TestFinish_FailedTaskCountFails(t *testing.T) {
	m := New(runner.New())
	m.running = true
	m = feedEvents(m, "@@STAT ok=2 changed=0 failed=1 skipped=0")
	m, _ = m.Update(doneMsg(runner.Result{})) // no exit err, but a task failed
	if !m.failed {
		t.Error("failed = false, want true when stats.Failed > 0")
	}
}

func TestFinish_CancelNotFailure(t *testing.T) {
	m := New(runner.New())
	m.running = true
	m, _ = m.Update(doneMsg(runner.Result{Canceled: true, Err: errBoom{}}))
	if m.failed {
		t.Error("canceled run must not be marked failed")
	}
	if !m.canceled {
		t.Error("canceled = false, want true")
	}
}

func TestRunning(t *testing.T) {
	m := New(runner.New())
	if m.Running() {
		t.Error("fresh model should not be running")
	}
}

type errBoom struct{}

func (errBoom) Error() string { return "boom" }
