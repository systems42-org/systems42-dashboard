package web_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Port of tests/test_moved_type_folder.py (issue 180): the metamodel moves
// domain terms to wiki/terms and goals to wiki/aims. List, search, detail
// page, links and goal coverage agree, and an edited declaration shows on
// the next request.
func TestMovedTypeFolders(t *testing.T) {
	t.Cleanup(func() { metamodel.UseTypes(metamodel.BuildTypes(nil)) })
	tmp := t.TempDir()
	root := repoRoot(t)
	mm := filepath.Join(tmp, "_system", "metamodel")
	if err := os.CopyFS(mm, os.DirFS(filepath.Join(root, "_system", "metamodel"))); err != nil {
		t.Fatal(err)
	}
	declare := func(typeFile, from, to string) {
		t.Helper()
		p := filepath.Join(mm, "types", typeFile)
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(b), "folder: "+from+"\n") {
			t.Fatalf("%s does not declare folder %s", typeFile, from)
		}
		text := strings.Replace(string(b), "folder: "+from+"\n", "folder: "+to+"\n", 1)
		if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	declare("type-domain-term.md", "wiki/domain-terms", "wiki/terms")
	declare("type-goal.md", "wiki/goals", "wiki/aims")

	wikiDir := filepath.Join(tmp, "wiki")
	writePage(t, wikiDir, "terms", "DT-001-customer",
		"id: DT-001\ntype: domain-term\ntitle: Customer\nstatus: draft\nstereotype: entity\n"+
			`related: ["[[DT-002-order]]", "[[STK-001-sales]]"]`,
		"\n# Customer\n\n**Definition.** Someone who buys. See [[DT-002-order]].\n")
	writePage(t, wikiDir, "terms", "DT-002-order",
		"id: DT-002\ntype: domain-term\ntitle: Order\nstatus: draft\nrelated: []",
		"\n# Order\n\n**Definition.** What a customer places.\n")
	writePage(t, wikiDir, "domain-terms", "DT-009-leftover",
		"id: DT-009\ntype: domain-term\ntitle: Leftover\nstatus: draft\nrelated: []",
		"\n# Leftover\n")
	writePage(t, wikiDir, "aims", "GOAL-002-faster",
		"id: GOAL-002\ntype: goal\ntitle: Faster checkout\nstatus: draft\nstereotype: objective\nrelated: []",
		"\n# Faster checkout\n")
	writePage(t, wikiDir, "functional-requirements", "FR-001-checkout",
		"id: FR-001\ntype: functional-requirement\ntitle: Checkout\nstatus: draft\nnotation: agile\n"+
			"level: feature\npriority: Must\n"+`goal: ["[[GOAL-002-faster]]"]`+"\nrelated: []",
		"\n# Checkout\n\n## Story\n\nAs a [[DT-001-customer]] I want to pay.\n")
	writePage(t, wikiDir, "stakeholders", "STK-001-sales",
		"id: STK-001\ntype: stakeholder\ntitle: Sales\nstatus: draft\n"+`related: ["[[DT-001-customer]]"]`,
		"\n# Sales\n")

	srv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      wikiDir,
			SourcesDir:   filepath.Join(tmp, "raw", "sources"),
			ConfigPath:   filepath.Join(tmp, "wiki.yaml"),
			DocsDir:      filepath.Join(tmp, "docs"),
			MetamodelDir: mm,
			NotationsDir: filepath.Join(tmp, "_system", "notations"),
			AnchorsDir:   filepath.Join(root, "_system", "anchors"),
		},
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})
	get := func(url string) string {
		t.Helper()
		rec := doGet(srv, url)
		if rec.Code != 200 {
			t.Fatalf("GET %s: status %d", url, rec.Code)
		}
		return rec.Body.String()
	}
	has := func(url, want string) {
		t.Helper()
		if body := get(url); !strings.Contains(body, want) {
			t.Fatalf("GET %s: missing %q", url, want)
		}
	}
	const term = "/page/terms/DT-001-customer"

	// the list
	list := get("/domain-terms")
	if !strings.Contains(list, `href="`+term+`"`) || !strings.Contains(list, `href="/page/terms/DT-002-order"`) {
		t.Fatal("the term list misses the moved pages")
	}
	if strings.Contains(list, "Leftover") || strings.Contains(list, "/page/domain-terms/") {
		t.Fatal("the term list shows a page of the folder the type left")
	}

	// search
	var index struct {
		Records []map[string]any `json:"records"`
	}
	if err := json.Unmarshal([]byte(get("/search.json")), &index); err != nil {
		t.Fatal(err)
	}
	found := map[string]map[string]any{}
	for _, r := range index.Records {
		found[r["id"].(string)] = r
	}
	if found["DT-001"]["url"] != term || found["DT-001"]["type"] != "Domain term" {
		t.Fatalf("search record of the term: %v", found["DT-001"])
	}
	if found["GOAL-002"]["url"] != "/page/aims/GOAL-002-faster" || found["GOAL-002"]["type"] != "Goal" {
		t.Fatalf("search record of the goal: %v", found["GOAL-002"])
	}

	// the detail page and the links to it
	detail := get(term)
	for _, want := range []string{`id="term-fields"`, `id="ego-cy"`, `href="/page/terms/DT-002-order"`,
		`href="/page/stakeholders/STK-001-sales"`} {
		if !strings.Contains(detail, want) {
			t.Fatalf("term page misses %q", want)
		}
	}
	if rec := doGet(srv, "/page/domain-terms/DT-001-customer"); rec.Code != 404 {
		t.Fatalf("the old address answers %d", rec.Code)
	}
	has("/stakeholders", `href="`+term+`"`)
	has("/page/stakeholders/STK-001-sales", `href="`+term+`"`)
	has("/functional-requirements/FR-001-checkout", `href="`+term+`"`)
	has("/graph/domain-terms", "DT-001-customer")

	// goals and their coverage
	has("/goals", `href="/page/aims/GOAL-002-faster"`)
	has("/goals", "/functional-requirements/FR-001-checkout")
	has("/functional-requirements/FR-001-checkout", `href="/page/aims/GOAL-002-faster"`)
	has("/page/aims/GOAL-002-faster", "/functional-requirements/FR-001-checkout")

	// an edited declaration shows on the next request
	declare("type-domain-term.md", "wiki/terms", "wiki/domain-terms")
	list = get("/domain-terms")
	if !strings.Contains(list, `href="/page/domain-terms/DT-009-leftover"`) || strings.Contains(list, "/page/terms/") {
		t.Fatal("the term list did not follow the edited declaration")
	}
	if plain := get(term); strings.Contains(plain, `id="term-fields"`) || strings.Contains(plain, `id="ego-cy"`) {
		t.Fatal("a page of an undeclared folder still shows as a domain term")
	}
}
