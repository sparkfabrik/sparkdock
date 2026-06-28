// Package status reports the health of sparkdock subsystems by delegating to
// the existing shell backend (sparkdock-check-updates and brew), never by
// recomputing update logic. The command runner is injected so the checker is
// unit-testable without invoking real binaries.
package status

import (
	"context"
	"fmt"
	"strings"
)

// Health is the freshness of a subsystem, mirroring the menu bar's dots.
type Health int

const (
	Unknown Health = iota
	OK
	Stale
	Unconfigured
)

// Subsystem is one row of the status dashboard.
type Subsystem struct {
	Key    string // stable id: sparkdock, brew, http-proxy, skills
	Name   string // display name
	Health Health
	Detail string
}

// Checker reports the status of all subsystems.
type Checker interface {
	Check(ctx context.Context) []Subsystem
}

// CommandResult is the outcome of running one external command.
type CommandResult struct {
	Stdout   string
	ExitCode int
	Err      error
}

// CommandRunner runs a command and returns its stdout and exit code. Injected
// so tests can supply canned results.
type CommandRunner func(ctx context.Context, name string, args ...string) CommandResult

// CmdChecker implements Checker against the shell backend.
type CmdChecker struct {
	// CheckUpdatesBin is the path to sparkdock-check-updates.
	CheckUpdatesBin string
	// BrewBin is the path to brew.
	BrewBin string
	// Run executes commands; must be non-nil.
	Run CommandRunner
}

// checkUpdates exit-code contract: 0 = updates available, 1 = none,
// 3 = not configured, anything else = error/unknown.
func healthFromCheckUpdates(r CommandResult) Health {
	if r.Err != nil {
		return Unknown
	}
	switch r.ExitCode {
	case 0:
		return Stale
	case 1:
		return OK
	case 3:
		return Unconfigured
	default:
		return Unknown
	}
}

// Check queries every subsystem. Calls are independent and could be parallelised
// later; kept sequential here for deterministic ordering and simplicity.
func (c CmdChecker) Check(ctx context.Context) []Subsystem {
	return []Subsystem{
		c.checkUpdatesSubsystem(ctx, "sparkdock", "Sparkdock", "sparkdock"),
		c.brewSubsystem(ctx),
		c.checkUpdatesSubsystem(ctx, "http-proxy", "HTTP proxy", "http-proxy"),
		c.checkUpdatesSubsystem(ctx, "skills", "Agent skills", "skills"),
	}
}

func (c CmdChecker) checkUpdatesSubsystem(ctx context.Context, key, name, arg string) Subsystem {
	res := c.Run(ctx, c.CheckUpdatesBin, arg)
	h := healthFromCheckUpdates(res)
	return Subsystem{Key: key, Name: name, Health: h, Detail: detailFor(h)}
}

func (c CmdChecker) brewSubsystem(ctx context.Context) Subsystem {
	res := c.Run(ctx, c.BrewBin, "outdated", "--quiet")
	sub := Subsystem{Key: "brew", Name: "Brew packages"}
	if res.Err != nil {
		sub.Health = Unknown
		sub.Detail = "check failed"
		return sub
	}
	n := countNonEmptyLines(res.Stdout)
	if n == 0 {
		sub.Health = OK
		sub.Detail = "up to date"
		return sub
	}
	sub.Health = Stale
	sub.Detail = fmt.Sprintf("%d to update", n)
	return sub
}

func detailFor(h Health) string {
	switch h {
	case OK:
		return "up to date"
	case Stale:
		return "updates available"
	case Unconfigured:
		return "not configured"
	default:
		return "unknown"
	}
}

func countNonEmptyLines(s string) int {
	n := 0
	for _, ln := range strings.Split(strings.TrimSpace(s), "\n") {
		if strings.TrimSpace(ln) != "" {
			n++
		}
	}
	return n
}
