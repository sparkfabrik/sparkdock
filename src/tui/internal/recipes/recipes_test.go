package recipes

import "testing"

const sampleDump = `{
  "recipes": {
    "device-info": {
      "name": "device-info",
      "doc": "Show device information",
      "private": false,
      "attributes": [{"group": "system"}],
      "parameters": []
    },
    "sf-harness-sync": {
      "name": "sf-harness-sync",
      "doc": "Fast sync of skills",
      "private": false,
      "attributes": [{"group": "ai-coding-harness"}],
      "parameters": [{"name": "force", "default": ""}]
    },
    "_helper": {
      "name": "_helper",
      "doc": "internal",
      "private": false,
      "attributes": [],
      "parameters": []
    },
    "old-alias-target": {
      "name": "old-alias-target",
      "doc": "hidden",
      "private": true,
      "attributes": [],
      "parameters": []
    },
    "attr-private": {
      "name": "attr-private",
      "doc": "hidden by attribute",
      "private": false,
      "attributes": ["private"],
      "parameters": []
    },
    "needs-arg": {
      "name": "needs-arg",
      "doc": "requires a value",
      "private": false,
      "attributes": [],
      "parameters": [{"name": "target", "default": null}]
    }
  }
}`

func TestParse_FiltersAndSorts(t *testing.T) {
	got, err := Parse([]byte(sampleDump))
	if err != nil {
		t.Fatalf("Parse error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 recipes, got %d: %+v", len(got), got)
	}
	// sorted by group: ai-coding-harness before system
	if got[0].Name != "sf-harness-sync" || got[0].Group != "ai-coding-harness" {
		t.Errorf("first = %+v, want sf-harness-sync in ai-coding-harness", got[0])
	}
	if got[1].Name != "device-info" || got[1].Doc != "Show device information" {
		t.Errorf("second = %+v, want device-info with doc", got[1])
	}
}

func TestParse_BadJSON(t *testing.T) {
	if _, err := Parse([]byte("not json")); err == nil {
		t.Error("want error on malformed dump")
	}
}
