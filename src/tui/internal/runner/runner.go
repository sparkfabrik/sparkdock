// Package runner executes a command (ansible-playbook, brew, sjust, …) attached
// to a pseudo-terminal, parses its output into a stream of feed.Events, detects
// interactive password prompts so the UI can answer them, and supports
// cancellation.
//
// Running under a PTY means any tool that asks for a sudo/become password does
// so the way it always would — we detect the prompt and write the answer back
// to the PTY. The password is never placed in argv, the environment, or a file;
// it travels only over the child's terminal, exactly as if typed.
//
// The command builder is injected (Builder) so the streaming, prompt, and
// cancellation logic can be tested against a fake process.
package runner

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/creack/pty"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
)

// Options configures a single run.
type Options struct {
	Dir               string   // working directory for the playbook
	Playbook          string   // playbook filename (relative to Dir)
	Inventory         string   // inventory spec, e.g. "localhost,"
	Tags              []string // optional --tags
	AskBecomePass     bool     // add --ask-become-pass so ansible prompts (we answer via PTY)
	ForceFail         bool     // demo/testing: -e force_fail=true
	Verbose           bool     // pass -v
	CallbackPluginDir string   // dir containing the sparkdock callback

	PtyRows, PtyCols int // terminal size to give the child; defaults to 24x80
}

// Result reports how a run ended.
type Result struct {
	Err      error // non-nil if the process exited non-zero or failed to start
	Canceled bool  // true if Cancel was called
}

// Builder constructs the command to run for the given options and context.
type Builder func(ctx context.Context, opts Options) *exec.Cmd

// Runner starts runs. Construct with New for the real ansible builder, or set
// Build directly in tests.
type Runner struct {
	Build Builder
}

// New returns a Runner that invokes the real ansible-playbook binary.
func New() *Runner {
	return &Runner{Build: AnsibleBuilder}
}

// Handle is a live run. Events streams parsed feed events until closed. Prompts
// delivers the text of each detected password prompt; the UI answers with
// Answer. Done delivers exactly one Result after Events closes.
type Handle struct {
	Events  <-chan feed.Event
	Prompts <-chan string
	Done    <-chan Result

	cmd      *exec.Cmd
	ptmx     *os.File
	canceled chan struct{}
}

// promptRe matches a trailing interactive password prompt with no newline yet,
// e.g. "Password:", "BECOME password:", "[sudo] password for user:".
var promptRe = regexp.MustCompile(`(?i)password(?: for [^:]*)?:\s*$`)

// Start launches the run under a PTY and returns a Handle.
func (r *Runner) Start(ctx context.Context, opts Options) *Handle {
	events := make(chan feed.Event, 64)
	prompts := make(chan string, 1)
	done := make(chan Result, 1)
	h := &Handle{Events: events, Prompts: prompts, Done: done, canceled: make(chan struct{})}

	cmd := r.Build(ctx, opts)
	h.cmd = cmd

	ptmx, err := pty.Start(cmd)
	if err != nil {
		close(events)
		close(prompts)
		done <- Result{Err: err}
		return h
	}
	h.ptmx = ptmx

	// Size the PTY to the view so tty-aware programs render to fit instead of a
	// default width that overflows and corrupts the layout.
	rows, cols := opts.PtyRows, opts.PtyCols
	if cols <= 0 {
		cols = 80
	}
	if rows <= 0 {
		rows = 24
	}
	_ = pty.Setsize(ptmx, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)})

	go h.pump(events, prompts, done)
	return h
}

