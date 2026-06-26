// Package runner executes an ansible-playbook process, parses its sparkdock
// callback output into a stream of feed.Events, and supports cancellation. The
// become password, when set, is placed on the SUBPROCESS environment only and
// never exported to the parent shell, written to argv, logged, or persisted.
//
// The command builder is injected (Builder) so the streaming, cancellation, and
// completion logic can be tested against a fake process.
package runner

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
)

// Options configures a single run.
type Options struct {
	Dir               string   // working directory for the playbook
	Playbook          string   // playbook filename (relative to Dir)
	Inventory         string   // inventory spec, e.g. "localhost,"
	Tags              []string // optional --tags
	BecomePass        string   // optional; set on child env only
	ForceFail         bool     // demo/testing: -e force_fail=true
	Verbose           bool     // pass -v
	CallbackPluginDir string   // dir containing the sparkdock callback
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

// Handle is a live run. Events streams parsed feed events until closed; Done
// then delivers exactly one Result.
type Handle struct {
	Events <-chan feed.Event
	Done   <-chan Result

	cmd      *exec.Cmd
	canceled chan struct{}
}

// Start launches the run and returns a Handle. The caller drains Events until
// the channel closes, then reads Done.
func (r *Runner) Start(ctx context.Context, opts Options) *Handle {
	events := make(chan feed.Event, 64)
	done := make(chan Result, 1)
	h := &Handle{Events: events, Done: done, canceled: make(chan struct{})}

	cmd := r.Build(ctx, opts)
	h.cmd = cmd

	pr, pw, err := os.Pipe()
	if err != nil {
		close(events)
		done <- Result{Err: err}
		return h
	}
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		pw.Close()
		pr.Close()
		close(events)
		done <- Result{Err: err}
		return h
	}

	go func() {
		pw.Close() // parent drops write end so the scanner observes EOF at child exit
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 1024*1024), 1024*1024)
		for sc.Scan() {
			events <- feed.Parse(sc.Text())
		}
		exitErr := cmd.Wait()
		close(events)
		select {
		case <-h.canceled:
			done <- Result{Err: exitErr, Canceled: true}
		default:
			done <- Result{Err: exitErr}
		}
	}()
	return h
}

// Cancel interrupts the running process so Ansible can unwind the current task.
// Safe to call multiple times and after completion.
func (h *Handle) Cancel() {
	select {
	case <-h.canceled:
		return // already cancelled
	default:
		close(h.canceled)
	}
	if h.cmd != nil && h.cmd.Process != nil {
		_ = h.cmd.Process.Signal(os.Interrupt)
	}
}

// becomeAuthNeedles are substrings Ansible emits when the become password is
// missing or wrong, used to decide whether to re-prompt rather than report a
// generic failure.
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
// stdout callback. The become password, if any, is appended to the child env
// only.
func AnsibleBuilder(ctx context.Context, opts Options) *exec.Cmd {
	inventory := opts.Inventory
	if inventory == "" {
		inventory = "localhost,"
	}
	args := []string{opts.Playbook, "-i", inventory, "-c", "local"}
	if len(opts.Tags) > 0 {
		args = append(args, "--tags", strings.Join(opts.Tags, ","))
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
	if opts.BecomePass != "" {
		cmd.Env = append(cmd.Env, "ANSIBLE_BECOME_PASS="+opts.BecomePass) // child-scoped only
	}
	return cmd
}

// ForCommand returns a Runner that runs an arbitrary command, streaming its
// combined output as plain feed lines (no Ansible callback). Used for sjust
// recipes and other non-Ansible operations shown in the runner view.
func ForCommand(name string, args ...string) *Runner {
	return &Runner{Build: func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, name, args...)
	}}
}
