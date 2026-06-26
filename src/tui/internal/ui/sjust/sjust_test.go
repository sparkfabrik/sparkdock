package sjust

import (
	"errors"
	"reflect"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func keyMsg(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "down":
		return tea.KeyMsg{Type: tea.KeyDown}
	case "up":
		return tea.KeyMsg{Type: tea.KeyUp}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

func loaded(m Model, recipes []string, err error) Model {
	m, _ = m.Update(loadedMsg{recipes: recipes, err: err})
	return m
}

func TestInitLoadsRecipes(t *testing.T) {
	m := New(func() ([]string, error) { return []string{"a", "b"}, nil })
	msg := m.Init()()
	lm, ok := msg.(loadedMsg)
	if !ok || !reflect.DeepEqual(lm.recipes, []string{"a", "b"}) {
		t.Fatalf("Init load = %+v", msg)
	}
}

func TestNavigateAndRun(t *testing.T) {
	m := loaded(New(nil), []string{"shell-enable", "device-info", "macos-defaults"}, nil)
	m, _ = m.Update(keyMsg("down"))
	m, _ = m.Update(keyMsg("down"))
	_, cmd := m.Update(keyMsg("enter"))
	run, ok := cmd().(RunMsg)
	if !ok || run.Recipe != "macos-defaults" {
		t.Fatalf("run = %+v", cmd())
	}
}

func TestNavigationClamps(t *testing.T) {
	m := loaded(New(nil), []string{"only"}, nil)
	m, _ = m.Update(keyMsg("up"))   // can't go above 0
	m, _ = m.Update(keyMsg("down")) // can't go past last
	if m.cursor != 0 {
		t.Errorf("cursor = %d, want 0", m.cursor)
	}
}

func TestBack(t *testing.T) {
	m := loaded(New(nil), []string{"a"}, nil)
	_, cmd := m.Update(keyMsg("esc"))
	if _, ok := cmd().(BackMsg); !ok {
		t.Fatalf("want BackMsg, got %T", cmd())
	}
}

func TestLoadError(t *testing.T) {
	m := loaded(New(nil), nil, errors.New("sjust not found"))
	if m.errMsg != "sjust not found" {
		t.Errorf("errMsg = %q", m.errMsg)
	}
}

func TestParseRecipes(t *testing.T) {
	out := "Available recipes:\n" +
		"    [group-name]\n" +
		"    shell-enable force   # enable shell\n" +
		"    device-info          # info\n" +
		"\n" +
		"    macos-defaults\n"
	got := parseRecipes(out)
	want := []string{"shell-enable", "device-info", "macos-defaults"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("parseRecipes = %v, want %v", got, want)
	}
}
