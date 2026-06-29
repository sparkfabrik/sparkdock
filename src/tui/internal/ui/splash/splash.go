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

// Glow timing: a click flares the logo for glowDur, redrawn every glowFrame,
// matching the logo sound's envelope.
const (
	glowDur   = 700 * time.Millisecond
	glowFrame = 45 * time.Millisecond
)

// MinElapsedMsg fires once the minimum splash time has passed.
type MinElapsedMsg struct{}

// TimeoutMsg fires at the maximum splash time, forcing a hand-off.
type TimeoutMsg struct{}

// glowTickMsg drives a frame of the logo flare; its time is compared to the
// flare's start to derive the animation phase.
type glowTickMsg time.Time

// Model is the splash page.
type Model struct {
	width, height int
	ver           version.Info

	glowStart  time.Time
	glowing    bool
	glowFactor float64
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

// Update dismisses on any key, and on a logo click plays the startup sound and
// starts the flare. A click never dismisses; the timer dismiss is handled by the
// app router.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m, func() tea.Msg { return ui.Navigate(ui.PageDashboard, "") }
	case tea.MouseMsg:
		if msg.Action == tea.MouseActionPress {
			audio.Play() // click the logo to hear it
			wasGlowing := m.glowing
			m.glowStart = time.Now()
			m.glowing = true
			m.glowFactor = 0
			if wasGlowing {
				// A flare is already running; restart its envelope (new
				// glowStart) and let the single tick loop carry it, rather than
				// spawning a second concurrent loop.
				return m, nil
			}
			return m, glowTick()
		}
	case glowTickMsg:
		if !m.glowing {
			return m, nil
		}
		phase := float64(time.Time(msg).Sub(m.glowStart)) / float64(glowDur)
		if phase >= 1 {
			m.glowing = false
			m.glowFactor = 0
			return m, nil
		}
		m.glowFactor = theme.GlowFactor(phase)
		return m, glowTick()
	}
	return m, nil
}

// glowTick schedules the next flare frame.
func glowTick() tea.Cmd {
	return tea.Tick(glowFrame, func(t time.Time) tea.Msg { return glowTickMsg(t) })
}

// View renders the centred splash.
func (m Model) View() string {
	st := theme.Default()
	w, h := m.width, m.height
	if w == 0 {
		w, h = 80, 24
	}
	markStyle, sparkStyle := st.Title, st.SparkS
	if m.glowing {
		markStyle = markStyle.Foreground(theme.Glow(theme.TitleGlowBase, m.glowFactor))
		sparkStyle = sparkStyle.Foreground(theme.Glow(theme.SparkGlowBase, m.glowFactor))
	}
	var mark string
	if w >= minWidth {
		mark = markStyle.Render(strings.TrimRight(wordmark, "\n"))
	} else {
		mark = markStyle.Render("S P A R K D O C K")
	}
	spark := sparkStyle.Render(theme.Spark)
	block := lipgloss.JoinVertical(lipgloss.Center,
		mark, "",
		spark+"  "+st.Dim.Render("dev environment manager")+"  "+spark, "",
		st.Amber.Render("beta")+st.Dim.Render(" · experimental"), "",
		st.Dim.Render(m.ver.Short()), "",
		st.Dim.Render("preparing… · click the logo · any key to skip"),
	)
	return lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, block)
}
