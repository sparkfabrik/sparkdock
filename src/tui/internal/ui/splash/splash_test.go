package splash

import (
	"testing"
	"time"
)

// A tick mid-flare advances the brightness and keeps the loop running.
func TestGlowTickMidFlareAdvancesAndReschedules(t *testing.T) {
	t0 := time.Unix(1000, 0)
	m := Model{glowing: true, glowStart: t0}

	m, cmd := m.Update(glowTickMsg(t0.Add(350 * time.Millisecond)))

	if !m.glowing {
		t.Fatal("flare should still be running mid-envelope")
	}
	if m.glowFactor <= 0 {
		t.Errorf("glowFactor = %v, want > 0 mid-flare", m.glowFactor)
	}
	if cmd == nil {
		t.Error("expected a reschedule command while glowing")
	}
}

// A tick past the duration ends the flare and stops the loop.
func TestGlowTickPastDurationEnds(t *testing.T) {
	t0 := time.Unix(1000, 0)
	m := Model{glowing: true, glowStart: t0}

	m, cmd := m.Update(glowTickMsg(t0.Add(glowDur + 50*time.Millisecond)))

	if m.glowing {
		t.Error("flare should have ended past glowDur")
	}
	if m.glowFactor != 0 {
		t.Errorf("glowFactor = %v, want 0 after the flare", m.glowFactor)
	}
	if cmd != nil {
		t.Error("expected no further reschedule after the flare ends")
	}
}

// A stray tick after the flare ended is ignored and does not restart the loop.
func TestGlowTickWhenNotGlowingIsNoop(t *testing.T) {
	m := Model{glowing: false}

	m, cmd := m.Update(glowTickMsg(time.Unix(2000, 0)))

	if m.glowing {
		t.Error("a tick must not start a flare on its own")
	}
	if cmd != nil {
		t.Error("a tick while not glowing should not reschedule")
	}
}
