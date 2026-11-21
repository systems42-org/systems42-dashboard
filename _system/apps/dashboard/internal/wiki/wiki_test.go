package wiki

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func makeValidWiki(t *testing.T, leaveOut ...string) string {
	t.Helper()
	skip := map[string]bool{}
	for _, s := range leaveOut {
		skip[s] = true
	}
	root := t.TempDir()
	for _, rel := range Required {
		if skip[rel] {
			continue
		}
		p := filepath.Join(root, filepath.FromSlash(strings.TrimSuffix(rel, "/")))
		if strings.HasSuffix(rel, "/") {
			if err := os.MkdirAll(p, 0o755); err != nil {
				t.Fatal(err)
			}
		} else {
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(p, []byte("system_name: x\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	return root
}

func TestPreflightComplete(t *testing.T) {
	root := makeValidWiki(t)
	if got := Missing(root); len(got) != 0 {
		t.Fatalf("expected no missing parts, got %v", got)
	}
}

func TestPreflightMissingNamedInOrder(t *testing.T) {
	root := makeValidWiki(t, "raw/", "_system/metamodel/")
	got := Missing(root)
	want := []string{"raw/", "_system/metamodel/"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("Missing = %v, want %v", got, want)
	}
	msg := PreflightMessage(root, got)
	if !strings.Contains(msg, "raw/, _system/metamodel/") || !strings.Contains(msg, "not a Systems42 wiki") {
		t.Fatalf("unexpected preflight message: %s", msg)
	}
}

func TestPreflightFileWhereFolderBelongs(t *testing.T) {
	root := makeValidWiki(t, "wiki/")
	if err := os.WriteFile(filepath.Join(root, "wiki"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Missing(root)
	if len(got) != 1 || got[0] != "wiki/" {
		t.Fatalf("expected [wiki/], got %v", got)
	}
}

func TestLoadConfigDefaultsAndLiveReload(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "wiki.yaml")
	docsDir := filepath.Join(dir, "docs")
	paths := Paths{RepoDir: dir, ConfigPath: cfgPath, DocsDir: docsDir}

	// Missing file falls back
	cfg := LoadConfig(paths, nil)
	if cfg.SystemName != DefaultSystemName || cfg.SystemNameSet || cfg.Tagline != "" || !cfg.Intro || cfg.Brand != DefaultBrand {
		t.Fatalf("unexpected default config: %+v", cfg)
	}

	// Blank config falls back
	_ = os.WriteFile(cfgPath, []byte("system_name: \"\"\ntagline: \"\"\n"), 0o644)
	cfg = LoadConfig(paths, nil)
	if cfg.SystemName != DefaultSystemName || cfg.SystemNameSet {
		t.Fatalf("blank config should fall back: %+v", cfg)
	}

	// Filled config + live reload
	_ = os.WriteFile(cfgPath, []byte("system_name: \"Bookshelf\"\ntagline: \"Lending, tracked\"\nintro: off\n"), 0o644)
	cfg = LoadConfig(paths, nil)
	if cfg.SystemName != "Bookshelf" || !cfg.SystemNameSet || cfg.Tagline != "Lending, tracked" || cfg.Intro {
		t.Fatalf("filled config mismatch: %+v", cfg)
	}
	_ = os.WriteFile(cfgPath, []byte("system_name: \"Second\"\n"), 0o644)
	cfg = LoadConfig(paths, nil)
	if cfg.SystemName != "Second" || !cfg.Intro {
		t.Fatalf("live reload failed: %+v", cfg)
	}

	// Malformed and non-dict YAML do not crash
	for _, bad := range []string{"system_name: [unclosed\n", "- a\n- b\n", "just a string\n"} {
		_ = os.WriteFile(cfgPath, []byte(bad), 0o644)
		cfg = LoadConfig(paths, nil)
		if cfg.SystemName != DefaultSystemName || cfg.SystemNameSet {
			t.Fatalf("bad yaml %q did not fall back: %+v", bad, cfg)
		}
	}

	// Non-string dashboard_version warns once
	var warnings []string
	_ = os.WriteFile(cfgPath, []byte("dashboard_version: 1.10\nbrand: 123\n"), 0o644)
	cfg = LoadConfig(paths, func(msg string) { warnings = append(warnings, msg) })
	if len(warnings) != 2 || cfg.Brand != DefaultBrand {
		t.Fatalf("expected 2 warnings and default brand, got warnings=%v brand=%q", warnings, cfg.Brand)
	}
}

func TestAboutDocTraversalGuard(t *testing.T) {
	root := t.TempDir()
	docs := filepath.Join(root, "docs")
	_ = os.MkdirAll(docs, 0o755)
	_ = os.WriteFile(filepath.Join(docs, "README.md"), []byte("# Hi\n"), 0o644)
	_ = os.WriteFile(filepath.Join(root, "secret.md"), []byte("# Secret\n"), 0o644)
	_ = os.Symlink(filepath.Join(root, "secret.md"), filepath.Join(docs, "escape.md"))

	if AboutDoc(docs, "docs/README.md") == "" {
		t.Fatal("expected valid docs/README.md to resolve")
	}
	for _, bad := range []string{"docs/../secret.md", "docs/escape.md", "secret.md", "docs/missing.md", "docs/README.txt"} {
		if got := AboutDoc(docs, bad); got != "" {
			t.Fatalf("expected %q to be rejected, got %q", bad, got)
		}
	}
}

func TestResolveBrandGuards(t *testing.T) {
	outer := t.TempDir()
	repo := filepath.Join(outer, "repo")
	brandOK := filepath.Join(repo, "mybrand")
	brandPartial := filepath.Join(repo, "partial")
	brandOutside := filepath.Join(outer, "outside")
	for _, d := range []string{brandOK, brandPartial, brandOutside} {
		_ = os.MkdirAll(d, 0o755)
	}
	for _, m := range BrandMarks {
		_ = os.WriteFile(filepath.Join(brandOK, m), []byte("<svg/>"), 0o644)
		_ = os.WriteFile(filepath.Join(brandOutside, m), []byte("<svg/>"), 0o644)
	}
	_ = os.WriteFile(filepath.Join(brandPartial, "favicon.svg"), []byte("<svg/>"), 0o644)
	_ = os.Symlink(brandOutside, filepath.Join(repo, "link-out"))

	if got := ResolveBrand(repo, "systems42", nil); got.ShippedName != "systems42" {
		t.Fatalf("shipped brand failed: %+v", got)
	}
	if got := ResolveBrand(repo, "mybrand", nil); got.Dir == "" {
		t.Fatalf("valid repo brand failed: %+v", got)
	}
	for _, bad := range []string{"../outside", brandOutside, "link-out", "partial", "nonexistent"} {
		var warned bool
		got := ResolveBrand(repo, bad, func(string) { warned = true })
		if got.ShippedName != DefaultBrand || !warned {
			t.Fatalf("expected fallback+warning for %q, got %+v warned=%v", bad, got, warned)
		}
	}
}

func TestStoreCachingAndSymlinkGuard(t *testing.T) {
	outer := t.TempDir()
	wikiDir := filepath.Join(outer, "wiki")
	goalsDir := filepath.Join(wikiDir, "goals")
	_ = os.MkdirAll(goalsDir, 0o755)
	secret := filepath.Join(outer, "secret.md")
	_ = os.WriteFile(secret, []byte("---\nid: SECRET\ntitle: Secret\n---\nsecret\n"), 0o644)

	pagePath := filepath.Join(goalsDir, "GOAL-001-vision.md")
	_ = os.WriteFile(pagePath, []byte("---\nid: GOAL-001\ntitle: First\nstatus: draft\n---\nbody\n"), 0o644)
	_ = os.Symlink(secret, filepath.Join(goalsDir, "GOAL-999-escape.md"))

	store := NewStore(Paths{RepoDir: outer, WikiDir: wikiDir, SourcesDir: filepath.Join(outer, "raw", "sources")})
	pages := store.LoadFolder("goals")
	if len(pages) != 1 || pages[0].Title() != "First" {
		t.Fatalf("expected only GOAL-001, got %d pages", len(pages))
	}

	// Update file with new content/size -> cache refreshes
	_ = os.WriteFile(pagePath, []byte("---\nid: GOAL-001\ntitle: Updated Title\nstatus: accepted\n---\nbody\n"), 0o644)
	pages = store.LoadFolder("goals")
	if len(pages) != 1 || pages[0].Title() != "Updated Title" || pages[0].Status() != "accepted" {
		t.Fatalf("cache did not refresh: %+v", pages)
	}

	// Replace with symlink outside wiki -> must immediately stop serving it
	_ = os.Remove(pagePath)
	_ = os.Symlink(secret, pagePath)
	if pages = store.LoadFolder("goals"); len(pages) != 0 {
		t.Fatalf("retargeted symlink should be rejected, got %d pages", len(pages))
	}
}

func TestComputeMaturityAndVisionSentence(t *testing.T) {
	m := ComputeMaturity([]string{"accepted", "in-progress", "open", "wontfix", "unknown"})
	if m.Total != 5 || m.Label != "1 accepted · 1 review · 2 draft · 1 deprecated" {
		t.Fatalf("unexpected maturity: %+v", m)
	}
	empty := ComputeMaturity(nil)
	if empty.Total != 0 || empty.Label != "nothing yet" {
		t.Fatalf("unexpected empty maturity: %+v", empty)
	}

	// Round half to even: 1/8 = 12.5% -> 12, 3/8 = 37.5% -> 38
	half := ComputeMaturity([]string{"accepted", "review", "review", "review", "draft", "draft", "draft", "draft"})
	if half.Segments[0].Pct != 12 || half.Segments[1].Pct != 38 || half.Segments[2].Pct != 50 {
		t.Fatalf("expected round-half-to-even [12, 38, 50], got %+v", half.Segments)
	}

	p := &Page{
		Stem:    "GOAL-001-vision",
		Meta:    map[string]any{"id": "GOAL-001", "stereotype": "vision"},
		Body:    "# Vision\n\n## Vision\n\n> follows Geoffrey Moore\n\n<!-- hint -->\n\nA **single** place for [[STK-001-readers|every reader]], e.g. the team. Second sentence here.\n\n## Next\n",
		ModTime: time.Now(),
	}
	got := VisionSentence(p, map[string]string{"STK-001-readers": "Readers"})
	want := "A single place for every reader, e.g. the team."
	if got != want {
		t.Fatalf("VisionSentence = %q, want %q", got, want)
	}
}
