package runview

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// structuredContent renders the sparkdock callback protocol: it decodes raw
// output into feed events, accumulates rendered lines and the running tally, and
// presents them in a scrollable viewport. Used for ansible runs.
type structuredContent struct {
	dec   feed.Decoder
	vp    viewport.Model
	width int

	lines []string // rendered, styled lines
	raw   []string // verbatim content lines, for the copyable log

	phaseName string
	taskName  string
	tally     feed.Stats
	hasTally  bool
}

func newStructuredContent(w, h int) *structuredContent {
	return &structuredContent{vp: viewport.New(w, h), width: w}
}

func (c *structuredContent) write(p []byte) {
	for _, e := range c.dec.Write(p) {
		c.apply(e)
	}
	c.vp.SetContent(c.body())
}

func (c *structuredContent) apply(e feed.Event) {
	if !e.IsControl() {
		c.raw = append(c.raw, e.Raw)
	}
	st := theme.Default()
	switch e.Kind {
	case feed.KindPhase:
		c.phaseName = e.Text
		c.lines = append(c.lines, st.Title.Render(theme.PhaseArrow+" "+e.Text))
	case feed.KindTask:
		c.taskName = e.Text
	case feed.KindStat:
		c.tally = e.Stats
		c.hasTally = true
	case feed.KindResult:
		c.lines = append(c.lines, "  "+glyph(st, e.Glyph)+" "+e.Text)
	case feed.KindPlain:
		c.lines = append(c.lines, "  "+e.Text)
	}
}

// body truncates each line to the width so a long line can't overflow.
func (c *structuredContent) body() string {
	w := max(c.width, 20)
	out := make([]string, len(c.lines))
	for i, l := range c.lines {
		out[i] = ansi.Truncate(l, w, "")
	}
	return strings.Join(out, "\n")
}

func (c *structuredContent) resize(w, h int) {
	c.width = w
	c.vp.Width = w
	c.vp.Height = h
	c.vp.SetContent(c.body())
}

func (c *structuredContent) render() string             { return c.vp.View() }
func (c *structuredContent) rawLog() []string           { return c.raw }
func (c *structuredContent) phase() string              { return c.phaseName }
func (c *structuredContent) task() string               { return c.taskName }
func (c *structuredContent) stats() (feed.Stats, bool)  { return c.tally, c.hasTally }
func (c *structuredContent) scroll(delta int) {
	if delta < 0 {
		c.vp.ScrollUp(-delta)
	} else {
		c.vp.ScrollDown(delta)
	}
}
func (c *structuredContent) gotoTop()                   { c.vp.GotoTop() }
func (c *structuredContent) gotoBottom()                { c.vp.GotoBottom() }

func (c *structuredContent) follow(mode ScrollMode) {
	if mode == PinTop {
		c.vp.GotoTop()
	} else {
		c.vp.GotoBottom()
	}
}

// finalize adds the final tally line (ansible only).
func (c *structuredContent) finalize() {
	if !c.hasTally {
		return
	}
	c.lines = append(c.lines, "", lipgloss.NewStyle().Bold(true).Render("Summary")+
		fmt.Sprintf("  %d ok · %d changed · %d failed · %d skipped",
			c.tally.OK, c.tally.Changed, c.tally.Failed, c.tally.Skipped))
	c.vp.SetContent(c.body())
}
