// Package audio plays a short startup sound when the user clicks the splash
// logo, the way OpenCode plays a sound on its logo. It is best-effort and
// non-blocking: it never delays or blocks the UI and degrades to a silent
// no-op when disabled or unsupported.
//
// The sound is "spark-zap", a short synthesized rising sweep with a sub-bass
// body (generated with ffmpeg, no third-party license; see assets/NOTICE),
// embedded into the binary. Disable with SPARKDOCK_TUI_NO_AUDIO=1. Only macOS
// (via the built-in afplay) is supported; elsewhere it is a no-op.
package audio

import (
	_ "embed"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
)

//go:embed assets/spark-zap.mp3
var sound []byte

var (
	once     sync.Once
	filePath string
)

// Play plays the startup sound asynchronously. It returns immediately and never
// blocks; failures are swallowed.
func Play() {
	if !enabled() {
		return
	}
	path, err := soundFile()
	if err != nil {
		return
	}
	cmd := exec.Command("afplay", path)
	if err := cmd.Start(); err != nil {
		return
	}
	go func() { _ = cmd.Wait() }() // reap without blocking the caller
}

// enabled reports whether the sound should play: macOS, not disabled, afplay
// present, and an embedded asset exists.
func enabled() bool {
	if os.Getenv("SPARKDOCK_TUI_NO_AUDIO") != "" {
		return false
	}
	if runtime.GOOS != "darwin" {
		return false
	}
	if len(sound) == 0 {
		return false
	}
	_, err := exec.LookPath("afplay")
	return err == nil
}

// soundFile writes the embedded sound to a temp file once and returns its path.
func soundFile() (string, error) {
	var err error
	once.Do(func() {
		path := filepath.Join(os.TempDir(), "sparkdock-tui-logo.mp3")
		err = os.WriteFile(path, sound, 0o600)
		if err == nil {
			filePath = path
		}
	})
	if filePath == "" {
		return "", os.ErrNotExist
	}
	return filePath, nil
}
