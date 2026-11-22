package web_test

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"
	"time"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "..", ".."))
}

func newRepoServer(t *testing.T) *web.Server {
	t.Helper()
	root := repoRoot(t)
	paths, err := wiki.ResolvePaths(root, func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	return web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		HelpMD:      dashboard.HelpMD(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})
}

var nonceAttrRE = regexp.MustCompile(`nonce="([^"]+)"`)

func TestHomeHeadersAndNonces(t *testing.T) {
	srv := newRepoServer(t)

	rec1 := httptest.NewRecorder()
	srv.ServeHTTP(rec1, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec1.Code != http.StatusOK {
		t.Fatalf("GET / status = %d, want 200", rec1.Code)
	}
	if rec1.Header().Get("X-Frame-Options") != "DENY" {
		t.Fatalf("missing X-Frame-Options: DENY")
	}
	csp1 := rec1.Header().Get("Content-Security-Policy")
	m1 := nonceAttrRE.FindStringSubmatch(rec1.Body.String())
	if m1 == nil || !strings.Contains(csp1, "'nonce-"+m1[1]+"'") {
		t.Fatalf("CSP nonce mismatch: csp=%q", csp1)
	}
	body1 := rec1.Body.String()
	if !strings.Contains(body1, `title="Built with Go"`) || !strings.Contains(body1, `/static/go-logo.svg?v=`) || !strings.Contains(body1, `class="stack-icon stack-icon-go"`) || !strings.Contains(body1, `width="45" height="18"`) || !strings.Contains(body1, `alt="Go"`) {
		t.Fatalf("expected sized Go stack badge in footer")
	}
	badgeIdx := strings.Index(body1, `class="stack-badge"`)
	if badgeIdx < 0 {
		t.Fatalf("missing stack-badge in home HTML")
	}
	badgeEnd := strings.Index(body1[badgeIdx:], "</span>")
	badgeHTML := body1[badgeIdx : badgeIdx+badgeEnd]
	if !strings.Contains(badgeHTML, "Built with") || strings.HasSuffix(strings.TrimSpace(badgeHTML), "Go") {
		t.Fatalf("footer stack badge should show 'Built with' + Go logo without duplicate 'Go' text: %q", badgeHTML)
	}
	if strings.Contains(body1, `Built with Python + Flask`) {
		t.Fatalf("Go dashboard footer should not claim Python + Flask")
	}

	rec2 := httptest.NewRecorder()
	srv.ServeHTTP(rec2, httptest.NewRequest(http.MethodGet, "/", nil))
	m2 := nonceAttrRE.FindStringSubmatch(rec2.Body.String())
	if m2 == nil || m1[1] == m2[1] {
		t.Fatalf("expected fresh nonce per request, got %q and %q", m1[1], m2[1])
	}
}

func TestStaticAndBrandAndNotFound(t *testing.T) {
	srv := newRepoServer(t)

	// Embedded static file
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/static/style.css", nil))
	if rec.Code != http.StatusOK || rec.Body.Len() == 0 {
		t.Fatalf("GET /static/style.css = %d (%d bytes)", rec.Code, rec.Body.Len())
	}

	// Verify every file under disk static/ is embedded
	diskStatic := filepath.Join(repoRoot(t), "_system", "apps", "dashboard", "static")
	_ = filepath.WalkDir(diskStatic, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || d.Name() == ".DS_Store" {
			return nil
		}
		rel, _ := filepath.Rel(diskStatic, p)
		rel = filepath.ToSlash(rel)
		if _, err := fs.Stat(dashboard.StaticFS(), rel); err != nil {
			t.Errorf("static file %s not embedded: %v", rel, err)
		}
		return nil
	})

	// Brand mark headers and cache policy
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/brand/mark-dark.svg", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /brand/mark-dark.svg = %d", rec.Code)
	}
	if !strings.Contains(rec.Header().Get("Content-Security-Policy"), "sandbox") {
		t.Fatalf("brand mark missing sandbox CSP: %q", rec.Header().Get("Content-Security-Policy"))
	}
	if rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("brand mark missing nosniff")
	}

	// Brand intro sandbox
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/brand/intro.html?theme=light", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /brand/intro.html = %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `data-theme="light"`) || !strings.Contains(rec.Body.String(), ":root") {
		t.Fatalf("brand intro missing theme or tokens")
	}
	if rec.Header().Get("X-Frame-Options") != "SAMEORIGIN" {
		t.Fatalf("brand intro X-Frame-Options = %q", rec.Header().Get("X-Frame-Options"))
	}

	// 404 renders styled not_found page
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/does-not-exist", nil))
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "not found") {
		t.Fatalf("404 response unexpected: status=%d", rec.Code)
	}
}

