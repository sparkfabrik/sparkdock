// Package dashboard renders the hub home: a flat grouped list mirroring the
// menu bar (Status, Actions, Tools, Company). Status rows are informational;
// the cursor lands only on selectable actions. Status is read from an injected
// status.Checker and never recomputed here.
package dashboard

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/sysinfo"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// SubsystemMsg carries one completed subsystem check; rows stream in as each
// check finishes instead of waiting for the slowest one.
type SubsystemMsg status.Subsystem

// checkTimeout bounds one subsystem check or system-info gather, so a hung
// command (network-stuck brew) can't pin a row on "…" forever.
const checkTimeout = 60 * time.Second

type itemKind int

const (
	kindStatus itemKind = iota
	kindRule
	kindGroup
	kindAction
)

type item struct {
	kind       itemKind
	id         string
	label      string
	detail     string
	health     status.Health
	selectable bool
}

// SysInfoMsg carries a completed system-info gather.
type SysInfoMsg sysinfo.Info

// Model is the dashboard page.
type Model struct {
	width, height int
	checker       status.Checker
	gatherer      sysinfo.Gatherer
	ver           version.Info
	subs          []status.Subsystem
	sys           sysinfo.Info
	sysReady      bool
	items         []item
	cursor        int
	restartHint   bool

	awaiting  map[string]bool // subsystem keys still being checked this round
	checkedAt time.Time       // when the last round completed, for the age hint
	now       func() time.Time

	showHelp bool
}

// loading reports whether a check round is still in flight; it is fully
// derived from the awaiting set.
func (m Model) loading() bool { return len(m.awaiting) > 0 }

// WithRestartHint marks that the running binary was updated, so the dashboard
// shows a relaunch notice until the user quits.
func (m Model) WithRestartHint() Model {
	m.restartHint = true
	return m
}

// New builds a dashboard bound to a status checker, a sysinfo gatherer, and
// version info.
func New(checker status.Checker, gatherer sysinfo.Gatherer, ver version.Info) Model {
	m := Model{checker: checker, gatherer: gatherer, ver: ver, now: time.Now}
	m.awaiting = m.allKeys()
	m.rebuild()
	return m
}

// Init triggers the first status load and system-info gather (New already
// marked every subsystem as awaiting).
func (m Model) Init() tea.Cmd { return tea.Batch(m.refresh(), m.sysGather()) }

// Refresh starts a new round of checks. Existing rows stay visible (with the
// refreshing indicator) and update in place as fresh results stream in.
func (m Model) Refresh() (Model, tea.Cmd) {
	m.awaiting = m.allKeys()
	return m, tea.Batch(m.refresh(), m.sysGather())
}

// Ready reports whether the current round of checks has fully landed.
func (m Model) Ready() bool { return !m.loading() }

// SetSize updates render dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

func (m Model) allKeys() map[string]bool {
	keys := map[string]bool{}
	if m.checker != nil {
		for _, k := range m.checker.Subsystems() {
			keys[k] = true
		}
	}
	return keys
}

// refresh fans out one command per subsystem so each row lands as soon as its
// check completes; with no checker there is nothing to fan out and the round
// is trivially complete.
func (m Model) refresh() tea.Cmd {
	checker := m.checker
	if checker == nil {
		return nil
	}
	keys := checker.Subsystems()
	cmds := make([]tea.Cmd, 0, len(keys))
	for _, key := range keys {
		cmds = append(cmds, func() tea.Msg {
			ctx, cancel := context.WithTimeout(context.Background(), checkTimeout)
			defer cancel()
			return SubsystemMsg(checker.CheckOne(ctx, key))
		})
	}
	return tea.Batch(cmds...)
}

func (m Model) sysGather() tea.Cmd {
	g := m.gatherer
	return func() tea.Msg {
		if g.Run == nil {
			return SysInfoMsg{}
		}
		ctx, cancel := context.WithTimeout(context.Background(), checkTimeout)
		defer cancel()
		return SysInfoMsg(g.Gather(ctx))
	}
}

