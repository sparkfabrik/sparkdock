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
		line := strings.TrimRight(string(d.buf[:i]), "\r")
		events = append(events, Parse(line))
		d.buf = d.buf[i+1:]
	}
	return events
}

// Flush emits any buffered, unterminated remainder as a final event.
func (d *Decoder) Flush() (Event, bool) {
	if len(d.buf) == 0 {
		return Event{}, false
	}
	e := Parse(strings.TrimRight(string(d.buf), "\r"))
	d.buf = nil
	return e, true
}
