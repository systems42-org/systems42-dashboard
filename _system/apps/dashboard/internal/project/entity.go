package project

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

type dmArrow struct {
	syntax string
	carded bool
}

var dmArrows = map[string]dmArrow{
	"association": {"-->", true},
	"aggregation": {"o--", true},
	"composition": {"*--", true},
	"inheritance": {"<|--", false},
}

var (
	dmWordSplitRE     = regexp.MustCompile(`[^A-Za-z0-9]+`)
	dmSectionStartRE  = regexp.MustCompile(`(?m)^\*\*([^*\n]+?)\.\*\*[ \t]*\n?`)
	dmSectionEndRE    = regexp.MustCompile(`(?m)^\*\*[^*\n]+?\.\*\*|^>[ \t]*\[!|^##[ \t]`)
	dmNoteStartRE     = regexp.MustCompile(`(?m)^>[ \t]*\[!note\][ \t]*([^\n]+)\n((?:^>.*(?:\n|$))+)`)
	dmQuotePrefixRE   = regexp.MustCompile(`^>\s?`)
	dmTranslitReplace = strings.NewReplacer(
		"ä", "ae", "ö", "oe", "ü", "ue", "ß", "ss",
		"Ä", "Ae", "Ö", "Oe", "Ü", "Ue", "ẞ", "Ss",
	)
)

func dmASCII(label string) string {
	s := dmTranslitReplace.Replace(label)
	decomposed := norm.NFKD.String(s)
	var out strings.Builder
	out.Grow(len(decomposed))
	for _, r := range decomposed {
		if !unicode.Is(unicode.Mn, r) {
			out.WriteRune(r)
		}
	}
	return out.String()
}

func dmClassName(label string, taken map[string]bool) string {
	words := dmWordSplitRE.Split(dmASCII(CleanLabel(label, true)), -1)
	var b strings.Builder
	for _, w := range words {
		if w == "" {
			continue
		}
		b.WriteString(strings.ToUpper(w[:1]))
		b.WriteString(w[1:])
	}
	base := b.String()
	if base == "" {
		base = "Entity"
	}
	if base[0] >= '0' && base[0] <= '9' {
		base = "E" + base
	}
	name := base
	for n := 2; taken[name]; n++ {
		name = fmt.Sprintf("%s%d", base, n)
	}
	taken[name] = true
	return name
}

// ExtractDMAttributeNames returns attribute names from frontmatter `attributes:`.
func ExtractDMAttributeNames(p *wiki.Page) []string {
	attributes := DMAttributes(p)
	out := make([]string, 0, len(attributes))
	for _, a := range attributes {
		out = append(out, a["name"].(string))
	}
	return out
}

// dmScalar returns a frontmatter value as text if it is a string or a whole
// number, else "".
func dmScalar(v any) string {
	switch v.(type) {
	case string, int, int64, uint64:
		return strings.TrimSpace(wiki.ScalarString(v))
	}
	return ""
}

// DMAttributes returns the entries of frontmatter `attributes:` that carry a
// name, as {name, type, multiplicity, identifier}.
func DMAttributes(p *wiki.Page) []map[string]any {
	list, ok := p.Meta["attributes"].([]any)
	if !ok {
		return []map[string]any{}
	}
	out := make([]map[string]any, 0, len(list))
	for _, item := range list {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		name, ok := m["name"].(string)
		if !ok || strings.TrimSpace(name) == "" {
			continue
		}
		identifier, _ := m["identifier"].(bool)
		out = append(out, map[string]any{
			"name":         name,
			"type":         dmScalar(m["type"]),
			"multiplicity": dmScalar(m["multiplicity"]),
			"identifier":   identifier,
		})
	}
	return out
}

// TermKind returns a domain term's kind: its stereotype, or "" for a plain
// term (FR-038).
func TermKind(p *wiki.Page) string {
	st := strings.ToLower(strings.TrimSpace(p.MetaString("stereotype")))
	for _, known := range wiki.DomainModelStereotypes {
		if st == known {
			return st
		}
	}
	return ""
}

// DMRelationships returns the entries of a term's `relationships:` that name a
// target, as edges. The target may be a stem no structured term has: the
// entity diagram drops those, the term page lists them (FR-039).
func DMRelationships(p *wiki.Page, index map[string]*wiki.Page) []map[string]any {
	out := make([]map[string]any, 0)
	for _, item := range p.AsList("relationships") {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}
		tgt := wiki.LinkStem(entry["to"], index)
		if tgt == "" {
			continue
		}
		kind := strings.ToLower(strings.TrimSpace(wiki.ScalarString(entry["kind"])))
		if kind == "" {
			kind = "association"
		}
		if kind == "generalization" {
			kind = "inheritance"
		}
		if _, valid := dmArrows[kind]; !valid {
			kind = "association"
		}
		if tgt == p.Stem && kind == "inheritance" {
			continue // a term may refer to itself, not inherit from itself
		}
		multRaw := entry["multiplicity"]
		mult := ""
		if multRaw != nil {
			mult = strings.TrimSpace(wiki.ScalarString(multRaw))
		}
		verbRaw := entry["label"]
		out = append(out, map[string]any{
			"source":      p.Stem,
			"target":      tgt,
			"verb":        CleanLabel(wiki.ScalarString(verbRaw), true),
			"cardinality": mult,
			"kind":        kind,
		})
	}
	return out
}

