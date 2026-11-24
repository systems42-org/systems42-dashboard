package web

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// A request reads a term's definition once, however many links name the term
// (FR-041): the second call answers from the request's memo, and a page of
// another type has no definition.
func TestTermDefinitionIsReadOncePerRequest(t *testing.T) {
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "..", ".."))
	tmp := t.TempDir()
	wikiDir := filepath.Join(tmp, "wiki")
	for folder, stem := range map[string]string{"domain-terms": "DT-001-order", "stakeholders": "STK-001-reader"} {
		if err := os.MkdirAll(filepath.Join(wikiDir, folder), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(wikiDir, folder, stem+".md"),
			[]byte("---\ntitle: T\n---\n\n**Definition.** The first text.\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	srv := NewServer(Options{Paths: wiki.Paths{
		RepoDir:      tmp,
		WikiDir:      wikiDir,
		SourcesDir:   filepath.Join(tmp, "raw", "sources"),
		ConfigPath:   filepath.Join(tmp, "wiki.yaml"),
		DocsDir:      filepath.Join(tmp, "docs"),
		MetamodelDir: filepath.Join(root, "_system", "metamodel"),
		NotationsDir: filepath.Join(root, "_system", "notations"),
		AnchorsDir:   filepath.Join(root, "_system", "anchors"),
	}})
	sn := newSnapshot(srv.Store)
	if got := sn.termDefinition("DT-001-order"); got != "The first text." {
		t.Fatalf("definition = %q", got)
	}
	sn.byStem()["DT-001-order"].Body = "**Definition.** Read again."
	if got := sn.termDefinition("DT-001-order"); got != "The first text." {
		t.Fatalf("the second link read the page again: %q", got)
	}
	if got := sn.termDefinition("STK-001-reader"); got != "" {
		t.Fatalf("a stakeholder got a definition: %q", got)
	}
	if got := sn.termDefinition("no-such-page"); got != "" {
		t.Fatalf("a missing page got a definition: %q", got)
	}
	if len(sn.definitions) != 3 {
		t.Fatalf("memo holds %d entries, want 3", len(sn.definitions))
	}
}
