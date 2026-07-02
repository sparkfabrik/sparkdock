// Package logview shows the full captured output of a run in a scrollable,
// copyable view and writes it to a known file, so a failure can be pasted
// elsewhere for support. Clipboard and file writes are injected dependencies,
// keeping the page unit-testable without touching the system.
package logview

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// BackMsg asks the app to return to the previous page.
type BackMsg struct{}

// Clipboard copies text to the system clipboard.
type Clipboard func(text string) error

// FileWriter persists the log to path (creating parent dirs as needed).
type FileWriter func(path string, data []byte) error

// Model is the log page.
type Model struct {
	width, height int
	vp            viewport.Model
	title         string
	lines         []string
	path          string
	copied        bool
	copyFailed    bool
	writeErr      error

	clip  Clipboard
	write FileWriter
	home  string
}

// New returns a log page wired to the system clipboard (pbcopy, falling back
// to OSC 52 for remote sessions) and the filesystem.
func New() Model {
	return Model{clip: systemClipboard, write: writeFile, home: os.Getenv("HOME")}
}

// SetSize updates dimensions and the viewport.
func (m *Model) SetSize(w, h int) {
	m.width, m.height = w, h
	m.vp.Width = w
	m.vp.Height = max(h-4, 1)
}

// Open loads the captured lines, writes them to the cache file, and shows them.
func (m *Model) Open(title string, lines []string) {
	m.title = title
	m.lines = lines
	m.copied, m.copyFailed = false, false
	m.path = m.logPath()
	m.writeErr = m.write(m.path, []byte(strings.Join(lines, "\n")+"\n"))
	m.vp = viewport.New(m.width, max(m.height-4, 1))
	m.vp.SetContent(strings.Join(lines, "\n"))
}

func (m Model) logPath() string {
	base := m.home
	if base == "" {
		return filepath.Join(os.TempDir(), "sparkdock-last-run.log")
	}
	return filepath.Join(base, ".cache", "sparkdock", "last-run.log")
}

// Update handles copy, scroll, and back.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, nil
	}
	switch key.String() {
	case "esc", "q", "l":
		return m, func() tea.Msg { return BackMsg{} }
	case "y":
		if err := m.clip(strings.Join(m.lines, "\n")); err == nil {
			m.copied, m.copyFailed = true, false
		} else {
			m.copyFailed = true
		}
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

// View renders the log with copy hint and saved path.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	header := st.Title.Render(" run log") + st.Dim.Render("   esc back")
	rule := st.Dim.Render(strings.Repeat("─", width))
	copyHint := "y copy to clipboard"
	switch {
	case m.copied:
		copyHint = st.OK.Render(theme.MarkOK + " copied to clipboard")
	case m.copyFailed:
		copyHint = st.Failed.Render(theme.MarkFailed + " copy failed (use the saved file)")
	}
	saved := st.Dim.Render(" saved: " + m.path)
	if m.writeErr != nil {
		saved = st.Failed.Render(" " + theme.MarkFailed + " could not save: " + m.writeErr.Error())
	}
	footer := st.Dim.Render(" "+copyHint+" · ↑↓ scroll · g/G top/bottom · esc back") + "\n" + saved
	return header + "\n" + rule + "\n" + m.vp.View() + "\n" + footer
}

// systemClipboard copies via pbcopy, falling back to OSC 52 when pbcopy cannot
// reach the clipboard (an SSH session into this machine).
func systemClipboard(text string) error {
	if err := pbcopy(text); err == nil {
		return nil
	}
	return osc52(text)
}

func pbcopy(text string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	return cmd.Run()
}

// osc52 copies by writing an OSC 52 escape to the controlling terminal: the
// terminal emulator stores the text in the local clipboard, which works where
// pbcopy cannot reach it (an SSH session into this machine).
func osc52(text string) error {
	tty, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer tty.Close()
	_, err = fmt.Fprintf(tty, "\x1b]52;c;%s\x07", base64.StdEncoding.EncodeToString([]byte(text)))
	return err
}

func writeFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}