// TermRelationships returns a term's relationships as its page shows them
// (FR-039). A target that is a page is named by ID and title and linked. Any
// other target stays as written.
func TermRelationships(p *wiki.Page, links map[string]wiki.PageRef, byStem map[string]*wiki.Page) []map[string]any {
	out := make([]map[string]any, 0)
	for _, r := range DMRelationships(p, byStem) {
		kind := r["kind"].(string)
		row := map[string]any{
			"kind":         kind,
			"label":        r["verb"],
			"target":       r["target"],
			"target_id":    "",
			"url":          "",
			"multiplicity": r["cardinality"],
		}
		if kind == "inheritance" {
			row["kind"] = "generalization"
		}
		// a multiplicity on a generalization means nothing, as in the diagram
		if !dmArrows[kind].carded {
			row["multiplicity"] = ""
		}
		if ref, ok := links[r["target"].(string)]; ok {
			if target := byStem[ref.Stem]; target != nil {
				row["target"] = target.Title()
				row["target_id"] = target.ID()
				row["url"] = wiki.PageURL(target.Folder, target.Stem)
			}
		}
		out = append(out, row)
	}
	return out
}

// DataModelNodes returns every class node in the entity diagram: one per
// structured domain term.
func DataModelNodes(domainTerms []*wiki.Page) []map[string]any {
	pages := wiki.DataModelPages(domainTerms)
	nodes := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		nodes = append(nodes, map[string]any{
			"key":        p.Stem,
			"id":         p.ID(),
			"label":      p.Title(),
			"context":    strings.TrimSpace(p.MetaString("bounded-context")),
			"stereotype": strings.ToLower(strings.TrimSpace(p.MetaString("stereotype"))),
			"attributes": ExtractDMAttributeNames(p),
			"aliases":    p.Aliases(),
			"url":        "/page/" + p.Folder + "/" + p.Stem,
		})
	}
	return nodes
}

// DataModelEdges returns the parent inheritance edges and frontmatter
// relationships edges among existing entity-diagram nodes.
func DataModelEdges(domainTerms []*wiki.Page, index map[string]*wiki.Page) []map[string]any {
	nodes := DataModelNodes(domainTerms)
	byStem := make(map[string]bool, len(nodes))
	for _, n := range nodes {
		byStem[n["key"].(string)] = true
	}

	out := make([]map[string]any, 0)
	for _, p := range wiki.DataModelPages(domainTerms) {
		for _, raw := range p.AsList("parent") {
			tgt := wiki.LinkStem(raw, index)
			if tgt != "" && byStem[tgt] && tgt != p.Stem {
				out = append(out, map[string]any{
					"source":      p.Stem,
					"target":      tgt,
					"verb":        "",
					"cardinality": "",
					"kind":        "inheritance",
				})
			}
		}
		for _, r := range DMRelationships(p, index) {
			if byStem[r["target"].(string)] {
				out = append(out, r)
			}
		}
	}
	return out
}

// DataModelContexts returns sorted unique non-empty bounded contexts.
func DataModelContexts(nodes []map[string]any) []string {
	set := map[string]bool{}
	for _, n := range nodes {
		if c := n["context"].(string); c != "" {
			set[c] = true
		}
	}
	out := make([]string, 0, len(set))
	for c := range set {
		out = append(out, c)
	}
	sort.Strings(out)
	return out
}

func encodeMermaidMember(name string) string {
	collapsed := strings.Join(strings.Fields(name), " ")
	var out strings.Builder
	out.Grow(len(collapsed))
	for _, r := range collapsed {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_' || r == ' ' || r == '-' {
			out.WriteRune(r)
		} else {
			fmt.Fprintf(&out, "#%d;", r)
		}
	}
	return out.String()
}

