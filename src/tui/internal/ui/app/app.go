// Package app is the root bubbletea model and page router. It owns each page's
// sub-model, broadcasts size changes, routes input to the active page, switches
// pages on navigation messages, and orchestrates runs: it builds the
// runner.Handle for each action, gates sudo actions behind the password page,
// caches the become password in memory for the session, and re-prompts on a
// sudo authentication failure.
package app

import (
	"context"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/dashboard"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/logview"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/password"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/runview"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/sjust"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/splash"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// Config locates the sparkdock install used to build run commands.
type Config struct {
	Root string // e.g. /opt/sparkdock
}

// runSpec fully describes a run the app can start (and retry).
type runSpec struct {
	title string
	rnr   *runner.Runner
	opts  runner.Options
	sudo  bool
}

// Model is the root application model.
type Model struct {
	cfg    Config
	page   ui.PageID
	width  int
	height int

	splash    splash.Model
	dashboard dashboard.Model
	runview   runview.Model
	password  password.Model
	logview   logview.Model
	sjust     sjust.Model

	ansible *runner.Runner

	become        string  // session-scoped, in memory only
	pendingAction string  // action awaiting a password
	last          runSpec // last started run, for retry
	hasLast       bool
}

// New builds the root model wired to its dependencies.
func New(cfg Config, ver version.Info, checker status.Checker) Model {
	return Model{
		cfg:       cfg,
		page:      ui.PageSplash,
		splash:    splash.New(ver),
		dashboard: dashboard.New(checker, ver),
		runview:   runview.New(),
		password:  password.New(),
		logview:   logview.New(),
		sjust:     sjust.New(sjust.DefaultLister),
		ansible:   runner.New(),
	}
}

// Init starts the splash timer and the dashboard's first status load.
func (m Model) Init() tea.Cmd {
	return tea.Batch(m.splash.Init(), m.dashboard.Init())
}

// Update routes messages and orchestrates runs.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.setSize(msg.Width, msg.Height)
		return m, nil

	case tea.KeyMsg:
		// ctrl+c cancels a live run; otherwise quits.
		if msg.String() == "ctrl+c" {
			if m.page == ui.PageRunner && m.runview.Running() {
				return m.route(msg)
			}
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

	case dashboard.StatusMsg:
		// Status can land while another page is active; always feed the dashboard.
		var cmd tea.Cmd
		m.dashboard, cmd = m.dashboard.Update(msg)
		return m, cmd

	case ui.NavigateMsg:
		return m.navigate(msg)

	case password.SubmitMsg:
		m.become = msg.Password
		return m.launch(m.pendingAction)

	case password.CancelMsg:
		m.page = ui.PageDashboard
		return m, nil

	case runview.RetryMsg:
		if m.hasLast {
			return m.start(m.last)
		}
		return m, nil

	case runview.OpenLogMsg:
		m.logview.Open(msg.Title, msg.Lines)
		m.page = ui.PageLog
		return m, nil

	case runview.BecomeFailedMsg:
		m.become = ""
		cmd := m.password.Prompt(m.last.title, "Incorrect password, try again")
		m.page = ui.PagePassword
		return m, cmd

	case runview.BackMsg:
		m.page = ui.PageDashboard
		return m, m.dashboard.Init() // refresh status after a run

	case logview.BackMsg:
		m.page = ui.PageRunner
		return m, nil

	case sjust.RunMsg:
		spec := runSpec{
			title: "sjust ▸ " + msg.Recipe,
			rnr:   runner.ForCommand("sjust", msg.Recipe),
		}
		return m.start(spec)

	case sjust.BackMsg:
		m.page = ui.PageDashboard
		return m, nil
	}

	return m.route(msg)
}

