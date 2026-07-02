package logview

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func keyMsg(s string) tea.KeyMsg {
	switch s {
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

func newWithFakes() (*Model, *[]string, *[]string) {
	var copied []string
	var written []string
	m := Model{
		home: "/home/test",
		clip: func(s string) error { copied = append(copied, s); return nil },
		write: func(path string, data []byte) error {
			written = append(written, path+"\n"+string(data))
			return nil
		},
	}
	return &m, &copied, &written
}

func TestOpen_WritesFileWithJoinedLines(t *testing.T) {
	m, _, written := newWithFakes()
	m.Open("Provisioning", []string{"line a", "line b"})
	if len(*written) != 1 {
		t.Fatalf("want 1 write, got %d", len(*written))
	}
	got := (*written)[0]
	if !strings.Contains(got, "/home/test/.cache/sparkdock/last-run.log") {
		t.Errorf("path wrong: %q", got)
	}
	if !strings.Contains(got, "line a\nline b") {
		t.Errorf("content wrong: %q", got)
	}
}

func TestCopy_InvokesClipboardAndMarksCopied(t *testing.T) {
	m, copied, _ := newWithFakes()
	m.Open("t", []string{"x", "y"})
	m2, _ := m.Update(keyMsg("y"))
	if len(*copied) != 1 || (*copied)[0] != "x\ny" {
		t.Fatalf("clipboard got %v", *copied)
	}
	if !m2.copied {
		t.Error("copied flag not set")
	}
}

func TestFirstOf_FallsThroughToNextClipboard(t *testing.T) {
	var got string
	clip := firstOf(
		func(string) error { return errBoom{} },
		func(s string) error { got = s; return nil },
	)
	if err := clip("text"); err != nil || got != "text" {
		t.Errorf("fallback clipboard not used; err=%v got=%q", err, got)
	}
}

func TestFirstOf_ReturnsLastError(t *testing.T) {
	clip := firstOf(
		func(string) error { return errBoom{} },
		func(string) error { return errBoom{} },
	)
	if err := clip("text"); err == nil {
		t.Error("want error when every clipboard fails")
	}
}

type errBoom struct{}

func (errBoom) Error() string { return "boom" }

func TestBack(t *testing.T) {
	m, _, _ := newWithFakes()
	for _, k := range []string{"esc", "q", "l"} {
		_, cmd := m.Update(keyMsg(k))
		if cmd == nil {
			t.Fatalf("%q produced no command", k)
		}
		if _, ok := cmd().(BackMsg); !ok {
			t.Errorf("%q did not emit BackMsg", k)
		}
	}
}

func TestLogPath_FallsBackWithoutHome(t *testing.T) {
	m := Model{home: ""}
	if !strings.HasSuffix(m.logPath(), "sparkdock-last-run.log") {
		t.Errorf("fallback path = %q", m.logPath())
	}
}