// BuildDataModelFullDiagram projects the Mermaid classDiagram (DR-027),
// optionally filtered by bounded context and/or 1-hop focus entity.
func BuildDataModelFullDiagram(nodes, edges []map[string]any, contextFilter, focus string) string {
	keep := map[string]bool{}
	for _, n := range nodes {
		if contextFilter == "" || n["context"].(string) == contextFilter {
			keep[n["key"].(string)] = true
		}
	}
	if focus != "" {
		if !keep[focus] {
			return ""
		}
		nbrs := map[string]bool{focus: true}
		for _, e := range edges {
			src, tgt := e["source"].(string), e["target"].(string)
			if src == focus {
				nbrs[tgt] = true
			} else if tgt == focus {
				nbrs[src] = true
			}
		}
		for k := range keep {
			if !nbrs[k] {
				delete(keep, k)
			}
		}
	}

	var kept []map[string]any
	for _, n := range nodes {
		if keep[n["key"].(string)] {
			kept = append(kept, n)
		}
	}
	if len(kept) == 0 {
		return ""
	}

	taken := map[string]bool{}
	nameOf := make(map[string]string, len(kept))
	for _, n := range kept {
		nameOf[n["key"].(string)] = dmClassName(n["label"].(string), taken)
	}

	decl := func(n map[string]any) string {
		ident := nameOf[n["key"].(string)]
		label := strings.ReplaceAll(CleanLabel(n["label"].(string), true), `"`, `'`)
		if label != ident {
			return fmt.Sprintf(`%s["%s"]`, ident, label)
		}
		return ident
	}

	lines := []string{"classDiagram"}
	for _, n := range kept {
		var body []string
		if st := n["stereotype"].(string); st != "" && st != "entity" {
			body = append(body, fmt.Sprintf("    <<%s>>", st))
		}
		for _, attr := range n["attributes"].([]string) {
			body = append(body, "    +"+encodeMermaidMember(attr))
		}
		if len(body) > 0 {
			lines = append(lines, fmt.Sprintf("  class %s {", decl(n)))
			for _, b := range body {
				lines = append(lines, "  "+b)
			}
			lines = append(lines, "  }")
		} else {
			lines = append(lines, fmt.Sprintf("  class %s", decl(n)))
		}
	}

	for _, e := range edges {
		srcKey, tgtKey := e["source"].(string), e["target"].(string)
		if !keep[srcKey] || !keep[tgtKey] {
			continue
		}
		kind := e["kind"].(string)
		arr := dmArrows[kind]
		src, dst := nameOf[srcKey], nameOf[tgtKey]
		if kind == "inheritance" {
			src, dst = dst, src
		}
		mult := strings.ReplaceAll(CleanLabel(e["cardinality"].(string), false), `\`, "")
		var line string
		if arr.carded && mult != "" {
			line = fmt.Sprintf(`  %s %s "%s" %s`, src, arr.syntax, mult, dst)
		} else {
			line = fmt.Sprintf("  %s %s %s", src, arr.syntax, dst)
		}
		if verb := e["verb"].(string); verb != "" {
			line += " : " + verb
		}
		lines = append(lines, line)
	}
	return strings.Join(lines, "\n")
}

func extractDMSections(p *wiki.Page, linkCtx render.LinkContext) [][]any {
	body := strings.ReplaceAll(p.Body, "\r\n", "\n")
	starts := dmSectionStartRE.FindAllStringSubmatchIndex(body, -1)
	out := make([][]any, 0, len(starts))
	for _, m := range starts {
		label := strings.TrimSpace(body[m[2]:m[3]])
		rest := body[m[1]:]
		if end := dmSectionEndRE.FindStringIndex(rest); end != nil {
			rest = rest[:end[0]]
		}
		secBody := strings.TrimRight(rest, " \t\r\n")
		out = append(out, []any{label, render.RenderMarkdown(secBody, linkCtx)})
	}
	return out
}

func extractDMNotes(p *wiki.Page, linkCtx render.LinkContext) []map[string]any {
	body := strings.ReplaceAll(p.Body, "\r\n", "\n")
	matches := dmNoteStartRE.FindAllStringSubmatch(body, -1)
	out := make([]map[string]any, 0, len(matches))
	for _, m := range matches {
		title := strings.TrimSpace(m[1])
		rawLines := strings.Split(strings.TrimSuffix(m[2], "\n"), "\n")
		cleaned := make([]string, len(rawLines))
		for i, line := range rawLines {
			cleaned[i] = dmQuotePrefixRE.ReplaceAllString(line, "")
		}
		joined := strings.TrimSpace(strings.Join(cleaned, "\n"))
		out = append(out, map[string]any{
			"title": title,
			"html":  render.RenderMarkdown(joined, linkCtx),
		})
	}
	return out
}

// DataModelEntities builds the per-entity catalog cards shown beneath the
// entity diagram on /entity-diagram.
func DataModelEntities(domainTerms []*wiki.Page, linkCtx render.LinkContext) []map[string]any {
	pages := wiki.DataModelPages(domainTerms)
	out := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		out = append(out, map[string]any{
			"id":              p.ID(),
			"stem":            p.Stem,
			"url":             "/page/" + p.Folder + "/" + p.Stem,
			"title":           p.Title(),
			"status":          p.Status(),
			"stereotype":      strings.TrimSpace(p.MetaString("stereotype")),
			"source_of_truth": strings.TrimSpace(p.MetaString("source-of-truth")),
			"attributes":      ExtractDMAttributeNames(p),
			"sections":        extractDMSections(p, linkCtx),
			"notes":           extractDMNotes(p, linkCtx),
		})
	}
	return out
}
