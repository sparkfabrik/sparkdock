// Package runview renders a running operation: a content region above a pinned,
// claude-code-style statusline, with cancel, retry, and a copyable log. It
// consumes a runner.Handle's raw output and delegates rendering to a content
// strategy: structured (the sparkdock callback → line list + tally) or terminal
// (a VT emulator → faithful live screen for arbitrary programs). Run
// orchestration (playbook, tags, sudo) lives in the app; this page only renders
// and controls a run it is handed.
package runview

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// chromeRows is the non-content rows: header, rule, a spacer, the statusline,
// and the footer.
const chromeRows = 5

// Messages flowing through the bubbletea loop while a run is live. Each carries
// the generation of the run that produced it: a cancelled previous run can still
// deliver late messages, and without the stamp its output would bleed into the
// new run (or its Done would mark the new run finished).
type (
	outMsg struct {
		gen int
		b   []byte
	}
	closedMsg struct{}
	doneMsg   struct {
		gen int
		res runner.Result
	}
	promptMsg struct {
		gen  int
		text string
	}
	promptsClosed struct{}
)

// PromptMsg tells the app the run is asking for a password; the app shows the
// password page and answers via AnswerPrompt.
type PromptMsg struct{ Text string }

// OpenLogMsg asks the app to open the captured output in the log page.
type OpenLogMsg struct {
	Title string
	Lines []string
}

// RetryMsg asks the app to re-run the last action.
type RetryMsg struct{}

// BackMsg asks the app to leave the runner page (only emitted once finished).
type BackMsg struct{}

// ScrollMode is how a run tracks output: streaming work follows the tail; a
// one-shot report pins to the top so it reads from the start.
type ScrollMode int

const (
	FollowTail ScrollMode = iota
	PinTop
)

// RenderMode selects the content renderer: Structured decodes the sparkdock
// callback into a line list; Terminal emulates a real terminal for arbitrary
// programs that redraw in place.
type RenderMode int

const (
	Structured RenderMode = iota
	Terminal
)

// content is a run's body renderer. Two implementations: structuredContent and
// terminalContent.
type content interface {
	write(p []byte)
	render() string
	resize(w, h int)
	finalize()
	rawLog() []string
	phase() string
	task() string
	stats() (feed.Stats, bool)
	follow(ScrollMode)
	scroll(delta int)
	gotoTop()
	gotoBottom()
}

// Model is the runner page.
type Model struct {
	width, height int

	handle  *runner.Handle
	content content
	gen     int // current run generation; stale-run messages are dropped

	sp     spinner.Model
	title  string
	start  time.Time
	scroll ScrollMode

	running  bool
	failed   bool
	canceled bool
}

// New returns a runner page.
func New() Model {
	sp := spinner.New()
	sp.Spinner = spinner.Dot
	sp.Style = lipgloss.NewStyle().Foreground(theme.Accent)
	return Model{sp: sp}
}

// SetSize updates dimensions, the active content renderer, and a live child's
// PTY (mirroring the sizing in app.start), so a mid-run terminal resize reaches
// the running program instead of leaving it rendering at a stale width.
func (m *Model) SetSize(w, h int) {
	m.width, m.height = w, h
	if m.content != nil {
		m.content.resize(w, m.bodyHeight())
	}
	if m.running && m.handle != nil {
		m.handle.Resize(max(h-chromeRows, 10), max(w-2, 20))
	}
}

func (m Model) bodyHeight() int { return max(m.height-chromeRows, 1) }

