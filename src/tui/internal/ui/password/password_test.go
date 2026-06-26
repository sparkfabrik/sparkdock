package password

import (
	"testing"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// key builds a KeyMsg for a named key or a rune.
func key(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

func msgOf(cmd tea.Cmd) tea.Msg {
	if cmd == nil {
		return nil
	}
	return cmd()
}

func TestSubmit_NonEmptyEmitsPassword(t *testing.T) {
	m := New()
	m.input.SetValue("hunter2")
	_, cmd := m.Update(key("enter"))
	sub, ok := msgOf(cmd).(SubmitMsg)
	if !ok {
		t.Fatalf("want SubmitMsg, got %T", msgOf(cmd))
	}
	if sub.Password != "hunter2" {
		t.Errorf("password = %q, want hunter2", sub.Password)
	}
}

func TestSubmit_EmptyRejected(t *testing.T) {
	m := New()
	m.input.SetValue("   ")
	m2, cmd := m.Update(key("enter"))
	if cmd != nil {
		t.Errorf("empty submit should not emit a command")
	}
	if m2.errMsg == "" {
		t.Error("empty submit should set an error message")
	}
}

func TestCancel(t *testing.T) {
	m := New()
	_, cmd := m.Update(key("esc"))
	if _, ok := msgOf(cmd).(CancelMsg); !ok {
		t.Fatalf("want CancelMsg, got %T", msgOf(cmd))
	}
}

func TestPrompt_ResetsValueAndError(t *testing.T) {
	m := New()
	m.input.SetValue("stale")
	m.errMsg = "old"
	m.Prompt("Run full provisioning", "Incorrect password, try again")
	if m.input.Value() != "" {
		t.Errorf("value not reset: %q", m.input.Value())
	}
	if m.errMsg != "Incorrect password, try again" {
		t.Errorf("errMsg = %q", m.errMsg)
	}
}

func TestEchoMasked(t *testing.T) {
	m := New()
	if m.input.EchoMode != textinput.EchoPassword {
		t.Error("input must mask the password")
	}
}
