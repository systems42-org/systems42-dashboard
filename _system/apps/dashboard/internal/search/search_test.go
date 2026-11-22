package search_test

import (
	"bytes"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/search"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func dashboardDir(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func loadFixtureIndex(t *testing.T) (map[string]any, []*wiki.Page) {
	t.Helper()
	dash := dashboardDir(t)
	fixture := filepath.Join(dash, "tests", "fixtures", "search-wiki")
	store := wiki.NewStore(wiki.Paths{
		WikiDir:    fixture,
		SourcesDir: filepath.Join(t.TempDir(), "sources"),
	})
	allPages := store.LoadAllPages()
	idx := search.BuildIndex(
		allPages,
		store.LoadFolder("domain-terms"),
		store.LoadFolder("glossary"),
		wiki.TitleIndex(allPages),
		wiki.LinkIndex(allPages),
		wiki.SourceIndex(store.LoadSources()),
	)
	return idx, allPages
}

func TestSearchIndexStructureAndPlain(t *testing.T) {
	idx, allPages := loadFixtureIndex(t)
	records := idx["records"].([]map[string]any)
	synonyms := idx["synonyms"].([][]string)

	byID := map[string]map[string]any{}
	for _, rec := range records {
		byID[rec["id"].(string)] = rec
	}

	// Plain drops link targets, headings, labels, and uses source IDs.
	iss1 := strings.ToLower(byID["ISS-001"]["plain"].(string))
	if !strings.Contains(iss1, "keyholder") || strings.Contains(iss1, "stk-023-keyholder") || strings.Contains(iss1, "[[") {
		t.Fatalf("unexpected ISS-001 plain: %q", iss1)
	}
	fr7 := byID["FR-007"]["plain"].(string)
	if strings.Contains(strings.ToLower(fr7), "grilling") {
		t.Fatalf("FR-007 plain leaked source stem: %q", fr7)
	}
	if !strings.HasPrefix(fr7, "Readers look from any page (SRC-006).") {
		t.Fatalf("FR-007 plain = %q", fr7)
	}

	// Fields and aliases.
	fr1Fields := byID["FR-001"]["fields"].(map[string][]string)
	if len(fr1Fields["priority"]) != 1 || fr1Fields["priority"][0] != "must" {
		t.Fatalf("FR-001 priority = %v, want [must]", fr1Fields["priority"])
	}
	stk23Aliases := byID["STK-023"]["aliases"].([]string)
	if len(stk23Aliases) != 1 || stk23Aliases[0] != "Jedi Master" {
		t.Fatalf("STK-023 aliases = %v", stk23Aliases)
	}

	// Bidirectional links exclude self.
	stk23Links := byID["STK-023"]["links"].([]string)
	linkSet := map[string]bool{}
	for _, id := range stk23Links {
		linkSet[id] = true
	}
	if !linkSet["ISS-001"] || !linkSet["GLO-001"] || !linkSet["FR-001"] || linkSet["STK-023"] {
		t.Fatalf("STK-023 links = %v", stk23Links)
	}

	// Glossary synonyms include facilitator / moderator.
	foundSyn := false
	for _, grp := range synonyms {
		if len(grp) == 2 && grp[0] == "facilitator" && grp[1] == "moderator" {
			foundSyn = true
		}
	}
	if !foundSyn {
		t.Fatalf("missing [facilitator moderator] synonym group in %v", synonyms)
	}

	// Filters & facets.
	filters := search.Filters(allPages)
	if len(filters["status"]) == 0 || len(filters["priority"]) == 0 || len(filters["tag"]) == 0 {
		t.Fatalf("filters incomplete: %+v", filters)
	}
	if filters["priority"][0]["value"] != "must" || filters["priority"][0]["label"] != "Must" {
		t.Fatalf("priority filter order = %v, want Must first", filters["priority"])
	}
	facets := search.Facets(records)
	if len(facets) == 0 {
		t.Fatalf("expected non-empty facets")
	}
}

func TestSearchHarnessWithNode(t *testing.T) {
	if _, err := exec.LookPath("node"); err != nil {
		t.Skip("node not installed")
	}
	idx, _ := loadFixtureIndex(t)
	raw, err := json.Marshal(idx)
	if err != nil {
		t.Fatal(err)
	}
	harness := filepath.Join(dashboardDir(t), "tests", "search_harness.js")
	run := func(query string) []struct {
		ID   string `json:"id"`
		Note string `json:"note"`
	} {
		cmd := exec.Command("node", harness, query)
		cmd.Stdin = bytes.NewReader(raw)
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("node harness %q failed: %v", query, err)
		}
		var hits []struct {
			ID   string `json:"id"`
			Note string `json:"note"`
		}
		if err := json.Unmarshal(out, &hits); err != nil {
			t.Fatalf("unmarshal harness %q: %v", query, err)
		}
		return hits
	}

	if hits := run("keyholder"); len(hits) == 0 || hits[0].ID != "STK-023" {
		t.Fatalf("query 'keyholder' = %+v, want STK-023 first", hits)
	}
	if hits := run("who starts the app"); len(hits) == 0 || hits[0].ID != "STK-023" {
		t.Fatalf("query 'who starts the app' = %+v, want STK-023 first", hits)
	}
	if hits := run("moderator"); len(hits) == 0 {
		t.Fatalf("query 'moderator' returned no hits")
	} else {
		foundFR1 := false
		for i := 0; i < len(hits) && i < 3; i++ {
			if hits[i].ID == "FR-001" {
				foundFR1 = true
			}
		}
		if !foundFR1 {
			t.Fatalf("query 'moderator' missing FR-001 in top 3: %+v", hits)
		}
	}
}
