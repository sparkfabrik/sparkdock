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
	if brew.Health != Stale || brew.Detail != "3 to update: docker, node, php" {
		t.Errorf("brew = %+v, want Stale '3 to update: docker, node, php'", brew)
	}
}

func TestBrew_ManyOutdatedFoldsIntoMore(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{
			"outdated": {Stdout: "a\nb\nc\nd\ne\n"},
		}),
	}
	got := c.CheckOne(context.Background(), "brew")
	if got.Detail != "5 to update: a, b, c +2 more" {
		t.Errorf("brew detail = %q, want '5 to update: a, b, c +2 more'", got.Detail)
	}
}

func TestBrew_NonZeroExitSurfacesStderr(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{
			"outdated": {ExitCode: 1, Stderr: "Error: brokén tap\nmore noise"},
		}),
	}
	got := c.CheckOne(context.Background(), "brew")
	if got.Health != Unknown {
		t.Errorf("brew health = %v, want Unknown on non-zero exit", got.Health)
	}
	if got.Detail != "check failed: Error: brokén tap" {
		t.Errorf("brew detail = %q, want the first stderr line", got.Detail)
	}
}

func TestCheckOne_UnknownKey(t *testing.T) {
	c := CmdChecker{Run: fakeRunner(nil)}
	if got := c.CheckOne(context.Background(), "nope"); got.Health != Unknown {
		t.Errorf("unknown key health = %v, want Unknown", got.Health)
	}
}

func TestSubsystems_Order(t *testing.T) {
	got := CmdChecker{}.Subsystems()
	want := []string{"sparkdock", "brew", "http-proxy", "skills"}
	if len(got) != len(want) {
		t.Fatalf("Subsystems() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("Subsystems() = %v, want %v", got, want)
		}
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