// Start renders the run represented by h under the given title, scroll, and
// render mode. A still-live previous run is cancelled first: its output is
// drained in the background (so its pump can deliver EOF and reap the child
// instead of blocking on a full channel) and its content finalized (stopping a
// terminal emulator's response forwarder).
func (m Model) Start(title string, h *runner.Handle, scroll ScrollMode, mode RenderMode) (Model, tea.Cmd) {
	if m.handle != nil && m.running {
		m.handle.Cancel()
		go func(old *runner.Handle) {
			for range old.Output {
			}
		}(m.handle)
		m.content.finalize()
	}
	m.gen++
	m.title = title
	m.scroll = scroll
	m.running, m.failed, m.canceled = true, false, false
	m.start = time.Now()
	if mode == Terminal {
		m.content = newTerminalContent(m.width, m.bodyHeight(), h)
	} else {
		m.content = newStructuredContent(m.width, m.bodyHeight())
	}
	m.handle = h
	return m, tea.Batch(waitOutput(h, m.gen), waitPrompt(h, m.gen), waitDone(h, m.gen), m.sp.Tick)
}

// Update advances the run.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.sp, cmd = m.sp.Update(msg)
		return m, cmd

	case outMsg:
		if msg.gen != m.gen {
			return m, nil // late output from a cancelled previous run
		}
		m.content.write(msg.b)
		if m.running {
			m.content.follow(m.scroll)
		}
		return m, waitOutput(m.handle, m.gen)

	case closedMsg:
		return m, nil

	case promptMsg:
		if msg.gen != m.gen {
			return m, nil
		}
		return m, tea.Batch(
			func() tea.Msg { return PromptMsg{Text: msg.text} },
			waitPrompt(m.handle, m.gen),
		)

	case promptsClosed:
		return m, nil

	case doneMsg:
		if msg.gen != m.gen {
			return m, nil // a cancelled previous run must not finish the new one
		}
		m.finish(msg.res)
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m *Model) finish(res runner.Result) {
	m.running = false
	m.canceled = res.Canceled
	stats, hasStats := m.content.stats()
	m.failed = !res.Canceled && (res.Err != nil || (hasStats && stats.Failed > 0))
	m.content.finalize()
	m.content.follow(m.scroll)
}

func (m Model) handleKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	if msg.String() == "ctrl+c" {
		if m.running && m.handle != nil {
			m.handle.Cancel()
		}
		return m, nil
	}
	if m.running {
		return m.handleRunningKey(msg)
	}
	switch msg.String() {
	case "esc", "q":
		return m, func() tea.Msg { return BackMsg{} }
	case "r":
		return m, func() tea.Msg { return RetryMsg{} }
	case "l":
		if lines := m.content.rawLog(); len(lines) > 0 {
			cp := append([]string(nil), lines...)
			return m, func() tea.Msg { return OpenLogMsg{Title: m.title, Lines: cp} }
		}
	case "up", "k":
		m.content.scroll(-1)
	case "down", "j":
		m.content.scroll(1)
	case "g":
		m.content.gotoTop()
	case "G":
		m.content.gotoBottom()
	}
	return m, nil
}

// handleRunningKey forwards input to the live process (so prompts like brew's
// "Proceed? [y/n]" are answerable), while arrows scroll.
func (m Model) handleRunningKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	if m.handle == nil {
		return m, nil
	}
	switch msg.Type {
	case tea.KeyUp:
		m.content.scroll(-1)
	case tea.KeyDown:
		m.content.scroll(1)
	case tea.KeyEnter:
		m.handle.WriteInput("\n")
	case tea.KeyBackspace:
		m.handle.WriteInput("\x7f")
	case tea.KeySpace:
		m.handle.WriteInput(" ")
	case tea.KeyRunes:
		m.handle.WriteInput(string(msg.Runes))
	}
	return m, nil
}

// Running reports whether a run is in progress.
func (m Model) Running() bool { return m.running }

// AnswerPrompt writes the password to the running process's PTY; the runner
// zeroes the buffer once written.
func (m Model) AnswerPrompt(password []byte) {
	if m.handle != nil {
		m.handle.Answer(password)
	}
}

// CancelRun cancels the in-progress run.
func (m Model) CancelRun() {
	if m.handle != nil {
		m.handle.Cancel()
	}
}

