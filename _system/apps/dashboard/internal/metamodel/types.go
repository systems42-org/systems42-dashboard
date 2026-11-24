package metamodel

import (
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
)

// TypeDecl is what a type page declares about its place in the wiki: its
// name, the folder under wiki/ ("" for a type kept elsewhere, such as
// sources), its ID prefix and its label.
type TypeDecl struct {
	Name   string
	Folder string
	Prefix string
	Label  string
}

// defaultTypes lists the types the dashboard has views for, with the folder,
// ID prefix and label the Systems42 metamodel gives them. A value here is
// used only when the repository's metamodel does not declare it (CON-006): a
// wiki without a metamodel folder, or a type page without that key.
var defaultTypes = []TypeDecl{
	{"goal", "goals", "GOAL", "Goal"},
	{"context", "context", "CTX", "Context"},
	{"external-interface", "external-interfaces", "EIF", "External interface"},
	{"functional-requirement", "functional-requirements", "FR", "Functional requirement"},
	{"activity-model", "activity-models", "ACT", "Activity model"},
	{"quality-requirement", "quality-requirements", "QR", "Quality requirement"},
	{"constraint", "constraints", "CON", "Constraint"},
	{"domain-term", "domain-terms", "DT", "Domain term"},
	{"stakeholder", "stakeholders", "STK", "Stakeholder"},
	{"issue", "issues", "ISS", "Issue"},
	{"decision-record", "decisions", "DR", "Decision record"},
	{"solution-strategy", "solution-strategy", "SOL", "Solution strategy"},
	{"building-block", "building-blocks", "BB", "Building block"},
	{"crosscutting-concept", "crosscutting-concepts", "CC", "Crosscutting concept"},
	{"runtime-scenario", "runtime-scenarios", "RS", "Runtime scenario"},
	{"deployment-node", "deployment-nodes", "DN", "Deployment node"},
}

// Presentation: the heading of a type's group in the relations and trace
// panels, and the order of the groups. A type without a heading here shows
// its metamodel label.
var groupLabels = map[string]string{
	"domain-term": "Domain terms", "stakeholder": "Stakeholders", "context": "Context",
	"external-interface": "External interfaces", "goal": "Goals",
	"functional-requirement": "Functional requirements", "activity-model": "Activity models",
	"quality-requirement": "Quality requirements", "constraint": "Constraints",
	"decision-record": "Decisions", "solution-strategy": "Solution strategies",
	"building-block": "Building blocks", "crosscutting-concept": "Crosscutting concepts",
	"runtime-scenario": "Runtime scenarios", "deployment-node": "Deployment nodes",
	"issue": "Issues",
}

var groupOrder = []string{
	"domain-term", "stakeholder", "context", "external-interface", "goal",
	"functional-requirement", "activity-model", "quality-requirement", "constraint",
	"decision-record", "solution-strategy", "building-block", "crosscutting-concept",
	"runtime-scenario", "deployment-node", "issue",
}

// UC: a migrated use case keeps its ID as a functional requirement (DR-038).
// The prefix is no type's own, so no type page declares it.
const (
	legacyPrefix      = "UC"
	legacyPrefixType  = "functional-requirement"
	legacyPrefixLabel = "Use cases"
)

// TypeDecls returns what each type page declares, in file order. The type
// lookups are built from this (CON-006).
func (r *Reader) TypeDecls() []TypeDecl {
	var out []TypeDecl
	for _, t := range r.load("types", "type") {
		name := strings.TrimSpace(strVal(t["name"]))
		if name == "" {
			continue
		}
		folder := ""
		if raw := strVal(t["folder"]); raw != "" {
			p := filepath.FromSlash(raw)
			if parent := filepath.Base(filepath.Dir(p)); parent == "wiki" || parent == "." {
				folder = filepath.Base(p)
			}
		}
		out = append(out, TypeDecl{
			Name:   name,
			Folder: folder,
			Prefix: strings.TrimSpace(strVal(t["prefix"])),
			Label:  strings.TrimSpace(strVal(t["label"])),
		})
	}
	return out
}

// Types answers where a type's pages live and what they are called: the one
// lookup behind every specialized loader and projection, matching the type
// lookups of catalog.py.
type Types struct {
	decls    []TypeDecl
	byName   map[string]TypeDecl
	byFolder map[string]string
	byPrefix map[string]string
	order    []string
}

