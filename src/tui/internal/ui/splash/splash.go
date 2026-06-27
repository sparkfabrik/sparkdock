// Package splash renders the launch splash: the SPARKDOCK block-font wordmark,
// a tagline, and the version. It auto-dismisses after a short timeout or on any
// key. Branding is typography, never a downscaled raster image.
package splash

import (
	_ "embed"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/audio"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

//go:embed assets/wordmark.txt
var wordmark string

// minWidth below which the block wordmark is replaced by a spaced text fallback.
const minWidth = 84

// Timing: show the splash at least minShow so it is not a flash, but no longer
// than maxShow so a slow status load never traps the user.
const (
	minShow = 900 * time.Millisecond
	maxShow = 8 * time.Second
)

// MinElapsedMsg fires once the minimum splash time has passed.
type MinElapsedMsg struct{}

// TimeoutMsg fires at the maximum splash time, forcing a hand-off.
type TimeoutMsg struct{}

// ClickedMsg fires when the user clicks the logo (the app holds the splash a
// little longer so they can keep clicking to hear the sound).
type ClickedMsg struct{}

// Model is the splash page.
type Model struct {
	width, height int
	ver           version.Info
}

// New returns a splash for the given version info.
func New(ver version.Info) Model { return Model{ver: ver} }

// Init starts the minimum and maximum splash timers.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		tea.Tick(minShow, func(time.Time) tea.Msg { return MinElapsedMsg{} }),
		tea.Tick(maxShow, func(time.Time) tea.Msg { return TimeoutMsg{} }),
	)
}

// SetSize updates the render dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

// Update plays the startup sound when the logo is clicked, and dismisses on any
// key or click (the timer dismiss is handled by the app router).
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m, func() tea.Msg { return ui.Navigate(ui.PageDashboard, "") }
	case tea.MouseMsg:
		if msg.Action == tea.MouseActionPress {
			audio.Play() // click the logo to hear it; the app holds the splash a bit
			return m, func() tea.Msg { return ClickedMsg{} }
		}
	}
	return m, nil
}

// View renders the centred splash.
func (m Model) View() string {
	st := theme.Default()
	w, h := m.width, m.height
	if w == 0 {
		w, h = 80, 24
	}
	var mark string
	if w >= minWidth {
		mark = st.Title.Render(strings.TrimRight(wordmark, "\n"))
	} else {
		mark = st.Title.Render("S P A R K D O C K")
	}
	spark := st.SparkS.Render(theme.Spark)
	block := lipgloss.JoinVertical(lipgloss.Center,
		mark, "",
		spark+"  "+st.Dim.Render("dev environment manager")+"  "+spark, "",
		st.Dim.Render(m.ver.Short()), "",
		st.Dim.Render("preparing… · click the logo · any key to skip"),
	)
	return lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, block)
}
