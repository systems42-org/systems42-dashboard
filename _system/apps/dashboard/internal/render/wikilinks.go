package render

import (
	"fmt"
	"html"
	"regexp"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	wikilinkRE     = regexp.MustCompile(`\[\[([^\]\|#]+)(?:#[^\]\|]+)?(?:\|([^\]]+))?\]\]`)
	plainMDRE      = regexp.MustCompile(`\*\*([^*]+)\*\*|` + "`([^`]+)`" + `|<(https?://[^>]+)>|\[([^\]]+)\]\([^)\s]+\)`)
	followsRE      = regexp.MustCompile(`^ {0,3}>[ \t]*follows[ \t]+(\S.*?)[ \t]*$`)
	followsPunctRE = regexp.MustCompile(`[.!?;:]`)
	fenceRE        = regexp.MustCompile("^ {0,3}(`{3,}|~{3,})")
	parensWrapRE   = regexp.MustCompile(`^\((.*)\)$`)
	leadingTheRE   = regexp.MustCompile(`(?i)^the\s+`)
)

const followsPlainMaxWords = 6

// LinkContext provides the per-request indexes needed to resolve wikilinks,
// source provenance links, and method anchors. When Links is nil, wikilinks
// render as styled spans rather than hyperlinks.
type LinkContext struct {
	Titles  map[string]string
	Links   map[string]wiki.PageRef
	Sources map[string]*wiki.Page
	Anchors map[string]metamodel.Anchor
}

// EscapeHTML escapes &, <, >, ", and ' matching MarkupSafe's escape().
func EscapeHTML(s string) string {
	return html.EscapeString(s)
}

// ReplaceWikilinks replaces every Obsidian [[target]] / [[target|alias]] in s
// by calling fn(target, alias).
func ReplaceWikilinks(s string, fn func(target, alias string) string) string {
	return wikilinkRE.ReplaceAllStringFunc(s, func(match string) string {
		sub := wikilinkRE.FindStringSubmatch(match)
		return fn(strings.TrimSpace(sub[1]), strings.TrimSpace(sub[2]))
	})
}

// AnchorTitle formats a method anchor's definition as plain text for a title
// attribute, matching app.py's anchor_title().
func AnchorTitle(a metamodel.Anchor) string {
	text := wikilinkRE.ReplaceAllStringFunc(a.Definition, func(match string) string {
		sub := wikilinkRE.FindStringSubmatch(match)
		if sub[2] != "" {
			return strings.TrimSpace(sub[2])
		}
		return strings.TrimSpace(sub[1])
	})
	return plainMDRE.ReplaceAllStringFunc(text, func(match string) string {
		sub := plainMDRE.FindStringSubmatch(match)
		for i := 1; i <= 4; i++ {
			if sub[i] != "" {
				return sub[i]
			}
		}
		return match
	})
}

// AnchorURL returns the /metamodel anchor fragment for a.
func AnchorURL(a metamodel.Anchor) string {
	return "/metamodel#" + a.ID
}

func anchorLink(a metamodel.Anchor, escapedLabel string) string {
	return fmt.Sprintf(`<a class="wl wl-anchor" href="%s" title="%s">%s</a>`,
		EscapeHTML(AnchorURL(a)), EscapeHTML(AnchorTitle(a)), escapedLabel)
}

