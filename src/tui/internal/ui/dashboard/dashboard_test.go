package dashboard

import (
	"context"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/sysinfo"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

func keyMsg(s string) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
}

type fakeChecker struct{ keys []string }

func (f fakeChecker) Subsystems() []string { return f.keys }
func (f fakeChecker) CheckOne(_ context.Context, key string) status.Subsystem {
	return status.Subsystem{Key: key, Health: status.OK, Detail: "up to date"}
}

func newTestModel(keys ...string) Model {
	m := New(fakeChecker{keys: keys}, sysinfo.Gatherer{}, version.Info{})
	m.SetSize(100, 40)
	return m
}

func TestStreaming_RowsLandIndividually(t *testing.T) {
	m := newTestModel("sparkdock", "brew")
	if m.Ready() {
		t.Fatal("model must start loading")
	}

	m, _ = m.Update(SubsystemMsg{Key: "brew", Health: status.Stale, Detail: "2 to update"})
	if m.Ready() {
		t.Fatal("one of two rows landed; round must still be in flight")
	}
	if !strings.Contains(m.View(), "2 to update") {
		t.Error("landed row must render before the round completes")
	}

	m, _ = m.Update(SubsystemMsg{Key: "sparkdock", Health: status.OK, Detail: "up to date"})
	if !m.Ready() {
		t.Error("all rows landed; round must be complete")
	}
}

func TestRefresh_KeepsRowsVisibleWhileReloading(t *testing.T) {
	m := newTestModel("sparkdock")
	m, _ = m.Update(SubsystemMsg{Key: "sparkdock", Health: status.OK, Detail: "up to date"})

	m, _ = m.Refresh()
	if m.Ready() {
		t.Error("refresh must mark the round in flight")
	}
	if !strings.Contains(m.View(), "up to date") {
		t.Error("previous rows must stay visible during a refresh")
	}
}

func TestCheckedAgo(t *testing.T) {
	base := time.Date(2026, 7, 2, 12, 0, 0, 0, time.UTC)
	m := newTestModel("sparkdock")
	m.now = func() time.Time { return base }
	m, _ = m.Update(SubsystemMsg{Key: "sparkdock", Health: status.OK})

	m.now = func() time.Time { return base.Add(30 * time.Second) }
	if got := m.checkedAgo(); got != " · checked just now" {
		t.Errorf("checkedAgo() = %q, want ' · checked just now'", got)
	}
	m.now = func() time.Time { return base.Add(5 * time.Minute) }
	if got := m.checkedAgo(); got != " · checked 5m ago" {
		t.Errorf("checkedAgo() = %q, want ' · checked 5m ago'", got)
	}
	m.now = func() time.Time { return base.Add(3 * time.Hour) }
	if got := m.checkedAgo(); got != " · checked 3h ago" {
		t.Errorf("checkedAgo() = %q, want ' · checked 3h ago'", got)
	}
}

func TestRecipesRowNavigatesToBrowser(t *testing.T) {
	m := newTestModel("sparkdock")
	// walk the cursor to the recipes row
	for range 10 {
		if it := m.current(); it != nil && it.id == "recipes" {
			break
		}
		m.move(1)
	}
	it := m.current()
	if it == nil || it.id != "recipes" {
		t.Fatal("recipes action row not reachable with the cursor")
	}
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter on the recipes row must emit a command")
	}
	nav, ok := cmd().(ui.NavigateMsg)
	if !ok || nav.To != ui.PageRecipes {
		t.Errorf("got %+v, want Navigate(PageRecipes)", nav)
	}
}

func TestHelpOverlayToggles(t *testing.T) {
	m := newTestModel("sparkdock")
	m, _ = m.Update(keyMsg("?"))
	if !m.HelpOpen() {
		t.Fatal("? must open the help overlay")
	}
	if !strings.Contains(m.View(), "keys") {
		t.Error("help view must render the key reference")
	}
	m, _ = m.Update(keyMsg("q"))
	if m.HelpOpen() {
		t.Error("q must close the overlay (not quit) while help is open")
	}
}

// --- macOS doctor ------------------------------------------------------------

// cursorTo walks the cursor to the row with the given id, bounded by the item
// count so a missing row fails the test instead of looping forever.
func cursorTo(t *testing.T, m *Model, id string) {
	t.Helper()
	for range len(m.items) + 1 {
		if it := m.current(); it != nil && it.id == id {
			return
		}
		m.move(1)
	}
	t.Fatalf("row %q not reachable with the cursor", id)
}

func TestDoctorRowNavigatesToRunner(t *testing.T) {
	m := newTestModel("doctor")
	cursorTo(t, &m, "doctor")

	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter on the doctor row must emit a command")
	}
	nav, ok := cmd().(ui.NavigateMsg)
	if !ok || nav.To != ui.PageRunner || nav.Action != "doctor" {
		t.Errorf("got %+v, want Navigate(PageRunner, \"doctor\")", nav)
	}
}

// Shift+D is the shortcut. Lowercase d is device info and must stay that way.
func TestDoctorShortcutKeys(t *testing.T) {
	m := newTestModel("doctor")

	_, cmd := m.Update(keyMsg("D"))
	if cmd == nil {
		t.Fatal("D must emit a command")
	}
	if nav, ok := cmd().(ui.NavigateMsg); !ok || nav.Action != "doctor" {
		t.Errorf("D gave %+v, want action \"doctor\"", nav)
	}

	_, cmd = m.Update(keyMsg("d"))
	if cmd == nil {
		t.Fatal("d must still emit a command")
	}
	if nav, ok := cmd().(ui.NavigateMsg); !ok || nav.Action != "device" {
		t.Errorf("d gave %+v, want action \"device\" (unchanged)", nav)
	}
}

// The doctor health row belongs in the status group above the rule, not among
// the actions.
func TestDoctorStatusRowIsInStatusGroup(t *testing.T) {
	m := newTestModel("doctor")
	m, _ = m.Update(SubsystemMsg{Key: "doctor", Health: status.Stale, Detail: "4 finding(s)"})

	ruleAt := -1
	for i, it := range m.items {
		if it.kind == kindRule {
			ruleAt = i
			break
		}
	}
	if ruleAt < 0 {
		t.Fatal("no rule separating status rows from actions")
	}

	found := false
	for _, it := range m.items[:ruleAt] {
		if it.kind == kindStatus && it.id == "doctor" {
			found = true
			if it.detail != "4 finding(s)" {
				t.Errorf("doctor status detail = %q, want the checker's detail", it.detail)
			}
		}
	}
	if !found {
		t.Error("doctor status row missing from the status group")
	}
}
