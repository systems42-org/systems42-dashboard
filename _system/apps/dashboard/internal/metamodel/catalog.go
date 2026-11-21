package metamodel

import (
	"sort"
	"strings"
)

// Area describes one of the three top-level Systems42 areas.
type Area struct {
	Key      string
	Label    string
	Subtitle string
	Href     string
	Colors   []string
}

// ToMap converts Area to the dict shape expected by base.html and index.html.
func (a Area) ToMap() map[string]any {
	cols := make([]string, len(a.Colors))
	copy(cols, a.Colors)
	return map[string]any{
		"key":      a.Key,
		"label":    a.Label,
		"subtitle": a.Subtitle,
		"href":     a.Href,
		"colors":   cols,
	}
}

// Areas defines the display order of the three cabinets, matching catalog.py.
var Areas = []Area{
	{Key: "requirements", Label: "Requirements", Subtitle: "goals, needs, constraints", Href: "/req42", Colors: []string{"req"}},
	{Key: "architecture", Label: "Architecture", Subtitle: "structure, interfaces, views", Href: "/arc42", Colors: []string{"arc"}},
	{Key: "commons", Label: "Commons", Subtitle: "shared by both peaks", Href: "/commons", Colors: []string{"req", "arc"}},
}

// AreaByKey indexes Areas by Key.
var AreaByKey = func() map[string]Area {
	m := make(map[string]Area, len(Areas))
	for _, a := range Areas {
		m[a.Key] = a
	}
	return m
}()

var areaOrder = map[string]int{
	"requirements": 0,
	"architecture": 1,
	"commons":      2,
}

type knownMeta struct {
	href   string
	slug   string
	colors []string
	note   string
}

const outNote = "deliberately not captured in this wiki."

var knownSections = map[string]knownMeta{
	"R1": {href: "/goals", colors: []string{"org"}},
	"R2": {colors: []string{"org"}, note: "Project resources — " + outNote},
	"R3": {href: "/req42/functional-requirements", slug: "functional-requirements", colors: []string{"req"}},
	"R4": {href: "/req42/models", slug: "models", colors: []string{"req"}},
	"R5": {colors: []string{"org"}, note: "Organisation / team setup — " + outNote},
	"R6": {colors: []string{"org"}, note: "Release planning — " + outNote},
	"A1": {colors: []string{"arc"}},
	"A2": {href: "/arc42/building-blocks", slug: "building-blocks", colors: []string{"arc"}},
	"A3": {href: "/arc42/deployment", slug: "deployment", colors: []string{"arc"}},
	"A4": {href: "/arc42/runtime", slug: "runtime", colors: []string{"arc"}},
	"A5": {href: "/arc42/concepts", slug: "concepts", colors: []string{"arc"}},
	"C1": {href: "/req42/quality", slug: "quality", colors: []string{"req"}},
	"C2": {href: "/req42/constraints", slug: "constraints", colors: []string{"req"}},
	"C3": {href: "/req42/scope", slug: "scope", colors: []string{"req", "arc"}},
	"C4": {href: "/stakeholders", colors: []string{"req", "arc"}},
	"C5": {href: "/domain-terms", colors: []string{"req"}},
	"C6": {href: "/issues", colors: []string{"org", "arc"}},
	"C7": {href: "/decisions", colors: []string{"req", "arc"}},
}

// DR-039 renamed wiki/glossary/ to wiki/domain-terms/. A section holding one
// reads both so wikis on either side of the rename show their terms.
var renamedFolders = map[string]string{
	"glossary":     "domain-terms",
	"domain-terms": "glossary",
}

var extraPathPrefixes = map[string]string{
	"/functional-requirements/": "requirements",
	"/entity-diagram":           "requirements",
	"/graph/domain-terms":       "commons",
}

var extraSectionPrefixes = map[string]string{
	"/functional-requirements/": "R3",
	"/entity-diagram":           "R4",
	"/graph/domain-terms":       "C5",
}

// Section combines a metamodel framework block with dashboard presentation
// metadata (route, slug, colours, note).
type Section struct {
	ID        string
	Area      string
	Title     string
	Folders   []string
	Href      string
	Slug      string
	Scope     string
	Colors    []string
	Note      string
	Framework string
}

// SectionFolders returns the section's folders plus the counterpart of any
// renamed folder (glossary <-> domain-terms).
func SectionFolders(s Section) []string {
	out := make([]string, 0, len(s.Folders)+1)
	seen := make(map[string]bool, len(s.Folders)+1)
	for _, f := range s.Folders {
		out = append(out, f)
		seen[f] = true
	}
	for _, f := range s.Folders {
		if other, ok := renamedFolders[f]; ok && !seen[other] {
			out = append(out, other)
			seen[other] = true
		}
	}
	return out
}

