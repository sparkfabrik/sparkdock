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

func checkAll(c CmdChecker) map[string]Subsystem {
	byKey := map[string]Subsystem{}
	for _, key := range c.Subsystems() {
		byKey[key] = c.CheckOne(context.Background(), key)
	}
	return byKey
}

func TestCheckOne_MapsExitCodesAndBrewCount(t *testing.T) {
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
	byKey := checkAll(c)
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
	want := []string{"sparkdock", "brew", "http-proxy", "skills", "doctor"}
	if len(got) != len(want) {
		t.Fatalf("Subsystems() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("Subsystems() = %v, want %v", got, want)
		}
	}
}

func TestCheckOne_BrewUpToDate(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{"outdated": {Stdout: "\n  \n"}}),
	}
	s := c.CheckOne(context.Background(), "brew")
	if s.Health != OK || s.Detail != "up to date" {
		t.Errorf("brew = %+v, want OK 'up to date'", s)
	}
}

func TestCheckOne_ErrorsBecomeUnknown(t *testing.T) {
	c := CmdChecker{
		Run: fakeRunner(map[string]CommandResult{
			"sparkdock": {Err: errors.New("boom")}, "http-proxy": {ExitCode: 1},
			"skills": {ExitCode: 1}, "outdated": {Err: errors.New("no brew")},
		}),
	}
	byKey := checkAll(c)
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

// --- macOS doctor row --------------------------------------------------------
//
// The contract between the shell backend and this row is one line on stdout.
// Everything the script logs goes to stderr, so these tests feed only that line.

func doctorChecker(res CommandResult) CmdChecker {
	return CmdChecker{
		DoctorBin: "macos-doctor",
		Run:       fakeRunner(map[string]CommandResult{"count": res}),
	}
}

func TestCheckOne_DoctorFindings(t *testing.T) {
	c := doctorChecker(CommandResult{
		Stdout: "MACOS_DOCTOR_STATUS: findings=4 cruft=1 warn=3 info=0 checks=8 skipped=0 failed=0 ids=apfs-snapshots,brew-health\n",
	})
	got := c.CheckOne(context.Background(), "doctor")
	if got.Health != Stale {
		t.Errorf("health = %v, want Stale", got.Health)
	}
	if got.Detail != "4 finding(s): apfs-snapshots, brew-health" {
		t.Errorf("detail = %q, want %q", got.Detail, "4 finding(s): apfs-snapshots, brew-health")
	}
}

func TestCheckOne_DoctorClean(t *testing.T) {
	c := doctorChecker(CommandResult{
		Stdout: "MACOS_DOCTOR_STATUS: findings=0 cruft=0 warn=0 info=0 checks=3 skipped=5 failed=0 ids=\n",
	})
	got := c.CheckOne(context.Background(), "doctor")
	if got.Health != OK || got.Detail != "no findings" {
		t.Errorf("got %+v, want OK 'no findings'", got)
	}
}

// A findings count above the summarize limit must not flood the row.
func TestCheckOne_DoctorSummarizesIDs(t *testing.T) {
	c := doctorChecker(CommandResult{
		Stdout: "MACOS_DOCTOR_STATUS: findings=9 ids=a,b,c,d\n",
	})
	got := c.CheckOne(context.Background(), "doctor")
	if got.Detail != "9 finding(s): a, b +2 more" {
		t.Errorf("detail = %q, want %q", got.Detail, "9 finding(s): a, b +2 more")
	}
}

// A backend that crashed prints no status line. That must read as Unknown with
// the cause named, never as a clean bill of health.
func TestCheckOne_DoctorNoStatusLine(t *testing.T) {
	c := doctorChecker(CommandResult{Stderr: "run.sh: line 4: syntax error", ExitCode: 2})
	got := c.CheckOne(context.Background(), "doctor")
	if got.Health != Unknown {
		t.Fatalf("health = %v, want Unknown", got.Health)
	}
	if got.Detail == "no findings" {
		t.Fatal("a missing status line must never report as clean")
	}
}

// An unset DoctorBin means the caller did not wire the row up. Report that
// rather than running an empty command.
func TestCheckOne_DoctorUnconfigured(t *testing.T) {
	c := CmdChecker{Run: fakeRunner(nil)}
	got := c.CheckOne(context.Background(), "doctor")
	if got.Health != Unconfigured {
		t.Errorf("health = %v, want Unconfigured", got.Health)
	}
}

func TestParseDoctorStatus_Malformed(t *testing.T) {
	for _, in := range []string{
		"",
		"some unrelated output\n",
		"MACOS_DOCTOR_STATUS: findings=notanumber\n",
	} {
		if _, _, ok := parseDoctorStatus(in); ok {
			t.Errorf("parseDoctorStatus(%q) ok = true, want false", in)
		}
	}
}
