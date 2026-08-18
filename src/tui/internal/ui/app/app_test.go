package app

import (
	"context"
	"os/exec"
	"testing"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/dashboard"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/password"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/runview"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/splash"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// stubChecker exposes one subsystem so the dashboard starts a round and the
// splash waits for it, mirroring the real startup sequence.
type stubChecker struct{}

func (stubChecker) Subsystems() []string { return []string{"stub"} }
func (stubChecker) CheckOne(context.Context, string) status.Subsystem {
	return status.Subsystem{Key: "stub", Health: status.OK}
}

// stubStatusMsg is the message completing the stub checker's round.
func stubStatusMsg() dashboard.SubsystemMsg {
	return dashboard.SubsystemMsg{Key: "stub", Health: status.OK}
}

// newTestApp wires an app whose ansible runner is a fast, harmless fake so
// starting a run never spawns ansible-playbook.
func newTestApp() Model {
	m := New(Config{Root: "/tmp"}, version.Info{}, Deps{Checker: stubChecker{}})
	m.ansible = &runner.Runner{Build: func(ctx context.Context, _ runner.Options) *exec.Cmd {
		return exec.CommandContext(ctx, "bash", "-c", "printf '@@DONE\\n'")
	}}
	m.setSize(80, 24)
	return m
}

func update(m Model, msg any) Model {
	next, _ := m.Update(msg)
	return next.(Model)
}

func TestActionStartsRunImmediately(t *testing.T) {
	// No pre-gating: a sudo action starts the run; the password is requested
	// reactively only if the process prompts.
	for _, action := range []string{"sync", "provision"} {
		m := update(newTestApp(), ui.Navigate(ui.PageRunner, action))
		if m.page != ui.PageRunner {
			t.Errorf("action %q: page = %v, want PageRunner", action, m.page)
		}
		if !m.hasLast {
			t.Errorf("action %q: last run not recorded", action)
		}
	}
}

func TestPromptShowsPasswordPageThenReturns(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "provision"))
	// the process asks for a password
	m = update(m, runview.PromptMsg{Text: "BECOME password:"})
	if m.page != ui.PagePassword {
		t.Fatalf("page = %v, want PagePassword on prompt", m.page)
	}
	// answering returns to the runner page
	m = update(m, password.SubmitMsg{Password: []byte("s3cret")})
	if m.page != ui.PageRunner {
		t.Errorf("page = %v, want PageRunner after answering", m.page)
	}
}

func TestPasswordCancelReturnsToRunner(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "provision"))
	m = update(m, runview.PromptMsg{Text: "BECOME password:"})
	m = update(m, password.CancelMsg{})
	if m.page != ui.PageRunner {
		t.Errorf("page = %v, want PageRunner after cancel", m.page)
	}
}

func TestSplash_DismissesOnlyWhenStatusReadyAndMinElapsed(t *testing.T) {
	m := newTestApp() // starts on splash
	m = update(m, splash.MinElapsedMsg{})
	if m.page != ui.PageSplash {
		t.Fatalf("page = %v, want PageSplash (status not loaded yet)", m.page)
	}
	m = update(m, stubStatusMsg())
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard once status ready and min elapsed", m.page)
	}
}

func TestSplash_StatusBeforeMinStillWaits(t *testing.T) {
	m := newTestApp()
	m = update(m, stubStatusMsg()) // ready, but min not elapsed
	if m.page != ui.PageSplash {
		t.Fatalf("page = %v, want PageSplash (min time not elapsed)", m.page)
	}
	m = update(m, splash.MinElapsedMsg{})
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard", m.page)
	}
}

func TestSplash_TimeoutForcesDismiss(t *testing.T) {
	m := newTestApp()
	m = update(m, splash.TimeoutMsg{}) // status never arrived
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard on timeout", m.page)
	}
}

func TestBackFromRecipeRunReturnsToBrowser(t *testing.T) {
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "sjust:device-info"))
	if m.page != ui.PageRunner {
		t.Fatalf("page = %v, want PageRunner", m.page)
	}
	m = update(m, runview.BackMsg{})
	if m.page != ui.PageRecipes {
		t.Errorf("page = %v, want PageRecipes after esc from a browser-launched run", m.page)
	}
	// A dashboard-launched run still returns home.
	m = update(m, ui.Navigate(ui.PageRunner, "sync"))
	m = update(m, runview.BackMsg{})
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard after esc from a dashboard run", m.page)
	}
}

func TestUnhandledActionReturnsToDashboard(t *testing.T) {
	// "self-update" has no run plan yet (deliberate follow-up), so it no-ops home.
	m := update(newTestApp(), ui.Navigate(ui.PageRunner, "self-update"))
	if m.page != ui.PageDashboard {
		t.Errorf("page = %v, want PageDashboard for unhandled action", m.page)
	}
}

// The doctor report is read-only, so it must not request sudo, and it is read
// from the top rather than followed like a build log.
func TestPlanForDoctor(t *testing.T) {
	m := New(Config{Root: "/opt/sparkdock"}, version.Info{}, Deps{Checker: stubChecker{}})

	spec, ok := m.planFor("doctor")
	if !ok {
		t.Fatal("planFor(\"doctor\") must be wired")
	}
	if spec.scroll != runview.PinTop {
		t.Errorf("scroll = %v, want PinTop for a one-shot report", spec.scroll)
	}
	if spec.render != runview.Structured {
		t.Errorf("render = %v, want Structured", spec.render)
	}
	if spec.sudo {
		t.Error("the doctor report path must never request sudo")
	}
	if spec.title != "macOS doctor" {
		t.Errorf("title = %q, want %q", spec.title, "macOS doctor")
	}
}

// The report script is resolved against Config.Root so a dev checkout runs its
// own checks instead of the /opt install's.
func TestPlanForDoctorUsesConfiguredRoot(t *testing.T) {
	m := New(Config{Root: "/tmp/checkout"}, version.Info{}, Deps{Checker: stubChecker{}})

	spec, ok := m.planFor("doctor")
	if !ok {
		t.Fatal("planFor(\"doctor\") must be wired")
	}
	cmd := spec.rnr.Build(context.Background(), runner.Options{})
	if len(cmd.Args) == 0 || cmd.Args[0] != "/tmp/checkout/sjust/scripts/macos-doctor/run.sh" {
		t.Errorf("cmd args = %v, want the run.sh under Config.Root", cmd.Args)
	}
}
