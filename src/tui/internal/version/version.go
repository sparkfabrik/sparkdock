// Package version reports the installed sparkdock revision. Sparkdock has no
// semver releases; it is identified by the git commit and branch of its install
// directory (default /opt/sparkdock), plus last-commit and last-update times.
package version

import (
	"os/exec"
	"strings"
	"time"
)

// Info describes the installed revision. Configured is false when root is not a
// usable git checkout (e.g. running from source, or not installed).
type Info struct {
	Commit     string
	Branch     string
	LastCommit time.Time
	LastUpdate time.Time
	Configured bool
}

// Short renders the canonical "<commit> (<branch>)" label, never a semver.
func (i Info) Short() string {
	if !i.Configured {
		return "not installed"
	}
	return i.Commit + " (" + i.Branch + ")"
}

// gitFunc runs git in dir and returns trimmed stdout. Injected for testing.
type gitFunc func(dir string, args ...string) (string, error)

// readFileFunc reads a file's contents. Injected for testing.
type readFileFunc func(path string) ([]byte, error)

// Reader resolves version info for a root directory. Side effects (git, file
// reads) are injected so Read is unit-testable without a real repository.
type Reader struct {
	Root     string
	Git      gitFunc
	ReadFile readFileFunc
	Now      func() time.Time
}

// NewReader returns a Reader wired to the real git binary and filesystem.
func NewReader(root string) *Reader {
	return &Reader{
		Root: root,
		Git:  execGit,
		Now:  time.Now,
	}
}

// Read collects the revision info, degrading gracefully: any missing piece
// leaves its zero value rather than failing the whole read.
func (r *Reader) Read() Info {
	commit, err := r.Git(r.Root, "rev-parse", "--short", "HEAD")
	if err != nil {
		return Info{Configured: false}
	}
	info := Info{Commit: commit, Configured: true}
	if branch, err := r.Git(r.Root, "rev-parse", "--abbrev-ref", "HEAD"); err == nil {
		info.Branch = branch
	}
	if iso, err := r.Git(r.Root, "log", "-1", "--format=%cI"); err == nil {
		if t, err := time.Parse(time.RFC3339, iso); err == nil {
			info.LastCommit = t
		}
	}
	if r.ReadFile != nil {
		if b, err := r.ReadFile(r.Root + "/.last_update"); err == nil {
			if t, err := time.Parse("2006-01-02 15:04:05", strings.TrimSpace(string(b))); err == nil {
				info.LastUpdate = t
			}
		}
	}
	return info
}

func execGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
