package web_test

import (
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Port of tests/test_delivery_status.py (issue #91, FR-048): a requirement
// page shows its delivery status as a badge, and the requirement list has a
// Delivery column and a delivery filter once a requirement has a value.

var (
	detailHeadRE      = regexp.MustCompile(`(?s)<div class="detail-head">.*?</div>`)
	deliveryBadgeRE   = regexp.MustCompile(`(?s)<span class="delivery[ "].*?</span>`)
	deliveryCheckedRE = regexp.MustCompile(`(?s)<span class="delivery-checked">(.*?)</span>`)
	deliverySelectRE  = regexp.MustCompile(`(?s)<select data-list-delivery>(.*?)</select>`)
	deliveryRowRE     = regexp.MustCompile(`<tr data-status="[^"]*" data-delivery="([^"]*)">\s*<td class="c-id"><code>([^<]*)</code>`)
)

const deliveryNotAllowed = ` title="The metamodel does not allow this delivery value for this requirement"`

func deliveryServer(t *testing.T, pages map[string]string) *web.Server {
	t.Helper()
	tmp := t.TempDir()
	wikiDir := filepath.Join(tmp, "wiki")
	sourcesDir := filepath.Join(tmp, "raw", "sources")
	docsDir := filepath.Join(tmp, "docs")
	for _, d := range []string{sourcesDir, docsDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	cfgPath := filepath.Join(tmp, "wiki.yaml")
	if err := os.WriteFile(cfgPath, []byte("system_name: Tracking\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for stem, frontmatter := range pages {
		writePage(t, wikiDir, "functional-requirements", stem, frontmatter, "# T\n\nText.\n")
	}
	root := repoRoot(t)
	return web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      wikiDir,
			SourcesDir:   sourcesDir,
			ConfigPath:   cfgPath,
			DocsDir:      docsDir,
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
}

func TestDeliveryStatus(t *testing.T) {
	const hostile = `"><script>alert(1)</script>`
	const hostileEscaped = `&#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt;`
	story := "status: draft\nnotation: agile\nlevel: story\n"
	pages := map[string]string{
		"FR-001-implemented": "id: FR-001\ntitle: Implemented\nstatus: accepted\nnotation: agile\nlevel: story\n" +
			"delivery: implemented\ndelivery-checked: 2026-11-20T00:30:00+01:00",
		"FR-002-outdated":      "id: FR-002\ntitle: Outdated\n" + story + "delivery: outdated\ndelivery-checked: 2026-10-01",
		"FR-003-removed":       "id: FR-003\ntitle: Removed\n" + story + "delivery: removed\ndelivery-checked: '2026-09-02T08:00:00Z'",
		"FR-004-no-record":     "id: FR-004\ntitle: No record\n" + story,
		"FR-005-blank":         "id: FR-005\ntitle: Blank\n" + story + "delivery:\ndelivery-checked:",
		"FR-006-unknown-state": "id: FR-006\ntitle: Unknown state\n" + story + "delivery: done",
		"FR-007-epic":          "id: FR-007\ntitle: Epic\nstatus: draft\nnotation: agile\nlevel: epic\ndelivery: implemented",
		"FR-008-partial-story": "id: FR-008\ntitle: Partial story\n" + story + "delivery: partial",
		"FR-009-hostile":       "id: FR-009\ntitle: Hostile\n" + story + "delivery: '" + hostile + "'\ndelivery-checked: '" + hostile + "'",
		"FR-010-checked-only":  "id: FR-010\ntitle: Checked only\n" + story + "delivery-checked: 2026-11-20",
		"FR-011-list-value":    "id: FR-011\ntitle: List value\n" + story + "delivery: [implemented, outdated]",
		"UC-001-partial":       "id: UC-001\ntitle: Partial use case\nstatus: draft\nnotation: use-case\nlevel: sea\ndelivery: partial",
		"UC-002-kite":          "id: UC-002\ntitle: Kite use case\nstatus: draft\nnotation: use-case\nlevel: kite\ndelivery: implemented",
		"FR-012-no-notation":   "id: FR-012\ntitle: No notation\nstatus: draft\ndelivery: partial",
	}
	srv := deliveryServer(t, pages)
	get := func(url string) string {
		t.Helper()
		rec := doGet(srv, url)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", url, rec.Code)
		}
		return rec.Body.String()
	}
	// badge markup and checked text in the head of a requirement page
	badge := func(stem string) (string, string) {
		t.Helper()
		doc := get("/functional-requirements/" + stem)
		heads := detailHeadRE.FindAllString(doc, -1)
		if len(heads) != 1 {
			t.Fatalf("%s: %d page heads", stem, len(heads))
		}
		if strings.Count(doc, `class="delivery`) != strings.Count(heads[0], `class="delivery`) {
			t.Errorf("%s: a delivery badge outside the page head", stem)
		}
		checked := ""
		if m := deliveryCheckedRE.FindStringSubmatch(heads[0]); m != nil {
			checked = m[1]
		}
		return deliveryBadgeRE.FindString(heads[0]), checked
	}

	want := map[string][2]string{
		"FR-001-implemented":   {`<span class="delivery delivery-implemented">implemented</span>`, "checked 2026-11-20"},
		"FR-002-outdated":      {`<span class="delivery delivery-outdated">implementation outdated</span>`, "checked 2026-10-01"},
		"FR-003-removed":       {`<span class="delivery delivery-removed">implementation removed</span>`, "checked 2026-09-02"},
		"UC-001-partial":       {`<span class="delivery delivery-partial">partly implemented</span>`, ""},
		"FR-012-no-notation":   {`<span class="delivery delivery-partial">partly implemented</span>`, ""},
		"FR-004-no-record":     {"", ""},
		"FR-005-blank":         {"", ""},
		"FR-010-checked-only":  {"", ""},
		"FR-011-list-value":    {"", ""},
		"FR-006-unknown-state": {`<span class="delivery"` + deliveryNotAllowed + `>done</span>`, ""},
		"FR-007-epic":          {`<span class="delivery"` + deliveryNotAllowed + `>implemented</span>`, ""},
		"FR-008-partial-story": {`<span class="delivery"` + deliveryNotAllowed + `>partial</span>`, ""},
		"UC-002-kite":          {`<span class="delivery"` + deliveryNotAllowed + `>implemented</span>`, ""},
		"FR-009-hostile":       {`<span class="delivery"` + deliveryNotAllowed + `>` + hostileEscaped + `</span>`, "checked " + hostileEscaped},
	}
	for stem, w := range want {
		b, c := badge(stem)
		if b != w[0] || c != w[1] {
			t.Errorf("%s:\n got %q, %q\nwant %q, %q", stem, b, c, w[0], w[1])
		}
	}
	// next to the status
	head := detailHeadRE.FindString(get("/functional-requirements/FR-001-implemented"))
	if !regexp.MustCompile(`<span class="status status-accepted">accepted</span>\s*<span class="delivery delivery-implemented">`).MatchString(head) {
		t.Errorf("the badge does not follow the status:\n%s", head)
	}
	if strings.Contains(get("/functional-requirements/FR-009-hostile"), "<script>alert(1)") {
		t.Error("a hostile delivery value reached the page as markup")
	}

	list := get("/req42/functional-requirements")
	if strings.Contains(list, "<script>alert(1)") {
		t.Error("a hostile delivery value reached the list as markup")
	}
	sel := deliverySelectRE.FindStringSubmatch(list)
	if sel == nil {
		t.Fatal("the requirement list has no delivery filter")
	}
	var options []string
	for _, m := range optionRE.FindAllStringSubmatch(sel[1], -1) {
		options = append(options, m[1]+"="+m[2])
	}
	wantOptions := "=All|partial=partly implemented|implemented=implemented|outdated=implementation outdated|" +
		"removed=implementation removed|none=No delivery record"
	if got := strings.Join(options, "|"); got != wantOptions {
		t.Errorf("filter options:\n got %s\nwant %s", got, wantOptions)
	}
	if !strings.Contains(list, `<th class="c-status" data-sort="text" data-key="delivery">Delivery</th>`) {
		t.Error("the requirement list has no Delivery column")
	}
	rows := map[string]string{}
	for _, m := range deliveryRowRE.FindAllStringSubmatch(list, -1) {
		rows[m[2]] = m[1]
	}
	wantRows := map[string]string{"FR-001": "implemented", "FR-002": "outdated", "FR-003": "removed", "FR-004": "",
		"FR-005": "", "FR-006": "done", "FR-007": "implemented", "FR-008": "partial", "FR-009": hostileEscaped,
		"FR-010": "", "FR-011": "", "FR-012": "partial", "UC-001": "partial", "UC-002": "implemented"}
	if len(rows) != len(wantRows) {
		t.Errorf("%d rows with a delivery value, want %d", len(rows), len(wantRows))
	}
	for id, w := range wantRows {
		if got, ok := rows[id]; !ok || got != w {
			t.Errorf("row %s: delivery %q (present %v), want %q", id, got, ok, w)
		}
	}
	if !regexp.MustCompile(`<td class="c-status" data-sort-value="implemented">\s*<span class="delivery delivery-implemented">implemented</span>\s*</td>`).MatchString(list) {
		t.Error("the Delivery cell lacks the badge")
	}
}

// A wiki without delivery values looks as before: no filter, no column.
func TestNoDeliveryValuesNoFilter(t *testing.T) {
	srv := deliveryServer(t, map[string]string{
		"FR-001-plain": "id: FR-001\ntitle: Plain\nstatus: draft\nnotation: agile\nlevel: story\ndelivery:",
		"FR-002-plain": "id: FR-002\ntitle: Other\nstatus: draft\nnotation: agile\nlevel: story",
	})
	for _, url := range []string{"/req42/functional-requirements", "/functional-requirements/FR-001-plain"} {
		rec := doGet(srv, url)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", url, rec.Code)
		}
		if doc := strings.ToLower(rec.Body.String()); strings.Contains(doc, "delivery") {
			t.Errorf("GET %s mentions delivery in a wiki that tracks none", url)
		}
	}
}