func TestVersionAndMetamodelNoticesAndIntroOff(t *testing.T) {
	tmp := t.TempDir()
	_ = os.MkdirAll(filepath.Join(tmp, "wiki"), 0o755)
	_ = os.MkdirAll(filepath.Join(tmp, "raw", "sources"), 0o755)
	_ = os.MkdirAll(filepath.Join(tmp, "_system", "metamodel"), 0o755)
	_ = os.MkdirAll(filepath.Join(tmp, "_system", "anchors"), 0o755)
	_ = os.WriteFile(filepath.Join(tmp, "_system", "wiki.yaml"), []byte("dashboard_version: \"0.1.0\"\nintro: off\n"), 0o644)
	_ = os.WriteFile(filepath.Join(tmp, "_system", "metamodel", "meta-metamodel.md"), []byte("---\nversion: 0.2\n---\n"), 0o644)

	paths, _ := wiki.ResolvePaths(tmp, func(string) string { return "" })
	srv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     "0.12.0",
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})

	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	body := rec.Body.String()
	if rec.Code != http.StatusOK {
		t.Fatalf("GET / = %d", rec.Code)
	}
	if !strings.Contains(body, "This wiki asks for dashboard 0.1.0. This is 0.12.0.") {
		t.Error("expected dashboard version mismatch banner")
	}
	if !strings.Contains(body, "This wiki's metamodel is version 0.2.") {
		t.Error("expected metamodel version mismatch banner")
	}
	if strings.Contains(body, "brand-intro-frame") {
		t.Error("intro: off should suppress brand intro script")
	}

	recIntro := httptest.NewRecorder()
	srv.ServeHTTP(recIntro, httptest.NewRequest(http.MethodGet, "/brand/intro.html", nil))
	if recIntro.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for /brand/intro.html when intro: off, got %d", recIntro.Code)
	}
}

