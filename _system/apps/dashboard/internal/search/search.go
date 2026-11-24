// Package search builds the client-ranked search index, synonyms, facets, and
// filter options for /search and /search.json (FR-001 to FR-009).
package search

import (
	"regexp"
	"sort"
	"strings"
	"unicode"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// SearchFields lists the frontmatter fields indexed as plain words (FR-006).
var SearchFields = []string{
	"tags", "status", "stereotype", "notation", "level", "priority", "kind", "state",
	"category", "dimensions",
}

var priorityOrder = map[string]int{
	"must":   0,
	"should": 1,
	"could":  2,
	"wont":   3,
	"won't":  4,
}

var (
	mdLinkRE       = regexp.MustCompile(`!?\[([^\]]*)\]\([^)]*\)`)
	htmlTagRE      = regexp.MustCompile(`<[^>]+>`)
	sourceIDRE     = regexp.MustCompile(`^[A-Z]+-\d+`)
	tableSepRE     = regexp.MustCompile(`^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$`)
	headingLineRE  = regexp.MustCompile(`^\s*(?:#{1,6}\s|>\s*\[![\w-]+\]|\*\*[^*]+\*\*\s*$)`)
	leadLabelRE    = regexp.MustCompile(`^(\s*(?:[-*+]\s+)?)\*\*[^*]{1,60}[.:]\*\*\s+`)
	lineMarkRE     = regexp.MustCompile(`^\s*(?:#{1,6}\s+|>\s*(?:\[![\w-]+\][-+]?\s*)?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+`)
	collapseWSRE   = regexp.MustCompile(`\s+`)
	doubleMarkerRE = regexp.MustCompile(`\*\*|__|~~|` + "`")
)

func isWordRune(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_'
}

// stripSearchEmphasis matches Python's `\*\*|__|~~|`|(?<!\w)\*(?=\S)|(?<=\S)\*(?!\w)`.
func stripSearchEmphasis(s string) string {
	s = doubleMarkerRE.ReplaceAllString(s, "")
	if !strings.ContainsRune(s, '*') {
		return s
	}
	runes := []rune(s)
	var out strings.Builder
	out.Grow(len(s))
	for i, r := range runes {
		if r == '*' {
			prevWord := i > 0 && isWordRune(runes[i-1])
			prevNonSpace := i > 0 && !unicode.IsSpace(runes[i-1])
			nextWord := i+1 < len(runes) && isWordRune(runes[i+1])
			nextNonSpace := i+1 < len(runes) && !unicode.IsSpace(runes[i+1])
			if (!prevWord && nextNonSpace) || (prevNonSpace && !nextWord) {
				continue
			}
		}
		out.WriteRune(r)
	}
	return out.String()
}

// Plain extracts reader-visible plain text from page.Body for client-side
// search ranking, matching app.py's search_plain().
func Plain(page *wiki.Page, titles map[string]string, sources map[string]*wiki.Page) string {
	body := strings.ReplaceAll(page.Body, "\r\n", "\n")
	body = render.UnwrapProse(render.DropFollows(body))
	body = render.ReplaceWikilinks(body, func(target, label string) string {
		parts := strings.Split(target, "/")
		base := parts[len(parts)-1]
		if label != "" {
			return label
		}
		if strings.HasPrefix(target, "raw/") || strings.HasPrefix(base, "SRC-") {
			if src := sources[base]; src != nil {
				return src.ID()
			}
			if id := sourceIDRE.FindString(base); id != "" {
				return id
			}
			return ""
		}
		if t, ok := titles[base]; ok {
			return t
		}
		return target
	})
	body = mdLinkRE.ReplaceAllString(body, "$1")
	body = htmlTagRE.ReplaceAllString(body, " ")

	var lines []string
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") ||
			tableSepRE.MatchString(line) ||
			headingLineRE.MatchString(line) {
			continue
		}
		line = leadLabelRE.ReplaceAllString(line, "$1")
		line = lineMarkRE.ReplaceAllString(line, "")
		line = strings.ReplaceAll(stripSearchEmphasis(line), "|", " ")
		line = strings.TrimSpace(collapseWSRE.ReplaceAllString(line, " "))
		if line != "" && line != "---" {
			lines = append(lines, line)
		}
	}
	return strings.Join(lines, "\n")
}

func fieldsOf(page *wiki.Page) map[string][]string {
	out := map[string][]string{}
	for _, key := range SearchFields {
		raw, ok := page.Meta[key]
		if !ok || raw == nil {
			continue
		}
		var items []any
		if list, ok := raw.([]any); ok {
			items = list
		} else {
			items = []any{raw}
		}
		var vals []string
		for _, x := range items {
			if x == nil {
				continue
			}
			if s := strings.ToLower(strings.TrimSpace(wiki.ScalarString(x))); s != "" {
				vals = append(vals, s)
			}
		}
		if len(vals) > 0 {
			out[key] = vals
		}
	}
	return out
}

