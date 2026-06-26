// Package sjust browses the sjust task runner's recipes and runs the selected
// one through the shared Runner. The recipe lister is injected so the page is
// testable without invoking sjust.
package sjust

import (
	"os/exec"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// RunMsg asks the app to run the named recipe.
type RunMsg struct{ Recipe string }

// BackMsg asks the app to return to the dashboard.
type BackMsg struct{}

type loadedMsg struct {
	recipes []string
	err     error
}

// Lister returns the available sjust recipe names.
type Lister func() ([]string, error)

// Model is the sjust browser page.
type Model struct {
	width, height int
	recipes       []string
	cursor        int
	errMsg        string
	loading       bool
	list          Lister
}

// New returns a browser wired to the given lister (DefaultLister for production).
func New(list Lister) Model {
	return Model{list: list, loading: true}
}

// Init loads the recipe list.
func (m Model) Init() tea.Cmd {
	list := m.list
	return func() tea.Msg {
		if list == nil {
			return loadedMsg{}
		}
		recipes, err := list()
		return loadedMsg{recipes: recipes, err: err}
	}
}

// SetSize updates dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

// Update handles loading, navigation, run, and back.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case loadedMsg:
		m.loading = false
		m.recipes = msg.recipes
		if msg.err != nil {
			m.errMsg = msg.err.Error()
		}
		if m.cursor >= len(m.recipes) {
			m.cursor = 0
		}
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "q":
			return m, func() tea.Msg { return BackMsg{} }
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.recipes)-1 {
				m.cursor++
			}
		case "enter":
			if m.cursor >= 0 && m.cursor < len(m.recipes) {
				recipe := m.recipes[m.cursor]
				return m, func() tea.Msg { return RunMsg{Recipe: recipe} }
			}
		}
	}
	return m, nil
}

// View renders the recipe list.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	var b strings.Builder
	b.WriteString(st.Title.Render(" sjust task runner") + st.Dim.Render("   esc back") + "\n")
	b.WriteString(st.Dim.Render(strings.Repeat("─", width)) + "\n\n")

	switch {
	case m.loading:
		b.WriteString(st.Dim.Render("  loading recipes…"))
		return b.String()
	case m.errMsg != "":
		b.WriteString("  " + st.Failed.Render(theme.MarkFailed+" "+m.errMsg))
		return b.String()
	case len(m.recipes) == 0:
		b.WriteString(st.Dim.Render("  no recipes found"))
		return b.String()
	}

	for i, r := range m.recipes {
		if i == m.cursor {
			b.WriteString("  " + st.Selected.Render(" "+r+" ") + "\n")
		} else {
			b.WriteString("    " + r + "\n")
		}
	}
	b.WriteString("\n" + st.Dim.Render(" ↑↓ move · ⏎ run · esc back"))
	return b.String()
}

// DefaultLister runs `sjust --list` and extracts recipe names.
func DefaultLister() ([]string, error) {
	out, err := exec.Command("sjust", "--list").Output()
	if err != nil {
		return nil, err
	}
	return parseRecipes(string(out)), nil
}

// parseRecipes extracts recipe names from `just --list` output: a header line
// followed by indented "  name args  # comment" lines. Only the first token of
// each indented line is kept.
func parseRecipes(out string) []string {
	var recipes []string
	for _, line := range strings.Split(out, "\n") {
		if !strings.HasPrefix(line, "    ") {
			continue // skip the header and blank lines
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if strings.HasPrefix(fields[0], "[") {
			continue // group header like "[ai-coding-harness]", not a recipe
		}
		recipes = append(recipes, fields[0])
	}
	return recipes
}
