// Package changelog extracts the Unreleased section from the repository's Keep
// a Changelog document for the TUI's what's-new page. Parsing is pure and
// line-oriented; rendering (styles, wrapping) is the page's concern.
package changelog

import "strings"

// Unreleased returns the lines between the "## [Unreleased]" heading and the
// next "## " heading, with leading and trailing blank lines removed. A missing
// section yields nil.
func Unreleased(md string) []string {
	var out []string
	in := false
	for _, ln := range strings.Split(md, "\n") {
		if strings.HasPrefix(ln, "## ") {
			if in {
				break
			}
			in = strings.Contains(ln, "[Unreleased]")
			continue
		}
		if in {
			out = append(out, strings.TrimRight(ln, " \t"))
		}
	}
	return trimBlank(out)
}

func trimBlank(lines []string) []string {
	start, end := 0, len(lines)
	for start < end && lines[start] == "" {
		start++
	}
	for end > start && lines[end-1] == "" {
		end--
	}
	if start == end {
		return nil
	}
	return lines[start:end]
}
