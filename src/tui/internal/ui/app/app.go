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
	"os"
	"path/filepath"
	"time"

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
	Root    string // e.g. /opt/sparkdock
	ExePath string // path to the running sparkdock-tui binary, for restart detection
}

// Deps are the injected backends the app wires into its pages.
type Deps struct {
	Checker  status.Checker
	Gatherer sysinfo.Gatherer
}

// runSpec describes a run the app can start (and retry).
type runSpec struct {
	title  string
	rnr    *runner.Runner
	opts   runner.Options
	sudo   bool               // prime the sudo timestamp before the run (ansible become)
	scroll runview.ScrollMode // how the runner view tracks output
	render runview.RenderMode // structured (callback) vs terminal emulation
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

	// binModTime is the running binary's mtime at startup; a self-update that
	// rebuilds it changes this, so we can advise a relaunch.
	binModTime time.Time
}

// New builds the root model wired to its dependencies.
func New(cfg Config, ver version.Info, deps Deps) Model {
	m := Model{
		cfg:       cfg,
		page:      ui.PageSplash,
		splash:    splash.New(ver),
		dashboard: dashboard.New(deps.Checker, deps.Gatherer, ver),
		runview:   runview.New(),
		password:  password.New(),
		logview:   logview.New(),
		ansible:   runner.New(),
	}
	if cfg.ExePath != "" {
		if fi, err := os.Stat(cfg.ExePath); err == nil {
			m.binModTime = fi.ModTime()
		}
	}
	return m
}

// binaryChanged reports whether the running binary was replaced since startup
// (a self-update that rebuilt sparkdock-tui), meaning a relaunch is needed to
// load the new version.
func (m Model) binaryChanged() bool {
	if m.cfg.ExePath == "" || m.binModTime.IsZero() {
		return false
	}
	fi, err := os.Stat(m.cfg.ExePath)
	if err != nil {
		return false
	}
	return fi.ModTime().After(m.binModTime)
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
		return m, m.dismissSplashIfReady()

	case splash.TimeoutMsg:
		if m.page == ui.PageSplash {
			m.page = ui.PageDashboard // never trap the user on a slow status load
			return m, tea.DisableMouse
		}
		return m, nil

	case dashboard.StatusMsg:
		var cmd tea.Cmd
		m.dashboard, cmd = m.dashboard.Update(msg)
		m.statusReady = true // status loaded in the background during the splash
		return m, tea.Batch(cmd, m.dismissSplashIfReady())

	case dashboard.SysInfoMsg:
		// May arrive while the splash is still up; force it to the dashboard so
		// the panel is populated rather than dropped.
		var cmd tea.Cmd
		m.dashboard, cmd = m.dashboard.Update(msg)
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
		// A self-update that rebuilt the binary means the running process is now
		// stale; advise a relaunch on the dashboard.
		if m.hasLast && m.last.opts.SelfUpdate && m.binaryChanged() {
			m.dashboard = m.dashboard.WithRestartHint()
		}
		return m.toDashboard()

	case logview.BackMsg:
		m.page = ui.PageRunner
		return m, nil
	}

	return m.route(msg)
}

// toDashboard returns to the home page and always re-checks status, so any
// change an action made (a self-update, an upgrade, a proxy start) is reflected
// immediately instead of showing stale dots until the next manual refresh.
func (m Model) toDashboard() (tea.Model, tea.Cmd) {
	m.page = ui.PageDashboard
	m.dashboard = m.dashboard.MarkLoading()
	return m, m.dashboard.Init()
}

func (m Model) navigate(msg ui.NavigateMsg) (tea.Model, tea.Cmd) {
	switch msg.To {
	case ui.PageRunner:
		return m.launch(msg.Action)
	default:
		fromSplash := m.page == ui.PageSplash
		m.page = msg.To
		if fromSplash && m.page == ui.PageDashboard {
			return m, tea.DisableMouse // restore native text selection/copy
		}
	}
	return m, nil
}

