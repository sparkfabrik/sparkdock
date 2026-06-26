// Package audio plays a short branded startup chime, the way OpenCode plays a
// sound on launch. It is best-effort and non-blocking: it never delays or
// blocks the UI, degrades to a silent no-op when disabled or unsupported, and
// synthesises the sound in-process so there is no external asset to ship.
//
// Disable with SPARKDOCK_TUI_NO_AUDIO=1. Only macOS (via the built-in afplay)
// is supported; elsewhere it is a no-op.
package audio

import (
	"encoding/binary"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
)

const (
	sampleRate = 44100
	noteDur    = 0.16 // seconds per note
)

// chime is the two-note startup sound, synthesised once.
var (
	once     sync.Once
	filePath string
)

// Play plays the startup chime asynchronously. It returns immediately and never
// blocks; failures are swallowed.
func Play() {
	if !enabled() {
		return
	}
	path, err := soundFile()
	if err != nil {
		return
	}
	// Detached and fire-and-forget: do not wait, do not block the UI.
	cmd := exec.Command("afplay", path)
	_ = cmd.Start()
	go func() { _ = cmd.Wait() }() // reap without blocking the caller
}

// enabled reports whether the chime should play: macOS, not disabled, afplay
// present.
func enabled() bool {
	if os.Getenv("SPARKDOCK_TUI_NO_AUDIO") != "" {
		return false
	}
	if runtime.GOOS != "darwin" {
		return false
	}
	_, err := exec.LookPath("afplay")
	return err == nil
}

// soundFile writes the synthesised chime to a temp file once and returns its
// path.
func soundFile() (string, error) {
	var err error
	once.Do(func() {
		path := filepath.Join(os.TempDir(), "sparkdock-tui-chime.wav")
		err = os.WriteFile(path, chimeWAV(), 0o600)
		if err == nil {
			filePath = path
		}
	})
	if filePath == "" {
		return "", os.ErrNotExist
	}
	return filePath, nil
}

// chimeWAV synthesises a soft two-note (E5 -> A5) chime as a 16-bit mono PCM
// WAV, each note enveloped to avoid clicks.
func chimeWAV() []byte {
	freqs := []float64{659.25, 880.0} // E5, A5
	perNote := int(noteDur * sampleRate)
	samples := make([]int16, 0, perNote*len(freqs))
	for _, f := range freqs {
		for i := 0; i < perNote; i++ {
			t := float64(i) / sampleRate
			env := envelope(float64(i), float64(perNote))
			v := env * 0.35 * math.Sin(2*math.Pi*f*t)
			samples = append(samples, int16(v*math.MaxInt16))
		}
	}
	return encodeWAV(samples)
}

// envelope is a short attack and a long decay so notes fade smoothly.
func envelope(i, n float64) float64 {
	const attack = 0.02
	pos := i / n
	if pos < attack {
		return pos / attack
	}
	return 1 - (pos-attack)/(1-attack) // linear decay to 0
}

// encodeWAV wraps mono 16-bit PCM samples in a canonical WAV container.
func encodeWAV(samples []int16) []byte {
	const (
		numChannels   = 1
		bitsPerSample = 16
	)
	dataLen := len(samples) * 2
	byteRate := sampleRate * numChannels * bitsPerSample / 8
	blockAlign := numChannels * bitsPerSample / 8

	buf := make([]byte, 0, 44+dataLen)
	le := binary.LittleEndian
	put32 := func(v uint32) { var b [4]byte; le.PutUint32(b[:], v); buf = append(buf, b[:]...) }
	put16 := func(v uint16) { var b [2]byte; le.PutUint16(b[:], v); buf = append(buf, b[:]...) }

	buf = append(buf, "RIFF"...)
	put32(uint32(36 + dataLen))
	buf = append(buf, "WAVE"...)
	buf = append(buf, "fmt "...)
	put32(16)              // PCM fmt chunk size
	put16(1)               // audio format: PCM
	put16(numChannels)     //
	put32(sampleRate)      //
	put32(uint32(byteRate))
	put16(uint16(blockAlign))
	put16(bitsPerSample)
	buf = append(buf, "data"...)
	put32(uint32(dataLen))
	for _, s := range samples {
		put16(uint16(s))
	}
	return buf
}
