// Package theme centralises every colour, glyph, and lipgloss style used by the
// TUI so the visual language lives in one place and pages stay free of literals.
package theme

import "github.com/charmbracelet/lipgloss"

// Brand and semantic colours. 256-colour codes keep output readable on the
// common terminals sparkdock targets; truecolor terminals render them faithfully.
var (
	Accent  = lipgloss.Color("99")  // brand purple
	Orange  = lipgloss.Color("208") // spark glyph
	Green   = lipgloss.Color("42")  // ok
	Amber   = lipgloss.Color("214") // stale / changed
	Yellow  = lipgloss.Color("220") // changed (content)
	Red     = lipgloss.Color("196") // failed
	Grey    = lipgloss.Color("240") // dim / secondary
	FgLight = lipgloss.Color("15")  // selected foreground
)

// Glyphs shared across views.
const (
	Spark       = "✦"
	DotOK       = "●"
	DotStale    = "◐"
	DotUnknown  = "○"
	MarkOK      = "✓"
	MarkChanged = "~"
	MarkFailed  = "✗"
	MarkSkipped = "»"
	Pointer     = "▸"
	PhaseArrow  = "▶"
)

// Styles is the resolved set of styles for a given width. Construct once per
// render via New; cheap to build, avoids global mutable state.
type Styles struct {
	Title    lipgloss.Style
	Dim      lipgloss.Style
	Group    lipgloss.Style
	Selected lipgloss.Style
	Action   lipgloss.Style
	OK       lipgloss.Style
	Changed  lipgloss.Style
	Failed   lipgloss.Style
	Skipped  lipgloss.Style
	Amber    lipgloss.Style
	SparkS   lipgloss.Style
}

// Default is the shared style set. Styles do not depend on width, so a single
// cached instance serves every page and avoids rebuilding per frame.
var defaultStyles = New()

// Default returns the cached style set.
func Default() Styles { return defaultStyles }

// New returns a fresh style set. Prefer Default in render paths; New exists for
// tests or callers wanting an independent instance.
func New() Styles {
	return Styles{
		Title:    lipgloss.NewStyle().Bold(true).Foreground(Accent),
		Dim:      lipgloss.NewStyle().Foreground(Grey),
		Group:    lipgloss.NewStyle().Bold(true).Foreground(Grey),
		Selected: lipgloss.NewStyle().Bold(true).Foreground(FgLight).Background(Accent),
		Action:   lipgloss.NewStyle().Bold(true),
		OK:       lipgloss.NewStyle().Foreground(Green),
		Changed:  lipgloss.NewStyle().Foreground(Yellow),
		Failed:   lipgloss.NewStyle().Foreground(Red),
		Skipped:  lipgloss.NewStyle().Foreground(Grey),
		Amber:    lipgloss.NewStyle().Foreground(Amber),
		SparkS:   lipgloss.NewStyle().Bold(true).Foreground(Orange),
	}
}
