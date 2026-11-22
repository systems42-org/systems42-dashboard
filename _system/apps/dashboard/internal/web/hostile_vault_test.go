package web_test

import (
	"fmt"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"golang.org/x/net/html"
	"gopkg.in/yaml.v3"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// Port of tests/test_hostile_vault.py and tests/test_hostile_every_type.py to
// Go (issue #80 Phase 1): proves the Go implementation upholds the exact
// security boundary of the Python reference.

func writePage(t *testing.T, wikiDir, folder, stem, frontmatter, body string) {
	t.Helper()
	p := filepath.Join(wikiDir, folder, stem+".md")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	content := "---\n" + frontmatter + "\n---\n" + body
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func doGet(srv http.Handler, rawTarget string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1"+rawTarget, nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	return rec
}

func TestHostileVault(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	wikiDir := filepath.Join(repo, "wiki")
	sourcesDir := filepath.Join(repo, "raw", "sources")
	docsDir := filepath.Join(repo, "docs")
	folders := []string{
		"glossary", "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
		"data-models", "activity-models", "use-cases", "functional-requirements",
		"quality-requirements", "constraints", "issues", "building-blocks", "decisions",
		"solution-strategy", "crosscutting-concepts", "runtime-scenarios", "deployment-nodes",
	}
	for _, f := range folders {
		_ = os.MkdirAll(filepath.Join(wikiDir, f), 0o755)
	}
	_ = os.MkdirAll(filepath.Join(wikiDir, ".obsidian"), 0o755)
	_ = os.MkdirAll(sourcesDir, 0o755)
	_ = os.MkdirAll(docsDir, 0o755)

	// Broken frontmatter, blank titles, scalars where lists belong
	writePage(t, wikiDir, "issues", "ISS-001-string-frontmatter", "just a string", "# T\n")
	writePage(t, wikiDir, "constraints", "CON-001-list-frontmatter", "- a\n- b", "# T\n")
	writePage(t, wikiDir, "glossary", "GLO-001-blank-title", "id: GLO-001\ntitle:\nstatus: draft\ntags: single\naliases: Alias\nrelated: 7", "**Definition.** plain.\n")
	writePage(t, wikiDir, "functional-requirements", "FR-001-scalar-parent", "id: FR-001\ntitle: Scalar parent\nstereotype: story\nparent: 7\ngoal: 7\nrelated: 7", "# T\n")
	writePage(t, wikiDir, "use-cases", "UC-001-scalar-goal", "id: UC-001\ntitle: Use case\ngoal: 7\nrelated: 7\nparent: 7", "# T\n")
	writePage(t, wikiDir, "stakeholders", "STK-001-list-influence", "id: STK-001\ntitle: Lists\ninfluence: [high]\ninterest: [low]\nprovides: 7\nreceives: 7", "# T\n")
	writePage(t, wikiDir, "context", "CTX-001-scalar-flows", "id: CTX-001\ntitle: Ctx\nrelated: 7", "# T\n")
	writePage(t, wikiDir, "external-interfaces", "EIF-001-scalar-flows", "id: EIF-001\ntitle: Eif\npartner: x\nflows: 7", "# T\n")
	writePage(t, wikiDir, "data-models", "DM-001-scalar-relationships", "id: DM-001\ntitle: Entity\nrelationships: 7\nparent: 7\nrelated: 7", "# T\n")
	writePage(t, wikiDir, "domain-terms", "DT-001-scalar-lists", "id: DT-001\ntitle: Term\nstereotype: entity\nattributes: 7\nrelationships: 7\nrelated: 7\naliases: 7", "**Definition.** A term.\n")
	writePage(t, wikiDir, "quality-requirements", "QR-001-scalar-dimensions", "id: QR-001\ntitle: Quality\ndimensions: 7\nrelated: 7", "# T\n")
	writePage(t, wikiDir, "building-blocks", "BB-001-scalars", "id: BB-001\ntitle: Block\nstate: current\nparent: 7\nuses: 7\ndrivers: 7\ndecisions: 7", "# T\n")
	writePage(t, wikiDir, "deployment-nodes", "DN-001-scalars", "id: DN-001\ntitle: Node\nstereotype: host\nstate: current\nparent: 7\nhosts: 7\nconnects: 7", "# T\n")
	writePage(t, wikiDir, "runtime-scenarios", "RS-001-scalars", "id: RS-001\ntitle: Scenario\nstate: current\nsteps: 7\nrealizes: 7", "# T\n")
	writePage(t, wikiDir, "crosscutting-concepts", "CC-001-scalars", "id: CC-001\ntitle: Concept\nstate: current\napplies-to: 7", "# T\n")
	writePage(t, wikiDir, "solution-strategy", "SOL-001-scalars", "id: SOL-001\ntitle: Strategy\nstate: current\ndrivers: 7\ndecisions: 7\nsuperseded-by: 7", "# T\n")
	writePage(t, wikiDir, "decisions", `DR-002-quote" onmouseover="x`, "id: DR-002\ntitle: Quote in the file name", "# T\n")
	writePage(t, wikiDir, "decisions", "DR-001-scalars", "id: DR-001\ntitle: Decision\nkind: 7\ndrivers: 7\ntags: 7", "# T\n")

	// Non-UTF-8 bytes (Latin-1)
	_ = os.WriteFile(filepath.Join(wikiDir, "glossary", "GLO-002-latin1.md"),
		[]byte("---\nid: GLO-002\ntitle: Latin-1\n---\n**Definition.** Gr\xfc\xdfe.\n"), 0o644)

	// Hostile markup
	writePage(t, wikiDir, "glossary", "GLO-003-hostile-title",
		`id: GLO-003`+"\n"+`title: "<img src=x onerror=alert(1)>"`,
		"**Definition.** <script>alert(2)</script> see [[GLO-004-linker]].\n")
	writePage(t, wikiDir, "glossary", "GLO-004-linker",
		"id: GLO-004\ntitle: Linker",
		"**Definition.** Points at [[GLO-003-hostile-title]] and "+
			"[[GLO-003-hostile-title|<b>an alias</b>]].\n\n"+
			`<a href="javascript:alert(3)">click</a> <img src=x onerror=alert(4)>`+"\n\n"+
			`<div id="settings-dialog" class="fbtn">hijack</div>`+"\n\n"+
			"| a | b |\n|:--|--:|\n| 1 | 2 |\n\n```mermaid\ngraph TD; A-->B\n```\n\n"+
			"A note.[^1]\n\n[^1]: The footnote.\n")
	writePage(t, wikiDir, "goals", "GOAL-001-vision",
		"id: GOAL-001\ntitle: Vision\nstereotype: vision",
		"# Vision\n\n## Vision\n\nA vision <script>alert(5)</script>.\n")

	// Hostile source record
	_ = os.WriteFile(filepath.Join(sourcesDir, "SRC-001-hostile.md"),
		[]byte("---\nid: SRC-001\ntitle: Source\ntype: source\ningested-pages: \"<b>x</b> [[GLO-004-linker]]\"\ntags: one\n---\n# Source\n\n<script>alert(6)</script>\n"), 0o644)

	// Files beside and above wiki/
	_ = os.WriteFile(filepath.Join(repo, "outside.md"), []byte("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n"), 0o644)
	_ = os.WriteFile(filepath.Join(wikiDir, ".obsidian", "outside.md"), []byte("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n"), 0o644)
	_ = os.WriteFile(filepath.Join(wikiDir, "outside.md"), []byte("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n"), 0o644)
	_ = os.WriteFile(filepath.Join(repo, "secret.txt"), []byte("TOP SECRET"), 0o644)

	// Brand folder with symlinked intro escaping the folder + extra secret file
	brandDir := filepath.Join(repo, "brand")
	_ = os.MkdirAll(brandDir, 0o755)
	for _, m := range wiki.BrandMarks {
		_ = os.WriteFile(filepath.Join(brandDir, m), []byte(`<svg xmlns="http://www.w3.org/2000/svg"/>`), 0o644)
	}
	_ = os.WriteFile(filepath.Join(repo, "elsewhere.html"), []byte("<p>OUTSIDE INTRO</p>"), 0o644)
	_ = os.Symlink(filepath.Join(repo, "elsewhere.html"), filepath.Join(brandDir, "intro.html"))
	_ = os.WriteFile(filepath.Join(brandDir, "secret.svg"), []byte("<svg>TOP SECRET</svg>"), 0o644)
	cfgPath := filepath.Join(tmp, "wiki.yaml")
	_ = os.WriteFile(cfgPath, []byte("system_name: Hostile\nbrand: brand\n"), 0o644)

	// Symlinks out of the wiki vs inside the wiki
	outDir := filepath.Join(tmp, "outside")
	_ = os.MkdirAll(outDir, 0o755)
	_ = os.WriteFile(filepath.Join(outDir, "notes.md"), []byte("---\nid: GLO-099\ntitle: Linked out\n---\nLINKED SECRET\n"), 0o644)
	_ = os.WriteFile(filepath.Join(outDir, "SRC-099-notes.md"), []byte("---\nid: SRC-099\ntitle: Linked out\n---\nLINKED SECRET\n"), 0o644)
	_ = os.Symlink(filepath.Join(outDir, "notes.md"), filepath.Join(wikiDir, "glossary", "GLO-005-linked-out.md"))
	_ = os.Symlink(outDir, filepath.Join(wikiDir, "linked"))
	_ = os.Symlink(filepath.Join(outDir, "SRC-099-notes.md"), filepath.Join(sourcesDir, "SRC-002-linked-out.md"))

	writePage(t, wikiDir, "constraints", "CON-002-link-target", "id: CON-002\ntitle: Linked inside", "LINKED INSIDE\n")
	_ = os.Symlink(filepath.Join(wikiDir, "constraints", "CON-002-link-target.md"), filepath.Join(wikiDir, "glossary", "GLO-006-linked-in.md"))
	_ = os.MkdirAll(filepath.Join(wikiDir, ".shared"), 0o755)
	_ = os.WriteFile(filepath.Join(wikiDir, ".shared", "LNK-001-inside.md"), []byte("---\nid: LNK-001\ntitle: In a linked folder\n---\nLINKED FOLDER\n"), 0o644)
	_ = os.Symlink(filepath.Join(wikiDir, ".shared"), filepath.Join(wikiDir, "shared"))

	mmDir := filepath.Join(repoRoot(t), "_system", "metamodel")
	anchorsDir := filepath.Join(repoRoot(t), "_system", "anchors")
	paths := wiki.Paths{
		RepoDir:      repo,
		WikiDir:      wikiDir,
		SourcesDir:   sourcesDir,
		ConfigPath:   cfgPath,
		DocsDir:      docsDir,
		MetamodelDir: mmDir,
		NotationsDir: filepath.Join(repoRoot(t), "_system", "notations"),
		AnchorsDir:   anchorsDir,
	}
	srv := web.NewServer(web.Options{
		Paths:       paths,
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})

	// 1. Every valid page and source renders 200 without crashing
	for _, f := range folders {
		if f == "functional-requirements" {
			continue
		}
		entries, _ := os.ReadDir(filepath.Join(wikiDir, f))
		for _, e := range entries {
			if !strings.HasSuffix(e.Name(), ".md") {
				continue
			}
			stem := strings.TrimSuffix(e.Name(), ".md")
			if stem == "GLO-005-linked-out" {
				continue
			}
			// Skip filename with double quote in raw URL path unless percent-encoded
			target := "/page/" + f + "/" + strings.ReplaceAll(strings.ReplaceAll(stem, `"`, `%22`), " ", `%20`)
			rec := doGet(srv, target)
			if rec.Code != http.StatusOK {
				t.Errorf("GET %s = %d, want 200", target, rec.Code)
			}
		}
	}
	for _, u := range []string{
		"/", "/req42", "/arc42", "/commons", "/req42/scope", "/req42/models",
		"/req42/quality", "/req42/constraints", "/req42/functional-requirements",
		"/goals", "/entity-diagram", "/graph/domain-terms",
		"/arc42/strategy", "/arc42/building-blocks", "/arc42/deployment", "/arc42/runtime", "/arc42/concepts",
		"/metamodel", "/method", "/changes", "/issues", "/issues?status=open",
		"/stakeholders", "/decisions", "/domain-terms", "/source/SRC-001-hostile",
	} {
		if rec := doGet(srv, u); rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", u, rec.Code)
		}
	}

	// 2. Bad fields fall back and non-UTF-8 renders replacement chars
	p := srv.Store.LoadPage("glossary", "GLO-001-blank-title")
	if p == nil || p.Title() != "GLO-001-blank-title" || len(p.Aliases()) != 1 || p.Aliases()[0] != "Alias" || len(p.AsStringList("tags")) != 1 || p.AsStringList("tags")[0] != "single" {
		t.Fatalf("GLO-001 fallback failed: %+v", p)
	}
	if rec := doGet(srv, "/page/glossary/GLO-002-latin1"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Gr\uFFFD\uFFFDe") {
		t.Fatalf("Latin-1 fallback failed: status=%d", rec.Code)
	}

	// 3. Titles and bodies render inert, while legitimate content survives
	rec := doGet(srv, "/page/glossary/GLO-004-linker")
	body := rec.Body.String()
	onerrorRE := regexp.MustCompile(`<img[^>]*onerror`)
	if onerrorRE.MatchString(body) {
		t.Error("hostile img onerror survived in GLO-004-linker")
	}
	for _, want := range []string{
		`&lt;img src=x onerror=alert(1)&gt;`,
		`&lt;b&gt;an alias&lt;/b&gt;`,
		`style="text-align:left"`,
		`class="language-mermaid"`,
		`<a class="wl" href="/page/glossary/GLO-003-hostile-title">`,
		`id="fn:1"`,
		`class="footnote-ref"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("GLO-004-linker missing expected safe content %q", want)
		}
	}
	for _, bad := range []string{"javascript:alert", "<script>alert", `class="fbtn"`} {
		if strings.Contains(body, bad) {
			t.Errorf("GLO-004-linker leaked %q", bad)
		}
	}
	if strings.Count(body, `id="settings-dialog"`) != 1 {
		t.Errorf("wiki text clobbered id=settings-dialog (count=%d)", strings.Count(body, `id="settings-dialog"`))
	}
	if rec := doGet(srv, "/page/glossary/GLO-003-hostile-title"); strings.Contains(rec.Body.String(), "<script>alert(2)") {
		t.Error("script tag leaked in GLO-003-hostile-title")
	}

	// 4. Frontmatter strings escaped in /source/SRC-001-hostile
	srcBody := doGet(srv, "/source/SRC-001-hostile").Body.String()
	if strings.Contains(srcBody, "<b>x</b>") || !strings.Contains(srcBody, "&lt;b&gt;x&lt;/b&gt;") {
		t.Error("ingested-pages ran as markup in /source/SRC-001-hostile")
	}
	if !strings.Contains(srcBody, `href="/page/glossary/GLO-004-linker"`) {
		t.Error("wikilink in ingested-pages did not resolve")
	}
	if strings.Contains(srcBody, "<script>alert(6)") {
		t.Error("script tag leaked in /source/SRC-001-hostile")
	}

	// 5. Traversal guards on /page/, /source/, /brand/
	for _, url := range []string{
		"/page/../outside", "/page/./outside", "/page/.obsidian/outside", "/page/%2e%2e/outside",
		"/page/no-such-folder/GLO-004-linker",
		"/page/glossary/..", "/page/glossary/.", "/page/glossary/..%2Foutside",
		"/source/..", "/source/../outside", "/source/%2e%2e%2foutside", "/source/no-such-source",
		"/brand/secret.svg", "/brand/intro.html", "/brand/..%2Fsecret.txt", "/brand/%2e%2e",
	} {
		rec := doGet(srv, url)
		if rec.Code != http.StatusNotFound || strings.Contains(rec.Body.String(), "TOP SECRET") || strings.Contains(rec.Body.String(), "OUTSIDE INTRO") {
			t.Errorf("traversal/forbidden %s = %d (leaked secret?)", url, rec.Code)
		}
	}
	if rec := doGet(srv, "/"); strings.Contains(rec.Body.String(), "OUTSIDE INTRO") {
		t.Error("symlinked brand intro leaked onto home page")
	}
	if rec := doGet(srv, "/brand/mark-dark.svg"); rec.Code != http.StatusOK || !strings.Contains(rec.Header().Get("Content-Security-Policy"), "sandbox") || rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("brand mark headers wrong: status=%d csp=%q", rec.Code, rec.Header().Get("Content-Security-Policy"))
	}

	// 6. Symlinks outside wiki rejected; symlinks inside wiki work
	for _, url := range []string{
		"/page/glossary/GLO-005-linked-out", "/page/linked/notes",
		"/page/linked/SRC-099-notes", "/source/SRC-002-linked-out", "/source/SRC-099",
	} {
		rec := doGet(srv, url)
		if rec.Code != http.StatusNotFound || strings.Contains(rec.Body.String(), "LINKED SECRET") {
			t.Errorf("outside symlink %s = %d", url, rec.Code)
		}
	}
	if home := doGet(srv, "/").Body.String(); strings.Contains(home, "LINKED SECRET") || strings.Contains(home, "Linked out") {
		t.Error("outside symlink leaked onto home page")
	}
	if rec := doGet(srv, "/page/glossary/GLO-006-linked-in"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "LINKED INSIDE") {
		t.Errorf("inside file symlink failed: status=%d", rec.Code)
	}
	if rec := doGet(srv, "/page/shared/LNK-001-inside"); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "LINKED FOLDER") {
		t.Errorf("inside dir symlink failed: status=%d", rec.Code)
	}

	// 7. Redirects: /page/adr/* and /page/functional-requirements/*
	if rec := doGet(srv, "/page/adr/0001-scalars"); rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/page/decisions/DR-001-scalars" {
		t.Errorf("ADR redirect = %d -> %q", rec.Code, rec.Header().Get("Location"))
	}
	if rec := doGet(srv, "/page/adr/9999-missing"); rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/decisions" {
		t.Errorf("missing ADR redirect = %d -> %q", rec.Code, rec.Header().Get("Location"))
	}
	if rec := doGet(srv, "/page/functional-requirements/FR-001-scalar-parent"); rec.Code != http.StatusFound || rec.Header().Get("Location") != "/functional-requirements/FR-001-scalar-parent" {
		t.Errorf("FR redirect = %d -> %q", rec.Code, rec.Header().Get("Location"))
	}

	// 8. CSP nonces and clickjacking protection on every HTML page
	scriptTagRE := regexp.MustCompile(`<script\b[^>]*>`)
	cspNonceRE := regexp.MustCompile(`'nonce-([\w-]{16,})'`)
	nonces := map[string]bool{}
	for _, url := range []string{"/", "/page/glossary/GLO-004-linker", "/source/SRC-001-hostile", "/no-such-page"} {
		rec := doGet(srv, url)
		csp := rec.Header().Get("Content-Security-Policy")
		if !strings.Contains(csp, "default-src 'self'") ||
			!strings.Contains(csp, "object-src 'none'") ||
			!strings.Contains(csp, "base-uri 'none'") ||
			!strings.Contains(csp, "frame-ancestors 'none'") ||
			rec.Header().Get("X-Frame-Options") != "DENY" {
			t.Errorf("CSP/XFO failed on %s: csp=%q xfo=%q", url, csp, rec.Header().Get("X-Frame-Options"))
		}
		m := cspNonceRE.FindStringSubmatch(csp)
		if m == nil {
			t.Fatalf("missing valid nonce in CSP on %s: %q", url, csp)
		}
		nonce := m[1]
		nonces[nonce] = true
		pageHTML := rec.Body.String()
		for _, tag := range scriptTagRE.FindAllString(pageHTML, -1) {
			if strings.Contains(tag, "src=") || strings.Contains(tag, `type="application/json"`) {
				continue
			}
			if !strings.Contains(tag, `nonce="`+nonce+`"`) {
				t.Errorf("%s has inline script without matching nonce: %s", url, tag)
			}
		}
	}
	if len(nonces) != 4 {
		t.Errorf("expected 4 distinct nonces, got %d", len(nonces))
	}
}

func checkLiveMarkup(t *testing.T, url, doc, mark string) {
	t.Helper()
	root, err := html.Parse(strings.NewReader(doc))
	if err != nil {
		t.Fatalf("%s: html.Parse failed: %v", url, err)
	}
	dialogIDs := 0
	var walk func(n *html.Node, scriptType string)
	walk = func(n *html.Node, scriptType string) {
		if n.Type == html.ElementNode {
			tag := strings.ToLower(n.Data)
			attrs := map[string]string{}
			for _, a := range n.Attr {
				k := strings.ToLower(a.Key)
				attrs[k] = a.Val
				if strings.HasPrefix(k, "on") && strings.Contains(a.Val, mark) {
					t.Errorf("%s: <%s %s=...> event handler from wiki text", url, tag, k)
				}
				if k == "href" || k == "src" || k == "action" || k == "formaction" {
					compact := strings.ToLower(strings.Join(strings.Fields(a.Val), ""))
					if strings.HasPrefix(compact, "javascript:") {
						t.Errorf("%s: <%s %s=javascript:...>", url, tag, k)
					}
				}
			}
			if attrs["id"] == "settings-dialog" {
				dialogIDs++
			}
			nextScript := scriptType
			if tag == "script" {
				nextScript = strings.ToLower(attrs["type"])
				if nextScript == "" {
					nextScript = "text/javascript"
				}
			}
			if tag == "span" && n.FirstChild != nil && n.FirstChild.Type == html.TextNode && strings.TrimSpace(n.FirstChild.Data) == mark+"span" {
				if attrs["id"] != "" {
					t.Errorf("%s: wiki <span> kept id=%q", url, attrs["id"])
				}
				for _, cls := range strings.Fields(attrs["class"]) {
					if cls == "fbtn" {
						t.Errorf("%s: wiki <span> kept class=fbtn", url)
					}
				}
			}
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				walk(c, nextScript)
			}
			return
		}
		if n.Type == html.TextNode && scriptType != "" && scriptType != "application/json" && strings.Contains(n.Data, mark) {
			t.Errorf("%s: <script> running wiki text: %q", url, n.Data)
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c, scriptType)
		}
	}
	walk(root, "")
	if dialogIDs > 1 {
		t.Errorf("%s: %d elements with id=settings-dialog", url, dialogIDs)
	}
}

func TestHostileEveryType(t *testing.T) {
	const mark = "XSSMARK"
	payload := fmt.Sprintf(
		`<script>%s()</script><img src=x onerror=%s()><a href="javascript:%s()">j</a><span id="settings-dialog" class="fbtn">%sspan</span>`,
		mark, mark, mark, mark,
	)

	root := repoRoot(t)
	tmp := t.TempDir()
	wikiDir := filepath.Join(tmp, "wiki")
	sourcesDir := filepath.Join(tmp, "sources")
	docsDir := filepath.Join(tmp, "docs")
	anchorsDir := filepath.Join(tmp, "anchors")
	mmDir := filepath.Join(tmp, "metamodel")
	for _, d := range []string{wikiDir, sourcesDir, docsDir, anchorsDir} {
		_ = os.MkdirAll(d, 0o755)
	}

	// Copy metamodel
	srcMM := filepath.Join(root, "_system", "metamodel")
	_ = filepath.WalkDir(srcMM, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(srcMM, p)
		dst := filepath.Join(mmDir, rel)
		if d.IsDir() {
			return os.MkdirAll(dst, 0o755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(dst, b, 0o644)
	})

	typeFolders := map[string]string{
		"domain-term": "domain-terms", "goal": "goals", "stakeholder": "stakeholders",
		"context": "context", "external-interface": "external-interfaces",
		"activity-model": "activity-models", "functional-requirement": "functional-requirements",
		"quality-requirement": "quality-requirements", "constraint": "constraints",
		"building-block": "building-blocks", "deployment-node": "deployment-nodes",
		"runtime-scenario": "runtime-scenarios", "crosscutting-concept": "crosscutting-concepts",
		"solution-strategy": "solution-strategy",
		"decision-record":   "decisions", "issue": "issues",
	}
	structural := map[string]bool{
		"id": true, "type": true, "status": true, "stereotype": true,
		"level": true, "kind": true, "parent": true, "state": true, "lane": true,
	}
	entryMap := map[string]any{
		"from": "[[STK-001-hostile]]", "to": "[[BB-001-hostile]]", "target": "[[DM-001-hostile]]",
	}
	for _, k := range []string{"data", "direction", "format", "trigger", "message", "note", "protocol", "name", "type", "label", "kind", "multiplicity", "verb", "cardinality"} {
		entryMap[k] = payload
	}
	hostileVal := func(v any, keep bool) any {
		if keep {
			return v
		}
		switch x := v.(type) {
		case []any:
			return []any{payload, "[[" + payload + "]]", entryMap}
		case map[string]any:
			m := map[string]any{}
			for k := range x {
				m[k] = payload
			}
			return m
		default:
			return payload
		}
	}

	placeholderRE := regexp.MustCompile(`\{\{\w+\}\}`)
	templateFields := func(name string) map[string]any {
		b, err := os.ReadFile(filepath.Join(root, "_templates", name+".md"))
		if err != nil {
			t.Fatal(err)
		}
		parts := strings.SplitN(string(b), "---", 3)
		clean := placeholderRE.ReplaceAllString(parts[1], "x")
		var m map[string]any
		_ = yaml.Unmarshal([]byte(clean), &m)
		if m == nil {
			m = map[string]any{}
		}
		return m
	}

	body := fmt.Sprintf(
		"# %s\n\n> follows [[HOSTILE]]\n\n**Definition.** %s [[HOSTILE]]\n\n## Vision\n\n%s\n\n"+
			"| a | b |\n|---|---|\n| %s | x |\n\n> [!note] %s\n\n"+
			"[[%s|%s]] [[SRC-001-hostile|%s]] [[HOSTILE|%s]]\n\nText {: #settings-dialog .fbtn }\n",
		payload, payload, payload, payload, payload, payload, payload, payload, payload,
	)

	writeMeta := func(p string, meta map[string]any) {
		b, err := yaml.Marshal(meta)
		if err != nil {
			t.Fatal(err)
		}
		_ = os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte("---\n"+string(b)+"---\n"+body), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	var urls []string
	for name, folder := range typeFolders {
		fields := templateFields(name)
		idStr := wiki.ScalarString(fields["id"])
		if idStr == "" {
			idStr = "X-000"
		}
		prefix := strings.Split(idStr, "-")[0]
		for n, keepStruct := range []bool{true, false} {
			idx := n + 1
			meta := map[string]any{}
			for k, v := range fields {
				meta[k] = hostileVal(v, keepStruct && structural[k])
			}
			meta["id"] = fmt.Sprintf("%s-00%d", prefix, idx)
			meta["title"] = payload
			if _, ok := meta["parent"]; ok && keepStruct {
				meta["parent"] = []any{}
			}
			stem := fmt.Sprintf("%s-00%d-hostile", prefix, idx)
			writeMeta(filepath.Join(wikiDir, folder, stem+".md"), meta)
			if folder != "functional-requirements" {
				urls = append(urls, "/page/"+folder+"/"+stem)
			}
		}
	}

	// Hostile vision goal
	writeMeta(filepath.Join(wikiDir, "goals", "GOAL-009-vision.md"), map[string]any{
		"id": "GOAL-009", "title": payload, "stereotype": "vision",
		"beneficiary": []any{payload}, "tile_claim": payload, "short_title": payload,
	})
	urls = append(urls, "/page/goals/GOAL-009-vision")

	// Hostile source record
	srcFields := templateFields("source")
	srcMeta := map[string]any{}
	for k, v := range srcFields {
		srcMeta[k] = hostileVal(v, k == "id" || k == "type")
	}
	srcMeta["id"] = "SRC-001"
	srcMeta["title"] = payload
	srcMeta["ingested-pages"] = []any{payload, "[[GLO-001-hostile]]"}
	writeMeta(filepath.Join(sourcesDir, "SRC-001-hostile.md"), srcMeta)
	urls = append(urls, "/source/SRC-001-hostile")

	// Hostile method anchors
	for _, pair := range [][2]string{{"hostile", "HOSTILE"}, {"payload", payload}} {
		b, _ := yaml.Marshal(map[string]any{
			"type": "anchor", "title": pair[1], "aliases": []any{payload}, "applies-to": []any{payload, "goal"},
		})
		_ = os.WriteFile(filepath.Join(anchorsDir, pair[0]+".md"),
			[]byte("---\n"+string(b)+"---\n# "+payload+"\n\n"+payload+" [x]("+payload+") https://example.org\n"), 0o644)
	}

	// Hostile about doc + outside secret + symlink escape inside docs/
	_ = os.MkdirAll(filepath.Join(docsDir, "brand", "svg"), 0o755)
	_ = os.WriteFile(filepath.Join(docsDir, "brand", "about.md"),
		[]byte("# "+payload+"\n\n"+payload+"\n\n![mark](svg/mark.svg)\n"), 0o644)
	_ = os.WriteFile(filepath.Join(docsDir, "brand", "svg", "mark.svg"),
		[]byte(`<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>`), 0o644)
	_ = os.WriteFile(filepath.Join(tmp, "secret.txt"), []byte("top-secret\n"), 0o644)
	_ = os.Symlink(filepath.Join(tmp, "secret.txt"), filepath.Join(docsDir, "brand", "leak.md"))

	// Hostile wiki.yaml
	cfgPath := filepath.Join(tmp, "wiki.yaml")
	cfgBytes, _ := yaml.Marshal(map[string]any{
		"system_name": payload, "tagline": payload,
		"about": "docs/brand/about.md", "about_label": payload, "intro": "off",
	})
	_ = os.WriteFile(cfgPath, cfgBytes, 0o644)

	srv := web.NewServer(web.Options{
		Paths: wiki.Paths{
			RepoDir:      tmp,
			WikiDir:      wikiDir,
			SourcesDir:   sourcesDir,
			ConfigPath:   cfgPath,
			DocsDir:      docsDir,
			MetamodelDir: mmDir,
			NotationsDir: filepath.Join(tmp, "notations"),
			AnchorsDir:   anchorsDir,
		},
		StaticFS:    dashboard.StaticFS(),
		TemplatesFS: dashboard.TemplatesFS(),
		BrandsFS:    dashboard.BrandsFS(),
		HelpMD:      dashboard.HelpMD(),
		Version:     dashboard.Version(),
		DisplayTZ:   "UTC",
		PublicURL:   "http://127.0.0.1:8080",
	})

	urls = append([]string{
		"/", "/req42", "/arc42", "/commons", "/req42/scope", "/req42/models",
		"/req42/quality", "/req42/constraints", "/req42/functional-requirements",
		"/goals", "/entity-diagram", "/graph/domain-terms",
		"/arc42/strategy", "/arc42/building-blocks", "/arc42/deployment", "/arc42/runtime", "/arc42/concepts",
		"/metamodel", "/method", "/changes", "/issues", "/issues?status=open",
		"/stakeholders", "/decisions", "/domain-terms",
		"/search", "/search.json", "/join", "/who", "/help", "/about",
		"/about/files/brand/svg/mark.svg", "/settings", "/does-not-exist",
	}, urls...)
	for _, u := range urls {
		rec := doGet(srv, u)
		if rec.Code >= 500 {
			t.Errorf("%s: HTTP %d", u, rec.Code)
			continue
		}
		if strings.HasPrefix(rec.Header().Get("Content-Type"), "text/html") {
			checkLiveMarkup(t, u, rec.Body.String(), mark)
		}
	}

	// Inert headers on /about/files/ and refusal of traversal / symlink escapes.
	svgRec := doGet(srv, "/about/files/brand/svg/mark.svg")
	if svgRec.Code != http.StatusOK || !strings.Contains(svgRec.Header().Get("Content-Security-Policy"), "sandbox") || svgRec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Errorf("/about/files/brand/svg/mark.svg headers unsafe: code=%d csp=%q xcto=%q",
			svgRec.Code, svgRec.Header().Get("Content-Security-Policy"), svgRec.Header().Get("X-Content-Type-Options"))
	}
	for _, escapeURL := range []string{"/about/files/../../secret.txt", "/about/files/../secret.txt", "/about/files/brand/leak.md"} {
		if rec := doGet(srv, escapeURL); rec.Code != http.StatusNotFound {
			t.Errorf("%s: got %d, want 404", escapeURL, rec.Code)
		}
	}

	// Non-vacuous check: escaped payload actually reached the rendered HTML
	for _, u := range []string{
		"/", "/req42/quality", "/metamodel", "/changes", "/issues", "/stakeholders", "/decisions", "/domain-terms",
		"/search", "/about",
		"/page/glossary/GLO-001-hostile", "/page/runtime-scenarios/RS-002-hostile", "/page/issues/ISS-001-hostile", "/source/SRC-001-hostile",
	} {
		body := doGet(srv, u).Body.String()
		if !strings.Contains(body, mark) || !strings.Contains(body, "&lt;script&gt;") {
			t.Errorf("%s: expected escaped hostile payload to be rendered", u)
		}
	}
}
