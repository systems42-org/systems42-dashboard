package project

import (
	"fmt"
	"sort"
	"strings"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Every live requirement shows exactly once in the hierarchy: under a root,
// as an orphan or outside the Agile hierarchy. An orphaned feature keeps its
// stories, and the counters equal what is shown.
func TestFRHierarchyLosesNoRequirement(t *testing.T) {
	fr := func(stem, notation, level, parent, status string) *wiki.Page {
		meta := map[string]any{
			"id": strings.Join(strings.SplitN(stem, "-", 3)[:2], "-"), "title": stem,
			"notation": notation, "level": level, "status": status,
		}
		if parent != "" {
			meta["parent"] = []any{"[[" + parent + "]]"}
		}
		return mkPage("functional-requirements", stem, meta, "")
	}
	frs := []*wiki.Page{
		fr("FR-001-lending", "agile", "epic", "", "draft"),
		fr("FR-002-checkout", "agile", "feature", "FR-001-lending", "draft"),
		fr("FR-003-scan", "agile", "story", "FR-002-checkout", "draft"),
		// a feature without a parent, and its story
		fr("FR-010-notify", "agile", "feature", "", "draft"),
		fr("FR-011-remind", "agile", "story", "FR-010-notify", "draft"),
		// a feature of a deprecated epic, and its story
		fr("FR-020-retired", "agile", "epic", "", "deprecated"),
		fr("FR-021-reports", "agile", "feature", "FR-020-retired", "draft"),
		fr("FR-022-monthly", "agile", "story", "FR-021-reports", "draft"),
		// an epic with a dangling parent stays a root with its chain
		fr("FR-030-search", "agile", "epic", "FR-999-missing", "draft"),
		fr("FR-031-filters", "agile", "feature", "FR-030-search", "draft"),
		fr("FR-032-by-author", "agile", "story", "FR-031-filters", "draft"),
		// cycles
		fr("FR-040-ping", "agile", "feature", "FR-041-pong", "draft"),
		fr("FR-041-pong", "agile", "feature", "FR-040-ping", "draft"),
		fr("FR-042-rally", "agile", "story", "FR-040-ping", "draft"),
		fr("FR-043-chicken", "agile", "story", "FR-044-egg", "draft"),
		fr("FR-044-egg", "agile", "story", "FR-043-chicken", "draft"),
		// self-parents
		fr("FR-050-own-feature", "agile", "feature", "FR-050-own-feature", "draft"),
		fr("FR-051-own-story", "agile", "story", "FR-051-own-story", "draft"),
		fr("FR-052-own-epic", "agile", "epic", "FR-052-own-epic", "draft"),
		// parents that take no such child
		fr("FR-070-story-of-a-story", "agile", "story", "FR-003-scan", "draft"),
		fr("FR-071-feature-of-a-feature", "agile", "feature", "FR-002-checkout", "draft"),
		fr("FR-072-its-story", "agile", "story", "FR-071-feature-of-a-feature", "draft"),
		fr("UC-001-summary", "use-case", "kite", "", "draft"),
		fr("FR-074-story-of-a-kite", "agile", "story", "UC-001-summary", "draft"),
		// a use case that roots a feature and its story
		fr("UC-002-borrow", "use-case", "sea", "", "draft"),
		fr("FR-080-reserve", "agile", "feature", "UC-002-borrow", "draft"),
		fr("FR-081-online", "agile", "story", "FR-080-reserve", "draft"),
	}
	h := BuildFRHierarchy(frs)

	var shown []string
	nFeat, nStory := 0, 0
	add := func(n map[string]any, level string) {
		shown = append(shown, n["stem"].(string))
		switch level {
		case "feature":
			nFeat++
		case "story":
			nStory++
		}
	}
	addAll := func(list any, level string) {
		nodes, _ := list.([]map[string]any)
		for _, n := range nodes {
			add(n, level)
		}
	}
	for _, key := range []string{"epics", "use_cases"} {
		for _, root := range h[key].([]map[string]any) {
			add(root, "")
			for _, f := range root["features"].([]map[string]any) {
				add(f, "feature")
				addAll(f["stories"], "story")
			}
			addAll(root["direct_stories"], "story")
			if root["n_features"].(int) != len(root["features"].([]map[string]any)) {
				t.Errorf("%s: n_features differs from its features", root["id"])
			}
		}
	}
	orphans := map[string][]string{}
	for _, o := range h["orphans"].([]map[string]any) {
		add(o, o["level"].(string))
		addAll(o["stories"], "story")
		ids := []string{}
		stories, _ := o["stories"].([]map[string]any)
		for _, s := range stories {
			ids = append(ids, s["id"].(string))
		}
		orphans[o["id"].(string)] = ids
	}
	addAll(h["other_notations"], "")

	var live []string
	for _, p := range frs {
		if p.Status() != "deprecated" {
			live = append(live, p.Stem)
		}
	}
	sort.Strings(shown)
	sort.Strings(live)
	if strings.Join(shown, " ") != strings.Join(live, " ") {
		t.Fatalf("hierarchy does not show every live requirement once:\nshown %v\nlive  %v", shown, live)
	}

	want := map[string][]string{
		"FR-010": {"FR-011"}, "FR-021": {"FR-022"}, "FR-040": {"FR-042"}, "FR-041": {},
		"FR-043": {}, "FR-044": {}, "FR-050": {}, "FR-051": {}, "FR-070": {},
		"FR-071": {"FR-072"}, "FR-074": {},
	}
	if fmt.Sprint(orphans) != fmt.Sprint(want) {
		t.Errorf("orphans = %v, want %v", orphans, want)
	}
	if h["total_epics"].(int) != 3 || h["total_features"].(int) != nFeat || h["total_stories"].(int) != nStory ||
		nFeat != 9 || nStory != 12 {
		t.Errorf("counters %v/%v/%v differ from what is shown: 3 epics, %d features, %d stories (want 9 and 12)",
			h["total_epics"], h["total_features"], h["total_stories"], nFeat, nStory)
	}

	// the detail page finds an orphaned feature with its story, and the
	// detail diagram draws the story
	node, lvl := FRHierarchyNode(h, "FR-010-notify")
	if lvl != "feature" || node == nil {
		t.Fatalf("orphaned feature not found: %v %q", node, lvl)
	}
	diag, links := MermaidFRSubtree(node, nil)
	if !strings.Contains(diag, "FR010 --> FR011[") || len(links) != 1 {
		t.Errorf("detail diagram of the orphaned feature misses its story:\n%s", diag)
	}
	if n, lvl := FRHierarchyNode(h, "FR-011-remind"); n == nil || lvl != "story" {
		t.Errorf("story of an orphaned feature not found: %v %q", n, lvl)
	}
	if n, lvl := FRHierarchyNode(h, "FR-043-chicken"); n == nil || lvl != "story" {
		t.Errorf("orphaned story not found: %v %q", n, lvl)
	}
}
