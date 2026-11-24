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

// Port of tests/test_fr_page_head.py (issue #183, FR-034): a requirement page
// shows created date, updated date and tags like every other page.

var (
	pageMetaRE   = regexp.MustCompile(`(?s)<p class="detail-meta">.*?</p>`)
	betweenTagRE = regexp.MustCompile(`>\s+<`)
)

func TestRequirementPageHead(t *testing.T) {
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
	if err := os.WriteFile(cfgPath, []byte("system_name: Page head\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	const hostile = `<script>alert(1)</script>`
	const hostileAttr = `"><img src=x onerror=alert(2)>`
	hostileTags := "tags:\n  - zebra-tag\n  - '" + hostile + "'\n  - '" + hostileAttr + "'"
	agile := "status: draft\nnotation: agile\nlevel: story\n"
	body := "# T\n\nText.\n"
	fr := "functional-requirements"
	writePage(t, wikiDir, fr, "FR-001-agile", "id: FR-001\ntitle: Agile story\n"+agile+
		"created: 2026-03-04\nupdated: 2026-05-06\ntags: [zebra-tag, second-tag]", body)
	writePage(t, wikiDir, fr, "UC-001-use-case", "id: UC-001\ntitle: A use case\nstatus: draft\nnotation: use-case\nlevel: user-goal\n"+
		"created: 2026-07-08\nupdated: 2026-09-10\ntags: [uc-tag]", body)
	writePage(t, wikiDir, fr, "FR-002-bare", "id: FR-002\ntitle: Bare\n"+agile, body)
	writePage(t, wikiDir, fr, "FR-003-blank", "id: FR-003\ntitle: Blank\n"+agile+"created:\nupdated:\ntags:", body)
	writePage(t, wikiDir, fr, "FR-005-odd", "id: FR-005\ntitle: Odd\n"+agile+"created: 2026-13-01\ntags: lonely", body)
	writePage(t, wikiDir, fr, "FR-006-updated-only", "id: FR-006\ntitle: Updated only\n"+agile+"updated: 2026-11-12", body)
	writePage(t, wikiDir, fr, "FR-007-like-generic", "id: FR-007\ntitle: Like generic\n"+agile+
		"created: 2026-03-04\nupdated: 2026-05-06\n"+hostileTags, body)
	writePage(t, wikiDir, "constraints", "CON-001-generic", "id: CON-001\ntitle: Generic\nstatus: draft\n"+
		"created: 2026-03-04\nupdated: 2026-05-06\n"+hostileTags, body)
	writePage(t, wikiDir, "constraints", "CON-002-bare", "id: CON-002\ntitle: Bare\nstatus: draft", body)

	root := repoRoot(t)
	srv := web.NewServer(web.Options{
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

	get := func(url string) string {
		t.Helper()
		rec := doGet(srv, url)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", url, rec.Code)
		}
		return rec.Body.String()
	}
	// the page-head line, whitespace between tags removed
	meta := func(url string) string {
		t.Helper()
		found := pageMetaRE.FindAllString(get(url), -1)
		if len(found) > 1 {
			t.Fatalf("GET %s: %d page-head lines", url, len(found))
		}
		if len(found) == 0 {
			return ""
		}
		return betweenTagRE.ReplaceAllString(found[0], "><")
	}

	want := map[string]string{
		"/functional-requirements/FR-001-agile": `<p class="detail-meta"><span>created 2026-03-04</span>` +
			`<span>· updated 2026-05-06</span>` +
			`<span>· <span class="tag-chip">zebra-tag</span><span class="tag-chip">second-tag</span></span></p>`,
		"/functional-requirements/UC-001-use-case": `<p class="detail-meta"><span>created 2026-07-08</span>` +
			`<span>· updated 2026-09-10</span><span>· <span class="tag-chip">uc-tag</span></span></p>`,
		"/functional-requirements/FR-005-odd": `<p class="detail-meta"><span>created 2026-13-01</span>` +
			`<span>· <span class="tag-chip">lonely</span></span></p>`,
		"/functional-requirements/FR-006-updated-only": `<p class="detail-meta"><span>· updated 2026-11-12</span></p>`,
	}
	for url, w := range want {
		if got := meta(url); got != w {
			t.Errorf("GET %s page head:\n got %s\nwant %s", url, got, w)
		}
	}

	// none of the three: no line, no placeholder
	for _, url := range []string{"/functional-requirements/FR-002-bare", "/functional-requirements/FR-003-blank", "/page/constraints/CON-002-bare"} {
		doc := get(url)
		for _, bad := range []string{"detail-meta", "tag-chip", "created", "updated"} {
			if strings.Contains(doc, bad) {
				t.Errorf("GET %s contains %q", url, bad)
			}
		}
	}

	// hostile tags come out escaped, with the markup of the generic page
	doc := get("/functional-requirements/FR-007-like-generic")
	if strings.Contains(doc, hostile) || strings.Contains(doc, "<img src=x") {
		t.Error("a hostile tag reached the requirement page as markup")
	}
	got := meta("/functional-requirements/FR-007-like-generic")
	for _, w := range []string{
		`<span class="tag-chip">&lt;script&gt;alert(1)&lt;/script&gt;</span>`,
		`<span class="tag-chip">&#34;&gt;&lt;img src=x onerror=alert(2)&gt;</span>`,
	} {
		if !strings.Contains(got, w) {
			t.Errorf("page head lacks %s:\n%s", w, got)
		}
	}
	if generic := meta("/page/constraints/CON-001-generic"); generic == "" || generic != got {
		t.Errorf("requirement and generic page head differ:\n%s\n%s", got, generic)
	}
}