func TestHeartbeatPresenceReloadAndDisconnect(t *testing.T) {
	srv := newRepoServer(t)

	// Before any ping: count is 0, list is empty array
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/presence/count", nil))
	if rec.Code != http.StatusOK || rec.Body.String() != `{"count":0}` {
		t.Fatalf("GET /presence/count = %d %s", rec.Code, rec.Body.String())
	}
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/presence/list", nil))
	if rec.Code != http.StatusOK || rec.Body.String() != `{"clients":[]}` {
		t.Fatalf("GET /presence/list = %d %s", rec.Code, rec.Body.String())
	}

	// First tab pings -> Yoda + facilitator
	req := httptest.NewRequest(http.MethodPost, "/ping", strings.NewReader(`{"client_id":"tab-a"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"nickname":"Yoda"`) || !strings.Contains(rec.Body.String(), `"is_facilitator":true`) {
		t.Fatalf("POST /ping = %d %s", rec.Code, rec.Body.String())
	}

	// Count is now 1
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/presence/count", nil))
	if rec.Code != http.StatusOK || rec.Body.String() != `{"count":1}` {
		t.Fatalf("GET /presence/count after ping = %d %s", rec.Code, rec.Body.String())
	}

	// Reload succeeds
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/reload", nil))
	if rec.Code != http.StatusOK || rec.Body.String() != `{"ok":true}` {
		t.Fatalf("POST /reload = %d %s", rec.Code, rec.Body.String())
	}

	// Non-facilitator disconnect-all is rejected with 403
	req = httptest.NewRequest(http.MethodPost, "/disconnect-all", strings.NewReader(`{"client_id":"other"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("non-facilitator /disconnect-all = %d, want 403", rec.Code)
	}

	// Facilitator disconnect-all returns 204
	req = httptest.NewRequest(http.MethodPost, "/disconnect-all", strings.NewReader(`{"client_id":"tab-a"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("facilitator /disconnect-all = %d, want 204", rec.Code)
	}

	// /leaving returns 204
	req = httptest.NewRequest(http.MethodPost, "/leaving", strings.NewReader(`{"client_id":"tab-a"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("POST /leaving = %d, want 204", rec.Code)
	}
}

func TestPageAndSourceDetailRoutes(t *testing.T) {
	srv := newRepoServer(t)

	// Decision detail with drivers trace, provenance chip, relations, breadcrumb
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/page/decisions/DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET DR-007 = %d", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{
		"DR-007",
		`href="/decisions"`,
		`href="/source/SRC-036-grilling-session-on-running-without-a-container-engine"`,
		`href="/functional-requirements/FR-055-`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("DR-007 missing %q", want)
		}
	}

	// Issue detail page with issue fields
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/page/issues/ISS-001-who-holds-the-keys-in-parallel-work", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "ISS-001") {
		t.Fatalf("GET ISS-001 = %d", rec.Code)
	}

	// Quality requirement detail with Q42 anchor format label
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/page/quality-requirements/QR-003-works-in-every-current-browser", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "QR-003") {
		t.Fatalf("GET QR-003 = %d", rec.Code)
	}

	// Source detail page with source-facts and resolved ingested-pages wikilinks
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/source/SRC-036-grilling-session-on-running-without-a-container-engine", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET SRC-036 = %d", rec.Code)
	}
	srcBody := rec.Body.String()
	if !strings.Contains(srcBody, `<dl class="source-facts">`) || !strings.Contains(srcBody, `/page/decisions/DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go`) {
		t.Errorf("SRC-036 missing source-facts or ingested-pages link")
	}

	// Legacy redirects
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/page/adr/0007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go", nil))
	if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/page/decisions/DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go" {
		t.Fatalf("ADR redirect = %d -> %q", rec.Code, rec.Header().Get("Location"))
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/page/functional-requirements/FR-055-second-implementation-in-go", nil))
	if rec.Code != http.StatusFound || rec.Header().Get("Location") != "/functional-requirements/FR-055-second-implementation-in-go" {
		t.Fatalf("FR redirect = %d -> %q", rec.Code, rec.Header().Get("Location"))
	}
}