func neighbourLinks(pages []*wiki.Page, linkIdx map[string]wiki.PageRef) map[string][]string {
	byStem := make(map[string]*wiki.Page, len(pages))
	sets := make(map[string]map[string]bool, len(pages))
	for _, p := range pages {
		byStem[p.Stem] = p
		if sets[p.ID()] == nil {
			sets[p.ID()] = map[string]bool{}
		}
	}
	for _, p := range pages {
		pid := p.ID()
		for tgt := range p.LinkTargets() {
			dest, ok := linkIdx[tgt]
			if !ok {
				continue
			}
			otherPage := byStem[dest.Stem]
			if otherPage == nil {
				continue
			}
			oid := otherPage.ID()
			if oid != pid {
				sets[pid][oid] = true
				if sets[oid] == nil {
					sets[oid] = map[string]bool{}
				}
				sets[oid][pid] = true
			}
		}
	}
	out := make(map[string][]string, len(sets))
	for id, s := range sets {
		list := make([]string, 0, len(s))
		for k := range s {
			list = append(list, k)
		}
		sort.Strings(list)
		out[id] = list
	}
	return out
}

// BuildRecords builds the flat list of search records over allPages.
func BuildRecords(allPages []*wiki.Page, titles map[string]string, linkIdx map[string]wiki.PageRef, sources map[string]*wiki.Page) []map[string]any {
	nbrs := neighbourLinks(allPages, linkIdx)
	records := make([]map[string]any, 0, len(allPages))
	for _, p := range allPages {
		typeLabel := metamodel.Label(p.Folder)
		url := "/page/" + p.Folder + "/" + p.Stem
		if metamodel.IsType(p.Folder, "functional-requirement") {
			url = "/functional-requirements/" + p.Stem
		}
		aliases := p.Aliases()
		if aliases == nil {
			aliases = []string{}
		}
		links := nbrs[p.ID()]
		if links == nil {
			links = []string{}
		}
		records = append(records, map[string]any{
			"id":      p.ID(),
			"type":    typeLabel,
			"title":   p.Title(),
			"status":  p.Status(),
			"url":     url,
			"aliases": aliases,
			"plain":   Plain(p, titles, sources),
			"fields":  fieldsOf(p),
			"links":   links,
		})
	}
	return records
}

// Synonyms builds lower-cased title+alias synonym groups from domain terms
// (FR-003).
func Synonyms(domainTerms []*wiki.Page) [][]string {
	out := make([][]string, 0, len(domainTerms))
	for _, p := range domainTerms {
		group := make([]string, 0, 1+len(p.Aliases()))
		if t := strings.ToLower(strings.TrimSpace(p.Title())); t != "" {
			group = append(group, t)
		}
		for _, a := range p.Aliases() {
			if s := strings.ToLower(strings.TrimSpace(a)); s != "" {
				group = append(group, s)
			}
		}
		out = append(out, group)
	}
	return out
}

// BuildIndex returns {records, synonyms} for /search.json and /search.
func BuildIndex(allPages, domainTerms []*wiki.Page, titles map[string]string, linkIdx map[string]wiki.PageRef, sources map[string]*wiki.Page) map[string]any {
	return map[string]any{
		"records":  BuildRecords(allPages, titles, linkIdx, sources),
		"synonyms": Synonyms(domainTerms),
	}
}

// Filters computes the status, priority, and tag dropdown options for /search
// (FR-009), keeping the first spelling seen for each lower-cased value.
func Filters(allPages []*wiki.Page) map[string][]map[string]any {
	labels := map[string]map[string]string{
		"status":   {},
		"priority": {},
		"tags":     {},
	}
	for _, p := range allPages {
		for key, seen := range labels {
			raw, ok := p.Meta[key]
			if !ok || raw == nil {
				continue
			}
			var items []any
			if list, ok := raw.([]any); ok {
				items = list
			} else {
				items = []any{raw}
			}
			for _, x := range items {
				if x == nil {
					continue
				}
				written := strings.TrimSpace(wiki.ScalarString(x))
				if written == "" {
					continue
				}
				low := strings.ToLower(written)
				if _, exists := seen[low]; !exists {
					seen[low] = written
				}
			}
		}
	}

	buildOpts := func(key string, usePrioOrder bool) []map[string]any {
		vals := labels[key]
		keys := make([]string, 0, len(vals))
		for k := range vals {
			keys = append(keys, k)
		}
		sort.SliceStable(keys, func(i, j int) bool {
			if usePrioOrder {
				ri, oki := priorityOrder[keys[i]]
				rj, okj := priorityOrder[keys[j]]
				if oki != okj {
					return oki
				}
				if oki && ri != rj {
					return ri < rj
				}
			}
			return keys[i] < keys[j]
		})
		out := make([]map[string]any, 0, len(keys))
		for _, k := range keys {
			out = append(out, map[string]any{
				"value": k,
				"label": vals[k],
			})
		}
		return out
	}

	return map[string][]map[string]any{
		"status":   buildOpts("status", false),
		"priority": buildOpts("priority", true),
		"tag":      buildOpts("tags", false),
	}
}

// Facets returns [typeName, count] pairs ordered by (-count, typeName).
func Facets(records []map[string]any) [][]any {
	tally := map[string]int{}
	for _, r := range records {
		tp := r["type"].(string)
		tally[tp]++
	}
	types := make([]string, 0, len(tally))
	for tp := range tally {
		types = append(types, tp)
	}
	sort.SliceStable(types, func(i, j int) bool {
		if tally[types[i]] != tally[types[j]] {
			return tally[types[i]] > tally[types[j]]
		}
		return types[i] < types[j]
	})
	out := make([][]any, 0, len(types))
	for _, tp := range types {
		out = append(out, []any{tp, tally[tp]})
	}
	return out
}
