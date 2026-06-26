package audio

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func TestChimeWAV_ValidHeader(t *testing.T) {
	w := chimeWAV()
	if len(w) < 44 {
		t.Fatalf("wav too short: %d bytes", len(w))
	}
	if !bytes.Equal(w[0:4], []byte("RIFF")) {
		t.Errorf("missing RIFF magic: %q", w[0:4])
	}
	if !bytes.Equal(w[8:12], []byte("WAVE")) {
		t.Errorf("missing WAVE magic: %q", w[8:12])
	}
	if !bytes.Equal(w[12:16], []byte("fmt ")) {
		t.Errorf("missing fmt chunk: %q", w[12:16])
	}
	// PCM format == 1
	if got := binary.LittleEndian.Uint16(w[20:22]); got != 1 {
		t.Errorf("audio format = %d, want 1 (PCM)", got)
	}
	// sample rate
	if got := binary.LittleEndian.Uint32(w[24:28]); got != sampleRate {
		t.Errorf("sample rate = %d, want %d", got, sampleRate)
	}
	// data chunk present
	if !bytes.Equal(w[36:40], []byte("data")) {
		t.Errorf("missing data chunk: %q", w[36:40])
	}
	// declared RIFF size matches body
	if got := binary.LittleEndian.Uint32(w[4:8]); int(got) != len(w)-8 {
		t.Errorf("RIFF size = %d, want %d", got, len(w)-8)
	}
}

func TestEnvelope_BoundsAndShape(t *testing.T) {
	n := 1000.0
	if v := envelope(0, n); v != 0 {
		t.Errorf("envelope at start = %v, want 0", v)
	}
	if v := envelope(n-1, n); v < 0 || v > 1 {
		t.Errorf("envelope near end = %v, want within [0,1]", v)
	}
	// peak (just after attack) should be near 1
	if v := envelope(0.02*n, n); v < 0.9 {
		t.Errorf("envelope at peak = %v, want ~1", v)
	}
}

func TestEnabled_DisabledByEnv(t *testing.T) {
	t.Setenv("SPARKDOCK_TUI_NO_AUDIO", "1")
	if enabled() {
		t.Error("audio should be disabled when SPARKDOCK_TUI_NO_AUDIO is set")
	}
}