// Update handles navigation, refresh, and incoming status.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case SubsystemMsg:
		m.upsert(status.Subsystem(msg))
		delete(m.awaiting, msg.Key)
		if len(m.awaiting) == 0 {
			m.stampRound()
		}
		m.rebuild()
		return m, nil
	case SysInfoMsg:
		m.sys = sysinfo.Info(msg)
		m.sysReady = true
		return m, nil
	case tea.KeyMsg:
		if m.showHelp {
			switch msg.String() {
			case "?", "esc", "q", "enter":
				m.showHelp = false
			}
			return m, nil
		}
		switch msg.String() {
		case "up", "k":
			m.move(-1)
		case "down", "j":
			m.move(1)
		case "r":
			return m.Refresh()
		case "d":
			return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, "device") }
		case "D":
			return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, "doctor") }
		case "s":
			return m, func() tea.Msg { return ui.Navigate(ui.PageRecipes, "") }
		case "?":
			m.showHelp = true
		case "enter":
			if it := m.current(); it != nil {
				if it.id == "recipes" {
					return m, func() tea.Msg { return ui.Navigate(ui.PageRecipes, "") }
				}
				return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, it.id) }
			}
		}
	}
	return m, nil
}

// HelpOpen reports whether the help overlay is showing, so the app can keep
// global keys (like q-to-quit) from stealing the overlay's dismiss keys.
func (m Model) HelpOpen() bool { return m.showHelp }

// stampRound records when the check round completed, for the age hint.
func (m *Model) stampRound() { m.checkedAt = m.now() }

// upsert replaces the subsystem with the same key, or appends a new row.
func (m *Model) upsert(s status.Subsystem) {
	for i := range m.subs {
		if m.subs[i].Key == s.Key {
			m.subs[i] = s
			return
		}
	}
	m.subs = append(m.subs, s)
}

func (m *Model) move(d int) {
	i := m.cursor
	for {
		i += d
		if i < 0 || i >= len(m.items) {
			return
		}
		if m.items[i].selectable {
			m.cursor = i
			return
		}
	}
}

func (m Model) current() *item {
	if m.cursor >= 0 && m.cursor < len(m.items) && m.items[m.cursor].selectable {
		it := m.items[m.cursor]
		return &it
	}
	return nil
}

// subByKey returns the checked subsystem for key, or a zero value.
func (m Model) subByKey(key string) status.Subsystem {
	for _, s := range m.subs {
		if s.Key == key {
			return s
		}
	}
	return status.Subsystem{Key: key, Health: status.Unknown, Detail: "…"}
}

func (m *Model) rebuild() {
	sd := m.subByKey("sparkdock")
	sdDetail := sd.Detail
	if sd.Health == status.OK && m.ver.Configured {
		sdDetail = "up to date · " + m.ver.Short()
	}
	items := []item{
		{kind: kindStatus, id: "sparkdock", label: "Sparkdock", detail: sdDetail, health: sd.Health},
		statusItem(m.subByKey("brew"), "Brew packages"),
		statusItem(m.subByKey("http-proxy"), "HTTP proxy"),
		statusItem(m.subByKey("skills"), "AI harness"),
		statusItem(m.subByKey("doctor"), "macOS doctor"),
		{kind: kindRule},
	}
	// When sparkdock itself is stale, the amber status dot on the Sparkdock row
	// already signals it; the self-update action is not wired yet, so no button
	// is shown rather than a dead one. Run `sparkdock` to self-update.
	// Action details show the equivalent shell command (the "$ " prompt signals
	// it is the CLI this action runs), so the TUI teaches the underlying command.
	// Live status (outdated counts, health) stays on the status rows above.
	items = append(items,
		item{kind: kindAction, id: "provision", label: "Update everything", detail: "$ sparkdock", selectable: true},
		item{kind: kindAction, id: "upgrade", label: "Upgrade Brew packages", detail: "$ brew upgrade", selectable: true},
		item{kind: kindAction, id: "sync", label: "Sync AI harness", detail: "$ sjust sf-harness-sync", selectable: true},
		item{kind: kindAction, id: "recipes", label: "Browse sjust recipes", detail: "$ sjust --list", selectable: true},
		item{kind: kindGroup, label: "HTTP proxy"},
		item{kind: kindAction, id: "proxy-status", label: "Check status", detail: "$ spark-http-proxy status", selectable: true},
		item{kind: kindAction, id: "proxy-start", label: "Start", detail: "$ spark-http-proxy start", selectable: true},
		item{kind: kindAction, id: "proxy-stop", label: "Stop", detail: "$ spark-http-proxy stop", selectable: true},
		item{kind: kindAction, id: "proxy-upgrade", label: "Upgrade", detail: "$ sjust http-proxy-install-update", selectable: true},
		item{kind: kindGroup, label: "macOS doctor"},
		item{kind: kindAction, id: "doctor", label: "Run diagnostics", detail: "$ sjust macos-doctor", selectable: true},
	)
	m.items = items
	if m.current() == nil {
		m.cursor = m.firstSelectable()
	}
}

