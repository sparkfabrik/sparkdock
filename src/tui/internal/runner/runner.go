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
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/creack/pty"
)

// Options configures a single run.
type Options struct {
	Dir               string   // working directory for the playbook
	Playbook          string   // playbook filename (relative to Dir)
	Inventory         string   // inventory spec, e.g. "localhost,"
	Tags              []string // optional --tags
	Sudo              bool     // prime the sudo timestamp first (sudo -v), so become works via sudo -n
	ForceFail         bool     // demo/testing: -e force_fail=true
	Verbose           bool     // pass -v
	CallbackPluginDir string   // dir containing the sparkdock callback
	SelfUpdate        bool     // git fetch + reset --hard origin/master before provisioning (only when Dir is the /opt install)

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

// Handle is a live run. Output streams raw PTY bytes until closed (the view
// decides how to render them: a structured decoder or a terminal emulator).
// Prompts delivers the text of each detected password prompt; the UI answers
// with Answer. Done delivers exactly one Result after Output closes.
type Handle struct {
	Output  <-chan []byte
	Prompts <-chan string
	Done    <-chan Result

	cmd      *exec.Cmd
	ptmx     *os.File
	canceled chan struct{}
	finished chan struct{} // closed once the child is reaped, stops escalation

	// mu guards ptmxClosed and the Setsize ioctl: pty.Setsize reads the raw fd
	// via File.Fd(), which races with the pump goroutine closing the file.
	// (Read/Write go through the runtime poller and need no extra locking.)
	mu         sync.Mutex
	ptmxClosed bool
}

// cancelGrace is how long Cancel waits for the child to honour SIGINT before
// escalating to SIGKILL. A variable so tests can shorten it.
var cancelGrace = 5 * time.Second

// promptRe matches a trailing interactive password prompt with no newline yet,
// e.g. "Password:", "BECOME password:", "[sudo] password for user:".
var promptRe = regexp.MustCompile(`(?i)password(?: for [^:]*)?:\s*$`)

// Start launches the run under a PTY and returns a Handle.
func (r *Runner) Start(ctx context.Context, opts Options) *Handle {
	output := make(chan []byte, 64)
	prompts := make(chan string, 1)
	done := make(chan Result, 1)
	h := &Handle{Output: output, Prompts: prompts, Done: done, canceled: make(chan struct{}), finished: make(chan struct{})}

	cmd := r.Build(ctx, opts)
	h.cmd = cmd

	ptmx, err := pty.Start(cmd)
	if err != nil {
		close(output)
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

	go h.pump(output, prompts, done)
	return h
}

// pump reads the PTY, forwarding raw bytes on output and signalling a password
// prompt when the pending (un-newlined) text looks like one. It does not parse
// or interpret the bytes; rendering is the view's responsibility.
func (h *Handle) pump(output chan<- []byte, prompts chan<- string, done chan<- Result) {
	// Guarantee exactly one Done is sent, even on a panic, so the UI never hangs
	// waiting on it. Deferred LIFO: channels close first, then Done is sent.
	var res Result
	defer func() {
		if r := recover(); r != nil {
			res = Result{Err: fmt.Errorf("runner: %v", r)}
		}
		done <- res
	}()
	defer close(h.finished)
	defer close(prompts)
	defer close(output)

	buf := make([]byte, 4096)
	var line []byte // pending line, for prompt detection only
	awaiting := false
	for {
		n, err := h.ptmx.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			output <- chunk
			for _, b := range buf[:n] {
				if b == '\n' {
					line = line[:0]
					awaiting = false
					continue
				}
				line = append(line, b)
			}
			// Cap the pending-line buffer so a process that never emits a newline
			// can't grow it without bound; the prompt sits at the tail anyway.
			if len(line) > 4096 {
				line = line[len(line)-512:]
			}
			if !awaiting && len(line) > 0 && promptRe.Match(line) {
				awaiting = true
				prompts <- strings.TrimSpace(string(line))
			}
		}
		if err != nil { // EOF, or EIO when the child exits and closes the PTY
			break
		}
	}

	exitErr := h.cmd.Wait()
	h.closePTY()
	select {
	case <-h.canceled:
		res = Result{Err: exitErr, Canceled: true}
	default:
		res = Result{Err: exitErr}
	}
}

// closePTY closes the PTY under the mutex so a concurrent Resize never touches
// a closing fd.
func (h *Handle) closePTY() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.ptmxClosed = true
	h.ptmx.Close()
}

// Resize updates the child's PTY size so tty-aware programs (brew progress
// bars, spinners) re-render to fit after the enclosing terminal is resized.
// The kernel delivers SIGWINCH to the child as part of the ioctl. Safe to call
// on a handle whose process failed to start or has already exited.
func (h *Handle) Resize(rows, cols int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.ptmx == nil || h.ptmxClosed || rows <= 0 || cols <= 0 {
		return
	}
	_ = pty.Setsize(h.ptmx, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)})
}

// Answer writes a password (plus newline) to the running process's PTY in
// response to a prompt. The secret travels only over the child's terminal.
func (h *Handle) Answer(password string) {
	if h.ptmx != nil {
		_, _ = io.WriteString(h.ptmx, password+"\n")
	}
}

// WriteInput forwards raw input to the running process's PTY, so the user can
// answer non-password prompts (e.g. brew's "Proceed? [y/n]") from the runner.
func (h *Handle) WriteInput(s string) {
	if h.ptmx != nil {
		_, _ = io.WriteString(h.ptmx, s)
	}
}