// Catalog holds the sections built from metamodel.Blocks() and lookup maps.
type Catalog struct {
	Sections        []Section
	ByID            map[string]Section
	BySlug          map[string]Section
	ByFolder        map[string]Section
	sectionsByHrefD []Section // sections with non-empty Href sorted longest Href first
}

func sectionHrefForScope(sid, scope string) string {
	if scope != "in" {
		return ""
	}
	if k, ok := knownSections[sid]; ok && k.href != "" {
		return k.href
	}
	return "/section/" + sid
}

// BuildCatalog constructs a Catalog from blocks, matching catalog.py's build().
func BuildCatalog(blocks []Block) *Catalog {
	var sections []Section
	seen := map[string]bool{}
	for _, b := range blocks {
		area, ok := AreaByKey[b.Area]
		if !ok || seen[b.ID] {
			continue
		}
		seen[b.ID] = true
		known := knownSections[b.ID]
		scope := b.Scope
		if scope == "" {
			scope = "in"
		}
		colors := known.colors
		if len(colors) == 0 {
			colors = area.Colors
		}
		colorsCopy := make([]string, len(colors))
		copy(colorsCopy, colors)
		foldersCopy := make([]string, len(b.Folders))
		copy(foldersCopy, b.Folders)
		note := known.note
		if note == "" {
			note = b.Note
		}
		title := b.Title
		if title == "" {
			title = b.ID
		}
		sections = append(sections, Section{
			ID:        b.ID,
			Area:      b.Area,
			Title:     title,
			Folders:   foldersCopy,
			Href:      sectionHrefForScope(b.ID, scope),
			Slug:      known.slug,
			Scope:     scope,
			Colors:    colorsCopy,
			Note:      note,
			Framework: b.Framework,
		})
	}
	sort.SliceStable(sections, func(i, j int) bool {
		return areaOrder[sections[i].Area] < areaOrder[sections[j].Area]
	})

	cat := &Catalog{
		Sections: sections,
		ByID:     make(map[string]Section, len(sections)),
		BySlug:   make(map[string]Section, len(sections)),
		ByFolder: make(map[string]Section),
	}
	for _, s := range sections {
		cat.ByID[s.ID] = s
		if s.Slug != "" {
			cat.BySlug[s.Slug] = s
		}
		for _, f := range SectionFolders(s) {
			if _, exists := cat.ByFolder[f]; !exists {
				cat.ByFolder[f] = s
			}
		}
		if s.Href != "" {
			cat.sectionsByHrefD = append(cat.sectionsByHrefD, s)
		}
	}
	sort.SliceStable(cat.sectionsByHrefD, func(i, j int) bool {
		return len(cat.sectionsByHrefD[i].Href) > len(cat.sectionsByHrefD[j].Href)
	})
	return cat
}

// SectionsOf returns the area's sections in diagram order.
func (c *Catalog) SectionsOf(areaKey string) []Section {
	var out []Section
	for _, s := range c.Sections {
		if s.Area == areaKey {
			out = append(out, s)
		}
	}
	return out
}

// SectionForPath resolves which section a request path belongs to.
func (c *Catalog) SectionForPath(path string) (Section, bool) {
	if strings.HasPrefix(path, "/page/") {
		parts := strings.SplitN(path, "/", 4)
		if len(parts) > 2 {
			s, ok := c.ByFolder[parts[2]]
			return s, ok
		}
		return Section{}, false
	}
	for prefix, sid := range extraSectionPrefixes {
		if strings.HasPrefix(path, prefix) {
			s, ok := c.ByID[sid]
			return s, ok
		}
	}
	for _, s := range c.sectionsByHrefD {
		if path == s.Href || strings.HasPrefix(path, s.Href+"/") || strings.HasPrefix(path, s.Href+"?") {
			return s, true
		}
	}
	return Section{}, false
}

// AreaForPath resolves which area a request path belongs to (false for home,
// help, search, join, who, etc.).
func (c *Catalog) AreaForPath(path string) (Area, bool) {
	for _, a := range Areas {
		if path == a.Href {
			return a, true
		}
	}
	if strings.HasPrefix(path, "/page/") {
		parts := strings.SplitN(path, "/", 4)
		if len(parts) > 2 {
			if s, ok := c.ByFolder[parts[2]]; ok {
				a, ok := AreaByKey[s.Area]
				return a, ok
			}
		}
		return Area{}, false
	}
	for prefix, key := range extraPathPrefixes {
		if strings.HasPrefix(path, prefix) {
			a, ok := AreaByKey[key]
			return a, ok
		}
	}
	for _, s := range c.sectionsByHrefD {
		if path == s.Href || strings.HasPrefix(path, s.Href+"/") || strings.HasPrefix(path, s.Href+"?") {
			a, ok := AreaByKey[s.Area]
			return a, ok
		}
	}
	return Area{}, false
}
