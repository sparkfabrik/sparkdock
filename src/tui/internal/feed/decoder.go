package feed

import (
	"bytes"
	"strings"
)

// Decoder turns a stream of raw output chunks into parsed Events. It buffers a
// partial trailing line across writes, emitting an Event per completed line.
// Use Flush at end-of-stream to emit any unterminated remainder.
type Decoder struct {
	buf []byte
}

// Write appends a chunk and returns the events for every newline-terminated
// line it completes.
func (d *Decoder) Write(p []byte) []Event {
	d.buf = append(d.buf, p...)
	var events []Event
	for {
		i := bytes.IndexByte(d.buf, '\n')
		if i < 0 {
			break
		}
		events = append(events, Parse(collapseCR(string(d.buf[:i]))))
		d.buf = d.buf[i+1:]
	}
	return events
}

// Flush emits any buffered, unterminated remainder as a final event.
func (d *Decoder) Flush() (Event, bool) {
	if len(d.buf) == 0 {
		return Event{}, false
	}
	e := Parse(collapseCR(string(d.buf)))
	d.buf = nil
	return e, true
}

// collapseCR resolves carriage returns within a single line the way a terminal
// would: each '\r' moves the cursor to column 0 and following characters
// overwrite in place. This turns in-place progress (e.g. git's
// "Receiving objects: 10%\r...100%") into just its final state, so single-line
// progress renders cleanly without a full terminal emulator.
func collapseCR(s string) string {
	if !strings.ContainsRune(s, '\r') {
		return s
	}
	var out []rune
	col := 0
	for _, r := range s {
		if r == '\r' {
			col = 0
			continue
		}
		if col < len(out) {
			out[col] = r
		} else {
			out = append(out, r)
		}
		col++
	}
	return string(out)
}
