package runview

import (
	"io"
	"strings"

	"github.com/charmbracelet/x/vt"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
)

// terminalContent renders arbitrary terminal programs (brew, spark-http-proxy,
// …) through a virtual terminal emulator, so in-place redraws (progress bars,
// cursor moves) display faithfully as a live screen rather than piling up.
//
// Programs that query their terminal (CSI 6n cursor position, OSC 10/11
// colors — anything charm/gum based) block until a reply arrives, and the
// emulator writes its replies to an internal pipe that itself blocks until
// read. A forwarder goroutine pumps that pipe into the child's PTY; without it
// the first query would freeze both the child and this UI.
//
// The forwarder is not closed deliberately: Emulator.Close races with a
// blocked Read (an unsynchronized flag upstream), so the goroutine is left
// parked on the pipe instead — it exits on the first forward that fails after
// the child's PTY closes, and a parked one costs a few KB for the session.
type terminalContent struct {
	emu *vt.Emulator
}

func newTerminalContent(w, h int, input io.Writer) *terminalContent {
	c := &terminalContent{emu: vt.NewEmulator(max(w, 1), max(h, 1))}
	if input != nil {
		go func() { _, _ = io.Copy(input, c.emu) }()
	}
	return c
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
