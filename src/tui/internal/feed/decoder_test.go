package feed

import "testing"

func TestDecoder_SplitsAcrossChunks(t *testing.T) {
	var d Decoder
	if ev := d.Write([]byte("@@PHASE Pack")); len(ev) != 0 {
		t.Fatalf("partial line should emit nothing, got %d", len(ev))
	}
	ev := d.Write([]byte("ages\n✓ docker\n@@DON"))
	if len(ev) != 2 {
		t.Fatalf("got %d events, want 2", len(ev))
	}
	if ev[0].Kind != KindPhase || ev[0].Text != "Packages" {
		t.Errorf("event 0 = %+v", ev[0])
	}
	if ev[1].Kind != KindResult || ev[1].Glyph != GlyphOK {
		t.Errorf("event 1 = %+v", ev[1])
	}
	// the trailing "@@DON" is buffered until completed
	e, ok := d.Flush()
	if !ok || e.Text != "@@DON" {
		t.Errorf("flush = %+v ok=%v", e, ok)
	}
}

func TestDecoder_StripsCarriageReturn(t *testing.T) {
	var d Decoder
	ev := d.Write([]byte("✓ done\r\n"))
	if len(ev) != 1 || ev[0].Text != "done" {
		t.Errorf("got %+v, want one result 'done' without CR", ev)
	}
}

func TestDecoder_FlushEmpty(t *testing.T) {
	var d Decoder
	if _, ok := d.Flush(); ok {
		t.Error("flush on empty buffer should report false")
	}
}
