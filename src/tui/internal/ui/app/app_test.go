package app

import (
	"context"
	"os/exec"
	"testing"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/password"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

type stubChecker struct{}

func (stubChecker) Check(context.Context) []status.Subsystem { return nil }

// newTestApp wires an app whose ansible runner is a fast, harmless fake so
// starting a run never spawns ansible-playbook.
func newTestApp() Model {
	m := New(Config{Root: "/tmp"}, version.Info{}, stubChecker{})
	m.ansible = &runner.Runner{Build: func(ctx context.Context, _ runner.Options) *exec.Cmd {
		return exec.CommandContext(ctx, "bash", "-c", "printf '@@DONE\\n'")
	}}
	m.setSize(80, 24)
	return m
}

func update(m Model, msg interface{}) Model {
	next, _ := m.Update(msg)
	return next.(Model)
}

func TestNonSudoActionStartsRunDirectly(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "sync"))
	if m.page != ui.PageRunner {
		t.Errorf("page = %v, want PageRunner", m.page)
	}
}

func TestSudoActionPromptsForPassword(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "provision"))
	if m.page != ui.PagePassword {
		t.Errorf("page = %v, want PagePassword", m.page)
	}
	if m.pendingAction != "provision" {
		t.Errorf("pendingAction = %q, want provision", m.pendingAction)
	}
}

func TestPasswordSubmitStartsRunAndCachesBecome(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "provision"))
	m = update(m, password.SubmitMsg{Password: "s3cret"})
	if m.page != ui.PageRunner {
		t.Errorf("page = %v, want PageRunner", m.page)
	}
	if m.become != "s3cret" {
		t.Errorf("become = %q, want cached", m.become)
	}
}

func TestCachedPasswordSkipsPrompt(t *testing.T) {
	m := newTestApp()
	m.become = "cached"
	m = update(m, ui.Navigate(ui.PageRunner, "upgrade"))
	if m.page != ui.PageRunner {
		t.Errorf("page = %v, want PageRunner (no prompt with cached password)", m.page)
	}
}

func TestPendingActionTracksLatestSudoAction(t *testing.T) {
	m := newTestApp()
	m.become = "cached" // both go straight to run
	m = update(m, ui.Navigate(ui.PageRunner, "provision"))
	if m.pendingAction != "provision" {
		t.Fatalf("pendingAction = %q, want provision", m.pendingAction)
	}
	m = update(m, ui.Navigate(ui.PageRunner, "upgrade"))
	if m.pendingAction != "upgrade" {
		t.Errorf("pendingAction = %q, want upgrade (must track latest for correct re-prompt)", m.pendingAction)
	}
}

func TestUnhandledActionReturnsToDashboard(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "device"))
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard for unhandled action", m.page)
	}
}

func TestSjustActionOpensBrowser(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "sjust"))
	if m.page != ui.PageSjust {
		t.Errorf("page = %v, want PageSjust", m.page)
	}
}

func TestNavigateToSjustDirect(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageSjust, ""))
	if m.page != ui.PageSjust {
		t.Errorf("page = %v, want PageSjust", m.page)
	}
}
