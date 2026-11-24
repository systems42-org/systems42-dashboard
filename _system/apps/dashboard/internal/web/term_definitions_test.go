package web_test

import (
	"html"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Port of tests/test_term_definitions.py: a link to a domain term carries the
// term's definition (FR-041), with the same pages and the same texts.

var termLinkRE = regexp.MustCompile(`<a class="wl wl-term" href="([^"]*)" title="([^"]*)">(.*?)</a>`)

// termLinks returns {href, definition, label} of every term link, the title decoded.
func termLinks(doc string) [][3]string {
	out := [][3]string{}
	for _, m := range termLinkRE.FindAllStringSubmatch(doc, -1) {
		out = append(out, [3]string{m[1], html.UnescapeString(m[2]), m[3]})
	}
	return out
}

func hasLink(links [][3]string, want [3]string) bool {
	for _, l := range links {
		if l == want {
			return true
		}
	}
	return false
}

func TestTermLinksCarryTheDefinition(t *testing.T) {
	tmp := t.TempDir()
	wikiDir := filepath.Join(tmp, "wiki")
	sourcesDir := filepath.Join(tmp, "raw", "sources")
	page := func(folder, stem, typ, title, body, extra string) {
		writePage(t, wikiDir, folder, stem,
			"id: "+stem[:strings.Index(stem[4:], "-")+4]+"\ntype: "+typ+"\ntitle: "+title+"\nstatus: draft\nsources: []\nrelated: []\ntags: []"+extra,
			"\n# "+title+"\n\n"+body+"\n")
	}
	long := "A thing to sell, " + strings.Repeat("with a very long list of properties, ", 12) + "and an end."
	hostile := `"><script>alert(1)</script> <img src=x onerror=alert(2)> it's ` +
		"[click](javascript:alert(3)) javascript:alert(4) a ` tick, a \\* star & an [open bracket"
	hostileText := `"><script>alert(1)</script> <img src=x onerror=alert(2)> it's ` +
		"click) javascript:alert(4) a ` tick, a \\* star & an [open bracket"
	order := "A customer's binding request for items, see Empty, code and the shop."

	page("domain-terms", "DT-001-order", "domain-term", "Order",
		"**Definition.** A customer's **binding** request for\n[[DT-002-item|items]], "+
			"see [[DT-003-empty]], `code` and [the shop](https://example.org).\n\n"+
			"**In context.** Sales only. An [[DT-001-order]] links itself.", "")
	page("domain-terms", "DT-002-item", "domain-term", "Item", "**Definition.** "+long, "")
	page("domain-terms", "DT-003-empty", "domain-term", "Empty", "No labelled paragraph here.", "")
	page("domain-terms", "DT-004-hostile", "domain-term", "Hostile", "**Definition.** "+hostile, "")
	page("stakeholders", "STK-001-reader", "stakeholder", "Reader",
		"**Definition.** A stakeholder is no term.\n\n"+
			"Reads an [[DT-001-order]], by ID an [[DT-001|order by id]], an [[DT-003-empty]] "+
			"and [[STK-002-other]].\n\n"+
			"Quoted: `[[DT-001-order]]`.\n\n```\n[[DT-001-order]]\n```\n\n"+
			"A stray ` tick before [[DT-004-hostile]].", "")
	page("stakeholders", "STK-002-other", "stakeholder", "Other",
		"**Definition.** A stakeholder is no term.\n\n"+
			strings.TrimSpace(strings.Repeat("[[DT-001-order]] and [[DT-002-item]]. ", 40)), "")
	page("functional-requirements", "FR-001-buy", "functional-requirement", "Buy",
		"## Story\n\nAs a reader I want an [[DT-001-order]].", "\nnotation: agile\nlevel: story")
	if err := os.MkdirAll(sourcesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sourcesDir, "SRC-001-notes.md"), []byte(
		"---\nid: SRC-001\ntitle: Notes\ntype: source\ningested-pages: \"[[DT-004-hostile]] <b>x</b>\"\n---\n\nNotes.\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	root := repoRoot(t)
	srv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      wikiDir,
			SourcesDir:   sourcesDir,
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
	const href = "/page/domain-terms/DT-001-order"

	// a page body: by file name and by ID, not for a term without a
	// definition, a page of another type or a link quoted as code
	body := get("/page/stakeholders/STK-001-reader")
	links := termLinks(body)
	if !hasLink(links, [3]string{href, order, "Order"}) || !hasLink(links, [3]string{href, order, "order by id"}) {
		t.Fatalf("term links on the reader page: %v", links)
	}
	for _, want := range []string{
		`<a class="wl" href="/page/domain-terms/DT-003-empty">Empty</a>`,
		`<a class="wl" href="/page/stakeholders/STK-002-other">Other</a>`,
		"<code>[[DT-001-order]]</code>",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("reader page misses %s", want)
		}
	}
	if strings.Contains(body, `title=""`) {
		t.Error("a link carries an empty title")
	}
	if !regexp.MustCompile(`<script src="/static/term-definition\.js[^"]*" defer></script>`).MatchString(body) {
		t.Error("the page does not load term-definition.js")
	}

	// a requirement page, the term list and the term's own page
	if !hasLink(termLinks(get("/functional-requirements/FR-001-buy")), [3]string{href, order, "Order"}) {
		t.Error("the requirement page's term link carries no definition")
	}
	listed := false
	for _, l := range termLinks(get("/domain-terms")) {
		if l[0] == "/page/domain-terms/DT-002-item" && l[2] == "items" && len([]rune(l[1])) == 298 && strings.HasSuffix(l[1], "…") {
			listed = true
		}
	}
	if !listed {
		t.Error("the term list's link to Item carries no cut definition")
	}
	if !hasLink(termLinks(get(href)), [3]string{href, order, "Order"}) {
		t.Error("a term's link to itself carries no definition")
	}

	// a hostile definition stays text, through Markdown and in a frontmatter value
	for _, url := range []string{"/page/stakeholders/STK-001-reader", "/source/SRC-001-notes"} {
		doc := get(url)
		if strings.Contains(doc, "<script>alert") || regexp.MustCompile(`<img[^>]*onerror`).MatchString(doc) ||
			regexp.MustCompile(`href="\s*javascript:`).MatchString(doc) {
			t.Errorf("%s: a definition ran as markup", url)
		}
		var got [][3]string
		for _, l := range termLinks(doc) {
			if strings.HasSuffix(l[0], "DT-004-hostile") {
				got = append(got, l)
			}
		}
		if len(got) != 1 || got[0] != [3]string{"/page/domain-terms/DT-004-hostile", hostileText, "Hostile"} {
			t.Errorf("%s: hostile term links %v", url, got)
		}
	}

	// many links to two terms
	if n := len(termLinks(get("/page/stakeholders/STK-002-other"))); n != 80 {
		t.Errorf("80 term links expected, got %d", n)
	}
}