// BuildTypes makes the lookups from what the type pages declare, filled from
// the defaults where a page leaves a key out, plus the default types no page
// declares.
func BuildTypes(decls []TypeDecl) *Types {
	defaults := make(map[string]TypeDecl, len(defaultTypes))
	for _, d := range defaultTypes {
		defaults[d.Name] = d
	}
	t := &Types{
		decls:    slices.Clone(decls),
		byName:   map[string]TypeDecl{},
		byFolder: map[string]string{},
		byPrefix: map[string]string{},
	}
	var names []string
	add := func(d TypeDecl) {
		if _, ok := t.byName[d.Name]; ok {
			return
		}
		t.byName[d.Name] = d
		names = append(names, d.Name)
	}
	for _, d := range decls {
		base, known := defaults[d.Name]
		if d.Folder == "" {
			d.Folder = base.Folder
		}
		if d.Prefix == "" {
			d.Prefix = base.Prefix
		}
		if d.Label == "" {
			d.Label = base.Label
			if !known {
				d.Label = d.Name
			}
		}
		add(d)
	}
	for _, d := range defaultTypes {
		add(d)
	}
	// declared types first, so a declared folder or prefix wins over a default
	for _, name := range names {
		d := t.byName[name]
		if _, ok := t.byFolder[d.Folder]; d.Folder != "" && !ok {
			t.byFolder[d.Folder] = name
		}
		if _, ok := t.byPrefix[d.Prefix]; d.Prefix != "" && !ok {
			t.byPrefix[d.Prefix] = name
		}
	}
	_, legacyTaken := t.byPrefix[legacyPrefix]
	for _, name := range groupOrder {
		t.order = append(t.order, t.byName[name].Prefix)
		if name == legacyPrefixType && !legacyTaken {
			t.order = append(t.order, legacyPrefix)
		}
	}
	if !legacyTaken {
		t.byPrefix[legacyPrefix] = legacyPrefixType
	}
	return t
}

// Folder returns the wiki folder that holds the pages of a type, "" for an
// unknown type.
func (t *Types) Folder(typeName string) string { return t.byName[typeName].Folder }

// TypeOf returns the type whose pages live in wiki/<folder>, or "".
func (t *Types) TypeOf(folder string) string { return t.byFolder[folder] }

// Is reports whether wiki/<folder> holds the pages of one of the named types.
func (t *Types) Is(folder string, typeNames ...string) bool {
	name, ok := t.byFolder[folder]
	return ok && slices.Contains(typeNames, name)
}

// Label returns the label of the type whose pages live in the folder, else
// the folder name: the "Type" of a page in lists, search and on its detail page.
func (t *Types) Label(folder string) string {
	if name, ok := t.byFolder[folder]; ok {
		return t.byName[name].Label
	}
	return folder
}

// FolderForPrefix returns the folder a page with this ID prefix belongs in, or "".
func (t *Types) FolderForPrefix(prefix string) string {
	return t.byName[t.byPrefix[prefix]].Folder
}

// GroupLabel returns the heading of the group that collects links to pages
// with this ID prefix. An unknown prefix is its own heading.
func (t *Types) GroupLabel(prefix string) string {
	name, ok := t.byPrefix[prefix]
	if !ok {
		return prefix
	}
	if prefix == legacyPrefix && name == legacyPrefixType && t.byName[name].Prefix != prefix {
		return legacyPrefixLabel
	}
	if l := groupLabels[name]; l != "" {
		return l
	}
	return t.byName[name].Label
}

// PrefixOrder returns the ID prefixes in the order their groups show.
func (t *Types) PrefixOrder() []string { return t.order }

// Types returns the lookups for the repository's type pages. It reads the
// pages through the reader's cache and builds new lookups only when a
// declaration changed.
func (r *Reader) Types() *Types {
	decls := r.TypeDecls()
	r.mu.RLock()
	last := r.types
	r.mu.RUnlock()
	if last != nil && slices.Equal(last.decls, decls) {
		return last
	}
	t := BuildTypes(decls)
	r.mu.Lock()
	r.types = t
	r.mu.Unlock()
	return t
}

// current holds the lookups every package asks. One process serves one wiki,
// so the server sets them once per request (UseTypes), as catalog.refresh()
// does in the Python dashboard.
var current atomic.Pointer[Types]

func init() { current.Store(BuildTypes(nil)) }

// UseTypes makes t the lookups the package-level functions below answer from.
func UseTypes(t *Types) { current.Store(t) }

// CurrentTypes returns the lookups in use.
func CurrentTypes() *Types { return current.Load() }

// Folder is CurrentTypes().Folder.
func Folder(typeName string) string { return current.Load().Folder(typeName) }

// TypeOf is CurrentTypes().TypeOf.
func TypeOf(folder string) string { return current.Load().TypeOf(folder) }

// IsType is CurrentTypes().Is.
func IsType(folder string, typeNames ...string) bool {
	return current.Load().Is(folder, typeNames...)
}

// Label is CurrentTypes().Label.
func Label(folder string) string { return current.Load().Label(folder) }

// FolderForPrefix is CurrentTypes().FolderForPrefix.
func FolderForPrefix(prefix string) string { return current.Load().FolderForPrefix(prefix) }

// GroupLabel is CurrentTypes().GroupLabel.
func GroupLabel(prefix string) string { return current.Load().GroupLabel(prefix) }

// PrefixOrder is CurrentTypes().PrefixOrder.
func PrefixOrder() []string { return current.Load().PrefixOrder() }
