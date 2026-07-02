package recipelist

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/recipes"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
)

func catalog() []recipes.Recipe {
	return []recipes.Recipe{
		{Name: "sf-harness-sync", Doc: "Sync skills", Group: "ai-coding-harness"},
		{Name: "clear-dns-cache", Doc: "Flush DNS", Group: "system"},
		{Name: "device-info", Doc: "Show device information", Group: "system"},
	}
}

func loadedModel() Model {
	m := New(nil)
	m.SetSize(90, 30)
	m, _ = m.Update(LoadedMsg{Recipes: catalog()})
	return m
}

func typeRunes(m Model, s string) Model {
	for _, r := range s {
		m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
	return m
}

func TestOpen_LoadsOnceAndCaches(t *testing.T) {
	calls := 0
	m := New(func(context.Context) ([]recipes.Recipe, error) {
		calls++
		return catalog(), nil
	})
	m, cmd := m.Open()
	if cmd == nil {
		t.Fatal("first open must load the catalog")
	}
	m, _ = m.Update(cmd().(LoadedMsg))
	if calls != 1 {
		t.Fatalf("loader calls = %d, want 1", calls)
	}
	if _, cmd = m.Open(); cmd != nil {
		t.Error("second open must reuse the cached catalog")
	}
}

func TestFilterNarrowsAndEscClears(t *testing.T) {
	m := loadedModel()
	m = typeRunes(m, "dns")
	if f := m.filtered(); len(f) != 1 || f[0].Name != "clear-dns-cache" {
		t.Fatalf("filtered = %+v, want only clear-dns-cache", f)
	}
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if len(m.filtered()) != 3 {
		t.Error("esc must clear the filter, not leave the page")
	}
}

func TestEnterEmitsSjustNavigate(t *testing.T) {
	m := loadedModel()
	m = typeRunes(m, "device")
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter on a recipe must emit a command")
	}
	nav, ok := cmd().(ui.NavigateMsg)
	if !ok || nav.To != ui.PageRunner || nav.Action != "sjust:device-info" {
		t.Errorf("got %+v, want Navigate(PageRunner, sjust:device-info)", nav)
	}
}

func TestEscWithoutFilterGoesBack(t *testing.T) {
	m := loadedModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd == nil {
		t.Fatal("esc must emit a command")
	}
	if _, ok := cmd().(BackMsg); !ok {
		t.Error("esc with no filter must emit BackMsg")
	}
}

func TestLoadErrorRendered(t *testing.T) {
	m := New(nil)
	m.SetSize(90, 30)
	m, _ = m.Update(LoadedMsg{Err: errors.New("just not found")})
	if !strings.Contains(m.View(), "just not found") {
		t.Error("load error must be rendered on the page")
	}
}

func TestViewNeverExceedsTerminalHeight(t *testing.T) {
	// Many groups: each header eats a row; the page must still fit the height.
	var cat []recipes.Recipe
	for i := 0; i < 40; i++ {
		g := string(rune('a' + i%20))
		cat = append(cat, recipes.Recipe{Name: fmt.Sprintf("recipe-%02d", i), Doc: "doc", Group: g})
	}
	m := New(nil)
	m.SetSize(80, 20)
	m, _ = m.Update(LoadedMsg{Recipes: cat})
	if got := strings.Count(m.View(), "\n") + 1; got > 20 {
		t.Errorf("view is %d rows for a 20-row terminal", got)
	}
	// Cursor at the bottom must stay visible without growing the page.
	for range 45 {
		m.move(1)
	}
	v := m.View()
	if got := strings.Count(v, "\n") + 1; got > 20 {
		t.Errorf("view is %d rows after scrolling, terminal is 20", got)
	}
	if !strings.Contains(v, "recipe-39") {
		t.Error("cursor row must be visible after scrolling to the bottom")
	}
}

func TestViewListsGroupsAndRecipes(t *testing.T) {
	m := loadedModel()
	v := m.View()
	for _, want := range []string{"ai-coding-harness", "system", "device-info", "Flush DNS"} {
		if !strings.Contains(v, want) {
			t.Errorf("view missing %q", want)
		}
	}
}
