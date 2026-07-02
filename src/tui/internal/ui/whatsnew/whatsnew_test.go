package whatsnew

import (
	"errors"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

const doc = `# Changelog

## [Unreleased]

### Added

- A shiny new page with a very long descriptive sentence that should wrap onto more than one line when the page is narrow enough
`

func openModel() Model {
	m := New(func() ([]byte, error) { return []byte(doc), nil })
	m.SetSize(60, 20)
	return m.Open()
}

func TestOpen_RendersUnreleased(t *testing.T) {
	v := openModel().View()
	for _, want := range []string{"what's new", "Added", "shiny new page"} {
		if !strings.Contains(v, want) {
			t.Errorf("view missing %q", want)
		}
	}
}

func TestOpen_SourceError(t *testing.T) {
	m := New(func() ([]byte, error) { return nil, errors.New("gone") })
	m.SetSize(60, 20)
	if v := m.Open().View(); !strings.Contains(v, "gone") {
		t.Errorf("view must surface the read error, got:\n%s", v)
	}
}

func TestEscEmitsBack(t *testing.T) {
	m := openModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd == nil {
		t.Fatal("esc must emit a command")
	}
	if _, ok := cmd().(BackMsg); !ok {
		t.Error("esc must emit BackMsg")
	}
}

func TestWrap(t *testing.T) {
	segs := wrap("aa bb cc dd", 5)
	if len(segs) != 2 || segs[0] != "aa bb" || segs[1] != "cc dd" {
		t.Errorf("wrap = %q, want [\"aa bb\", \"cc dd\"]", segs)
	}
	for _, s := range segs {
		if len(s) > 5 {
			t.Errorf("segment %q exceeds width", s)
		}
	}
}
