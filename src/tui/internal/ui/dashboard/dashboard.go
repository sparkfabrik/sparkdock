// Package dashboard renders the hub home: a flat grouped list mirroring the
// menu bar (Status, Actions, Tools, Company). Status rows are informational;
// the cursor lands only on selectable actions. Status is read from an injected
// status.Checker and never recomputed here.
package dashboard

import (
	"context"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/audio"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/sysinfo"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/theme"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// StatusMsg carries a completed status check back into the model.
type StatusMsg []status.Subsystem

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

// StatusMsg / SysInfoMsg carry async results back into the model.
// (StatusMsg is declared above.)

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
	loading       bool
}

// New builds a dashboard bound to a status checker, a sysinfo gatherer, and
// version info.
func New(checker status.Checker, gatherer sysinfo.Gatherer, ver version.Info) Model {
	m := Model{checker: checker, gatherer: gatherer, ver: ver, loading: true}
	m.rebuild()
	return m
}

// Init triggers the first status load and system-info gather.
func (m Model) Init() tea.Cmd { return tea.Batch(m.refresh(), m.sysGather()) }

// SetSize updates render dimensions.
func (m *Model) SetSize(w, h int) { m.width, m.height = w, h }

func (m Model) refresh() tea.Cmd {
	checker := m.checker
	return func() tea.Msg {
		if checker == nil {
			return StatusMsg(nil)
		}
		return StatusMsg(checker.Check(context.Background()))
	}
}

func (m Model) sysGather() tea.Cmd {
	g := m.gatherer
	return func() tea.Msg {
		if g.Run == nil {
			return SysInfoMsg{}
		}
		return SysInfoMsg(g.Gather(context.Background()))
	}
}

// Update handles navigation, refresh, and incoming status.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case StatusMsg:
		m.subs = []status.Subsystem(msg)
		m.loading = false
		m.rebuild()
		return m, nil
	case SysInfoMsg:
		m.sys = sysinfo.Info(msg)
		m.sysReady = true
		return m, nil
	case tea.MouseMsg:
		// click the header logo (top row) to replay the sound
		if msg.Action == tea.MouseActionPress && msg.Y == 0 {
			audio.Play()
		}
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			m.move(-1)
		case "down", "j":
			m.move(1)
		case "r":
			m.loading = true
			return m, tea.Batch(m.refresh(), m.sysGather())
		case "d":
			return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, "device") }
		case "enter":
			if it := m.current(); it != nil {
				return m, func() tea.Msg { return ui.Navigate(ui.PageRunner, it.id) }
			}
		}
	}
	return m, nil
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
		statusItem(m.subByKey("skills"), "Agent skills"),
		{kind: kindRule},
	}
	if sd.Health == status.Stale {
		items = append(items, item{kind: kindAction, id: "self-update", label: "Update Sparkdock", detail: sd.Detail, selectable: true})
	}
	items = append(items,
		item{kind: kindAction, id: "provision", label: "Run full provisioning", selectable: true},
		item{kind: kindAction, id: "upgrade", label: "Upgrade Brew packages", detail: m.subByKey("brew").Detail, selectable: true},
		item{kind: kindAction, id: "sync", label: "Sync AI harness", selectable: true},
		item{kind: kindGroup, label: "HTTP proxy"},
		item{kind: kindAction, id: "proxy-status", label: "Status", selectable: true},
		item{kind: kindAction, id: "proxy-start", label: "Start", selectable: true},
		item{kind: kindAction, id: "proxy-stop", label: "Stop", selectable: true},
		item{kind: kindAction, id: "proxy-upgrade", label: "Upgrade", selectable: true},
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
	var lines []string
	if s.Model != "" {
		lines = append(lines, row("Model", s.Model))
	}
	if s.Serial != "" {
		lines = append(lines, row("Serial", s.Serial))
	}
	if chip != "" {
		lines = append(lines, row("Chip", chip))
	}
	if s.MemTotal > 0 {
		lines = append(lines, row("Memory", fmt.Sprintf("%s free / %s", gb(s.MemFree), gb(s.MemTotal))))
	}
	if s.DiskTotal > 0 {
		lines = append(lines, row("Disk", fmt.Sprintf("%s / %s free", gb(s.DiskFree), gb(s.DiskTotal))))
	}
	if s.OS != "" {
		lines = append(lines, row("macOS", s.OS))
	}
	return strings.Join(lines, "\n")
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

// View renders the dashboard.
func (m Model) View() string {
	st := theme.Default()
	width := m.width
	if width < 40 {
		width = 40
	}
	var b strings.Builder
	b.WriteString(" " + st.SparkS.Render(theme.Spark) + " " + st.Title.Render("sparkdock") +
		st.Dim.Render("   ·   dev environment manager") + "\n")
	b.WriteString(st.Dim.Render(strings.Repeat("─", width)) + "\n")

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
			line := "   " + st.Action.Render(theme.Pointer+" "+it.label)
			if i == m.cursor {
				line = "  " + st.Selected.Render(" "+theme.Pointer+" "+it.label+" ")
			}
			if it.detail != "" {
				line += "  " + st.Dim.Render(it.detail)
			}
			b.WriteString(line + "\n")
		}
	}
	flushCols()

	b.WriteString("\n" + st.Dim.Render(strings.Repeat("─", width)) + "\n")
	left := " " + st.SparkS.Render(theme.Spark) + " " + st.Dim.Render(m.ver.Short())
	if m.loading {
		left = " " + st.Amber.Render("◐") + " " + st.Dim.Render("refreshing…")
	}
	hint := func(k, label string) string { return st.SparkS.Render(k) + " " + st.Dim.Render(label) }
	sep := st.Dim.Render(" · ")
	keys := strings.Join([]string{
		hint("↑↓", "move"), hint("⏎", "select"), hint("r", "refresh"),
		hint("d", "device"), hint("q", "quit"),
	}, sep) + " "
	gap := max(width-lipgloss.Width(left)-lipgloss.Width(keys), 1)
	b.WriteString(left + strings.Repeat(" ", gap) + keys)
	return b.String()
}
