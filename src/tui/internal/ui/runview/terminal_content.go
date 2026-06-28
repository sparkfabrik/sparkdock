package runview

import (
	"strings"

	"github.com/charmbracelet/x/vt"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
)

// terminalContent renders arbitrary terminal programs (brew, spark-http-proxy,
// …) through a virtual terminal emulator, so in-place redraws (progress bars,
// cursor moves) display faithfully as a live screen rather than piling up.
type terminalContent struct {
	emu *vt.Emulator
}

func newTerminalContent(w, h int) *terminalContent {
	return &terminalContent{emu: vt.NewEmulator(max(w, 1), max(h, 1))}
}

func (c *terminalContent) write(p []byte)  { _, _ = c.emu.Write(p) }
func (c *terminalContent) render() string  { return c.emu.Render() }
func (c *terminalContent) resize(w, h int) { c.emu.Resize(max(w, 1), max(h, 1)) }
func (c *terminalContent) finalize()       {}

// rawLog returns the current screen for the copyable log.
func (c *terminalContent) rawLog() []string { return strings.Split(c.emu.Render(), "\n") }

// A terminal program has no structured phase/task/tally, and its live screen is
// already at the right position, so scroll controls are no-ops.
func (c *terminalContent) phase() string             { return "" }
func (c *terminalContent) task() string              { return "" }
func (c *terminalContent) stats() (feed.Stats, bool) { return feed.Stats{}, false }
func (c *terminalContent) follow(ScrollMode)         {}
func (c *terminalContent) scroll(int)                {}
func (c *terminalContent) gotoTop()                  {}
func (c *terminalContent) gotoBottom()               {}