// launch resolves an action to a run and starts it immediately; any password is
// requested reactively once the process prompts for it.
func (m Model) launch(action string) (tea.Model, tea.Cmd) {
	spec, ok := m.planFor(action)
	if !ok {
		return m.toDashboard() // unhandled action: stay home, still refresh
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
	m.runview, cmd = m.runview.Start(spec.title, handle, spec.scroll, spec.render)
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
		// "Update everything" is the equivalent of bare `sparkdock`: self-update
		// the install to upstream master, then provision. SelfUpdate is guarded in
		// the runner to the /opt install, so a dev checkout is only provisioned.
		opts := ansibleOpts()
		opts.SelfUpdate = true
		return runSpec{title: "Updating everything", rnr: m.ansible, opts: opts, sudo: true, scroll: runview.FollowTail, render: runview.Structured}, true
	case "upgrade":
		// --yes skips the confirmation prompt (official flag). A recent brew
		// change (PR #21882) made `brew upgrade` upgrade auto_updates casks even
		// non-greedy; HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 restores the old
		// behaviour of leaving self-updating apps to update themselves. Formulae
		// need no sudo; a cask that does prompts on the PTY. brew redraws progress
		// in place, so emulate a terminal.
		brewEnv := []string{"HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1"}
		return runSpec{title: "Upgrading Brew packages", rnr: runner.ForCommandEnv(brewEnv, "brew", "upgrade", "--yes"), scroll: runview.FollowTail, render: runview.Terminal}, true
	case "sync":
		return runSpec{title: "Syncing AI harness", rnr: m.ansible, opts: ansibleOpts("ai-harness-sync"), scroll: runview.FollowTail, render: runview.Structured}, true
	case "proxy-status":
		return runSpec{title: "HTTP proxy · status", rnr: runner.ForCommand("spark-http-proxy", "status"), scroll: runview.PinTop, render: runview.Structured}, true
	case "proxy-start":
		return runSpec{title: "HTTP proxy · start", rnr: runner.ForCommand("spark-http-proxy", "start"), scroll: runview.FollowTail, render: runview.Terminal}, true
	case "proxy-stop":
		return runSpec{title: "HTTP proxy · stop", rnr: runner.ForCommand("spark-http-proxy", "stop"), scroll: runview.FollowTail, render: runview.Terminal}, true
	case "proxy-upgrade":
		// Canonical path: the recipe git-updates the http-proxy repo, then
		// re-provisions. Run it with the sparkdock callback env so its nested
		// ansible emits the structured feed too; render Structured (the decoder's
		// \r handling keeps git's progress clean). The nested --ask-become-pass
		// prompt is answered via the password page.
		return runSpec{title: "HTTP proxy · upgrade", rnr: runner.ForCommandEnv(m.callbackEnv(), "sjust", "http-proxy-install-update"), scroll: runview.FollowTail, render: runview.Structured}, true
	case "device":
		return runSpec{title: "Device info", rnr: runner.ForCommand("ayse-get-sm"), scroll: runview.PinTop, render: runview.Structured}, true
	default:
		return runSpec{}, false
	}
}

// dismissSplashIfReady hands off to the dashboard once status has loaded and the
// minimum splash time has passed, returning a command to disable mouse reporting
// so normal terminal text selection/copy works on the content pages.
func (m *Model) dismissSplashIfReady() tea.Cmd {
	if m.page == ui.PageSplash && m.statusReady && m.splashMin {
		m.page = ui.PageDashboard
		return tea.DisableMouse
	}
	return nil
}

// callbackEnv enables the sparkdock stdout callback for a recipe that runs
// ansible, so its nested playbook produces the structured feed. The callback
// dir is absolute, so ansible loads it regardless of the recipe's working dir.
func (m Model) callbackEnv() []string {
	dir := filepath.Join(m.cfg.Root, "ansible", "callback_plugins")
	if abs, err := filepath.Abs(dir); err == nil {
		dir = abs
	}
	return []string{
		"ANSIBLE_STDOUT_CALLBACK=sparkdock",
		"ANSIBLE_CALLBACK_PLUGINS=" + dir,
		"PYTHONUNBUFFERED=1",
		"ANSIBLE_FORCE_COLOR=0",
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
