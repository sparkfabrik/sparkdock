// Command sparkdock-tui is the terminal hub for sparkdock.
//
// Dispatch:
//
//	sparkdock-tui            (interactive TTY)  -> launch the TUI hub
//	sparkdock-tui update     / non-TTY / --no-tui -> headless (delegates out)
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

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"

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

	if !interactive() || headlessRequested(os.Args[1:]) {
		runHeadless()
		return
	}

	ver := version.NewReader(root).Read()
	deps := app.Deps{
		Checker: status.CmdChecker{
			CheckUpdatesBin: root + "/bin/sparkdock-check-updates",
			BrewBin:         "brew",
			Run:             execRunner,
		},
		Gatherer: sysinfo.Gatherer{Run: execRunner},
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

// runHeadless is a placeholder for the headless path. The production version
// will delegate to the bash entrypoint / `just run-ansible-playbook`.
func runHeadless() {
	fmt.Println("sparkdock-tui: headless mode — delegate to the provisioner (not yet wired)")
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