// RenderWikilinks replaces [[...]] tokens with hyperlinks (when ctx.Links is
// non-nil and the target resolves) or styled spans. Labels are HTML-escaped;
// surrounding text is untouched.
func RenderWikilinks(text string, ctx LinkContext) string {
	return wikilinkRE.ReplaceAllStringFunc(text, func(match string) string {
		sub := wikilinkRE.FindStringSubmatch(match)
		target := strings.TrimSpace(sub[1])
		alias := sub[2]
		parts := strings.Split(target, "/")
		base := parts[len(parts)-1]

		labelRaw := base
		if alias != "" {
			labelRaw = strings.TrimSpace(alias)
		} else if t, ok := ctx.Titles[base]; ok {
			labelRaw = t
		}
		label := EscapeHTML(labelRaw)

		if ctx.Links != nil && (strings.HasPrefix(target, "raw/") || strings.HasPrefix(base, "SRC-")) {
			if src, ok := ctx.Sources[base]; ok && src != nil {
				srcLabel := src.Title()
				if alias != "" {
					srcLabel = strings.TrimSpace(alias)
				}
				return fmt.Sprintf(`<a class="wl" href="%s">%s</a>`,
					EscapeHTML("/source/"+src.Stem), EscapeHTML(srcLabel))
			}
		} else if len(ctx.Links) > 0 {
			if dest, ok := wiki.ResolveLink(target, ctx.Links); ok {
				return fmt.Sprintf(`<a class="wl" href="%s">%s</a>`,
					EscapeHTML(wiki.PageURL(dest.Folder, dest.Stem)), label)
			}
		}
		if ctx.Links != nil && ctx.Anchors != nil {
			if a, ok := ctx.Anchors[strings.ToLower(base)]; ok {
				aLabel := a.Name
				if alias != "" {
					aLabel = strings.TrimSpace(alias)
				}
				return anchorLink(a, EscapeHTML(aLabel))
			}
		}
		return fmt.Sprintf(`<span class="wl">%s</span>`, label)
	})
}

// RenderWikilinksText escapes all text between wikilinks and resolves wikilinks
// within it, for plain-text frontmatter values such as ingested-pages.
func RenderWikilinksText(text string, ctx LinkContext) string {
	locs := wikilinkRE.FindAllStringIndex(text, -1)
	if len(locs) == 0 {
		return EscapeHTML(text)
	}
	var b strings.Builder
	pos := 0
	for _, loc := range locs {
		b.WriteString(EscapeHTML(text[pos:loc[0]]))
		b.WriteString(RenderWikilinks(text[loc[0]:loc[1]], ctx))
		pos = loc[1]
	}
	b.WriteString(EscapeHTML(text[pos:]))
	return b.String()
}

func fencedLines(lines []string) []bool {
	out := make([]bool, len(lines))
	fence := ""
	for i, line := range lines {
		m := fenceRE.FindStringSubmatch(line)
		if fence != "" {
			if m != nil && m[1][0] == fence[0] && len(m[1]) >= len(fence) {
				fence = ""
			}
			out[i] = true
		} else if m != nil {
			fence = m[1]
			out[i] = true
		}
	}
	return out
}

// findCodeSpans locates inline backtick spans within block without crossing a
// blank line, matching app.py's _CODE_SPAN_RE without needing RE2 lookbehind.
func findCodeSpans(block string) [][2]int {
	var spans [][2]int
	n := len(block)
	i := 0
	for i < n {
		if block[i] != '`' {
			i++
			continue
		}
		// Backslash before the opening backtick escapes it.
		if i > 0 && block[i-1] == '\\' {
			i++
			continue
		}
		// Measure opening run of backticks.
		openStart := i
		for i < n && block[i] == '`' {
			i++
		}
		runLen := i - openStart
		// Scan forward within the same paragraph for a matching exact-length run.
		j := i
		found := -1
		for j < n {
			// A blank line ends the paragraph, so an unclosed span stops here.
			if block[j] == '\n' {
				k := j + 1
				for k < n && (block[k] == ' ' || block[k] == '\t') {
					k++
				}
				if k < n && block[k] == '\n' {
					break
				}
			}
			if block[j] == '`' {
				closeStart := j
				for j < n && block[j] == '`' {
					j++
				}
				if j-closeStart == runLen && closeStart > i {
					found = j
					break
				}
				continue
			}
			j++
		}
		if found >= 0 {
			spans = append(spans, [2]int{openStart, found})
			i = found
		}
	}
	return spans
}

