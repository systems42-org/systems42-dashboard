package project

import (
	"regexp"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	nidRE           = regexp.MustCompile(`[^A-Za-z0-9]`)
	wlAliasRE       = regexp.MustCompile(`\[\[[^\]|]+\|([^\]]+)\]\]`)
	wlPlainRE       = regexp.MustCompile(`\[\[([^\]]+)\]\]`)
	trailingParenRE = regexp.MustCompile(`\s*\([^)]*\)\s*$`)
	stripMermaidRE  = regexp.MustCompile(`[<>"|\[\]]`)
	collapseWSRE    = regexp.MustCompile(`\s+`)
	mmEscapeRE      = regexp.MustCompile(`[#;]`)
)

// DiagramNodeID strips all non-alphanumeric characters to form a safe Mermaid
// node identifier, matching app.py's _diagram_node_id().
func DiagramNodeID(raw string) string {
	s := nidRE.ReplaceAllString(raw, "")
	if s == "" {
		return "N"
	}
	return s
}

// CleanLabel resolves wikilinks, optionally drops a trailing parenthetical,
// replaces '&' with ' and ', strips Mermaid/HTML delimiters, and collapses space.
func CleanLabel(s string, dropParenthetical bool) string {
	t := wlAliasRE.ReplaceAllString(s, "$1")
	t = wlPlainRE.ReplaceAllStringFunc(t, func(m string) string {
		sub := wlPlainRE.FindStringSubmatch(m)
		parts := strings.Split(sub[1], "/")
		return parts[len(parts)-1]
	})
	if dropParenthetical {
		t = trailingParenRE.ReplaceAllString(t, "")
	}
	t = strings.ReplaceAll(t, "&", " and ")
	t = stripMermaidRE.ReplaceAllString(t, "")
	return strings.TrimSpace(collapseWSRE.ReplaceAllString(t, " "))
}

// ShortTitle returns short_title frontmatter if set, else page title.
func ShortTitle(p *wiki.Page) string {
	if s := strings.TrimSpace(p.MetaString("short_title")); s != "" {
		return s
	}
	return strings.TrimSpace(p.Title())
}

// NodeLink returns the {id, title, url} dict for diagram node link lists (QR-001).
func NodeLink(p *wiki.Page) map[string]any {
	return map[string]any{
		"id":    p.ID(),
		"title": p.Title(),
		"url":   wiki.PageURL(p.Folder, p.Stem),
	}
}

// MMEscape encodes '#' and ';' as Mermaid entity codes in one pass and
// collapses whitespace, matching app.py's _mm_escape().
func MMEscape(s string) string {
	collapsed := strings.Join(strings.Fields(s), " ")
	return mmEscapeRE.ReplaceAllStringFunc(collapsed, func(m string) string {
		if m == "#" {
			return "#35;"
		}
		return "#59;"
	})
}

// EdgeText escapes edge label text for Mermaid double-quoted labels.
func EdgeText(s string) string {
	return strings.ReplaceAll(MMEscape(s), `"`, `'`)
}

// Lifecycle returns "outdated" for deprecated pages, else PageState(p).
func Lifecycle(p *wiki.Page) string {
	if p.Status() == "deprecated" {
		return "outdated"
	}
	return wiki.PageState(p)
}

// Entries returns page.Meta[field] normalized to a slice (wrapping a single
// non-nil scalar/map in a 1-element slice), matching app.py's _entries().
func Entries(p *wiki.Page, field string) []any {
	v := p.Meta[field]
	if v == nil {
		return nil
	}
	if list, ok := v.([]any); ok {
		return list
	}
	if s, ok := v.(string); ok && s == "" {
		return nil
	}
	return []any{v}
}

// SortedByID returns a copy of pages stably sorted by p.ID().
func SortedByID(pages []*wiki.Page) []*wiki.Page {
	cp := make([]*wiki.Page, len(pages))
	copy(cp, pages)
	sort.SliceStable(cp, func(i, j int) bool {
		return cp[i].ID() < cp[j].ID()
	})
	return cp
}

// LinkGroups groups stems by type prefix in RelTypeOrder, matching app.py's _link_groups().
func LinkGroups(stems []string, byStem map[string]*wiki.Page) []map[string]any {
	buckets := map[string][]map[string]any{}
	var extraOrder []string
	inRelOrder := map[string]bool{}
	for _, t := range wiki.RelTypeOrder {
		inRelOrder[t] = true
	}
	for _, st := range stems {
		p := byStem[st]
		if p == nil {
			continue
		}
		tp := wiki.TypeOf(st)
		if _, exists := buckets[tp]; !exists && !inRelOrder[tp] {
			extraOrder = append(extraOrder, tp)
		}
		buckets[tp] = append(buckets[tp], map[string]any{
			"id":    p.ID(),
			"label": p.Title(),
			"type":  tp,
			"url":   wiki.PageURL(p.Folder, st),
		})
	}
	order := append(append([]string{}, wiki.RelTypeOrder...), extraOrder...)
	out := []map[string]any{}
	for _, tp := range order {
		links, ok := buckets[tp]
		if !ok {
			continue
		}
		lbl := wiki.TypeLabel[tp]
		if lbl == "" {
			lbl = tp
		}
		out = append(out, map[string]any{
			"type":  tp,
			"label": lbl,
			"links": links,
		})
	}
	return out
}

func firstRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max])
}

func runeLen(s string) int {
	return len([]rune(s))
}