func TestPhase2AreasListsMetamodelAndCustomSection(t *testing.T) {
	srv := newRepoServer(t)

	// Areas and req42 blocks
	for _, u := range []string{"/req42", "/arc42", "/commons", "/req42/quality", "/req42/constraints", "/method", "/changes", "/domain-terms", "/stakeholders", "/decisions", "/issues", "/metamodel"} {
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, u, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d, want 200", u, rec.Code)
		}
	}
	// arc42 slug under /req42/ returns 404
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/req42/building-blocks", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("GET /req42/building-blocks = %d, want 404", rec.Code)
	}

	// Redirects preserve CSP + XFO + query
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/glossary?sort=title", nil))
	if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/domain-terms?sort=title" || rec.Header().Get("X-Frame-Options") != "DENY" {
		t.Fatalf("GET /glossary?sort=title = %d loc=%q xfo=%q", rec.Code, rec.Header().Get("Location"), rec.Header().Get("X-Frame-Options"))
	}
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/adrs", nil))
	if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/decisions" {
		t.Fatalf("GET /adrs = %d loc=%q", rec.Code, rec.Header().Get("Location"))
	}
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/section/C6", nil))
	if rec.Code != http.StatusFound || rec.Header().Get("Location") != "/issues" {
		t.Fatalf("GET /section/C6 = %d loc=%q", rec.Code, rec.Header().Get("Location"))
	}

	// /method links ISS-002 while open
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/method", nil))
	if !strings.Contains(rec.Body.String(), "ISS-002") {
		t.Error("expected ISS-002 link on /method")
	}

	// /issues legacy ?filter=open and case-insensitive ?section=c2
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/issues?filter=open&section=c2&severity=bogus", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `value="open" selected`) || !strings.Contains(rec.Body.String(), `value="C2" selected`) {
		t.Fatalf("GET /issues filtered unexpected: status=%d", rec.Code)
	}

	// Custom metamodel section A6 and renamed C6 (FR-044) plus unsafe projection route check
	tmp := t.TempDir()
	for _, f := range []string{"issues", "risks", "decisions"} {
		_ = os.MkdirAll(filepath.Join(tmp, "wiki", f), 0o755)
	}
	_ = os.MkdirAll(filepath.Join(tmp, "raw", "sources"), 0o755)
	_ = os.MkdirAll(filepath.Join(tmp, "_system", "anchors"), 0o755)
	_ = os.WriteFile(filepath.Join(tmp, "_system", "wiki.yaml"), []byte("system_name: Demo\nintro: off\n"), 0o644)

	srcMM := filepath.Join(repoRoot(t), "_system", "metamodel")
	dstMM := filepath.Join(tmp, "_system", "metamodel")
	_ = filepath.WalkDir(srcMM, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(srcMM, p)
		dst := filepath.Join(dstMM, rel)
		if d.IsDir() {
			return os.MkdirAll(dst, 0o755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(dst, b, 0o644)
	})
	// Rename C6 and add A6 + risk type + unsafe projection route
	fwCommons := filepath.Join(dstMM, "frameworks", "fw-commons.md")
	cb, _ := os.ReadFile(fwCommons)
	_ = os.WriteFile(fwCommons, []byte(strings.Replace(string(cb), `title: "Issues"`, `title: "Open Points"`, 1)), 0o644)

	fwArc := filepath.Join(dstMM, "frameworks", "fw-arc42.md")
	ab, _ := os.ReadFile(fwArc)
	_ = os.WriteFile(fwArc, []byte(strings.Replace(string(ab),
		"scope: in}\n",
		"scope: in}\n  - {id: A6, title: \"Risks\", types: [risk], scope: in}\n", 1)), 0o644)
	_ = os.WriteFile(filepath.Join(dstMM, "types", "type-risk.md"), []byte(
		"---\ntype: metamodel\nconstruct: type\nname: risk\nprefix: RSK\nfolder: wiki/risks\nlabel: Risk\nblock: A6\nlifecycle: content\nfields: []\n---\n\n# Type: risk\n\nA technical risk.\n"), 0o644)
	_ = os.WriteFile(filepath.Join(dstMM, "projections", "proj-evil.md"), []byte(
		"---\ntype: metamodel\nconstruct: projection\nname: evil-proj\noutput: table\nimplemented: //evil.example/x\nreads: []\n---\n\n# Evil\n\nTest unsafe route.\n"), 0o644)
	_ = os.WriteFile(filepath.Join(tmp, "wiki", "risks", "RSK-001-lockin.md"), []byte(
		"---\nid: RSK-001\ntype: risk\ntitle: Vendor lock-in\nstatus: draft\n---\n\n# Vendor lock-in\n"), 0o644)
	_ = os.WriteFile(filepath.Join(tmp, "wiki", "issues", "ISS-001-risk.md"), []byte(
		"---\nid: ISS-001\ntype: issue\ntitle: Mitigate lock-in\nstatus: open\nseverity: major\nrelated: [\"[[RSK-001-lockin]]\"]\n---\n\n# Mitigate\n"), 0o644)

	paths, _ := wiki.ResolvePaths(tmp, func(string) string { return "" })
	customSrv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})

	// /section/A6 and lowercase /section/a6 both render RSK-001; /section/R2 is 404 (out of scope)
	for _, u := range []string{"/section/A6", "/section/a6"} {
		r2 := httptest.NewRecorder()
		customSrv.ServeHTTP(r2, httptest.NewRequest(http.MethodGet, u, nil))
		if r2.Code != http.StatusOK || !strings.Contains(r2.Body.String(), "RSK-001") {
			t.Fatalf("GET %s = %d (missing RSK-001)", u, r2.Code)
		}
	}
	rOut := httptest.NewRecorder()
	customSrv.ServeHTTP(rOut, httptest.NewRequest(http.MethodGet, "/section/R2", nil))
	if rOut.Code != http.StatusNotFound {
		t.Fatalf("GET /section/R2 = %d, want 404", rOut.Code)
	}
	rArc := httptest.NewRecorder()
	customSrv.ServeHTTP(rArc, httptest.NewRequest(http.MethodGet, "/arc42", nil))
	if !strings.Contains(rArc.Body.String(), "A6 · Risks") || !strings.Contains(rArc.Body.String(), `href="/issues?section=A6"`) {
		t.Error("/arc42 missing custom A6 tile")
	}
	rIss := httptest.NewRecorder()
	customSrv.ServeHTTP(rIss, httptest.NewRequest(http.MethodGet, "/issues?section=A6", nil))
	if !strings.Contains(rIss.Body.String(), "ISS-001") || !strings.Contains(rIss.Body.String(), ">Open Points<") {
		t.Error("/issues missing A6 filter hit or renamed C6 nav label")
	}
	rMM := httptest.NewRecorder()
	customSrv.ServeHTTP(rMM, httptest.NewRequest(http.MethodGet, "/metamodel", nil))
	if strings.Contains(rMM.Body.String(), `href="//evil.example/x"`) {
		t.Error("/metamodel linked protocol-relative projection route //evil.example/x")
	}
	if !strings.Contains(rMM.Body.String(), `href="/arc42/deployment"`) || strings.Contains(rMM.Body.String(), `href="/arc42/deployment,"`) {
		t.Error("/metamodel did not strip trailing comma from projection route /arc42/deployment")
	}
}

