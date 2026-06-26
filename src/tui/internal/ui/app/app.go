// Package app is the root bubbletea model. It owns the page router: it holds
// each page's sub-model, broadcasts size changes, routes input to the active
// page, and switches pages on NavigateMsg. Pages stay decoupled, communicating
// only through ui messages.
package app

import (
	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/dashboard"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/splash"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// Model is the root application model.
type Model struct {
	page      ui.PageID
	width     int
	height    int
	splash    splash.Model
	dashboard dashboard.Model
}

// New builds the root model wired to version info and a status checker.
func New(ver version.Info, checker status.Checker) Model {
	return Model{
		page:      ui.PageSplash,
		splash:    splash.New(ver),
		dashboard: dashboard.New(checker, ver),
	}
}

// Init starts the splash timer and the dashboard's first status load.
func (m Model) Init() tea.Cmd {
	return tea.Batch(m.splash.Init(), m.dashboard.Init())
}

// Update routes messages to the active page and handles global concerns.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.splash.SetSize(msg.Width, msg.Height)
		m.dashboard.SetSize(msg.Width, msg.Height)
		return m, nil

	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
		if m.page == ui.PageDashboard && msg.String() == "q" {
			return m, tea.Quit
		}

	case splash.DismissMsg:
		if m.page == ui.PageSplash {
			m.page = ui.PageDashboard
		}
		return m, nil

	case ui.NavigateMsg:
		// Pages beyond the dashboard are added incrementally; unknown targets
		// are ignored so navigation never crashes during the build-out.
		switch msg.To {
		case ui.PageSplash, ui.PageDashboard:
			m.page = msg.To
		}
		return m, nil
	}

	return m.routeToPage(msg)
}

// routeToPage forwards a message to the active page's Update.
func (m Model) routeToPage(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch m.page {
	case ui.PageSplash:
		m.splash, cmd = m.splash.Update(msg)
	case ui.PageDashboard:
		m.dashboard, cmd = m.dashboard.Update(msg)
	}
	return m, cmd
}

// View renders the active page.
func (m Model) View() string {
	switch m.page {
	case ui.PageSplash:
		return m.splash.View()
	default:
		return m.dashboard.View()
	}
}
