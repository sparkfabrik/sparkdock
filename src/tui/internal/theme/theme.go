// Package theme centralises every colour, glyph, and lipgloss style used by the
// TUI so the visual language lives in one place and pages stay free of literals.
package theme

import (
	"fmt"
	"math"

	"github.com/charmbracelet/lipgloss"
)

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

// Glow base RGB for the logo flare. The wordmark base approximates the brand
// purple (256-colour 99) and the spark base the orange glyph (208); both are
// interpolated toward white at the flare's peak. Truecolor terminals render the
// ramp smoothly; lipgloss downsamples it on 256-colour terminals.
var (
	TitleGlowBase = [3]int{0x87, 0x5F, 0xFF}
	SparkGlowBase = [3]int{0xFF, 0x87, 0x00}
)

// GlowFactor maps an animation phase in [0,1] to a brightness factor in [0,1],
// mirroring the logo sound's envelope: a fast attack to a white-hot peak, then
// an exponential decay back to the base colour. Outside (0,1) it is 0.
func GlowFactor(phase float64) float64 {
	if phase <= 0 || phase >= 1 {
		return 0
	}
	const attack = 0.18
	if phase < attack {
		return phase / attack
	}
	return math.Exp(-3.5 * (phase - attack) / (1 - attack))
}

// Glow interpolates a base RGB colour toward white by factor f (clamped to
// [0,1]) and returns it as a truecolor hex value. f=0 is the base colour, f=1 is
// white.
func Glow(base [3]int, f float64) lipgloss.Color {
	f = math.Max(0, math.Min(1, f))
	mix := func(c int) int { return c + int(math.Round(float64(255-c)*f)) }
	return lipgloss.Color(fmt.Sprintf("#%02X%02X%02X", mix(base[0]), mix(base[1]), mix(base[2])))
}

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

// ActionRow renders one selectable row of a picker list: the pointer and label,
// highlighted when selected, with an optional dim detail. Both the dashboard's
// action list and the recipe browser use it, so the selection styling cannot
// drift between the two.
func ActionRow(st Styles, selected bool, label, detail string) string {
	line := "   " + st.Action.Render(Pointer+" "+label)
	if selected {
		line = "  " + st.Selected.Render(" "+Pointer+" "+label+" ")
	}
	if detail != "" {
		line += "  " + st.Dim.Render(detail)
	}
	return line
}

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
