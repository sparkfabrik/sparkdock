// Package feed parses the line-oriented protocol emitted by the sparkdock
// Ansible stdout callback. The protocol interleaves machine-readable control
// markers with human-readable content lines:
//
//	@@PHASE <name>                          start of a play/phase
//	@@TASK  <name>                          current task (status only)
//	@@STAT  ok=.. changed=.. failed=.. skipped=..
//	@@DONE                                  end of run
//	✓ / ~ / ✗ / » <text>                    content lines (ok/changed/failed/skipped)
//	<anything else>                         plain content line
//
// Parse is a pure function so it can be exhaustively unit-tested without a
// running Ansible process.
package feed

import (
	"strconv"
	"strings"
)

// Kind classifies a parsed line.
type Kind int

const (
	KindPlain  Kind = iota // content line, no recognised glyph
	KindResult             // content line with an ok/changed/failed/skipped glyph
	KindPhase              // @@PHASE
	KindTask               // @@TASK
	KindStat               // @@STAT
	KindDone               // @@DONE
)

// Glyph classifies a result content line.
type Glyph int

const (
	GlyphNone Glyph = iota
	GlyphOK
	GlyphChanged
	GlyphFailed
	GlyphSkipped
)

// Stats holds cumulative task tallies from an @@STAT marker.
type Stats struct {
	OK, Changed, Failed, Skipped int
}

// Event is the parsed representation of a single feed line.
type Event struct {
	Kind  Kind
	Glyph Glyph  // valid when Kind == KindResult
	Text  string // payload: phase/task name, or content text without the glyph
	Stats Stats  // valid when Kind == KindStat
	Raw   string // the original line, unmodified (used for the copyable log)
}

// IsControl reports whether the event is a machine marker rather than content.
func (e Event) IsControl() bool {
	return e.Kind == KindPhase || e.Kind == KindTask || e.Kind == KindStat || e.Kind == KindDone
}

const (
	prefixPhase = "@@PHASE "
	prefixTask  = "@@TASK "
	prefixStat  = "@@STAT "
	tokenDone   = "@@DONE"
)

// glyphPrefixes maps a leading rune+space to its Glyph. Order is irrelevant;
// each is a distinct two-byte-plus-space prefix.
var glyphPrefixes = []struct {
	prefix string
	glyph  Glyph
}{
	{"✓ ", GlyphOK},
	{"~ ", GlyphChanged},
	{"✗ ", GlyphFailed},
	{"» ", GlyphSkipped},
}

// Parse converts a single raw line into an Event. It never returns an error;
// unrecognised input becomes a KindPlain event carrying the verbatim text.
func Parse(line string) Event {
	switch {
	case line == tokenDone:
		return Event{Kind: KindDone, Raw: line}
	case strings.HasPrefix(line, prefixPhase):
		return Event{Kind: KindPhase, Text: strings.TrimSpace(line[len(prefixPhase):]), Raw: line}
	case strings.HasPrefix(line, prefixTask):
		return Event{Kind: KindTask, Text: strings.TrimSpace(line[len(prefixTask):]), Raw: line}
	case strings.HasPrefix(line, prefixStat):
		return Event{Kind: KindStat, Stats: parseStats(line[len(prefixStat):]), Raw: line}
	}
	for _, gp := range glyphPrefixes {
		if strings.HasPrefix(line, gp.prefix) {
			return Event{Kind: KindResult, Glyph: gp.glyph, Text: line[len(gp.prefix):], Raw: line}
		}
	}
	return Event{Kind: KindPlain, Text: line, Raw: line}
}

// parseStats reads "ok=.. changed=.. failed=.. skipped=.." in any order,
// ignoring malformed or unknown tokens.
func parseStats(s string) Stats {
	var st Stats
	for _, tok := range strings.Fields(s) {
		key, val, ok := strings.Cut(tok, "=")
		if !ok {
			continue
		}
		n, err := strconv.Atoi(val)
		if err != nil {
			continue
		}
		switch key {
		case "ok":
			st.OK = n
		case "changed":
			st.Changed = n
		case "failed":
			st.Failed = n
		case "skipped":
			st.Skipped = n
		}
	}
	return st
}