// View renders header, content region, pinned statusline, and footer.
func (m Model) View() string {
	st := theme.Default()
	width := max(m.width, 40)
	header := st.Title.Render(" "+m.title) + st.Dim.Render("   esc back")
	rule := st.Dim.Render(strings.Repeat("─", width))

	glyphRune := m.sp.View()
	switch {
	case m.failed:
		glyphRune = st.Failed.Render(theme.MarkFailed)
	case m.canceled:
		glyphRune = st.Amber.Render("⚠")
	case !m.running:
		glyphRune = st.OK.Render(theme.MarkOK)
	}

	left := m.statusLeft(st)
	right := m.statusRight(st, glyphRune)
	gap := max(width-lipgloss.Width(left)-lipgloss.Width(right)-1, 1)
	statusline := " " + left + strings.Repeat(" ", gap) + right

	return header + "\n" + rule + "\n" + m.content.render() + "\n\n" + statusline + "\n" + m.footer(st)
}

func (m Model) statusLeft(st theme.Styles) string {
	switch {
	case m.failed:
		return st.Failed.Render(theme.MarkFailed+" Failed") + st.Dim.Render(" · "+m.title)
	case m.canceled:
		return st.Amber.Render("⚠ Cancelled") + st.Dim.Render(" · "+m.title)
	case !m.running:
		return st.OK.Render(theme.MarkOK+" Completed") + st.Dim.Render(" · "+m.title)
	}
	if p := m.content.phase(); p != "" {
		return st.Title.Render(p) + st.Dim.Render(" "+theme.Pointer+" ") + m.content.task()
	}
	return st.Title.Render(strings.TrimSpace(m.title))
}

func (m Model) statusRight(st theme.Styles, glyphRune string) string {
	if stats, ok := m.content.stats(); ok {
		return fmt.Sprintf("%s  %s · %s · %s · %s", glyphRune,
			st.OK.Render(fmt.Sprintf("%d ok", stats.OK)),
			st.Changed.Render(fmt.Sprintf("%d changed", stats.Changed)),
			st.Failed.Render(fmt.Sprintf("%d failed", stats.Failed)),
			st.Dim.Render(m.elapsed()))
	}
	return glyphRune + "  " + st.Dim.Render(m.elapsed())
}

func (m Model) footer(st theme.Styles) string {
	switch {
	case m.failed:
		return st.Failed.Render(" ✗ run failed · l view log · r retry · esc back")
	case m.canceled:
		return st.Amber.Render(" ⚠ cancelled · l view log · r retry · esc back")
	case !m.running:
		return st.Dim.Render(" ✓ done · l view log · esc back")
	default:
		return st.Dim.Render(" ctrl+c cancel · ↑↓ scroll · type to answer prompts")
	}
}

func (m Model) elapsed() string {
	d := time.Since(m.start)
	return fmt.Sprintf("%02d:%02d", int(d.Minutes()), int(d.Seconds())%60)
}

func glyph(st theme.Styles, g feed.Glyph) string {
	switch g {
	case feed.GlyphOK:
		return st.OK.Render(theme.MarkOK)
	case feed.GlyphChanged:
		return st.Changed.Render(theme.MarkChanged)
	case feed.GlyphFailed:
		return st.Failed.Render(theme.MarkFailed)
	case feed.GlyphSkipped:
		return st.Skipped.Render(theme.MarkSkipped)
	default:
		return " "
	}
}

func waitOutput(h *runner.Handle, gen int) tea.Cmd {
	return func() tea.Msg {
		b, ok := <-h.Output
		if !ok {
			return closedMsg{}
		}
		return outMsg{gen: gen, b: b}
	}
}

func waitPrompt(h *runner.Handle, gen int) tea.Cmd {
	return func() tea.Msg {
		p, ok := <-h.Prompts
		if !ok {
			return promptsClosed{}
		}
		return promptMsg{gen: gen, text: p}
	}
}

func waitDone(h *runner.Handle, gen int) tea.Cmd {
	return func() tea.Msg { return doneMsg{gen: gen, res: <-h.Done} }
}
