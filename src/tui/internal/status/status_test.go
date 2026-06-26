package status

import (
	"context"
	"errors"
	"testing"
)

// fakeRunner returns canned results keyed by the first argument.
func fakeRunner(byArg map[string]CommandResult) CommandRunner {
	return func(_ context.Context, name string, args ...string) CommandResult {
		key := ""
		if len(args) > 0 {
			key = args[0]
		}
		if r, ok := byArg[key]; ok {
			return r
		}
		return CommandResult{Err: errors.New("unexpected call: " + name + " " + key)}
	}
}

func TestCheck_MapsExitCodesAndBrewCount(t *testing.T) {
	c := CmdChecker{
		CheckUpdatesBin: "check-updates",
		BrewBin:         "brew",
		Run: fakeRunner(map[string]CommandResult{
			"sparkdock":  {ExitCode: 1}, // up to date
			"http-proxy": {ExitCode: 0}, // updates available
			"skills":     {ExitCode: 3}, // not configured
			"outdated":   {Stdout: "docker\nnode\nphp\n"},
		}),
	}
	got := c.Check(context.Background())
	if len(got) != 4 {
		t.Fatalf("want 4 subsystems, got %d", len(got))
	}
	byKey := map[string]Subsystem{}
	for _, s := range got {
		byKey[s.Key] = s
	}
	if byKey["sparkdock"].Health != OK {
		t.Errorf("sparkdock health = %v, want OK", byKey["sparkdock"].Health)
	}
	if byKey["http-proxy"].Health != Stale {
		t.Errorf("http-proxy health = %v, want Stale", byKey["http-proxy"].Health)
	}
	if byKey["skills"].Health != Unconfigured {
		t.Errorf("skills health = %v, want Unconfigured", byKey["skills"].Health)
	}
	brew := byKey["brew"]
	if brew.Health != Stale || brew.Detail != "3 to update" {
		t.Errorf("brew = %+v, want Stale '3 to update'", brew)
	}
}

func TestCheck_BrewUpToDate(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{
			"sparkdock": {ExitCode: 1}, "http-proxy": {ExitCode: 1}, "skills": {ExitCode: 1},
			"outdated": {Stdout: "\n  \n"},
		}),
	}
	for _, s := range c.Check(context.Background()) {
		if s.Key == "brew" {
			if s.Health != OK || s.Detail != "up to date" {
				t.Errorf("brew = %+v, want OK 'up to date'", s)
			}
		}
	}
}

func TestCheck_ErrorsBecomeUnknown(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{
			"sparkdock": {Err: errors.New("boom")}, "http-proxy": {ExitCode: 1},
			"skills": {ExitCode: 1}, "outdated": {Err: errors.New("no brew")},
		}),
	}
	byKey := map[string]Subsystem{}
	for _, s := range c.Check(context.Background()) {
		byKey[s.Key] = s
	}
	if byKey["sparkdock"].Health != Unknown {
		t.Errorf("sparkdock health = %v, want Unknown", byKey["sparkdock"].Health)
	}
	if byKey["brew"].Health != Unknown {
		t.Errorf("brew health = %v, want Unknown", byKey["brew"].Health)
	}
}

func TestHealthFromCheckUpdates(t *testing.T) {
	cases := map[int]Health{0: Stale, 1: OK, 3: Unconfigured, 2: Unknown, 99: Unknown}
	for code, want := range cases {
		if got := healthFromCheckUpdates(CommandResult{ExitCode: code}); got != want {
			t.Errorf("exit %d -> %v, want %v", code, got, want)
		}
	}
}
