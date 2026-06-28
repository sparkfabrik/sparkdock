package feed

import "testing"

func TestParse_ControlMarkers(t *testing.T) {
	tests := []struct {
		name string
		line string
		want Event
	}{
		{"phase", "@@PHASE Packages", Event{Kind: KindPhase, Text: "Packages", Raw: "@@PHASE Packages"}},
		{"phase trims", "@@PHASE   HTTP Proxy  ", Event{Kind: KindPhase, Text: "HTTP Proxy", Raw: "@@PHASE   HTTP Proxy  "}},
		{"task", "@@TASK Install docker", Event{Kind: KindTask, Text: "Install docker", Raw: "@@TASK Install docker"}},
		{"done", "@@DONE", Event{Kind: KindDone, Raw: "@@DONE"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Parse(tt.line); got != tt.want {
				t.Errorf("Parse(%q) = %+v, want %+v", tt.line, got, tt.want)
			}
		})
	}
}

func TestParse_Stat(t *testing.T) {
	got := Parse("@@STAT ok=4 changed=2 failed=1 skipped=3")
	if got.Kind != KindStat {
		t.Fatalf("kind = %v, want KindStat", got.Kind)
	}
	want := Stats{OK: 4, Changed: 2, Failed: 1, Skipped: 3}
	if got.Stats != want {
		t.Errorf("stats = %+v, want %+v", got.Stats, want)
	}
}

func TestParse_StatOutOfOrderAndMalformed(t *testing.T) {
	got := Parse("@@STAT failed=2 bogus ok=x changed=5")
	want := Stats{OK: 0, Changed: 5, Failed: 2, Skipped: 0}
	if got.Stats != want {
		t.Errorf("stats = %+v, want %+v", got.Stats, want)
	}
}

func TestParse_ResultGlyphs(t *testing.T) {
	tests := []struct {
		line  string
		glyph Glyph
		text  string
	}{
		{"✓ docker present", GlyphOK, "docker present"},
		{"~ orbstack upgraded", GlyphChanged, "orbstack upgraded"},
		{"✗ dns failed: denied", GlyphFailed, "dns failed: denied"},
		{"» skipped step", GlyphSkipped, "skipped step"},
	}
	for _, tt := range tests {
		got := Parse(tt.line)
		if got.Kind != KindResult || got.Glyph != tt.glyph || got.Text != tt.text {
			t.Errorf("Parse(%q) = kind %v glyph %v text %q; want KindResult glyph %v text %q",
				tt.line, got.Kind, got.Glyph, got.Text, tt.glyph, tt.text)
		}
	}
}

func TestParse_Plain(t *testing.T) {
	got := Parse("PLAY [localhost] ***")
	if got.Kind != KindPlain || got.Text != "PLAY [localhost] ***" {
		t.Errorf("got %+v, want plain text preserved", got)
	}
}

func TestParse_RawPreserved(t *testing.T) {
	line := "  weird   spacing  "
	if got := Parse(line); got.Raw != line {
		t.Errorf("Raw = %q, want %q", got.Raw, line)
	}
}

func TestEvent_IsControl(t *testing.T) {
	control := []string{"@@PHASE x", "@@TASK y", "@@STAT ok=1", "@@DONE"}
	for _, l := range control {
		if !Parse(l).IsControl() {
			t.Errorf("Parse(%q).IsControl() = false, want true", l)
		}
	}
	content := []string{"✓ ok", "plain line"}
	for _, l := range content {
		if Parse(l).IsControl() {
			t.Errorf("Parse(%q).IsControl() = true, want false", l)
		}
	}
}
