package runner

import (
	"context"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// scriptBuilder returns a Builder that runs a shell script.
func scriptBuilder(script string) Builder {
	return func(ctx context.Context, _ Options) *exec.Cmd {
		return exec.CommandContext(ctx, "bash", "-c", script)
	}
}

// drain consumes all raw output and returns it joined with the final Result.
func drain(t *testing.T, h *Handle) (string, Result) {
	t.Helper()
	var sb strings.Builder
	for chunk := range h.Output {
		sb.Write(chunk)
	}
	select {
	case res := <-h.Done:
		return sb.String(), res
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for Done")
		return "", Result{}
	}
}

func TestStart_StreamsOutput(t *testing.T) {
	script := `printf '@@PHASE Packages\n'; printf '%s\n' '✓ docker present'; printf '@@DONE\n'`
	r := &Runner{Build: scriptBuilder(script)}
	h := r.Start(context.Background(), Options{})
	out, res := drain(t, h)

	if res.Err != nil {
		t.Fatalf("Result.Err = %v, want nil", res.Err)
	}
	for _, want := range []string{"@@PHASE Packages", "✓ docker present", "@@DONE"} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q; got:\n%s", want, out)
		}
	}
}

func TestStart_NonZeroExitReportsError(t *testing.T) {
	r := &Runner{Build: scriptBuilder(`printf 'boom\n'; exit 2`)}
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
	r := &Runner{Build: scriptBuilder(`printf 'slow\n'; sleep 1; printf 'done\n'`)}
	h := r.Start(context.Background(), Options{})
	<-h.Output // first chunk
	h.Cancel()
	for range h.Output { // drain the rest
	}
	res := <-h.Done
	if !res.Canceled {
		t.Errorf("Result.Canceled = false, want true")
	}
}

func TestAnsibleBuilder_Flags(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{
		Playbook:  "playbook.yml",
		Tags:      []string{"docker", "cask"},
		ForceFail: true,
	})
	joined := ""
	for _, a := range cmd.Args {
		joined += a + " "
	}
	if !contains(joined, "--tags") || !contains(joined, "docker,cask") {
		t.Errorf("argv missing tags: %v", cmd.Args)
	}
	if !contains(joined, "force_fail=true") {
		t.Errorf("argv missing force_fail: %v", cmd.Args)
	}
	// no become password env, and no --ask-become-pass (sudo is primed instead)
	for _, kv := range cmd.Env {
		if contains(kv, "ANSIBLE_BECOME_PASS") {
			t.Errorf("env must not carry a become password: %q", kv)
		}
	}
}

func TestAnsibleBuilder_SudoAsksBecomePass(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{Playbook: "playbook.yml", Sudo: true})
	joined := ""
	for _, a := range cmd.Args {
		joined += a + " "
	}
	if !contains(joined, "--ask-become-pass") {
		t.Errorf("sudo run must add --ask-become-pass: %v", cmd.Args)
	}
	// no password anywhere in env or argv
	for _, kv := range cmd.Env {
		if contains(kv, "ANSIBLE_BECOME_PASS") {
			t.Errorf("env must not carry a become password: %q", kv)
		}
	}
}

func TestAnsibleBuilder_SelfUpdateWrapsInGuardedGit(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{
		Playbook:   "ansible/macos.yml",
		Dir:        "/opt/sparkdock",
		Sudo:       true,
		SelfUpdate: true,
	})
	if cmd.Args[0] != "bash" || cmd.Args[1] != "-c" {
		t.Fatalf("self-update run must be a bash -c wrapper: %v", cmd.Args)
	}
	script := cmd.Args[2]
	// The git step is guarded to the /opt install so a dev checkout is never reset.
	if !contains(script, `"$SPARKDOCK_DIR" = /opt/sparkdock`) {
		t.Errorf("self-update script must guard on /opt/sparkdock: %q", script)
	}
	if !contains(script, "git fetch") || !contains(script, "reset --hard") {
		t.Errorf("self-update script must fetch and reset: %q", script)
	}
	if !contains(script, `exec ansible-playbook "$@"`) {
		t.Errorf("self-update script must exec ansible-playbook with $@: %q", script)
	}
	// The playbook and become flag travel as positional args ($@), not shell-spliced.
	joined := ""
	for _, a := range cmd.Args {
		joined += a + " "
	}
	if !contains(joined, "ansible/macos.yml") || !contains(joined, "--ask-become-pass") {
		t.Errorf("ansible args missing from positional args: %v", cmd.Args)
	}
	var hasDir bool
	for _, kv := range cmd.Env {
		if kv == "SPARKDOCK_DIR=/opt/sparkdock" {
			hasDir = true
		}
		if contains(kv, "ANSIBLE_BECOME_PASS") {
			t.Errorf("env must not carry a become password: %q", kv)
		}
	}
	if !hasDir {
		t.Errorf("env must carry SPARKDOCK_DIR for the guard: %v", cmd.Env)
	}
}

func TestAnsibleBuilder_NoSelfUpdateRunsAnsibleDirectly(t *testing.T) {
	cmd := AnsibleBuilder(context.Background(), Options{Playbook: "ansible/macos.yml"})
	if cmd.Args[0] != "ansible-playbook" {
		t.Errorf("without SelfUpdate the command must be ansible-playbook directly: %v", cmd.Args)
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

	var out strings.Builder
	for chunk := range h.Output {
		out.Write(chunk)
	}
	<-h.Done
	if !contains(out.String(), "answered:hunter2") {
		t.Errorf("answer not delivered to the process; output:\n%s", out.String())
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
