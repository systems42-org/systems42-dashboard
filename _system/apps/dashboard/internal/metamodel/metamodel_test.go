package metamodel

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func repoMetamodelDir(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// internal/metamodel/metamodel_test.go -> _system/metamodel
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "..", "metamodel"))
}

func TestVersionCheck(t *testing.T) {
	dir := t.TempDir()
	r := NewReader(dir, "", "")

	// Missing when neither file exists
	if got := r.VersionCheck(); got.State != "missing" || got.Version != "" {
		t.Fatalf("expected missing, got %+v", got)
	}

	// Supported version in meta-metamodel.md
	metaPath := filepath.Join(dir, "meta-metamodel.md")
	_ = os.WriteFile(metaPath, []byte("---\nversion: 0.1\n---\n"), 0o644)
	if got := r.VersionCheck(); got.State != "supported" || got.Version != "0.1" || got.File != "meta-metamodel.md" {
		t.Fatalf("expected supported 0.1, got %+v", got)
	}

	// Raw scalar preservation: 0.10 must stay "0.10", not float "0.1"
	verPath := filepath.Join(dir, "metamodel-version.md")
	_ = os.WriteFile(verPath, []byte("---\nversion: 0.10\n---\n"), 0o644)
	if got := r.VersionCheck(); got.State != "unsupported" || got.Version != "0.10" || got.File != "metamodel-version.md" {
		t.Fatalf("expected unsupported 0.10 from metamodel-version.md, got %+v", got)
	}
}

func TestCatalogFromRepoMetamodel(t *testing.T) {
	mmDir := repoMetamodelDir(t)
	r := NewReader(mmDir, "", "")
	vc := r.VersionCheck()
	if vc.State != "supported" {
		t.Fatalf("expected repo metamodel supported, got %+v", vc)
	}

	cat := BuildCatalog(r.Blocks())
	if len(cat.Sections) == 0 {
		t.Fatal("expected sections from repo metamodel")
	}

	for _, sid := range []string{"R1", "R3", "R4", "A2", "A5", "C1", "C5", "C6", "C7"} {
		if _, ok := cat.ByID[sid]; !ok {
			t.Fatalf("missing section %s in catalog", sid)
		}
	}

	// DR-039: both glossary and domain-terms map to C5
	if s, ok := cat.ByFolder["glossary"]; !ok || s.ID != "C5" {
		t.Fatalf("glossary should map to C5, got %+v (%v)", s, ok)
	}
	if s, ok := cat.ByFolder["domain-terms"]; !ok || s.ID != "C5" {
		t.Fatalf("domain-terms should map to C5, got %+v (%v)", s, ok)
	}

	// Longest href match: /req42/functional-requirements -> R3, /req42 -> requirements area only
	if s, ok := cat.SectionForPath("/req42/functional-requirements"); !ok || s.ID != "R3" {
		t.Fatalf("expected R3 for /req42/functional-requirements, got %+v (%v)", s, ok)
	}
	if a, ok := cat.AreaForPath("/req42"); !ok || a.Key != "requirements" {
		t.Fatalf("expected requirements for /req42, got %+v (%v)", a, ok)
	}
	if _, ok := cat.AreaForPath("/"); ok {
		t.Fatal("expected no area for /")
	}
}
