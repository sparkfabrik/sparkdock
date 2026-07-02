// Package recipelist renders a filterable browser over the sjust recipe
// catalog. Typing narrows the list, enter runs the selected recipe through the
// shared runner (as `sjust <name>`), esc clears the filter or goes back. The
// catalog is loaded once per session through an injected recipes.Loader.
package recipelist

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/recipes"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
)

// chromeRows is the non-list rows: header, rule, filter line, spacer, footer.
const chromeRows = 5

// loadTimeout bounds the `just --dump` call.
const loadTimeout = 15 * time.Second

// LoadedMsg carries the fetched catalog (or its error) into the model.
type LoadedMsg struct {
	Recipes []recipes.Recipe
	Err     error
}

// BackMsg asks the app to return to the dashboard.
type BackMsg struct{}

// Model is the recipe browser page.
type Model struct {
	width, height int
	loader        recipes.Loader

	all     []recipes.Recipe
	hay     []string // lowercase name+doc+group per recipe, built once on load
	query   string
	cursor  int
	loading bool
	loaded  bool
	errMsg  string
}

// New returns a recipe browser bound to a catalog loader.
func New(loader recipes.Loader) Model {
	return Model{loader: loader}
}

// SetSize updates render dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

// Open shows the page, fetching the catalog on first use (it is cached for the
// session; press R on the page to reload).
func (m Model) Open() (Model, tea.Cmd) {
	if m.loaded || m.loading {
		return m, nil
	}
	return m.load()
}

func (m Model) load() (Model, tea.Cmd) {
	m.loading = true
	m.errMsg = ""
	loader := m.loader
	return m, func() tea.Msg {
		if loader == nil {
			return LoadedMsg{Err: errors.New("recipe loader not wired")}
		}
		ctx, cancel := context.WithTimeout(context.Background(), loadTimeout)
		defer cancel()
		rs, err := loader(ctx)
		return LoadedMsg{Recipes: rs, Err: err}
	}
}

// Update handles catalog arrival, filtering, and selection.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case LoadedMsg:
		m.loading = false
		m.loaded = true
		if msg.Err != nil {
			m.errMsg = msg.Err.Error()
			return m, nil
		}
		m.all = msg.Recipes
		m.hay = make([]string, len(m.all))
		for i, r := range m.all {
			m.hay[i] = strings.ToLower(r.Name + " " + r.Doc + " " + r.Group)
		}
		m.clamp()
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc:
		if m.query != "" {
			m.query = ""
			m.clamp()
			return m, nil
		}
		return m, func() tea.Msg { return BackMsg{} }
	case tea.KeyUp:
		m.move(-1)
		return m, nil
	case tea.KeyDown:
		m.move(1)
		return m, nil
	case tea.KeyBackspace:
		if m.query != "" {
			r := []rune(m.query)
			m.query = string(r[:len(r)-1])
			m.clamp()
		}
		return m, nil
	case tea.KeyEnter:
		if r, ok := m.current(); ok {
			name := r.Name
			return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, "sjust:"+name) }
		}
		return m, nil
	case tea.KeyRunes:
		if string(msg.Runes) == "R" && m.query == "" {
			return m.load()
		}
		m.query += string(msg.Runes)
		m.clamp()
		return m, nil
	}
	return m, nil
}

// filtered returns the recipes matching the query (case-insensitive substring
// over name, doc, and group).
func (m Model) filtered() []recipes.Recipe {
	if m.query == "" {
		return m.all
	}
	q := strings.ToLower(m.query)
	var out []recipes.Recipe
	for i, r := range m.all {
		if strings.Contains(m.hay[i], q) {
			out = append(out, r)
		}
	}
	return out
}

func (m *Model) move(d int) {
	n := len(m.filtered())
	if n == 0 {
		return
	}
	m.cursor = min(max(m.cursor+d, 0), n-1)
}

func (m *Model) clamp() {
	if n := len(m.filtered()); m.cursor >= n {
		m.cursor = max(n-1, 0)
	}
}

func (m Model) current() (recipes.Recipe, bool) {
	f := m.filtered()
	if m.cursor >= 0 && m.cursor < len(f) {
		return f[m.cursor], true
	}
	return recipes.Recipe{}, false
}

// View renders the browser: header, filter, windowed list, footer.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	var b strings.Builder
	b.WriteString(" " + st.SparkS.Render(theme.Spark) + " " + st.Title.Render("sjust recipes") +
		st.Dim.Render("   ·   type to filter · esc back") + "\n")
	b.WriteString(st.Dim.Render(strings.Repeat("─", width)) + "\n")

	filter := " " + st.Dim.Render("filter: ")
	if m.query != "" {
		filter += st.Title.Render(m.query)
	} else {
		filter += st.Dim.Render("(all)")
	}
	f := m.filtered()
	filter += st.Dim.Render(fmt.Sprintf("   %d/%d", len(f), len(m.all)))
	b.WriteString(filter + "\n")

	switch {
	case m.loading:
		b.WriteString("\n  " + st.Amber.Render(theme.DotStale) + " " + st.Dim.Render("loading recipe catalog…") + "\n")
	case m.errMsg != "":
		b.WriteString("\n  " + st.Failed.Render(theme.MarkFailed+" "+m.errMsg) + "\n")
		b.WriteString("  " + st.Dim.Render("R reload · esc back") + "\n")
	default:
		b.WriteString(m.listView(st, width, f))
	}

	b.WriteString("\n" + st.Dim.Render(" ⏎ run · ↑↓ move · type filter · R reload · esc back"))
	return b.String()
}

// displayLine is one rendered row of the list: either a group header or the
// recipe at idx. Group headers occupy real rows, so the scroll window must be
// computed over these, not over recipe indices alone — otherwise the page
// renders taller than the terminal and the top gets clipped.
type displayLine struct {
	header string // non-empty: a group header row
	idx    int    // recipe index into the filtered slice when header == ""
}

func displayLines(f []recipes.Recipe) []displayLine {
	var out []displayLine
	lastGroup := "\x00"
	for i, r := range f {
		if r.Group != lastGroup {
			lastGroup = r.Group
			label := r.Group
			if label == "" {
				label = "other"
			}
			out = append(out, displayLine{header: label})
		}
		out = append(out, displayLine{idx: i})
	}
	return out
}

// listView renders a cursor-centred window of the filtered recipes, sized in
// rendered rows (group headers included) so the page never exceeds the
// terminal height.
func (m Model) listView(st theme.Styles, width int, f []recipes.Recipe) string {
	if len(f) == 0 {
		return "\n  " + st.Dim.Render("no recipes match the filter") + "\n"
	}
	rows := max(m.height-chromeRows, 3)
	lines := displayLines(f)
	cursorLine := 0
	for i, dl := range lines {
		if dl.header == "" && dl.idx == m.cursor {
			cursorLine = i
			break
		}
	}
	start := 0
	if cursorLine >= rows {
		start = cursorLine - rows + 1
	}
	end := min(start+rows, len(lines))

	var b strings.Builder
	for _, dl := range lines[start:end] {
		if dl.header != "" {
			b.WriteString("  " + st.Group.Render(dl.header) + "\n")
			continue
		}
		r := f[dl.idx]
		line := theme.ActionRow(st, dl.idx == m.cursor, r.Name, r.Doc)
		b.WriteString(ansi.Truncate(line, width, "…") + "\n")
	}
	return b.String()
}
