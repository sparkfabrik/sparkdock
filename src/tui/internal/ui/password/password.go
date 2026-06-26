// Package password renders the masked become-password prompt. It only collects
// input and emits Submit/Cancel; the app owns the password lifetime (in-memory,
// session-scoped, never persisted) and decides when to re-prompt.
package password

import (
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// SubmitMsg carries an entered password to the app.
type SubmitMsg struct{ Password string }

// CancelMsg signals the user backed out of the prompt.
type CancelMsg struct{}

// Model is the password page.
type Model struct {
	width, height int
	input         textinput.Model
	title         string
	errMsg        string
}

// New returns a password page with a masked input.
func New() Model {
	ti := textinput.New()
	ti.Placeholder = "macOS password"
	ti.EchoMode = textinput.EchoPassword
	ti.EchoCharacter = '•'
	ti.Prompt = "  password: "
	return Model{input: ti}
}

// SetSize updates dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

// Prompt resets the page for a fresh ask. errMsg is shown when re-prompting
// after an incorrect password; pass "" for the first ask.
func (m *Model) Prompt(title, errMsg string) tea.Cmd {
	m.title = title
	m.errMsg = errMsg
	m.input.SetValue("")
	m.input.Focus()
	return textinput.Blink
}

// Update handles entry, submit, and cancel.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "esc":
			m.input.Blur()
			return m, func() tea.Msg { return CancelMsg{} }
		case "enter":
			if strings.TrimSpace(m.input.Value()) == "" {
				m.errMsg = "password cannot be empty"
				return m, nil
			}
			pw := m.input.Value()
			m.input.SetValue("") // don't retain the secret in the input buffer
			m.input.Blur()
			return m, func() tea.Msg { return SubmitMsg{Password: pw} }
		}
	}
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

// View renders the prompt.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	var b strings.Builder
	b.WriteString(st.Title.Render(" sparkdock") + st.Dim.Render(" · sudo required") + "   " + st.Dim.Render("esc cancel") + "\n")
	b.WriteString(st.Dim.Render(strings.Repeat("─", width)) + "\n\n")
	b.WriteString("  " + strings.TrimSpace(m.title) + " needs administrator access.\n\n")
	b.WriteString(m.input.View() + "\n\n")
	if m.errMsg != "" {
		b.WriteString("  " + st.Failed.Render(theme.MarkFailed+" "+m.errMsg) + "\n\n")
	}
	b.WriteString(st.Dim.Render("  ⏎ continue · esc cancel") + "\n")
	b.WriteString(st.Dim.Render("  ⓘ held in memory for this session, passed only to the ansible subprocess (not your shell)"))
	return b.String()
}
