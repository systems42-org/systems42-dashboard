package web_test

import (
	"html"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Port of tests/test_term_fields.py: the term page shows kind, aliases,
// attributes and relationships (FR-039), and the term list shows the kind and
// filters by it (FR-038).

var (
	tagRE     = regexp.MustCompile(`<[^>]+>`)
	rowRE     = regexp.MustCompile(`(?s)<tr([^>]*)>(.*?)</tr>`)
	cellRE    = regexp.MustCompile(`(?s)<td[^>]*>(.*?)</td>`)
	hrefRE    = regexp.MustCompile(`href="([^"]*)"`)
	fieldRE   = regexp.MustCompile(`(?s)<dt>(.*?)</dt>\s*<dd>(.*?)</dd>`)
	dataKind  = regexp.MustCompile(`data-kind="([^"]*)"`)
	dataState = regexp.MustCompile(`data-status="([^"]*)"`)
)

func visibleText(fragment string) string {
	return strings.Join(strings.Fields(html.UnescapeString(tagRE.ReplaceAllString(fragment, " "))), " ")
}

// sectionRows returns the body rows of the table in <section id=...>, each a
// list of cell HTML.
func sectionRows(t *testing.T, doc, id string) [][]string {
	t.Helper()
	_, rest, ok := strings.Cut(doc, `id="`+id+`"`)
	if !ok {
		t.Fatalf("no section %s", id)
	}
	rest, _, _ = strings.Cut(rest, "</section>")
	_, body, _ := strings.Cut(rest, "<tbody>")
	rows := [][]string{}
	for _, m := range rowRE.FindAllStringSubmatch(body, -1) {
		cells := []string{}
		for _, c := range cellRE.FindAllStringSubmatch(m[2], -1) {
			cells = append(cells, c[1])
		}
		rows = append(rows, cells)
	}
	return rows
}

func termFields(doc string) map[string]string {
	out := map[string]string{}
	_, rest, ok := strings.Cut(doc, `<dl class="issue-fields" id="term-fields">`)
	if !ok {
		return out
	}
	rest, _, _ = strings.Cut(rest, "</dl>")
	for _, m := range fieldRE.FindAllStringSubmatch(rest, -1) {
		out[m[1]] = m[2]
	}
	return out
}

// listRows returns {id: [kind attribute, kind cell text, status]} of the term list.
func listRows(t *testing.T, doc string) map[string][3]string {
	t.Helper()
	_, body, ok := strings.Cut(doc, `<tbody id="glossary-body">`)
	if !ok {
		t.Fatal("no term list")
	}
	body, _, _ = strings.Cut(body, "</tbody>")
	out := map[string][3]string{}
	for _, m := range rowRE.FindAllStringSubmatch(body, -1) {
		cells := cellRE.FindAllStringSubmatch(m[2], -1)
		out[visibleText(cells[0][1])] = [3]string{
			dataKind.FindStringSubmatch(m[1])[1], visibleText(cells[2][1]), dataState.FindStringSubmatch(m[1])[1],
		}
	}
	return out
}

func TestTermFieldsAndKindFilter(t *testing.T) {
	tmp := t.TempDir()
	wikiDir := filepath.Join(tmp, "wiki")
	terms := map[string]string{
		"DT-001-training": `title: Training
status: accepted
stereotype: entity
aliases: [Course, "Class <b>"]
attributes:
- {name: training_id, type: string, multiplicity: "1", identifier: true}
- {name: price, type: Money, multiplicity: "0..1"}
- {name: seats, type: integer, multiplicity: 1}
relationships:
- {to: "[[DT-002-session]]", label: schedules, kind: composition, multiplicity: "0..*"}
- {to: "[[DT-004-offer|Offer]]", kind: generalization, multiplicity: "5"}
- {to: "[[DT-003-review]]", label: gets, multiplicity: "0..1"}
- {to: "[[DT-099-ghost]]", label: haunts, kind: aggregation, multiplicity: "2"}`,
		"DT-002-session": "title: Session\nstatus: draft\nstereotype: value-object",
		"DT-003-review":  "title: Review\nstatus: accepted",
		"DT-004-offer":   "title: Offer\nstatus: draft\nstereotype: Sum-Type",
		"DT-005-note":    "title: Note\nstatus: draft\nstereotype: gadget\naliases: [Memo]",
	}
	for stem, fields := range terms {
		writePage(t, wikiDir, "domain-terms", stem, "id: "+stem[:6]+"\ntype: domain-term\n"+fields,
			"\n**Definition.** Meaning of "+stem+".\n")
	}
	root := repoRoot(t)
	srv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      wikiDir,
			SourcesDir:   filepath.Join(tmp, "raw", "sources"),
			ConfigPath:   filepath.Join(tmp, "wiki.yaml"),
			DocsDir:      filepath.Join(tmp, "docs"),
			MetamodelDir: filepath.Join(root, "_system", "metamodel"),
			NotationsDir: filepath.Join(root, "_system", "notations"),
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
			t.Fatalf("%s: status %d", url, rec.Code)
		}
		return rec.Body.String()
	}
	texts := func(rows [][]string) [][]string {
		out := [][]string{}
		for _, row := range rows {
			cells := []string{}
			for _, c := range row {
				cells = append(cells, visibleText(c))
			}
			out = append(out, cells)
		}
		return out
	}

	// --- the term page (FR-039) ---
	page := get("/page/domain-terms/DT-001-training")
	fields := termFields(page)
	if got := visibleText(fields["Kind"]); got != "entity" {
		t.Errorf("kind = %q", got)
	}
	if got := visibleText(fields["Aliases"]); got != "Course, Class <b>" {
		t.Errorf("aliases = %q", got)
	}
	if strings.Contains(fields["Aliases"], "<b>") {
		t.Error("an alias is text, not markup")
	}
	wantAttributes := [][]string{
		{"training_id identifier", "string", "1"},
		{"price", "Money", "0..1"},
		{"seats", "integer", "1"},
	}
	if got := texts(sectionRows(t, page, "term-attributes")); !reflect.DeepEqual(got, wantAttributes) {
		t.Errorf("attributes = %v", got)
	}
	relationships := sectionRows(t, page, "term-relationships")
	wantRelationships := [][]string{
		{"composition", "schedules", "DT-002 Session", "0..*"},
		{"generalization", "", "DT-004 Offer", ""},
		{"association", "gets", "DT-003 Review", "0..1"},
		{"aggregation", "haunts", "DT-099-ghost", "2"},
	}
	if got := texts(relationships); !reflect.DeepEqual(got, wantRelationships) {
		t.Fatalf("relationships = %v", got)
	}
	wantLinks := []string{"/page/domain-terms/DT-002-session", "/page/domain-terms/DT-004-offer", "/page/domain-terms/DT-003-review", ""}
	for i, row := range relationships {
		link := ""
		if m := hrefRE.FindStringSubmatch(row[2]); m != nil {
			link = m[1]
			get(link) // the link works
		}
		if link != wantLinks[i] {
			t.Errorf("relationship %d links to %q, want %q", i, link, wantLinks[i])
		}
	}

	// a value object without attributes or relationships: the kind, no empty sections
	page = get("/page/domain-terms/DT-002-session")
	if got := visibleText(termFields(page)["Kind"]); got != "value-object" {
		t.Errorf("kind = %q", got)
	}
	if strings.Contains(page, "term-attributes") || strings.Contains(page, "term-relationships") {
		t.Error("a term without structure shows a structure section")
	}
	if got := visibleText(termFields(get("/page/domain-terms/DT-004-offer"))["Kind"]); got != "sum-type" {
		t.Errorf("kind = %q", got)
	}
	// a plain term: no kind, no structure sections
	page = get("/page/domain-terms/DT-003-review")
	for _, mark := range []string{"term-fields", "term-attributes", "term-relationships"} {
		if strings.Contains(page, mark) {
			t.Errorf("a plain term shows %s", mark)
		}
	}
	// a stereotype the metamodel does not know is no kind. The aliases still show
	page = get("/page/domain-terms/DT-005-note")
	if f := termFields(page); len(f) != 1 || visibleText(f["Aliases"]) != "Memo" || strings.Contains(page, "gadget") {
		t.Errorf("unknown stereotype: fields = %v", f)
	}

	// --- the term list (FR-038) ---
	page = get("/domain-terms")
	wantRows := map[string][3]string{
		"DT-001": {"entity", "entity", "accepted"},
		"DT-002": {"value-object", "value-object", "draft"},
		"DT-003": {"", "", "accepted"},
		"DT-004": {"sum-type", "sum-type", "draft"},
		"DT-005": {"", "", "draft"},
	}
	if got := listRows(t, page); !reflect.DeepEqual(got, wantRows) {
		t.Errorf("list rows = %v", got)
	}
	if !strings.Contains(page, `data-key="kind"`) {
		t.Error("the kind column does not sort")
	}
	shown := func(query string) []string {
		ids := []string{}
		for id := range listRows(t, get("/domain-terms"+query)) {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		return ids
	}
	for query, want := range map[string][]string{
		"?kind=entity":       {"DT-001"},
		"?kind=value-object": {"DT-002"},
		"?kind=sum-type":     {"DT-004"},
		"?kind=none":         {"DT-003", "DT-005"},
		"?kind=gadget":       {"DT-001", "DT-002", "DT-003", "DT-004", "DT-005"},
	} {
		if got := shown(query); !reflect.DeepEqual(got, want) {
			t.Errorf("%s shows %v, want %v", query, got, want)
		}
	}
	page = get("/domain-terms?kind=none")
	for _, want := range []string{`<option value="none" selected>No kind</option>`, "Showing 2 of 5 terms", "5 terms</span>"} {
		if !strings.Contains(page, want) {
			t.Errorf("?kind=none lacks %q", want)
		}
	}

	// with the status filter: the server leaves the rows of the kind, and the
	// list layer hides those whose data-status is not accepted
	page = get("/domain-terms?kind=none&status=accepted&sort=title:desc")
	rows := listRows(t, page)
	if len(rows) != 2 || rows["DT-003"][2] != "accepted" || rows["DT-005"][2] != "draft" {
		t.Errorf("kind and status: rows = %v", rows)
	}
	for _, want := range []string{"data-list-status", `<input type="hidden" name="status" value="accepted">`,
		`<input type="hidden" name="sort" value="title:desc">`} {
		if !strings.Contains(page, want) {
			t.Errorf("kind and status: page lacks %q", want)
		}
	}

	// a kind with no term: the table stays, with a hint
	if err := os.Remove(filepath.Join(wikiDir, "domain-terms", "DT-002-session.md")); err != nil {
		t.Fatal(err)
	}
	page = get("/domain-terms?kind=value-object")
	if len(listRows(t, page)) != 0 || !strings.Contains(page, "No terms match this filter.") ||
		strings.Contains(page, "No agreed pages in this list.") {
		t.Error("an empty kind does not show the hint alone")
	}
}
