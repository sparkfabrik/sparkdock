package audio

import "testing"

func TestSoundEmbedded(t *testing.T) {
	if len(sound) == 0 {
		t.Fatal("embedded sound is empty")
	}
	// MP3 files start with an ID3 tag ("ID3") or an MPEG frame sync (0xFF).
	if !(sound[0] == 'I' && sound[1] == 'D' && sound[2] == '3') && sound[0] != 0xFF {
		t.Errorf("embedded sound does not look like an MP3: % x", sound[:3])
	}
}

func TestEnabled_DisabledByEnv(t *testing.T) {
	t.Setenv("SPARKDOCK_TUI_NO_AUDIO", "1")
	if enabled() {
		t.Error("audio should be disabled when SPARKDOCK_TUI_NO_AUDIO is set")
	}
}