// pump reads the PTY, emitting completed lines as events and signalling a
// password prompt when the pending (un-newlined) text looks like one.
func (h *Handle) pump(events chan<- feed.Event, prompts chan<- string, done chan<- Result) {
	defer close(events)
	defer close(prompts)

	buf := make([]byte, 4096)
	var line []byte
	awaiting := false
	for {
		n, err := h.ptmx.Read(buf)
		for _, b := range buf[:n] {
			if b == '\n' {
				events <- feed.Parse(strings.TrimRight(string(line), "\r"))
				line = line[:0]
				awaiting = false
				continue
			}
			line = append(line, b)
		}
		if !awaiting && len(line) > 0 && promptRe.Match(line) {
			awaiting = true
			prompts <- strings.TrimSpace(string(line))
		}
		if err != nil { // EOF, or EIO when the child exits and closes the PTY
			if len(line) > 0 && !awaiting {
				events <- feed.Parse(strings.TrimRight(string(line), "\r"))
			}
			break
		}
	}

	exitErr := h.cmd.Wait()
	h.ptmx.Close()
	select {
	case <-h.canceled:
		done <- Result{Err: exitErr, Canceled: true}
	default:
		done <- Result{Err: exitErr}
	}
}

// Answer writes a password (plus newline) to the running process's PTY in
// response to a prompt. The secret travels only over the child's terminal.
func (h *Handle) Answer(password string) {
	if h.ptmx != nil {
		_, _ = io.WriteString(h.ptmx, password+"\n")
	}
}

// Cancel interrupts the running process so it can unwind. Safe to call multiple
// times and after completion.
func (h *Handle) Cancel() {
	select {
	case <-h.canceled:
		return
	default:
		close(h.canceled)
	}
	if h.cmd != nil && h.cmd.Process != nil {
		_ = h.cmd.Process.Signal(os.Interrupt)
	}
}

// becomeAuthNeedles are substrings Ansible emits when the become password is
// wrong, used to decide whether to re-prompt rather than report a failure.
var becomeAuthNeedles = []string{
	"Incorrect sudo password",
	"Incorrect su password",
	"Missing sudo password",
	"sudo: a password is required",
	"Invalid/incorrect password",
}

// IsBecomeAuthFailure reports whether any captured output line indicates a
// sudo/become authentication failure.
func IsBecomeAuthFailure(lines []string) bool {
	for _, ln := range lines {
		for _, needle := range becomeAuthNeedles {
			if strings.Contains(ln, needle) {
				return true
			}
		}
	}
	return false
}

// AnsibleBuilder builds a real ansible-playbook invocation with the sparkdock
// stdout callback. --ask-become-pass is added when AskBecomePass is set, so
// ansible prompts for the become password on the PTY (which the UI answers).
func AnsibleBuilder(ctx context.Context, opts Options) *exec.Cmd {
	inventory := opts.Inventory
	if inventory == "" {
		inventory = "localhost,"
	}
	args := []string{opts.Playbook, "-i", inventory, "-c", "local"}
	if opts.Dir != "" {
		if abs, err := filepath.Abs(opts.Dir); err == nil {
			args = append(args, "-e", "dev_env_dir="+abs)
		}
	}
	if len(opts.Tags) > 0 {
		args = append(args, "--tags", strings.Join(opts.Tags, ","))
	}
	if opts.AskBecomePass {
		args = append(args, "--ask-become-pass")
	}
	if opts.Verbose {
		args = append(args, "-v")
	}
	if opts.ForceFail {
		args = append(args, "-e", "force_fail=true")
	}
	cmd := exec.CommandContext(ctx, "ansible-playbook", args...)
	cmd.Dir = opts.Dir
	cmd.Env = append(os.Environ(),
		"ANSIBLE_STDOUT_CALLBACK=sparkdock",
		"PYTHONUNBUFFERED=1",
		"ANSIBLE_FORCE_COLOR=0",
	)
	if opts.CallbackPluginDir != "" {
		cmd.Env = append(cmd.Env, "ANSIBLE_CALLBACK_PLUGINS="+filepath.Clean(opts.CallbackPluginDir))
	}
	return cmd
}

// ForCommand returns a Runner that runs an arbitrary command, streaming its
// combined output as plain feed lines (no Ansible callback). Used for brew,
// sjust recipes, and other non-Ansible operations shown in the runner view.
func ForCommand(name string, args ...string) *Runner {
	return &Runner{Build: func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, name, args...)
	}}
}