func statusItem(s status.Subsystem, name string) item {
	return item{kind: kindStatus, id: s.Key, label: name, detail: s.Detail, health: s.Health}
}

func (m Model) firstSelectable() int {
	for i, it := range m.items {
		if it.selectable {
			return i
		}
	}
	return 0
}

func dot(st theme.Styles, h status.Health) string {
	switch h {
	case status.OK:
		return st.OK.Render(theme.DotOK)
	case status.Stale:
		return st.Amber.Render(theme.DotStale)
	case status.Unconfigured:
		return st.Dim.Render(theme.DotUnknown)
	default:
		return st.Dim.Render(theme.DotUnknown)
	}
}

// sysInfoBlock renders the right-hand system-info panel, or "" until the first
// gather completes.
func (m Model) sysInfoBlock(st theme.Styles) string {
	if !m.sysReady {
		return ""
	}
	s := m.sys
	row := func(label, value string) string {
		return st.Dim.Render(fmt.Sprintf("%-7s", label)) + " " + value
	}
	chip := s.Chip
	if s.Cores > 0 {
		chip += fmt.Sprintf(" · %d-core CPU", s.Cores)
	}
	if s.GPUCores > 0 {
		chip += fmt.Sprintf(" · %d-core GPU", s.GPUCores)
	}
	// model, serial, and macOS version on one line
	ident := s.Model
	if s.Serial != "" {
		ident = strings.TrimSpace(ident + " · " + s.Serial)
	}
	if s.OS != "" {
		ident = strings.TrimSpace(ident + " · macOS " + s.OS)
	}
	var lines []string
	if ident != "" {
		lines = append(lines, row("Model", ident))
	}
	if chip != "" {
		lines = append(lines, row("Chip", chip))
	}
	if s.MemTotal > 0 {
		mem := fmt.Sprintf("%s free / %s", gb(s.MemFree), gb(s.MemTotal))
		if s.MemCached > 0 {
			mem = fmt.Sprintf("%s free · %s cached / %s", gb(s.MemFree), gb(s.MemCached), gb(s.MemTotal))
		}
		lines = append(lines, row("Memory", mem))
	}
	if s.DiskTotal > 0 {
		lines = append(lines, row("Disk", fmt.Sprintf("%s free / %s", gb(s.DiskFree), gb(s.DiskTotal))))
	}
	return strings.Join(lines, "\n")
}

// checkedAgo formats the age of the last completed check round for the footer,
// or "" before the first round completes.
func (m Model) checkedAgo() string {
	if m.checkedAt.IsZero() {
		return ""
	}
	d := m.now().Sub(m.checkedAt)
	switch {
	case d < time.Minute:
		return " · checked just now"
	case d < time.Hour:
		return fmt.Sprintf(" · checked %dm ago", int(d.Minutes()))
	default:
		return fmt.Sprintf(" · checked %dh ago", int(d.Hours()))
	}
}

// gb formats a byte count as whole gigabytes.
func gb(bytes uint64) string {
	return fmt.Sprintf("%.0f GB", float64(bytes)/(1<<30))
}

// truncateBlock clips every line of a multi-line block to width cells
// (ANSI-aware), so the right column can never overflow into the left.
func truncateBlock(block string, width int) string {
	lines := strings.Split(block, "\n")
	for i, l := range lines {
		lines[i] = ansi.Truncate(l, width, "")
	}
	return strings.Join(lines, "\n")
}

