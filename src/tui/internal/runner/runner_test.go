package runner

import (
	"context"
	"os/exec"
	"testing"
	"time"

	"github.com/sparkfabrik/sparkdock/src/tui/internal/feed"
)

// scriptBuilder returns a Builder that runs a shell script emitting a fixed feed.
func scriptBuilder(script string) Builder {
	return func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, "bash", "-c", script)
	}
}

func drain(t *testing.T, h *Handle) ([]feed.Event, Result) {
	t.Helper()
	var events []feed.Event
	for e := range h.Events {
		events = append(events, e)
	}
	select {
	case res := <-h.Done:
		return events, res
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for Done")
		return nil, Result{}
	}
}

func TestStart_StreamsParsedEvents(t *testing.T) {
	script := `printf '@@PHASE Packages\n'; printf '%s\n' '✓ docker present'; printf '@@STAT ok=1 changed=0 failed=0 skipped=0\n'; printf '@@DONE\n'`
	r := &Runner{Build: scriptBuilder(script)}
	h := r.Start(context.Background(), Options{})
	events, res := drain(t, h)

	if res.Err != nil {
		t.Fatalf("Result.Err = %v, want nil", res.Err)
	}
	if len(events) != 4 {
		t.Fatalf("got %d events, want 4: %+v", len(events), events)
	}
	if events[0].Kind != feed.KindPhase || events[0].Text != "Packages" {
		t.Errorf("event 0 = %+v", events[0])
	}
	if events[1].Kind != feed.KindResult || events[1].Glyph != feed.GlyphOK {
		t.Errorf("event 1 = %+v", events[1])
	}
	if events[2].Kind != feed.KindStat || events[2].Stats.OK != 1 {
		t.Errorf("event 2 = %+v", events[2])
	}
	if events[3].Kind != feed.KindDone {
		t.Errorf("event 3 = %+v", events[3])
	}
}

func TestStart_NonZeroExitReportsError(t *testing.T) {
	r := &Runner{Build: scriptBuilder(`printf '✗ boom\n'; exit 2`)}
	h := r.Start(context.Background(), Options{})
	_, res := drain(t, h)
	if res.Err == nil {
		t.Fatal("Result.Err = nil, want non-nil for exit 2")
	}
}

func TestStart_FailedBuildStillCompletes(t *testing.T) {
	r := &Runner{Build: func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, "definitely-not-a-real-binary-xyz")
	}}
	h := r.Start(context.Background(), Options{})
	_, res := drain(t, h)
	if res.Err == nil {
		t.Fatal("Result.Err = nil, want start error")
	}
}

func TestCancel_MarksCanceled(t *testing.T) {
	// long-running script; cancel mid-flight.
	r := &Runner{Build: scriptBuilder(`printf '@@PHASE Slow\n'; sleep 1; printf '@@DONE\n'`)}
	h := r.Start(context.Background(), Options{})
	// read the first event, then cancel
	<-h.Events
	h.Cancel()
	// drain the rest
	for range h.Events {
	}
	res := <-h.Done
	if !res.Canceled {
		t.Errorf("Result.Canceled = false, want true")
	}
}

func TestAnsibleBuilder_Flags(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{
		Playbook:      "playbook.yml",
		Tags:          []string{"docker", "cask"},
		AskBecomePass: true,
		ForceFail:     true,
	})
	joined := ""
	for _, a := range cmd.Args {
		joined += a + " "
	}
	if !contains(joined, "--tags") || !contains(joined, "docker,cask") {
		t.Errorf("argv missing tags: %v", cmd.Args)
	}
	if !contains(joined, "--ask-become-pass") {
		t.Errorf("argv missing --ask-become-pass: %v", cmd.Args)
	}
	if !contains(joined, "force_fail=true") {
		t.Errorf("argv missing force_fail: %v", cmd.Args)
	}
	// no password anywhere; the env carries no become secret
	for _, kv := range cmd.Env {
		if contains(kv, "ANSIBLE_BECOME_PASS") {
			t.Errorf("env must not carry a become password: %q", kv)
		}
	}
}

func TestStart_DetectsPasswordPromptAndAnswers(t *testing.T) {
	// Script prints a prompt with no newline, reads a line, echoes it back.
	script := `printf 'Password: '; read -r p; printf '\n@@TASK got\n'; printf '%s\n' "answered:$p"; printf '@@DONE\n'`
	r := &Runner{Build: scriptBuilder(script)}
	h := r.Start(context.Background(), Options{})

	// wait for the prompt, then answer
	select {
	case p := <-h.Prompts:
		if !contains(p, "Password:") {
			t.Fatalf("prompt = %q, want it to contain Password:", p)
		}
		h.Answer("hunter2")
	case <-time.After(5 * time.Second):
		t.Fatal("no prompt received")
	}

	var got []feed.Event
	for e := range h.Events {
		got = append(got, e)
	}
	<-h.Done
	var sawAnswer bool
	for _, e := range got {
		if contains(e.Raw, "answered:hunter2") {
			sawAnswer = true
		}
	}
	if !sawAnswer {
		t.Errorf("answer not delivered to the process; events=%v", got)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func TestIsBecomeAuthFailure(t *testing.T) {
	if !IsBecomeAuthFailure([]string{"ok", "sudo: a password is required", "more"}) {
		t.Error("should detect become auth failure")
	}
	if !IsBecomeAuthFailure([]string{"✗ task: Incorrect sudo password"}) {
		t.Error("should detect incorrect sudo password")
	}
	if IsBecomeAuthFailure([]string{"✓ docker present", "PLAY RECAP"}) {
		t.Error("false positive on clean output")
	}
}

func TestAnsibleBuilder_PassesDevEnvDir(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{Dir: "/tmp/checkout", Playbook: "ansible/macos.yml"})
	joined := ""
	for _, a := range cmd.Args {
		joined += a + " "
	}
	if !contains(joined, "-e dev_env_dir=/tmp/checkout") {
		t.Errorf("argv missing dev_env_dir override: %v", cmd.Args)
	}
	if cmd.Dir != "/tmp/checkout" {
		t.Errorf("cmd.Dir = %q, want /tmp/checkout", cmd.Dir)
	}
}
