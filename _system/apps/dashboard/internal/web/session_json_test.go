package web_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// A session endpoint answers 400 to a JSON body that is not an object and
// leaves the session as it was (issue #184). "anon" holds the facilitator
// role here: the worst case, because a body read as an empty object would act
// with the facilitator's rights.
func TestSessionEndpointsRejectJSONThatIsNotAnObject(t *testing.T) {
	paths, err := wiki.ResolvePaths(repoRoot(t), func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	var shutdowns []string
	srv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		HelpMD:      dashboard.HelpMD(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
		OnShutdown: func(reason string) {
			mu.Lock()
			shutdowns = append(shutdowns, reason)
			mu.Unlock()
		},
	})
	post := func(target, body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		srv.ServeHTTP(rec, req)
		return rec
	}
	get := func(target string) string {
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, target, nil))
		return rec.Body.String()
	}
	hidden := func() string {
		body := get("/settings")
		return body[strings.LastIndex(body, `"hidden"`):]
	}

	routes := []string{"/ping", "/leaving", "/settings", "/disconnect-all"}
	notObjects := []string{`["x"]`, `[]`, `"x"`, `""`, `7`, `0`, `1.5`, `true`, `false`}

	// Before any page has connected: a rejected ping must not connect one.
	for _, body := range notObjects {
		if rec := post("/ping", body); rec.Code != http.StatusBadRequest {
			t.Fatalf("POST /ping %s = %d, want 400", body, rec.Code)
		}
	}
	if got := get("/presence/count"); got != `{"count":0}` {
		t.Fatalf("rejected pings connected a page: %s", got)
	}

	// No body, an unreadable body and null still mean an empty object.
	for _, body := range []string{"", "{not json", "null"} {
		rec := post("/ping", body)
		if rec.Code != http.StatusOK || rec.Body.String() != `{"nickname":"Yoda","is_facilitator":true}` {
			t.Fatalf("POST /ping %q = %d %s", body, rec.Code, rec.Body.String())
		}
		rec = post("/settings", body)
		if rec.Code != http.StatusBadRequest || rec.Body.String() != `{"error":"unknown","unknown":[]}` {
			t.Fatalf("POST /settings %q = %d %s", body, rec.Code, rec.Body.String())
		}
	}
	if rec := post("/settings", `{"hidden":["C6"]}`); rec.Code != http.StatusOK {
		t.Fatalf("POST /settings as anon facilitator = %d %s", rec.Code, rec.Body.String())
	}

	wantHidden, wantList := hidden(), get("/presence/list")
	if !strings.Contains(wantHidden, `"C6"`) || !strings.Contains(wantList, `"Yoda"`) {
		t.Fatalf("setup: hidden %s, list %s", wantHidden, wantList)
	}
	for _, route := range routes {
		for _, body := range notObjects {
			rec := post(route, body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("POST %s %s = %d, want 400", route, body, rec.Code)
			}
			if got := rec.Body.String(); got != `{"error":"not-an-object"}` {
				t.Fatalf("POST %s %s body = %s", route, body, got)
			}
			if got := hidden(); got != wantHidden {
				t.Fatalf("POST %s %s changed the view: %s", route, body, got)
			}
		}
	}
	// A rejected /leaving would drop "anon" from the list, a rejected ping
	// with another identity would add a row.
	if got := get("/presence/list"); got != wantList {
		t.Fatalf("rejected bodies changed presence: %s, want %s", got, wantList)
	}
	// /disconnect-all calls OnShutdown 400 ms after a request it accepts.
	time.Sleep(600 * time.Millisecond)
	mu.Lock()
	n := len(shutdowns)
	mu.Unlock()
	if n != 0 {
		t.Fatalf("rejected bodies triggered shutdown: %v", shutdowns)
	}

	// The same route with a valid object still stops the server.
	if rec := post("/disconnect-all", `{}`); rec.Code != http.StatusNoContent {
		t.Fatalf("POST /disconnect-all {} = %d, want 204", rec.Code)
	}
	time.Sleep(600 * time.Millisecond)
	mu.Lock()
	n = len(shutdowns)
	mu.Unlock()
	if n != 1 {
		t.Fatalf("valid /disconnect-all: %d shutdowns, want 1", n)
	}
}
