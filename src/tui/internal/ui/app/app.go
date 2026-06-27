// Package app is the root bubbletea model and page router. It owns each page's
// sub-model, broadcasts size changes, routes input to the active page, switches
// pages on navigation messages, and orchestrates runs.
//
// Sudo is handled reactively: a run starts immediately, and when the underlying
// process asks for a password (detected via the PTY), the app shows the password
// page and writes the answer back to the process. The password is never cached,
// stored, or placed in argv/env.
package app

import (
	"context"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/runner"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/sysinfo"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/dashboard"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/logview"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/password"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/runview"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/splash"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

// Config locates the sparkdock install used to build run commands.
type Config struct {
	Root string // e.g. /opt/sparkdock
}

// Deps are the injected backends the app wires into its pages.
type Deps struct {
	Checker  status.Checker
	Gatherer sysinfo.Gatherer
}

// runSpec describes a run the app can start (and retry).
type runSpec struct {
	title string
	rnr   *runner.Runner
	opts  runner.Options
	sudo  bool // ansible runs only: add --ask-become-pass so ansible prompts
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

	ansible *runner.Runner

	last    runSpec // last started run, for retry / re-prompt
	hasLast bool

	// splash dismissal: hand off to the dashboard once status is loaded and the
	// minimum splash time has passed.
	statusReady bool
	splashMin   bool
}

// New builds the root model wired to its dependencies.
func New(cfg Config, ver version.Info, deps Deps) Model {
	return Model{
		cfg:       cfg,
		page:      ui.PageSplash,
		splash:    splash.New(ver),
		dashboard: dashboard.New(deps.Checker, deps.Gatherer, ver),
		runview:   runview.New(),
		password:  password.New(),
		logview:   logview.New(),
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
		if msg.String() == "ctrl+c" {
			if m.page == ui.PageRunner && m.runview.Running() {
				return m.route(msg)
			}
			return m, tea.Quit
		}
		if m.page == ui.PageDashboard && msg.String() == "q" {
			return m, tea.Quit
		}

	case splash.MinElapsedMsg:
		m.splashMin = true
		m.dismissSplashIfReady()
		return m, nil

	case splash.TimeoutMsg:
		if m.page == ui.PageSplash {
			m.page = ui.PageDashboard // never trap the user on a slow status load
		}
		return m, nil

	case dashboard.StatusMsg:
		var cmd tea.Cmd
		m.dashboard, cmd = m.dashboard.Update(msg)
		m.statusReady = true // status loaded in the background during the splash
		m.dismissSplashIfReady()
		return m, cmd

	case ui.NavigateMsg:
		return m.navigate(msg)

	case runview.PromptMsg:
		// The run is asking for a password; collect it on the password page.
		title := "This operation"
		if m.hasLast {
			title = m.last.title
		}
		cmd := m.password.Prompt(title, "")
		m.page = ui.PagePassword
		return m, cmd

	case password.SubmitMsg:
		m.runview.AnswerPrompt(msg.Password)
		m.page = ui.PageRunner
		return m, nil

	case password.CancelMsg:
		m.runview.CancelRun()
		m.page = ui.PageRunner
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

	case runview.BackMsg:
		m.page = ui.PageDashboard
		return m, m.dashboard.Init() // refresh status after a run

	case logview.BackMsg:
		m.page = ui.PageRunner
		return m, nil
	}

	return m.route(msg)
}

func (m Model) navigate(msg ui.NavigateMsg) (tea.Model, tea.Cmd) {
	switch msg.To {
	case ui.PageRunner:
		return m.launch(msg.Action)
	default:
		m.page = msg.To
	}
	return m, nil
}

// launch resolves an action to a run and starts it immediately; any password is
// requested reactively once the process prompts for it.
func (m Model) launch(action string) (tea.Model, tea.Cmd) {
	spec, ok := m.planFor(action)
	if !ok {
		m.page = ui.PageDashboard // unhandled action: stay home
		return m, nil
	}
	return m.start(spec)
}

func (m Model) start(spec runSpec) (tea.Model, tea.Cmd) {
	if spec.sudo {
		spec.opts.Sudo = true
	}
	// Size the child's PTY to the runner view's content area (lines are indented
	// by two columns, so leave room for that).
	spec.opts.PtyCols = max(m.width-2, 20)
	spec.opts.PtyRows = max(m.height-5, 10)
	handle := spec.rnr.Start(context.Background(), spec.opts)
	var cmd tea.Cmd
	m.runview, cmd = m.runview.Start(spec.title, handle)
	m.last, m.hasLast = spec, true
	m.page = ui.PageRunner
	return m, cmd
}

// planFor maps a dashboard action id to a run spec. Returns ok=false for
// actions not yet wired (Company links, self-update).
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
		// brew casks may invoke sudo; prime it once up front.
		return runSpec{title: "Upgrading Brew packages", rnr: runner.ForSudoCommand("brew", "upgrade")}, true
	case "sync":
		return runSpec{title: "Syncing AI harness", rnr: m.ansible, opts: ansibleOpts("ai-harness-sync")}, true
	case "proxy-status":
		return runSpec{title: "HTTP proxy · status", rnr: runner.ForCommand("spark-http-proxy", "status")}, true
	case "proxy-start":
		return runSpec{title: "HTTP proxy · start", rnr: runner.ForCommand("spark-http-proxy", "start")}, true
	case "proxy-stop":
		return runSpec{title: "HTTP proxy · stop", rnr: runner.ForCommand("spark-http-proxy", "stop")}, true
	case "proxy-upgrade":
		return runSpec{title: "HTTP proxy · upgrade", rnr: m.ansible, opts: ansibleOpts("http-proxy"), sudo: true}, true
	case "device":
		return runSpec{title: "Device info", rnr: runner.ForCommand("ayse-get-sm")}, true
	default:
		return runSpec{}, false
	}
}

// dismissSplashIfReady hands off to the dashboard once status has loaded and the
// minimum splash time has passed, unless the user is holding it via clicks.
func (m *Model) dismissSplashIfReady() {
	if m.page == ui.PageSplash && m.statusReady && m.splashMin {
		m.page = ui.PageDashboard
	}
}

func (m *Model) setSize(w, h int) {
	m.width, m.height = w, h
	m.splash.SetSize(w, h)
	m.dashboard.SetSize(w, h)
	m.runview.SetSize(w, h)
	m.password.SetSize(w, h)
	m.logview.SetSize(w, h)
}

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
	default:
		return m.dashboard.View()
	}
}
