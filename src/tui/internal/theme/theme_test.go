package theme

import "testing"

func TestGlowFactorEndpointsAreZero(t *testing.T) {
	for _, phase := range []float64{-0.5, 0, 1, 1.5} {
		if got := GlowFactor(phase); got != 0 {
			t.Errorf("GlowFactor(%v) = %v, want 0", phase, got)
		}
	}
}

func TestGlowFactorPeaksAtAttack(t *testing.T) {
	// The attack reaches full brightness (1.0) at phase 0.18; the decay only
	// falls from there, so 0.18 is the maximum over (0,1).
	peak := GlowFactor(0.18)
	if peak < 0.99 || peak > 1.01 {
		t.Fatalf("GlowFactor(0.18) = %v, want ~1", peak)
	}
	if mid := GlowFactor(0.6); mid >= peak {
		t.Errorf("decay GlowFactor(0.6) = %v should be below peak %v", mid, peak)
	}
	if early := GlowFactor(0.09); early <= 0 || early >= peak {
		t.Errorf("attack GlowFactor(0.09) = %v should be between 0 and peak", early)
	}
}

func TestGlowZeroIsBaseFullIsWhite(t *testing.T) {
	base := [3]int{0xFF, 0x87, 0x00}
	if got := Glow(base, 0); got != "#FF8700" {
		t.Errorf("Glow(base, 0) = %q, want #FF8700", got)
	}
	if got := Glow(base, 1); got != "#FFFFFF" {
		t.Errorf("Glow(base, 1) = %q, want #FFFFFF", got)
	}
}

func TestGlowClampsOutOfRange(t *testing.T) {
	base := [3]int{0x10, 0x20, 0x30}
	if got := Glow(base, -1); got != "#102030" {
		t.Errorf("Glow(base, -1) = %q, want base #102030", got)
	}
	if got := Glow(base, 2); got != "#FFFFFF" {
		t.Errorf("Glow(base, 2) = %q, want white #FFFFFF", got)
	}
}
