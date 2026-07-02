// Package whatsnew renders the CHANGELOG's Unreleased section in a scrollable
// page, so a user can see what the next update brings (or what just landed)
// without leaving the hub. The document source is injected for testability.
package whatsnew

import (
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/changelog"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// BackMsg asks the app to return to the dashboard.
type BackMsg struct{}

// Source reads the changelog document (typically CHANGELOG.md at the install
// root).
type Source func() ([]byte, error)

// Model is the what's-new page.
type Model struct {
	width, height int
	src           Source
	vp            viewport.Model
	lines         []string
	errMsg        string
	opened        bool
}

// New returns a what's-new page reading from src.
func New(src Source) Model {
	return Model{src: src}
}

// SetSize updates dimensions and re-renders the viewport content.
func (m *Model) SetSize(w, h int) {
	m.width, m.height = w, h
	m.vp.Width = w
	m.vp.Height = max(h-4, 1)
	if m.opened {
		m.vp.SetContent(m.render())
	}
}

// Open (re)reads the changelog and shows its Unreleased section.
func (m Model) Open() Model {
	m.opened = true
	m.errMsg = ""
	m.lines = nil
	if m.src == nil {
		m.errMsg = "changelog source not wired"
		return m
	}
	data, err := m.src()
	if err != nil {
		m.errMsg = err.Error()
		return m
	}
	m.lines = changelog.Unreleased(string(data))
	m.vp = viewport.New(m.width, max(m.height-4, 1))
	m.vp.SetContent(m.render())
	return m
}

// Update handles scroll and back keys.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, nil
	}
	switch key.String() {
	case "esc", "q", "w":
		return m, func() tea.Msg { return BackMsg{} }
	case "up", "k":
		m.vp.ScrollUp(1)
	case "down", "j":
		m.vp.ScrollDown(1)
	case "g":
		m.vp.GotoTop()
	case "G":
		m.vp.GotoBottom()
	}
	return m, nil
}

// render styles the raw changelog lines: section headers stand out, bullets
// wrap to the width instead of being cut mid-sentence.
func (m Model) render() string {
	st := theme.Default()
	width := max(m.width-4, 30)
	var b strings.Builder
	for _, ln := range m.lines {
		switch {
		case strings.HasPrefix(ln, "### "):
			b.WriteString(" " + st.Group.Render(strings.TrimPrefix(ln, "### ")) + "\n")
		case strings.HasPrefix(ln, "- "):
			for i, seg := range wrap(strings.TrimPrefix(ln, "- "), width) {
				prefix := "   " + st.SparkS.Render("•") + " "
				if i > 0 {
					prefix = "     "
				}
				b.WriteString(prefix + st.Dim.Render(seg) + "\n")
			}
		case ln == "":
			b.WriteString("\n")
		default:
			b.WriteString(" " + st.Dim.Render(ansi.Truncate(ln, width, "…")) + "\n")
		}
	}
	if b.Len() == 0 {
		return " " + st.Dim.Render("no unreleased changes")
	}
	return b.String()
}

// wrap greedily wraps text into segments of at most width cells, breaking on
// spaces.
func wrap(text string, width int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return []string{""}
	}
	var out []string
	line := words[0]
	for _, w := range words[1:] {
		if len(line)+1+len(w) > width {
			out = append(out, line)
			line = w
			continue
		}
		line += " " + w
	}
	return append(out, line)
}

// View renders header, content, and footer.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	header := " " + st.SparkS.Render(theme.Spark) + " " + st.Title.Render("what's new") +
		st.Dim.Render("   ·   unreleased changes") + "\n" +
		st.Dim.Render(strings.Repeat("─", width))
	body := m.vp.View()
	if m.errMsg != "" {
		body = "\n  " + st.Failed.Render(theme.MarkFailed+" could not read the changelog: "+m.errMsg)
	}
	footer := st.Dim.Render(" ↑↓ scroll · g/G top/bottom · esc back")
	return header + "\n" + body + "\n" + footer
}
