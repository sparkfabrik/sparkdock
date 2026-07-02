// Package recipes lists the sjust recipes a user can run from the TUI. It
// shells out to `just --dump` for the machine-readable catalog (never parsing
// justfile syntax itself) and keeps only public recipes that are runnable
// without arguments. Parsing is a pure function so it is unit-tested against
// canned dumps.
package recipes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Recipe is one runnable sjust recipe.
type Recipe struct {
	Name  string
	Doc   string
	Group string
}

// Loader fetches the recipe catalog; injected so the browser page is testable
// without a just binary.
type Loader func(ctx context.Context) ([]Recipe, error)

// Load runs `just --dump` against the install's sjust justfile and parses the
// catalog.
func Load(ctx context.Context, root string) ([]Recipe, error) {
	justfile := filepath.Join(root, "sjust", "justfile")
	out, err := exec.CommandContext(ctx, "just",
		"--dump", "--dump-format", "json", "--justfile", justfile).Output()
	if err != nil {
		// Output captures stderr on the exit error; it carries the actionable
		// reason (missing justfile, parse error), so surface its first line.
		var ee *exec.ExitError
		if errors.As(err, &ee) && len(ee.Stderr) > 0 {
			line, _, _ := strings.Cut(strings.TrimSpace(string(ee.Stderr)), "\n")
			return nil, fmt.Errorf("just --dump failed: %s", line)
		}
		return nil, fmt.Errorf("just --dump failed: %w", err)
	}
	return Parse(out)
}

// dump mirrors the fragment of `just --dump` JSON the browser needs. The
// attributes array mixes bare strings ("private") with objects ({"group": …}).
type dump struct {
	Recipes map[string]struct {
		Name       string `json:"name"`
		Doc        string `json:"doc"`
		Private    bool   `json:"private"`
		Attributes []any  `json:"attributes"`
		Parameters []struct {
			Name    string `json:"name"`
			Default any    `json:"default"`
		} `json:"parameters"`
	} `json:"recipes"`
}

// Parse extracts the public, argument-free recipes from a `just --dump` JSON
// document, sorted by group then name.
func Parse(data []byte) ([]Recipe, error) {
	var d dump
	if err := json.Unmarshal(data, &d); err != nil {
		return nil, fmt.Errorf("parsing just dump: %w", err)
	}
	var out []Recipe
	for name, r := range d.Recipes {
		if r.Private || strings.HasPrefix(name, "_") || isPrivate(r.Attributes) {
			continue
		}
		// A parameter without a default makes the recipe unrunnable from a
		// picker (no argument prompt), so skip it.
		runnable := true
		for _, p := range r.Parameters {
			if p.Default == nil {
				runnable = false
				break
			}
		}
		if !runnable {
			continue
		}
		out = append(out, Recipe{Name: name, Doc: r.Doc, Group: group(r.Attributes)})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Group != out[j].Group {
			return out[i].Group < out[j].Group
		}
		return out[i].Name < out[j].Name
	})
	return out, nil
}

func isPrivate(attrs []any) bool {
	for _, a := range attrs {
		if s, ok := a.(string); ok && s == "private" {
			return true
		}
	}
	return false
}

func group(attrs []any) string {
	for _, a := range attrs {
		if m, ok := a.(map[string]any); ok {
			if g, ok := m["group"].(string); ok {
				return g
			}
		}
	}
	return ""
}