// Cancel interrupts the running process so it can unwind. The child runs as the
// leader of its own session (the pty library sets Setsid), so the whole process
// group is signalled — a bare Signal to the direct child would leave nested
// processes (ansible under bash) running. If the group ignores SIGINT, Cancel
// escalates to SIGKILL after a grace period. Safe to call multiple times and
// after completion.
func (h *Handle) Cancel() {
	select {
	case <-h.canceled:
		return
	default:
		close(h.canceled)
	}
	if h.cmd == nil || h.cmd.Process == nil {
		return
	}
	pid := h.cmd.Process.Pid
	signalGroup(pid, syscall.SIGINT)
	grace := cancelGrace // read synchronously; the goroutine may outlive callers
	go func() {
		select {
		case <-h.finished:
		case <-time.After(grace):
			signalGroup(pid, syscall.SIGKILL)
		}
	}()
}

// signalGroup signals the process group led by pid, falling back to the single
// process if the group is already gone.
func signalGroup(pid int, sig syscall.Signal) {
	if err := syscall.Kill(-pid, sig); err != nil {
		_ = syscall.Kill(pid, sig)
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
// stdout callback. When Sudo is set, --ask-become-pass is added so ansible
// prompts once for the become password and feeds it to every become task itself
// (reliable regardless of the tty's sudo timestamp). The UI answers the prompt
// on the PTY via the masked password page; the password is never cached. When
// SelfUpdate is set, the run first force-syncs the install to upstream master
// (see selfUpdateWrap), so "Update everything" matches bare `sparkdock`.
func AnsibleBuilder(ctx context.Context, opts Options) *exec.Cmd {
	args := ansibleArgs(opts)
	env := ansibleEnv(opts)

	if opts.SelfUpdate {
		return selfUpdateWrap(ctx, opts, args, env)
	}

	cmd := exec.CommandContext(ctx, "ansible-playbook", args...)
	cmd.Dir = opts.Dir
	cmd.Env = env
	return cmd
}

// ansibleArgs builds the ansible-playbook argument list from opts.
func ansibleArgs(opts Options) []string {
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
	if opts.Sudo {
		args = append(args, "--ask-become-pass")
	}
	if opts.Verbose {
		args = append(args, "-v")
	}
	if opts.ForceFail {
		args = append(args, "-e", "force_fail=true")
	}
	return args
}

// ansibleEnv builds the environment for an ansible run with the sparkdock
// stdout callback.
func ansibleEnv(opts Options) []string {
	env := append(os.Environ(),
		"ANSIBLE_STDOUT_CALLBACK=sparkdock",
		"PYTHONUNBUFFERED=1",
		"ANSIBLE_FORCE_COLOR=0",
	)
	if opts.CallbackPluginDir != "" {
		env = append(env, "ANSIBLE_CALLBACK_PLUGINS="+filepath.Clean(opts.CallbackPluginDir))
	}
	return env
}

// selfUpdateScript force-syncs the install to upstream master, then execs the
// provided ansible-playbook command. The git step is guarded to the /opt
// install (passed as $SPARKDOCK_DIR) so it never resets a dev checkout. It
// fetches first and only stashes + resets once upstream is reachable, so a
// failed fetch never leaves a dangling stash; any local changes are stashed so
// nothing is lost, mirroring the `sparkdock` entrypoint. If upstream is
// unreachable it provisions the current checkout rather than aborting the run.
// ansible-playbook arguments arrive as "$@", so no shell quoting is needed.
const selfUpdateScript = `set -e
if [ "$SPARKDOCK_DIR" = /opt/sparkdock ]; then
  cd "$SPARKDOCK_DIR"
  if git fetch --quiet origin master; then
    if ! git diff --quiet HEAD || [ -n "$(git ls-files --others --exclude-standard)" ]; then
      git stash push -u -m "sparkdock-tui auto-update" >/dev/null 2>&1 || true
    fi
    echo "Updating sparkdock from upstream (origin/master)…"
    git reset --hard --quiet origin/master
    echo "Provisioning the updated checkout…"
  else
    echo "Could not reach upstream; provisioning the current checkout…"
  fi
fi
exec ansible-playbook "$@"`

// selfUpdateWrap wraps the ansible command in the self-update shell script.
func selfUpdateWrap(ctx context.Context, opts Options, args, env []string) *exec.Cmd {
	cmdArgs := append([]string{"-c", selfUpdateScript, "sparkdock-update"}, args...)
	cmd := exec.CommandContext(ctx, "bash", cmdArgs...)
	cmd.Dir = opts.Dir
	cmd.Env = append(env, "SPARKDOCK_DIR="+opts.Dir)
	return cmd
}

// ForCommand returns a Runner that runs an arbitrary command, streaming its
// combined output as plain feed lines (no Ansible callback).
func ForCommand(name string, args ...string) *Runner {
	return &Runner{Build: func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, name, args...)
	}}
}

// ForCommandEnv is ForCommand with extra environment appended to the child, used
// to switch on the sparkdock stdout callback for recipes that run ansible (so a
// recipe's nested playbook produces the structured feed too).
func ForCommandEnv(extraEnv []string, name string, args ...string) *Runner {
	return &Runner{Build: func(ctx context.Context, _ Options) *exec.Cmd {
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.Env = append(os.Environ(), extraEnv...)
		return cmd
	}}
}
