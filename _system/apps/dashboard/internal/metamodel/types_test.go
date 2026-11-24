package metamodel

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeType(t *testing.T, dir, name, front string) string {
	t.Helper()
	p := filepath.Join(dir, "types", "type-"+name+".md")
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	text := "---\ntype: metamodel\nconstruct: type\nname: " + name + "\n" + front + "---\n\n# Type\n"
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// Without a metamodel the lookups answer with the Systems42 defaults.
func TestTypesDefaults(t *testing.T) {
	ty := NewReader(t.TempDir(), "", "").Types()
	if ty.Folder("domain-term") != "domain-terms" || ty.TypeOf("decisions") != "decision-record" {
		t.Fatalf("defaults: %q %q", ty.Folder("domain-term"), ty.TypeOf("decisions"))
	}
	if ty.Label("goals") != "Goal" || ty.Label("notes") != "notes" {
		t.Fatalf("labels: %q %q", ty.Label("goals"), ty.Label("notes"))
	}
	if ty.FolderForPrefix("UC") != "functional-requirements" || ty.GroupLabel("UC") != "Use cases" {
		t.Fatalf("UC: %q %q", ty.FolderForPrefix("UC"), ty.GroupLabel("UC"))
	}
	if ty.GroupLabel("SOL") != "Solution strategies" || ty.GroupLabel("XYZ") != "XYZ" {
		t.Fatalf("group labels: %q %q", ty.GroupLabel("SOL"), ty.GroupLabel("XYZ"))
	}
	want := []string{"DT", "STK", "CTX", "EIF", "GOAL", "FR", "UC", "ACT", "QR", "CON", "DR",
		"SOL", "BB", "CC", "RS", "DN", "ISS"}
	if !reflect.DeepEqual(ty.PrefixOrder(), want) {
		t.Fatalf("order: %v", ty.PrefixOrder())
	}
	if ty.Folder("unknown") != "" || ty.TypeOf("unknown") != "" || ty.Is("unknown", "") {
		t.Fatal("an unknown type or folder must match nothing")
	}
}

// A type page decides folder, prefix and label. A key it leaves out, and a
// type no page declares, keep the default. An edit shows on the next call.
func TestTypesFollowTheTypePages(t *testing.T) {
	dir := t.TempDir()
	r := NewReader(dir, "", "")
	page := writeType(t, dir, "domain-term", "prefix: TERM\nfolder: wiki/terms\nlabel: Term\n")
	writeType(t, dir, "goal", "folder: wiki/aims\n")
	writeType(t, dir, "risk", "prefix: RSK\nfolder: wiki/risks\nlabel: Risk\n")
	writeType(t, dir, "source", "prefix: SRC\nfolder: raw/sources\nlabel: Source\n")

	ty := r.Types()
	if ty.Folder("domain-term") != "terms" || ty.TypeOf("terms") != "domain-term" || ty.TypeOf("domain-terms") != "" {
		t.Fatalf("moved folder: %q %q %q", ty.Folder("domain-term"), ty.TypeOf("terms"), ty.TypeOf("domain-terms"))
	}
	if ty.Label("terms") != "Term" || ty.FolderForPrefix("TERM") != "terms" || ty.FolderForPrefix("DT") != "" {
		t.Fatalf("declared label and prefix: %q %q %q", ty.Label("terms"), ty.FolderForPrefix("TERM"), ty.FolderForPrefix("DT"))
	}
	if ty.GroupLabel("TERM") != "Domain terms" || ty.PrefixOrder()[0] != "TERM" {
		t.Fatalf("group of a renamed prefix: %q %v", ty.GroupLabel("TERM"), ty.PrefixOrder())
	}
	// goal: folder declared, prefix and label from the defaults
	if ty.Folder("goal") != "aims" || ty.Label("aims") != "Goal" || ty.FolderForPrefix("GOAL") != "aims" {
		t.Fatalf("goal: %q %q %q", ty.Folder("goal"), ty.Label("aims"), ty.FolderForPrefix("GOAL"))
	}
	// a type the dashboard has no view for
	if ty.Label("risks") != "Risk" || ty.GroupLabel("RSK") != "Risk" || !ty.Is("risks", "risk") {
		t.Fatalf("risk: %q %q", ty.Label("risks"), ty.GroupLabel("RSK"))
	}
	// sources live outside wiki/: no wiki folder is theirs
	if ty.Folder("source") != "" || ty.TypeOf("sources") != "" {
		t.Fatalf("source: %q %q", ty.Folder("source"), ty.TypeOf("sources"))
	}
	if ty.Folder("stakeholder") != "stakeholders" {
		t.Fatalf("undeclared type: %q", ty.Folder("stakeholder"))
	}
	if r.Types() != ty {
		t.Fatal("unchanged type pages must not build new lookups")
	}

	writeType(t, dir, "domain-term", "prefix: DT\nfolder: wiki/glossary\nlabel: Domain term\n")
	if got := r.Types().Folder("domain-term"); got != "glossary" {
		t.Fatalf("after the edit: %q (%s)", got, page)
	}
}
