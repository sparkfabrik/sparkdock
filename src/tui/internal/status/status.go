// Package status reports the health of sparkdock subsystems by delegating to
// the existing shell backend (sparkdock-check-updates and brew), never by
// recomputing update logic. The command runner is injected so the checker is
// unit-testable without invoking real binaries.
package status

import (
	"context"
	"fmt"
	"strconv"
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

// Checker reports subsystem status one subsystem at a time, so callers can run
// the checks concurrently and stream each result into the UI as it lands.
type Checker interface {
	// Subsystems lists the checkable subsystem keys in display order.
	Subsystems() []string
	// CheckOne checks a single subsystem by key.
	CheckOne(ctx context.Context, key string) Subsystem
}

// CommandResult is the outcome of running one external command.
type CommandResult struct {
	Stdout   string
	Stderr   string // captured so a failing check can name its cause
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
	// DoctorBin is the path to the macos-doctor run script. It is invoked with
	// "count", which runs only the checks marked cheap and prints nothing but the
	// MACOS_DOCTOR_STATUS line: this row refreshes on every dashboard load and on
	// 'r', so it must not sample over time or walk large directory trees.
	DoctorBin string
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

// subsystemOrder is the display order of the checkable subsystems.
var subsystemOrder = []string{"sparkdock", "brew", "http-proxy", "skills", "doctor"}

// Subsystems lists the checkable subsystem keys in display order.
func (c CmdChecker) Subsystems() []string {
	return append([]string(nil), subsystemOrder...)
}

// CheckOne checks a single subsystem by key.
func (c CmdChecker) CheckOne(ctx context.Context, key string) Subsystem {
	switch key {
	case "sparkdock":
		return c.checkUpdatesSubsystem(ctx, "sparkdock", "Sparkdock", "sparkdock")
	case "brew":
		return c.brewSubsystem(ctx)
	case "http-proxy":
		return c.checkUpdatesSubsystem(ctx, "http-proxy", "HTTP proxy", "http-proxy")
	case "skills":
		return c.checkUpdatesSubsystem(ctx, "skills", "Agent skills", "skills")
	case "doctor":
		return c.doctorSubsystem(ctx)
	default:
		return Subsystem{Key: key, Health: Unknown, Detail: "unknown"}
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
	// brew outdated exits non-zero only on real errors, so treat that as a
	// failed check too (its stdout would not be a package list).
	if res.Err != nil || res.ExitCode != 0 {
		sub.Health = Unknown
		sub.Detail = failDetail(res)
		return sub
	}
	names := nonEmptyLines(res.Stdout)
	if len(names) == 0 {
		sub.Health = OK
		sub.Detail = "up to date"
		return sub
	}
	sub.Health = Stale
	sub.Detail = fmt.Sprintf("%d to update: %s", len(names), summarizeNames(names, 3))
	return sub
}

// doctorStatusPrefix marks the machine-readable summary line that run.sh prints
// on stdout. Everything the script logs goes to stderr, so this line is the only
// contract between the shell backend and this row.
const doctorStatusPrefix = "MACOS_DOCTOR_STATUS:"

// parseDoctorStatus pulls findings count and check ids out of the status line.
// Returns ok=false when no such line is present, which is what a crashed or
// missing backend looks like.
func parseDoctorStatus(stdout string) (findings int, ids []string, ok bool) {
	for _, ln := range nonEmptyLines(stdout) {
		if !strings.HasPrefix(ln, doctorStatusPrefix) {
			continue
		}
		for _, field := range strings.Fields(strings.TrimPrefix(ln, doctorStatusPrefix)) {
			key, value, found := strings.Cut(field, "=")
			if !found {
				continue
			}
			switch key {
			case "findings":
				n, err := strconv.Atoi(value)
				if err != nil {
					return 0, nil, false
				}
				findings = n
			case "ids":
				if value != "" {
					ids = strings.Split(value, ",")
				}
			}
		}
		return findings, ids, true
	}
	return 0, nil, false
}

func (c CmdChecker) doctorSubsystem(ctx context.Context) Subsystem {
	sub := Subsystem{Key: "doctor", Name: "macOS doctor"}

	// An unset DoctorBin means the caller did not wire this row up; report it as
	// unconfigured rather than running an empty command.
	if c.DoctorBin == "" {
		sub.Health = Unconfigured
		sub.Detail = "not configured"
		return sub
	}

	res := c.Run(ctx, c.DoctorBin, "count")
	findings, ids, ok := parseDoctorStatus(res.Stdout)
	if !ok {
		sub.Health = Unknown
		sub.Detail = failDetail(res)
		return sub
	}
	if findings == 0 {
		sub.Health = OK
		sub.Detail = "no findings"
		return sub
	}

	sub.Health = Stale
	sub.Detail = fmt.Sprintf("%d finding(s)", findings)
	if len(ids) > 0 {
		sub.Detail += ": " + summarizeNames(ids, 2)
	}
	return sub
}

// summarizeNames joins up to max names, folding the rest into a "+N more" tail
// so the detail never floods the status row.
func summarizeNames(names []string, max int) string {
	if len(names) <= max {
		return strings.Join(names, ", ")
	}
	return fmt.Sprintf("%s +%d more", strings.Join(names[:max], ", "), len(names)-max)
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

// failDetail names the failure cause on the status row, preferring the
// command's own stderr over a generic label.
func failDetail(r CommandResult) string {
	cause := ""
	if lines := nonEmptyLines(r.Stderr); len(lines) > 0 {
		cause = lines[0]
	} else if r.Err != nil {
		cause = r.Err.Error()
	}
	if cause == "" {
		return "check failed"
	}
	if r := []rune(cause); len(r) > 60 {
		cause = string(r[:60]) + "…"
	}
	return "check failed: " + cause
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, ln := range strings.Split(strings.TrimSpace(s), "\n") {
		if ln = strings.TrimSpace(ln); ln != "" {
			out = append(out, ln)
		}
	}
	return out
}