// helpView renders the key-reference overlay page.
func (m Model) helpView(st theme.Styles, width int) string {
	row := func(key, what string) string {
		return "   " + st.SparkS.Render(fmt.Sprintf("%-7s", key)) + " " + st.Dim.Render(what)
	}
	sections := []string{
		" " + st.Title.Render("keys") + st.Dim.Render("   ·   ? or esc to close"),
		st.Dim.Render(strings.Repeat("─", width)),
		"",
		"  " + st.Group.Render("Dashboard"),
		row("↑↓ j k", "move between actions"),
		row("⏎", "run the selected action"),
		row("r", "refresh status"),
		row("s", "browse and run sjust recipes"),
		row("d", "device info"),
		row("D", "run macOS doctor"),
		row("?", "this help"),
		row("q", "quit"),
		"",
		"  " + st.Group.Render("While a run is live"),
		row("ctrl+c", "cancel the run"),
		row("↑↓", "scroll output"),
		row("type", "answer the program's prompts (y/n, …)"),
		"",
		"  " + st.Group.Render("After a run"),
		row("l", "open the full log (y copies it)"),
		row("r", "retry"),
		row("esc", "back to the dashboard"),
	}
	return strings.Join(sections, "\n")
}

// View renders the dashboard.
func (m Model) View() string {
	st := theme.Default()
	width := m.width
	if width < 40 {
		width = 40
	}
	if m.showHelp {
		return m.helpView(st, width)
	}
	var b strings.Builder
	b.WriteString(" " + st.SparkS.Render(theme.Spark) + " " + st.Title.Render("sparkdock") +
		" " + st.Amber.Render("beta") +
		st.Dim.Render("   ·   dev environment manager") + "\n")
	b.WriteString(st.Dim.Render(strings.Repeat("─", width)) + "\n")
	if m.restartHint {
		b.WriteString(" " + st.Amber.Render("↻ sparkdock-tui was updated — quit (q) and run `sparkdock tui` again to load the new version") + "\n")
	}

	// Status rows form the left column; the system-info block sits on the right.
	var statusRows []string
	colsFlushed := false
	flushCols := func() {
		if colsFlushed {
			return
		}
		colsFlushed = true
		left := strings.Join(statusRows, "\n")
		right := m.sysInfoBlock(st)
		const gapW = 5
		budget := width - lipgloss.Width(left) - gapW
		if right != "" && budget >= 24 {
			right = truncateBlock(right, budget)
			b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, left, strings.Repeat(" ", gapW), right) + "\n")
		} else {
			b.WriteString(left + "\n")
		}
	}

	for i, it := range m.items {
		switch it.kind {
		case kindStatus:
			statusRows = append(statusRows, fmt.Sprintf("  %s  %-16s %s", dot(st, it.health), it.label, st.Dim.Render(it.detail)))
		case kindRule:
			flushCols()
			b.WriteString("  " + st.Dim.Render(strings.Repeat("─", max(width-4, 30))) + "\n")
		case kindGroup:
			flushCols()
			b.WriteString("\n  " + st.Group.Render(it.label) + "\n")
		case kindAction:
			flushCols()
			b.WriteString(theme.ActionRow(st, i == m.cursor, it.label, it.detail) + "\n")
		}
	}
	flushCols()

	b.WriteString("\n" + st.Dim.Render(strings.Repeat("─", width)) + "\n")
	left := " " + st.SparkS.Render(theme.Spark) + " " + st.Dim.Render(m.ver.Short()+m.checkedAgo())
	if m.loading() {
		left = " " + st.Amber.Render(theme.DotStale) + " " + st.Dim.Render("refreshing…")
	}
	hint := func(k, label string) string { return st.SparkS.Render(k) + " " + st.Dim.Render(label) }
	sep := st.Dim.Render(" · ")
	keys := strings.Join([]string{
		hint("↑↓", "move"), hint("⏎", "select"), hint("r", "refresh"),
		hint("s", "recipes"), hint("d", "device"), hint("D", "doctor"),
		hint("?", "help"), hint("q", "quit"),
	}, sep) + " "
	gap := max(width-lipgloss.Width(left)-lipgloss.Width(keys), 1)
	b.WriteString(left + strings.Repeat(" ", gap) + keys)
	return b.String()
}
