package runview

import (
	"strings"
	"testing"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
)

// structuredModel returns a runner page already in a structured run, so Update
// can be driven with outMsg without a live handle.
func structuredModel() Model {
	m := New()
	m.width, m.height = 80, 24
	m.running = true
	m.content = newStructuredContent(80, 18)
	return m
}

func feedBytes(m Model, s string) Model {
	m, _ = m.Update(outMsg([]byte(s)))
	return m
}

func TestStructured_CapturesContentAndStats(t *testing.T) {
	m := structuredModel()
	m = feedBytes(m, "@@PHASE Packages\n✓ docker present\n~ orbstack upgraded\n@@STAT ok=1 changed=1 failed=0 skipped=0\nPLAY RECAP noise\n")
	stats, ok := m.content.stats()
	if !ok || stats.OK != 1 || stats.Changed != 1 {
		t.Errorf("stats = %+v ok=%v", stats, ok)
	}
	joined := strings.Join(m.content.rawLog(), "\n")
	if !strings.Contains(joined, "docker present") || !strings.Contains(joined, "PLAY RECAP noise") {
		t.Errorf("raw missing content: %q", joined)
	}
	if strings.Contains(joined, "@@PHASE") || strings.Contains(joined, "@@STAT") {
		t.Errorf("raw should not contain control markers: %q", joined)
	}
}

func TestFinish_Success(t *testing.T) {
	m := structuredModel()
	m = feedBytes(m, "@@STAT ok=3 changed=1 failed=0 skipped=0\n")
	m, _ = m.Update(doneMsg(runner.Result{}))
	if m.running || m.failed || m.canceled {
		t.Errorf("want success state; running=%v failed=%v canceled=%v", m.running, m.failed, m.canceled)
	}
}

func TestFinish_NonZeroExitFails(t *testing.T) {
	m := structuredModel()
	m, _ = m.Update(doneMsg(runner.Result{Err: errBoom{}}))
	if !m.failed {
		t.Error("failed = false, want true on non-zero exit")
	}
}

func TestFinish_FailedTaskCountFails(t *testing.T) {
	m := structuredModel()
	m = feedBytes(m, "@@STAT ok=2 changed=0 failed=1 skipped=0\n")
	m, _ = m.Update(doneMsg(runner.Result{}))
	if !m.failed {
		t.Error("failed = false, want true when stats.Failed > 0")
	}
}

func TestFinish_CancelNotFailure(t *testing.T) {
	m := structuredModel()
	m, _ = m.Update(doneMsg(runner.Result{Canceled: true, Err: errBoom{}}))
	if m.failed {
		t.Error("canceled run must not be marked failed")
	}
	if !m.canceled {
		t.Error("canceled = false, want true")
	}
}

func TestTerminalContent_RendersWrites(t *testing.T) {
	c := newTerminalContent(40, 5)
	c.write([]byte("hello world"))
	if !strings.Contains(c.render(), "hello world") {
		t.Errorf("terminal render missing text: %q", c.render())
	}
	if _, ok := c.stats(); ok {
		t.Error("terminal content should report no stats")
	}
}

func TestRunning(t *testing.T) {
	if New().Running() {
		t.Error("fresh model should not be running")
	}
}

type errBoom struct{}

func (errBoom) Error() string { return "boom" }
