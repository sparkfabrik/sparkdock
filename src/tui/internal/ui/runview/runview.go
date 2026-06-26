// Package runview renders a running operation: a scrolling content region above
// a pinned, claude-code-style statusline (phase, task, ok/changed/failed,
// elapsed). It consumes a runner.Handle's event stream and supports cancel,
// retry, and opening the captured output. Run orchestration (which playbook,
// which tags, the become password) lives in the app; this page only renders and
// controls a run it is handed.
package runview

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
)

// Messages flowing through the bubbletea loop while a run is live.
type (
	eventMsg  feed.Event
	closedMsg struct{}
	doneMsg   runner.Result
)

// OpenLogMsg asks the app to open the captured output in the log page.
type OpenLogMsg struct {
	Title string
	Lines []string
}

// RetryMsg asks the app to re-run the last action.
type RetryMsg struct{}

// Model is the runner page.
type Model struct {
	width, height int

	rnr    *runner.Runner
	handle *runner.Handle

	vp    viewport.Model
	sp    spinner.Model
	title string
	start time.Time

	phase string
	task  string
	stats feed.Stats

	lines []string // rendered content
	raw   []string // verbatim output for the copyable log

	running  bool
	failed   bool
	canceled bool
}

// New returns a runner page bound to a runner backend.
func New(rnr *runner.Runner) Model {
	sp := spinner.New()
	sp.Spinner = spinner.Dot
	sp.Style = lipgloss.NewStyle().Foreground(theme.Accent)
	return Model{rnr: rnr, sp: sp}
}

// SetSize updates dimensions and the viewport.
func (m *Model) SetSize(w, h int) {
	m.width, m.height = w, h
	m.vp.Width = w
	m.vp.Height = max(h-4, 1) // header, rule, statusline, footer
}

// Start launches a run described by opts under the given title. If a previous
// run is somehow still live, it is cancelled first so its goroutine cannot leak
// or bleed events into the new run.
func (m Model) Start(title string, opts runner.Options) (Model, tea.Cmd) {
	if m.handle != nil && m.running {
		m.handle.Cancel()
	}
	m.title = title
	m.running, m.failed, m.canceled = true, false, false
	m.phase, m.task = "starting", "…"
	m.stats = feed.Stats{}
	m.lines, m.raw = nil, nil
	m.start = time.Now()
	m.vp = viewport.New(m.width, max(m.height-4, 1))

	m.handle = m.rnr.Start(context.Background(), opts)
	return m, tea.Batch(waitEvent(m.handle), waitDone(m.handle), m.sp.Tick)
}

// Update advances the run; returns true from handled when it consumed the msg.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.sp, cmd = m.sp.Update(msg)
		return m, cmd

	case eventMsg:
		m.apply(feed.Event(msg))
		m.vp.SetContent(strings.Join(m.lines, "\n"))
		m.vp.GotoBottom()
		return m, waitEvent(m.handle)

	case closedMsg:
		return m, nil

	case doneMsg:
		m.finish(runner.Result(msg))
		m.vp.SetContent(strings.Join(m.lines, "\n"))
		m.vp.GotoBottom()
		return m, nil

	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (Model, tea.Cmd) {
	switch msg.String() {
	case "ctrl+c":
		if m.running && m.handle != nil {
			m.handle.Cancel()
		}
		return m, nil
	case "r":
		if !m.running {
			return m, func() tea.Msg { return RetryMsg{} }
		}
	case "l":
		if len(m.raw) > 0 {
			lines := append([]string(nil), m.raw...)
			return m, func() tea.Msg { return OpenLogMsg{Title: m.title, Lines: lines} }
		}
	case "up", "k":
		m.vp.ScrollUp(1)
	case "down", "j":
		m.vp.ScrollDown(1)
	}
	return m, nil
}

// Running reports whether a run is in progress (the app uses it to gate "back").
func (m Model) Running() bool { return m.running }

func (m *Model) apply(e feed.Event) {
	if !e.IsControl() {
		m.raw = append(m.raw, e.Raw)
	}
	st := theme.Default()
	switch e.Kind {
	case feed.KindPhase:
		m.phase = e.Text
		m.lines = append(m.lines, st.Title.Render(theme.PhaseArrow+" "+e.Text))
	case feed.KindTask:
		m.task = e.Text
	case feed.KindStat:
		m.stats = e.Stats
	case feed.KindResult:
		m.lines = append(m.lines, "  "+glyph(st, e.Glyph)+" "+e.Text)
	case feed.KindPlain:
		m.lines = append(m.lines, "  "+e.Text)
	}
}

func (m *Model) finish(res runner.Result) {
	m.running = false
	m.canceled = res.Canceled
	m.failed = !res.Canceled && (res.Err != nil || m.stats.Failed > 0)
	st := theme.Default()
	switch {
	case m.canceled:
		m.task = "cancelled"
		m.lines = append(m.lines, "", st.Amber.Render("⚠ cancelled by user"))
	case m.failed:
		m.task = "failed"
		detail := ""
		if res.Err != nil {
			detail = " (" + res.Err.Error() + ")"
		}
		m.lines = append(m.lines, "", st.Failed.Render("✗ run failed")+detail)
	default:
		m.task = "complete"
		m.lines = append(m.lines, "", lipgloss.NewStyle().Bold(true).Render("Summary")+m.summary())
	}
}

func (m Model) summary() string {
	return fmt.Sprintf("  %d ok · %d changed · %d failed · %d skipped",
		m.stats.OK, m.stats.Changed, m.stats.Failed, m.stats.Skipped)
}

// View renders header, scrolling region, pinned statusline, and footer.
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
	left := st.Title.Render(m.phase) + st.Dim.Render(" "+theme.Pointer+" ") + m.task
	right := fmt.Sprintf("%s  %s · %s · %s · %s", glyphRune,
		st.OK.Render(fmt.Sprintf("%d ok", m.stats.OK)),
		st.Changed.Render(fmt.Sprintf("%d changed", m.stats.Changed)),
		st.Failed.Render(fmt.Sprintf("%d failed", m.stats.Failed)),
		st.Dim.Render(m.elapsed()))
	gap := max(width-lipgloss.Width(left)-lipgloss.Width(right)-1, 1)
	statusline := " " + left + strings.Repeat(" ", gap) + right

	return header + "\n" + rule + "\n" + m.vp.View() + "\n" + statusline + "\n" + m.footer(st)
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
		return st.Dim.Render(" ctrl+c cancel · ↑↓ scroll")
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

func waitEvent(h *runner.Handle) tea.Cmd {
	return func() tea.Msg {
		e, ok := <-h.Events
		if !ok {
			return closedMsg{}
		}
		return eventMsg(e)
	}
}

func waitDone(h *runner.Handle) tea.Cmd {
	return func() tea.Msg { return doneMsg(<-h.Done) }
}
