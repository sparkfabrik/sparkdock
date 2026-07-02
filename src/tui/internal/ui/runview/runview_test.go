package runview

import (
	"context"
	"os/exec"
	"strings"
	"testing"
	"time"

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
	m, _ = m.Update(outMsg{gen: m.gen, b: []byte(s)})
	return m
}

func finish(m Model, res runner.Result) Model {
	m, _ = m.Update(doneMsg{gen: m.gen, res: res})
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
	m = finish(m, runner.Result{})
	if m.running || m.failed || m.canceled {
		t.Errorf("want success state; running=%v failed=%v canceled=%v", m.running, m.failed, m.canceled)
	}
}

func TestFinish_NonZeroExitFails(t *testing.T) {
	m := structuredModel()
	m = finish(m, runner.Result{Err: errBoom{}})
	if !m.failed {
		t.Error("failed = false, want true on non-zero exit")
	}
}

func TestFinish_FailedTaskCountFails(t *testing.T) {
	m := structuredModel()
	m = feedBytes(m, "@@STAT ok=2 changed=0 failed=1 skipped=0\n")
	m = finish(m, runner.Result{})
	if !m.failed {
		t.Error("failed = false, want true when stats.Failed > 0")
	}
}

func TestFinish_CancelNotFailure(t *testing.T) {
	m := structuredModel()
	m = finish(m, runner.Result{Canceled: true, Err: errBoom{}})
	if m.failed {
		t.Error("canceled run must not be marked failed")
	}
	if !m.canceled {
		t.Error("canceled = false, want true")
	}
}

// TestTerminalRun_AnswersCursorPositionQuery reproduces the gum/charm hang:
// the child queries its terminal with CSI 6n and blocks until a reply arrives.
// The reply exists only if the emulator's response pipe is forwarded to the
// child's PTY; without the forwarder both the child and the UI froze.
func TestTerminalRun_AnswersCursorPositionQuery(t *testing.T) {
	script := `printf '\033[6n'; IFS= read -r -d R reply; printf 'got-reply\n'`
	r := &runner.Runner{Build: func(ctx context.Context, _ runner.Options) *exec.Cmd {
		return exec.CommandContext(ctx, "bash", "-c", script)
	}}
	h := r.Start(context.Background(), runner.Options{PtyRows: 24, PtyCols: 80})
	c := newTerminalContent(80, 24, h)

	var out strings.Builder
	done := false
	for !done {
		select {
		case chunk, ok := <-h.Output:
			if !ok {
				done = true
				break
			}
			out.Write(chunk)
			c.write(chunk) // triggers the emulator's CPR reply via the forwarder
		case <-time.After(5 * time.Second):
			h.Cancel()
			t.Fatal("child never received the cursor position reply (forwarder broken)")
		}
	}
	<-h.Done
	if !strings.Contains(out.String(), "got-reply") {
		t.Errorf("child did not confirm the reply; output: %q", out.String())
	}
}

func TestTerminalContent_RendersWrites(t *testing.T) {
	c := newTerminalContent(40, 5, nil)
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

func TestStaleRunMessagesDropped(t *testing.T) {
	m := structuredModel()
	m.gen = 2 // a second run is live; gen-1 messages are leftovers

	m, _ = m.Update(outMsg{gen: 1, b: []byte("old run noise\n")})
	if joined := strings.Join(m.content.rawLog(), "\n"); strings.Contains(joined, "old run noise") {
		t.Errorf("stale output leaked into the new run's content: %q", joined)
	}

	m, _ = m.Update(doneMsg{gen: 1, res: runner.Result{Canceled: true}})
	if !m.running || m.canceled {
		t.Errorf("stale done finished the new run; running=%v canceled=%v", m.running, m.canceled)
	}

	m, cmd := m.Update(promptMsg{gen: 1, text: "Password:"})
	if cmd != nil {
		t.Error("stale prompt must not surface the password page")
	}
	_ = m
}

type errBoom struct{}

func (errBoom) Error() string { return "boom" }