// OutsideCode applies sub to markdown outside fenced code blocks and inline
// code spans, so wikilinks quoted as code stay literal text.
func OutsideCode(text string, sub func(string) string) string {
	lines := strings.Split(text, "\n")
	fenced := fencedLines(lines)
	type block struct {
		isFenced bool
		lines    []string
	}
	var blocks []block
	for i, line := range lines {
		if len(blocks) > 0 && blocks[len(blocks)-1].isFenced == fenced[i] {
			blocks[len(blocks)-1].lines = append(blocks[len(blocks)-1].lines, line)
		} else {
			blocks = append(blocks, block{isFenced: fenced[i], lines: []string{line}})
		}
	}
	out := make([]string, 0, len(blocks))
	for _, blk := range blocks {
		joined := strings.Join(blk.lines, "\n")
		if blk.isFenced {
			out = append(out, joined)
			continue
		}
		spans := findCodeSpans(joined)
		if len(spans) == 0 {
			out = append(out, sub(joined))
			continue
		}
		var b strings.Builder
		pos := 0
		for _, sp := range spans {
			b.WriteString(sub(joined[pos:sp[0]]))
			b.WriteString(joined[sp[0]:sp[1]])
			pos = sp[1]
		}
		b.WriteString(sub(joined[pos:]))
		out = append(out, b.String())
	}
	return strings.Join(out, "\n")
}

type followsNote struct {
	line int
	text string
}

func followsNotes(body string) []followsNote {
	lines := strings.Split(body, "\n")
	fenced := fencedLines(lines)
	var out []followsNote
	for i, line := range lines {
		if fenced[i] {
			continue
		}
		m := followsRE.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		txt := m[1]
		if !wikilinkRE.MatchString(txt) && (len(strings.Fields(txt)) > followsPlainMaxWords || followsPunctRE.MatchString(txt)) {
			continue
		}
		out = append(out, followsNote{line: i, text: txt})
	}
	return out
}

// DropFollows removes "> follows ..." lines outside fenced code so they appear
// only as page-head format labels (FR-035).
func DropFollows(body string) string {
	notes := followsNotes(body)
	if len(notes) == 0 {
		return body
	}
	drop := make(map[int]bool, len(notes))
	for _, n := range notes {
		drop[n.line] = true
	}
	lines := strings.Split(body, "\n")
	kept := make([]string, 0, len(lines)-len(drop))
	for i, line := range lines {
		if !drop[i] {
			kept = append(kept, line)
		}
	}
	return strings.Join(kept, "\n")
}

// FormatLabels extracts deduplicated page-head format labels from "> follows"
// notes in body, matching app.py's format_labels().
func FormatLabels(body string, ctx LinkContext) []map[string]any {
	notes := followsNotes(body)
	out := []map[string]any{}
	seen := map[string]bool{}
	for _, fn := range notes {
		line := fn.text
		note := strings.TrimSpace(strings.Trim(wikilinkRE.ReplaceAllString(line, ""), " ,;."))
		if m := parensWrapRE.FindStringSubmatch(note); m != nil {
			note = strings.TrimSpace(m[1])
		}
		var found []map[string]any
		for _, wm := range wikilinkRE.FindAllStringSubmatch(line, -1) {
			rawTarget := strings.TrimSpace(wm[1])
			parts := strings.Split(rawTarget, "/")
			base := parts[len(parts)-1]
			if a, ok := ctx.Anchors[strings.ToLower(base)]; ok {
				found = append(found, map[string]any{
					"label": a.Name,
					"url":   AnchorURL(a),
					"title": AnchorTitle(a),
				})
			} else if dest, ok := ctx.Links[base]; ok {
				lbl := base
				if t, ok := ctx.Titles[base]; ok {
					lbl = t
				}
				found = append(found, map[string]any{
					"label": lbl,
					"url":   wiki.PageURL(dest.Folder, dest.Stem),
					"title": "",
				})
			} else {
				lbl := base
				if wm[2] != "" {
					lbl = strings.TrimSpace(wm[2])
				}
				found = append(found, map[string]any{
					"label": lbl,
					"url":   "",
					"title": "",
				})
			}
		}
		if len(found) == 0 {
			found = []map[string]any{{
				"label": leadingTheRE.ReplaceAllString(line, ""),
				"url":   "",
				"title": "",
			}}
			note = ""
		}
		for i, item := range found {
			key := strings.ToLower(fmt.Sprint(item["label"]))
			if seen[key] {
				continue
			}
			seen[key] = true
			nVal := ""
			if i == 0 {
				nVal = note
			}
			out = append(out, map[string]any{
				"label": item["label"],
				"url":   item["url"],
				"title": item["title"],
				"note":  nVal,
			})
		}
	}
	return out
}