func TestPhase3ProjectionRoutesAndFilters(t *testing.T) {
	srv := newRepoServer(t)

	for _, u := range []string{
		"/req42/scope", "/req42/models", "/req42/functional-requirements",
		"/goals", "/entity-diagram", "/graph/domain-terms",
		"/arc42/strategy", "/arc42/building-blocks", "/arc42/deployment", "/arc42/runtime", "/arc42/concepts",
		"/functional-requirements/FR-055-an-installable-dashboard-app",
	} {
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, u, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d, want 200", u, rec.Code)
		}
	}

	// Phase 3 legacy redirects
	for _, pair := range [][2]string{
		{"/data-model?context=Core", "/entity-diagram?context=Core"},
		{"/graph/glossary?edges=related", "/graph/domain-terms?edges=related"},
		{"/req42/backlog", "/req42/functional-requirements"},
	} {
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, pair[0], nil))
		if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != pair[1] {
			t.Fatalf("GET %s = %d loc=%q, want 301 -> %q", pair[0], rec.Code, rec.Header().Get("Location"), pair[1])
		}
	}

	// Focus filter on fixture:domain-model (exercises selectattr|map|first in data_model.html)
	fixtureRoot := filepath.Join(repoRoot(t), "_system", "apps", "dashboard", "tests", "fixtures", "domain-model")
	mmDir := filepath.Join(repoRoot(t), "_system", "metamodel")
	anchorsDir := filepath.Join(repoRoot(t), "_system", "anchors")
	dmSrv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      fixtureRoot,
			WikiDir:      filepath.Join(fixtureRoot, "wiki"),
			SourcesDir:   filepath.Join(fixtureRoot, "raw", "sources"),
			ConfigPath:   filepath.Join(fixtureRoot, "wiki.yaml"),
			DocsDir:      filepath.Join(fixtureRoot, "docs"),
			MetamodelDir: mmDir,
			NotationsDir: filepath.Join(repoRoot(t), "_system", "notations"),
			AnchorsDir:   anchorsDir,
		},
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})
	rec := httptest.NewRecorder()
	dmSrv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/entity-diagram?focus=DT-002-order", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Order") || !strings.Contains(rec.Body.String(), "and its direct neighbours") {
		t.Fatalf("GET /entity-diagram?focus=DT-002-order failed: status=%d", rec.Code)
	}
}

