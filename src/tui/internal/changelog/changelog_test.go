package changelog

import (
	"strings"
	"testing"
)

const sample = `# Changelog

Intro prose.

## [Unreleased]

### Added

- New recipe browser
- Faster status

### Fixed

- PTY resize

## [1.0.0] - 2026-01-01

### Added

- Old release entry
`

func TestUnreleased_ExtractsSection(t *testing.T) {
	got := Unreleased(sample)
	joined := strings.Join(got, "\n")
	for _, want := range []string{"### Added", "New recipe browser", "### Fixed", "PTY resize"} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing %q in:\n%s", want, joined)
		}
	}
	if strings.Contains(joined, "Old release entry") {
		t.Errorf("released entries must not leak in:\n%s", joined)
	}
	if got[0] == "" || got[len(got)-1] == "" {
		t.Error("blank edges must be trimmed")
	}
}

func TestUnreleased_MissingSection(t *testing.T) {
	if got := Unreleased("# Changelog\n\n## [1.0.0]\n- x\n"); got != nil {
		t.Errorf("want nil for a document without Unreleased, got %v", got)
	}
}
