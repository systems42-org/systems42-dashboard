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

	if _, ok := cat.ByFolder["glossary"]; ok {
		t.Fatal("glossary is no folder of the metamodel (DR-039)")
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

func TestAnchorsVocabAndSectionHref(t *testing.T) {
	mmDir := repoMetamodelDir(t)
	anchorsDir := filepath.Clean(filepath.Join(mmDir, "..", "anchors"))
	r := NewReader(mmDir, "", anchorsDir)

	anchors := r.MethodAnchors()
	if len(anchors) == 0 {
		t.Fatal("expected method anchors from repo _system/anchors")
	}
	idx := AnchorIndex(anchors)
	if a, ok := idx["q42"]; !ok || a.Slug == "" {
		t.Fatalf("expected q42 alias in AnchorIndex, got %+v (%v)", a, ok)
	}

	lc := r.Lifecycle("issue")
	if len(lc) == 0 {
		t.Fatal("expected non-empty issue lifecycle from metamodel")
	}
	sev := r.FieldValues("issue", "severity")
	if len(sev) == 0 {
		t.Fatal("expected non-empty issue severity values from metamodel")
	}

	cat := BuildCatalog(r.Blocks())
	if href := SectionHref(cat.ByID["C6"]); href != "/issues" {
		t.Fatalf("SectionHref(C6) = %q, want /issues", href)
	}
	if href := SectionHref(Section{ID: "X9", Area: "requirements"}); href != "/req42#tile-x9" {
		t.Fatalf("SectionHref(X9) = %q, want /req42#tile-x9", href)
	}
}

func TestLoadAnchorsAndNotations(t *testing.T) {
	mmDir := repoMetamodelDir(t)
	notDir := t.TempDir()
	_ = os.WriteFile(filepath.Join(notDir, "not-custom.md"), []byte(
		"---\ntype: metamodel\nconstruct: notation\nname: custom\ntitle: Custom\nlevels: [a, b]\n---\n\n"+
			"# Custom\n\n<!-- levels: a, b -->\n## Summary\n\n<!-- levels: b -->\n**Details.** text\n"), 0o644)

	r := NewReader(mmDir, notDir, "")
	mm := r.Load()
	if !mm.Present || len(mm.Types) == 0 || len(mm.Relations) == 0 || len(mm.Projections) == 0 || len(mm.Rules) == 0 {
		t.Fatalf("Load missing constructs: present=%v types=%d rel=%d proj=%d rules=%d",
			mm.Present, len(mm.Types), len(mm.Relations), len(mm.Projections), len(mm.Rules))
	}
	if len(mm.Frameworks) < 3 || StrVal(mm.Frameworks[0]["name"]) != "req42" || StrVal(mm.Frameworks[1]["name"]) != "commons" || StrVal(mm.Frameworks[2]["name"]) != "arc42" {
		t.Fatalf("unexpected framework order: %+v", mm.Frameworks)
	}
	if StrVal(mm.Types[0]["name"]) != "goal" || StrVal(mm.Types[len(mm.Types)-1]["name"]) != "source" {
		t.Fatalf("unexpected type block order: first=%q last=%q", StrVal(mm.Types[0]["name"]), StrVal(mm.Types[len(mm.Types)-1]["name"]))
	}
	for _, tp := range mm.Types {
		if StrVal(tp["_summary"]) == "" {
			t.Errorf("empty _summary for type %q", StrVal(tp["name"]))
		}
	}

	anc := Anchors(mm)
	if anc["FR"] != "type-functional-requirement" || anc["goal"] != "type-goal" {
		t.Fatalf("unexpected Anchors: FR=%q goal=%q", anc["FR"], anc["goal"])
	}
	if got := r.TypeForFolder("quality-requirements"); got != "quality-requirement" {
		t.Fatalf("TypeForFolder(quality-requirements) = %q", got)
	}

	foundCustom := false
	for _, n := range mm.Notations {
		if StrVal(n["name"]) == "custom" {
			foundCustom = true
			secs, _ := n["_sections"].([]map[string]any)
			if len(secs) != 2 || StrVal(secs[0]["heading"]) != "Summary" || StrVal(secs[1]["heading"]) != "Details" {
				t.Fatalf("unexpected notation sections: %+v", secs)
			}
		}
	}
	if !foundCustom {
		t.Fatal("expected project-specific notation from NotationsDir")
	}
}

// A block without a title shows its ID in the catalog and in Load (issue 205).
// A block without an ID and a block entry that is plain text declare no block.
func TestBlockWithoutTitleShowsItsID(t *testing.T) {
	dir := t.TempDir()
	for _, d := range []string{"frameworks", "types"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	fwPath := filepath.Join(dir, "frameworks", "fw-req42.md")
	declare := func(r4 string) {
		t.Helper()
		text := "---\ntype: metamodel\nconstruct: framework\nname: req42\narea: requirements\nblocks:\n" +
			"  - " + r4 + "\n" +
			"  - {number: \"98\", title: \"Block without an ID\", types: [], scope: in}\n" +
			"  - a block that is plain text\n---\n\n# Framework: req42\n"
		if err := os.WriteFile(fwPath, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	typePage := "---\ntype: metamodel\nconstruct: type\nname: activity-model\nblock: R4\n" +
		"folder: wiki/activity-models\n---\n\n# Type: activity-model\n"
	if err := os.WriteFile(filepath.Join(dir, "types", "type-activity-model.md"), []byte(typePage), 0o644); err != nil {
		t.Fatal(err)
	}

	shown := func(want string) {
		t.Helper()
		r := NewReader(dir, "", "")
		cat := BuildCatalog(r.Blocks())
		if len(cat.Sections) != 1 || cat.Sections[0].ID != "R4" || cat.Sections[0].Title != want {
			t.Fatalf("catalog: expected one section R4 titled %q, got %+v", want, cat.Sections)
		}
		mm := r.Load()
		if len(mm.Blocks) != 1 || strVal(mm.Blocks[0]["id"]) != "R4" || strVal(mm.Blocks[0]["title"]) != want {
			t.Fatalf("load: expected one block R4 titled %q, got %+v", want, mm.Blocks)
		}
		if len(mm.Types) != 1 || strVal(mm.Types[0]["block_title"]) != want {
			t.Fatalf("load: expected block_title %q, got %+v", want, mm.Types)
		}
	}

	declare("{id: R4, types: [activity-model], scope: in}")
	shown("R4")
	declare("{id: R4, title: \"Helper Models\", types: [activity-model], scope: in}")
	shown("Helper Models")
}
