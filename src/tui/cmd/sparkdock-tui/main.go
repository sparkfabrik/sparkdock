// Command sparkdock-tui is the terminal hub for sparkdock.
//
// Dispatch:
//
//	sparkdock-tui                     (interactive TTY) -> launch the TUI hub
//	sparkdock-tui update / --no-tui   -> exec the sparkdock bash entrypoint
//	sparkdock-tui with no TTY         -> refuse with guidance (never provisions
//	                                     implicitly from a pipe)
//
// The headless path is intentionally a thin delegate: real provisioning is
// driven by the existing bash entrypoint and Ansible, not reimplemented here.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/recipes"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/status"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/sysinfo"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/ui/app"
	"github.com/sparkfabrik/sparkdock/src/tui/internal/version"
)

func main() {
	root := os.Getenv("SPARKDOCK_ROOT")
	if root == "" {
		root = "/opt/sparkdock"
	}

	if headlessRequested(os.Args[1:]) {
		runHeadless(root)
		return
	}
	if !interactive() {
		fmt.Fprintln(os.Stderr, "sparkdock-tui: stdin/stdout is not a terminal; run `sparkdock` to provision headlessly, or `sparkdock-tui update` to delegate explicitly")
		os.Exit(1)
	}

	ver := version.NewReader(root).Read()
	deps := app.Deps{
		Checker: status.CmdChecker{
			CheckUpdatesBin: root + "/bin/sparkdock-check-updates",
			BrewBin:         "brew",
			DoctorBin:       root + "/sjust/scripts/macos-doctor/run.sh",
			Run:             execRunner,
		},
		Gatherer: sysinfo.Gatherer{Run: execRunner},
		Recipes: func(ctx context.Context) ([]recipes.Recipe, error) {
			return recipes.Load(ctx, root)
		},
	}

	exePath, _ := os.Executable()

	prog := tea.NewProgram(
		app.New(app.Config{Root: root, ExePath: exePath}, ver, deps),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(), // so the splash logo is clickable
	)
	if _, err := prog.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "sparkdock-tui:", err)
		os.Exit(1)
	}
}

// interactive reports whether both stdin and stdout are terminals.
func interactive() bool {
	return term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd()))
}

func headlessRequested(args []string) bool {
	for _, a := range args {
		if a == "update" || a == "--no-tui" {
			return true
		}
	}
	return false
}

// runHeadless replaces this process with the sparkdock bash entrypoint, which
// owns self-update and full provisioning (the exact behaviour of running bare
// `sparkdock`). Tries the install the binary was configured for first, then
// PATH.
func runHeadless(root string) {
	candidates := []string{filepath.Join(root, "bin", "sparkdock.macos")}
	if p, err := exec.LookPath("sparkdock"); err == nil {
		candidates = append(candidates, p)
	}
	for _, path := range candidates {
		// Exec never returns on success (the entrypoint takes over the terminal)
		// and fails fast on a missing or non-executable path.
		_ = syscall.Exec(path, []string{path}, os.Environ())
	}
	fmt.Fprintf(os.Stderr, "sparkdock-tui: could not exec the sparkdock entrypoint (tried %s)\n", candidates)
	os.Exit(1)
}

// execRunner adapts os/exec to status.CommandRunner, distinguishing a command
// that ran with a non-zero exit from one that could not run at all. Stderr is
// captured (Output stores it on the ExitError) so a failing check can surface
// its cause instead of a bare "check failed".
func execRunner(ctx context.Context, name string, args ...string) status.CommandResult {
	out, err := exec.CommandContext(ctx, name, args...).Output()
	if err == nil {
		return status.CommandResult{Stdout: string(out), ExitCode: 0}
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return status.CommandResult{Stdout: string(out), Stderr: string(ee.Stderr), ExitCode: ee.ExitCode()}
	}
	return status.CommandResult{Err: err}
}
