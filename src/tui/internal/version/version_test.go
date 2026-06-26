package version

import (
	"errors"
	"testing"
	"time"
)

func TestRead_FullyConfigured(t *testing.T) {
	r := &Reader{
		Root: "/opt/sparkdock",
		Git: func(dir string, args ...string) (string, error) {
			if dir != "/opt/sparkdock" {
				t.Fatalf("git dir = %q", dir)
			}
			switch args[0] + " " + args[1] {
			case "rev-parse --short":
				return "e3d9bbe", nil
			case "rev-parse --abbrev-ref":
				return "master", nil
			case "log -1":
				return "2026-06-26T13:30:57+02:00", nil
			}
			return "", errors.New("unexpected")
		},
		ReadFile: func(path string) ([]byte, error) {
			return []byte("2026-06-26 16:02:54\n"), nil
		},
	}
	got := r.Read()
	if !got.Configured || got.Commit != "e3d9bbe" || got.Branch != "master" {
		t.Fatalf("got %+v", got)
	}
	if got.Short() != "e3d9bbe (master)" {
		t.Errorf("Short() = %q", got.Short())
	}
	if got.LastCommit.IsZero() || got.LastUpdate.IsZero() {
		t.Errorf("timestamps not parsed: %+v", got)
	}
}

func TestRead_NotConfigured(t *testing.T) {
	r := &Reader{
		Git: func(string, ...string) (string, error) { return "", errors.New("not a repo") },
	}
	got := r.Read()
	if got.Configured {
		t.Errorf("Configured = true, want false")
	}
	if got.Short() != "not installed" {
		t.Errorf("Short() = %q, want %q", got.Short(), "not installed")
	}
}

func TestRead_PartialDegradation(t *testing.T) {
	// commit resolves but branch/log/file do not; must stay Configured.
	r := &Reader{
		Git: func(dir string, args ...string) (string, error) {
			if args[0] == "rev-parse" && args[1] == "--short" {
				return "abc1234", nil
			}
			return "", errors.New("nope")
		},
	}
	got := r.Read()
	if !got.Configured || got.Commit != "abc1234" || got.Branch != "" {
		t.Errorf("got %+v", got)
	}
	if !got.LastCommit.IsZero() {
		t.Errorf("LastCommit should be zero, got %v", got.LastCommit)
	}
	_ = time.Now
}