// navigate handles a page switch requested by a page.
func (m Model) navigate(msg ui.NavigateMsg) (tea.Model, tea.Cmd) {
	switch msg.To {
	case ui.PageSjust:
		m.page = ui.PageSjust
		return m, m.sjust.Init()
	case ui.PageRunner:
		// The dashboard routes every action here; the app decides what to do.
		if msg.Action == "sjust" {
			m.page = ui.PageSjust
			return m, m.sjust.Init()
		}
		return m.launch(msg.Action)
	default:
		m.page = msg.To
	}
	return m, nil
}

// launch resolves an action to a run, gating sudo actions behind the password.
func (m Model) launch(action string) (tea.Model, tea.Cmd) {
	spec, ok := m.planFor(action)
	if !ok {
		m.page = ui.PageDashboard // unhandled action: stay home
		return m, nil
	}
	// Track the action so a become re-prompt re-launches the right one, even
	// when the password was already cached and the prompt was skipped.
	m.pendingAction = action
	if spec.sudo && m.become == "" {
		cmd := m.password.Prompt(spec.title, "")
		m.page = ui.PagePassword
		return m, cmd
	}
	return m.start(spec)
}

// start launches the run described by spec and shows the runner page.
func (m Model) start(spec runSpec) (tea.Model, tea.Cmd) {
	spec.opts.BecomePass = m.become // always use the current password
	handle := spec.rnr.Start(context.Background(), spec.opts)
	var cmd tea.Cmd
	m.runview, cmd = m.runview.Start(spec.title, handle)
	m.last, m.hasLast = spec, true
	m.page = ui.PageRunner
	return m, cmd
}

// planFor maps a dashboard action id to a run spec. Returns ok=false for
// actions not yet wired (proxy, device, company links, self-update).
func (m Model) planFor(action string) (runSpec, bool) {
	ansibleOpts := func(tags ...string) runner.Options {
		return runner.Options{
			Dir:               m.cfg.Root,
			Playbook:          "ansible/macos.yml",
			Inventory:         "ansible/inventory.ini",
			CallbackPluginDir: "ansible/callback_plugins",
			Tags:              tags,
		}
	}
	switch action {
	case "provision":
		return runSpec{title: "Running full provisioning", rnr: m.ansible, opts: ansibleOpts(), sudo: true}, true
	case "upgrade":
		// A plain `brew upgrade`, not a provisioning run.
		return runSpec{title: "Upgrading Brew packages", rnr: runner.ForCommand("brew", "upgrade")}, true
	case "sync":
		return runSpec{title: "Syncing AI harness", rnr: m.ansible, opts: ansibleOpts("ai-harness-sync"), sudo: false}, true
	default:
		return runSpec{}, false
	}
}

func (m *Model) setSize(w, h int) {
	m.width, m.height = w, h
	m.splash.SetSize(w, h)
	m.dashboard.SetSize(w, h)
	m.runview.SetSize(w, h)
	m.password.SetSize(w, h)
	m.logview.SetSize(w, h)
	m.sjust.SetSize(w, h)
}

// route forwards a message to the active page.
func (m Model) route(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch m.page {
	case ui.PageSplash:
		m.splash, cmd = m.splash.Update(msg)
	case ui.PageDashboard:
		m.dashboard, cmd = m.dashboard.Update(msg)
	case ui.PageRunner:
		m.runview, cmd = m.runview.Update(msg)
	case ui.PagePassword:
		m.password, cmd = m.password.Update(msg)
	case ui.PageLog:
		m.logview, cmd = m.logview.Update(msg)
	case ui.PageSjust:
		m.sjust, cmd = m.sjust.Update(msg)
	}
	return m, cmd
}

// View renders the active page.
func (m Model) View() string {
	switch m.page {
	case ui.PageSplash:
		return m.splash.View()
	case ui.PageRunner:
		return m.runview.View()
	case ui.PagePassword:
		return m.password.View()
	case ui.PageLog:
		return m.logview.View()
	case ui.PageSjust:
		return m.sjust.View()
	default:
		return m.dashboard.View()
	}
}
