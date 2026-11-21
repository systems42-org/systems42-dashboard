package web_test

import (
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"

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