func TestPhase4And5SearchSettingsHelpAbout(t *testing.T) {
	srv := newRepoServer(t)

	// /search, /search.json, /join, /who, /help
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/search", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "S42Search.filter(") {
		t.Fatalf("GET /search failed: %d", rec.Code)
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/search.json", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /search.json = %d, want 200", rec.Code)
	}
	var sidx map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &sidx); err != nil {
		t.Fatalf("unmarshal /search.json: %v", err)
	}
	if _, ok := sidx["records"]; !ok {
		t.Fatalf("/search.json missing records key")
	}
	if _, ok := sidx["synonyms"]; !ok {
		t.Fatalf("/search.json missing synonyms key")
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/join", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "<svg") || !strings.Contains(rec.Body.String(), "http://127.0.0.1:8080") {
		t.Fatalf("GET /join failed: %d", rec.Code)
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/who", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "/presence/list") {
		t.Fatalf("GET /who failed: %d", rec.Code)
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/help", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `<h2 id="llm-wiki">`) || !strings.Contains(rec.Body.String(), "systems42-sections.svg") {
		t.Fatalf("GET /help failed: status=%d", rec.Code)
	}

	// /settings GET + POST authorization, validation, and live view hiding (FR-046)
	postJSON := func(s *web.Server, target, body string) *httptest.ResponseRecorder {
		r := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		s.ServeHTTP(r, req)
		return r
	}
	if r := postJSON(srv, "/ping", `{"client_id":"yoda"}`); r.Code != http.StatusOK {
		t.Fatalf("ping yoda = %d", r.Code)
	}
	if r := postJSON(srv, "/ping", `{"client_id":"padawan"}`); r.Code != http.StatusOK {
		t.Fatalf("ping padawan = %d", r.Code)
	}
	if r := postJSON(srv, "/settings", `{"client_id":"padawan","hidden":["C4"]}`); r.Code != http.StatusForbidden {
		t.Fatalf("non-facilitator POST /settings = %d, want 403", r.Code)
	}
	if r := postJSON(srv, "/settings", `{"client_id":"yoda","hidden":["C4","bogus"]}`); r.Code != http.StatusBadRequest {
		t.Fatalf("unknown ID POST /settings = %d, want 400", r.Code)
	}
	rSave := postJSON(srv, "/settings", `{"client_id":"yoda","hidden":["c4","architecture"]}`)
	if rSave.Code != http.StatusOK {
		t.Fatalf("facilitator POST /settings = %d, want 200", rSave.Code)
	}
	var saved struct {
		OK     bool     `json:"ok"`
		Hidden []string `json:"hidden"`
	}
	if err := json.Unmarshal(rSave.Body.Bytes(), &saved); err != nil || !saved.OK || len(saved.Hidden) != 2 || saved.Hidden[0] != "architecture" || saved.Hidden[1] != "C4" {
		t.Fatalf("unexpected POST /settings reply: %s", rSave.Body.String())
	}

	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if strings.Contains(rec.Body.String(), `href="/stakeholders"`) {
		t.Fatalf("hidden C4 still shown on /")
	}
	// Hidden section remains directly addressable by URL.
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/stakeholders", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("hidden /stakeholders returned %d, want 200", rec.Code)
	}
	if r := postJSON(srv, "/settings", `{"client_id":"yoda","hidden":[]}`); r.Code != http.StatusOK {
		t.Fatalf("unhide POST /settings = %d", r.Code)
	}

	// /about and /about/files/ with relative image rewriting, symlink rejection, and disconnect-all
	tmp := t.TempDir()
	docs := filepath.Join(tmp, "docs")
	_ = os.MkdirAll(filepath.Join(docs, "brand", "svg"), 0o755)
	_ = os.WriteFile(filepath.Join(docs, "brand", "README.md"),
		[]byte("# Brand\n\n![mark](svg/mark.svg) ![shared](../shared.svg) ![out](../../secret.md)\n"), 0o644)
	_ = os.WriteFile(filepath.Join(docs, "brand", "svg", "mark.svg"), []byte(`<svg xmlns="http://www.w3.org/2000/svg"/>`), 0o644)
	_ = os.WriteFile(filepath.Join(docs, "shared.svg"), []byte(`<svg xmlns="http://www.w3.org/2000/svg"/>`), 0o644)
	_ = os.WriteFile(filepath.Join(tmp, "secret.md"), []byte("# secret\n"), 0o644)
	_ = os.Symlink(filepath.Join(tmp, "secret.md"), filepath.Join(docs, "brand", "leak.md"))
	cfgPath := filepath.Join(tmp, "wiki.yaml")
	_ = os.WriteFile(cfgPath, []byte("system_name: Demo\nabout: docs/brand/README.md\n"), 0o644)

	shutdownCh := make(chan string, 1)
	aboutSrv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      filepath.Join(tmp, "wiki"),
			SourcesDir:   filepath.Join(tmp, "raw", "sources"),
			ConfigPath:   cfgPath,
			DocsDir:      docs,
			MetamodelDir: filepath.Join(repoRoot(t), "_system", "metamodel"),
			NotationsDir: filepath.Join(repoRoot(t), "_system", "notations"),
			AnchorsDir:   filepath.Join(repoRoot(t), "_system", "anchors"),
		},
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		HelpMD:      dashboard.HelpMD(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
		OnShutdown:  func(reason string) { shutdownCh <- reason },
	})

	rec = httptest.NewRecorder()
	aboutSrv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/about", nil))
	body := rec.Body.String()
	if rec.Code != http.StatusOK || !strings.Contains(body, `src="/about/files/brand/svg/mark.svg"`) || !strings.Contains(body, `src="/about/files/shared.svg"`) || !strings.Contains(body, `src="../../secret.md"`) {
		t.Fatalf("GET /about unexpected rewrite: status=%d body=%s", rec.Code, body)
	}
	rec = httptest.NewRecorder()
	aboutSrv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/about/files/shared.svg", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Header().Get("Content-Security-Policy"), "sandbox") {
		t.Fatalf("GET /about/files/shared.svg = %d csp=%q", rec.Code, rec.Header().Get("Content-Security-Policy"))
	}
	rec = httptest.NewRecorder()
	aboutSrv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/about/files/brand/leak.md", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("symlink escape /about/files/brand/leak.md = %d, want 404", rec.Code)
	}

	// Disconnect-all requires facilitator and triggers OnShutdown asynchronously.
	_ = postJSON(aboutSrv, "/ping", `{"client_id":"yoda"}`)
	_ = postJSON(aboutSrv, "/ping", `{"client_id":"guest"}`)
	if r := postJSON(aboutSrv, "/disconnect-all", `{"client_id":"guest"}`); r.Code != http.StatusForbidden {
		t.Fatalf("non-facilitator /disconnect-all = %d, want 403", r.Code)
	}
	if r := postJSON(aboutSrv, "/disconnect-all", `{"client_id":"yoda"}`); r.Code != http.StatusNoContent {
		t.Fatalf("facilitator /disconnect-all = %d, want 204", r.Code)
	}
	select {
	case reason := <-shutdownCh:
		if reason == "" {
			t.Fatalf("disconnect-all fired empty shutdown reason")
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("disconnect-all did not invoke OnShutdown within 2s")
	}
}
