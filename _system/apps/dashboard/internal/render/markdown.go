package render

import (
	"bytes"
	"regexp"
	"strings"

	"github.com/yuin/goldmark"
	gast "github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	extast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/renderer"
	goldmarkhtml "github.com/yuin/goldmark/renderer/html"
	"github.com/yuin/goldmark/util"
)

var (
	calloutRE        = regexp.MustCompile(`(?m)^>[ \t]*\[!(\w+)\][ \t]*(.*)$`)
	blockStartRE     = regexp.MustCompile("^(\\s*([-*+]|\\d+[.)])\\s|\\s*#|\\s*>|\\s*\\||\\s*```|\\s*~~~|\\s{4,}\\S|\t|\\s*<)")
	listStartRE      = regexp.MustCompile(`^\s*([-*+]|\d+[.)])\s`)
	ulMarkerRE       = regexp.MustCompile(`^( *)([-*+])(\s.*)$`)
	olMarkerRE       = regexp.MustCompile(`^( *)(\d+)([.)])(\s.*)$`)
	bqLineRE         = regexp.MustCompile(`^( {0,3}>[ \t]?)(.*)$`)
	tableSepRE       = regexp.MustCompile(`^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$`)
	tableOpenRE      = regexp.MustCompile(`(?i)<table\b`)
	tableCloseRE     = regexp.MustCompile(`(?i)</table\s*>`)
	collapseSpaceRE  = regexp.MustCompile(`\s+`)
	labeledEndRE     = regexp.MustCompile(`\n\s*\n|\n\s*\*\*`)
	pamBulletStartRE = regexp.MustCompile(`(?m)^[ \t]*-\s+\*\*([A-Za-z]+)\.\*\*\s+`)
	pamBulletEndRE   = regexp.MustCompile(`\n[ \t]*-\s+\*\*|\n##\s|\n\s*\n`)
	emphasisRE       = regexp.MustCompile(`\*(\S[^*]*?)\*`)
	htmlTagRE        = regexp.MustCompile(`<[^>]*>`)
)

// footnoteListRenderer overrides goldmark's default <div class="footnotes">
// with Python-Markdown's singular <div class="footnote"> so the sanitizer's
// class allow-list and HTML parity match Python-Markdown exactly.
type footnoteListRenderer struct{}

func (r *footnoteListRenderer) RegisterFuncs(reg renderer.NodeRendererFuncRegisterer) {
	reg.Register(extast.KindFootnoteList, r.renderFootnoteList)
}

func (r *footnoteListRenderer) renderFootnoteList(w util.BufWriter, _ []byte, _ gast.Node, entering bool) (gast.WalkStatus, error) {
	if entering {
		_, _ = w.WriteString("<div class=\"footnote\">\n<hr>\n<ol>\n")
	} else {
		_, _ = w.WriteString("</ol>\n</div>\n")
	}
	return gast.WalkContinue, nil
}

var mdConverter = goldmark.New(
	goldmark.WithExtensions(
		extension.NewTable(
			extension.WithTableCellAlignMethod(extension.TableCellAlignStyle),
		),
		extension.NewFootnote(
			extension.WithFootnoteLinkClass("footnote-ref"),
			extension.WithFootnoteBacklinkClass("footnote-backref"),
			extension.WithFootnoteBacklinkHTML("↩"),
			extension.WithFootnoteBacklinkTitle("Jump back to footnote ^^ in the text"),
		),
	),
	goldmark.WithRendererOptions(
		goldmarkhtml.WithUnsafe(),
		renderer.WithNodeRenderers(
			util.Prioritized(&footnoteListRenderer{}, 100),
		),
	),
)

// UnwrapProse joins hard-wrapped prose lines into one line per paragraph and
// inserts a blank line between a prose line and a following list, matching
// app.py's _unwrap_prose().
func UnwrapProse(body string) string {
	lines := strings.Split(body, "\n")

	tableLines := map[int]bool{}
	for i, line := range lines {
		if strings.Contains(line, "|") && tableSepRE.MatchString(line) {
			tableLines[i] = true
			if i > 0 && strings.Contains(lines[i-1], "|") {
				tableLines[i-1] = true
			}
			for j := i + 1; j < len(lines) && strings.TrimSpace(lines[j]) != "" && strings.Contains(lines[j], "|"); j++ {
				tableLines[j] = true
			}
		}
	}

	fenced := fencedLines(lines)
	out := make([]string, 0, len(lines))
	inList := false
	for idx, line := range lines {
		stripped := strings.TrimSpace(line)
		if fenced[idx] {
			inList = false
			out = append(out, line)
			continue
		}
		if stripped == "" {
			inList = false
			out = append(out, line)
			continue
		}

		isListStart := listStartRE.MatchString(line)
		isBlockStart := isListStart || blockStartRE.MatchString(line) || tableLines[idx]

		if inList && !isBlockStart {
			out = append(out, strings.TrimLeft(line, " \t"))
			continue
		}

		prev := ""
		if len(out) > 0 {
			prev = out[len(out)-1]
		}
		prevIsProse := strings.TrimSpace(prev) != "" &&
			!blockStartRE.MatchString(prev) &&
			!tableLines[idx-1] &&
			!inList

		if isBlockStart {
			if prevIsProse && isListStart {
				out = append(out, "")
			}
			out = append(out, line)
			inList = isListStart
			continue
		}

		if prevIsProse && !strings.HasSuffix(prev, "  ") {
			out[len(out)-1] = strings.TrimRight(prev, " \t") + " " + stripped
		} else {
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}

// WrapTables puts every HTML table inside a scroll box (QR-001).
func WrapTables(htmlStr string) string {
	htmlStr = tableOpenRE.ReplaceAllString(htmlStr, `<div class="table-scroll"><table`)
	return tableCloseRE.ReplaceAllString(htmlStr, `</table></div>`)
}

func titleWord(s string) string {
	if s == "" {
		return ""
	}
	return strings.ToUpper(s[:1]) + strings.ToLower(s[1:])
}

// normalizePythonMarkdownLists aligns CommonMark (goldmark) with
// Python-Markdown's 4-space nested list rule and sane_lists extension:
// a sub-item indented fewer than 4 spaces deeper than its parent list does
// not nest. Same-kind markers become siblings at the parent indent; opposite-
// kind markers stay literal continuation text inside the current item.
func normalizePythonMarkdownLists(body string) string {
	lines := strings.Split(body, "\n")
	fenced := fencedLines(lines)
	type listFrame struct {
		indent int
		kind   string // "ul" or "ol"
	}
	var stack []listFrame
	inBQPara := false

	for i, line := range lines {
		if fenced[i] {
			stack = nil
			inBQPara = false
			continue
		}
		if bq := bqLineRE.FindStringSubmatch(line); bq != nil {
			prefix, rest := bq[1], bq[2]
			trimmed := strings.TrimSpace(rest)
			if trimmed == "" {
				inBQPara = false
				continue
			}
			expRest := strings.ReplaceAll(rest, "\t", "    ")
			if m := ulMarkerRE.FindStringSubmatch(expRest); m != nil {
				if inBQPara {
					lines[i] = prefix + m[1] + `\` + m[2] + m[3]
				}
				continue
			}
			if m := olMarkerRE.FindStringSubmatch(expRest); m != nil {
				if inBQPara {
					lines[i] = prefix + m[1] + m[2] + `\` + m[3] + m[4]
				}
				continue
			}
			if !strings.HasPrefix(trimmed, "#") && !strings.HasPrefix(trimmed, ">") {
				inBQPara = true
			} else {
				inBQPara = false
			}
			continue
		}
		inBQPara = false
		if strings.TrimSpace(line) == "" {
			// A blank line does not immediately pop an active list, unless a
			// non-indented non-list block follows; keep stack for now.
			continue
		}
		expanded := strings.ReplaceAll(line, "\t", "    ")
		var kind string
		var indent int
		var ulM, olM []string
		if m := ulMarkerRE.FindStringSubmatch(expanded); m != nil {
			kind = "ul"
			indent = len(m[1])
			ulM = m
		} else if m := olMarkerRE.FindStringSubmatch(expanded); m != nil {
			kind = "ol"
			indent = len(m[1])
			olM = m
		}

		if kind == "" {
			// Plain line: pop list frames deeper than this line's indent if it
			// starts a new top-level block (indent 0 after a blank line).
			leading := len(expanded) - len(strings.TrimLeft(expanded, " "))
			if leading == 0 && i > 0 && strings.TrimSpace(lines[i-1]) == "" {
				stack = nil
			}
			continue
		}

		// Pop any frames deeper than this item's indent.
		for len(stack) > 0 && indent < stack[len(stack)-1].indent {
			stack = stack[:len(stack)-1]
		}
		if len(stack) == 0 {
			stack = append(stack, listFrame{indent: indent, kind: kind})
			continue
		}
		top := stack[len(stack)-1]
		if indent >= top.indent+4 {
			stack = append(stack, listFrame{indent: indent, kind: kind})
			continue
		}
		if indent == top.indent {
			if kind != top.kind {
				stack[len(stack)-1].kind = kind
			}
			continue
		}
		// top.indent < indent < top.indent+4: Python-Markdown does not nest.
		if kind == top.kind {
			// Same kind: sibling item at top.indent.
			pad := strings.Repeat(" ", top.indent)
			if ulM != nil {
				lines[i] = pad + ulM[2] + ulM[3]
			} else {
				lines[i] = pad + olM[2] + olM[3] + olM[4]
			}
		} else {
			// Opposite kind (sane_lists): literal continuation text.
			if ulM != nil {
				lines[i] = ulM[1] + `\` + ulM[2] + ulM[3]
			} else {
				lines[i] = olM[1] + olM[2] + `\` + olM[3] + olM[4]
			}
		}
	}
	return strings.Join(lines, "\n")
}

// RenderMarkdown converts a wiki page body to sanitised HTML matching app.py's
// render_markdown().
func RenderMarkdown(body string, ctx LinkContext) string {
	body = strings.ReplaceAll(body, "\r\n", "\n")
	body = DropFollows(body)
	body = UnwrapProse(body)
	body = normalizePythonMarkdownLists(body)
	body = OutsideCode(body, func(chunk string) string {
		return RenderWikilinks(chunk, ctx)
	})
	body = calloutRE.ReplaceAllStringFunc(body, func(match string) string {
		sub := calloutRE.FindStringSubmatch(match)
		label := sub[2]
		if label == "" {
			label = titleWord(sub[1])
		}
		return "> **" + label + "**"
	})

	var buf bytes.Buffer
	if err := mdConverter.Convert([]byte(body), &buf); err != nil {
		return ""
	}
	return SanitizeHTML(WrapTables(buf.String()), false)
}

// RenderMarkdownCustom renders Markdown using a custom outside-code link
// rewriter (used by /metamodel for in-page construct anchors), without
// Obsidian callout conversion or DropFollows.
func RenderMarkdownCustom(body string, rewriteOutsideCode func(string) string) string {
	body = strings.ReplaceAll(body, "\r\n", "\n")
	body = UnwrapProse(body)
	body = normalizePythonMarkdownLists(body)
	if rewriteOutsideCode != nil {
		body = OutsideCode(body, rewriteOutsideCode)
	}
	var buf bytes.Buffer
	if err := mdConverter.Convert([]byte(body), &buf); err != nil {
		return ""
	}
	return SanitizeHTML(WrapTables(buf.String()), false)
}

// RenderMarkdownInline renders one line of Markdown with a custom link rewriter
// and strips a single outer <p>...</p> wrapper for table cells.
func RenderMarkdownInline(body string, rewriteOutsideCode func(string) string) string {
	h := strings.TrimSpace(RenderMarkdownCustom(body, rewriteOutsideCode))
	if strings.HasPrefix(h, "<p>") && strings.HasSuffix(h, "</p>") && strings.Count(h, "<p>") == 1 {
		h = h[3 : len(h)-4]
	}
	return h
}

// ExtractLabeled pulls the paragraph introduced by **<label>.**, collapses
// whitespace, resolves wikilinks, and sanitises the HTML (matching app.py's
// extract_labeled()).
func ExtractLabeled(body, label string, ctx LinkContext) string {
	body = strings.ReplaceAll(body, "\r\n", "\n")
	startRE := regexp.MustCompile(`\*\*` + regexp.QuoteMeta(label) + `\.\*\*\s*`)
	m := startRE.FindStringIndex(body)
	if m == nil {
		return ""
	}
	rest := body[m[1]:]
	if end := labeledEndRE.FindStringIndex(rest); end != nil {
		rest = rest[:end[0]]
	}
	raw := strings.TrimSpace(collapseSpaceRE.ReplaceAllString(rest, " "))
	if raw == "" {
		return ""
	}
	return SanitizeHTML(RenderWikilinks(raw, ctx), false)
}

// ExtractPAMBullet pulls a bullet-style `- **<label>.** ...` field from a page
// body, matching app.py's extract_pam_bullet().
func ExtractPAMBullet(body, label string, ctx LinkContext) string {
	body = strings.ReplaceAll(body, "\r\n", "\n")
	for _, m := range pamBulletStartRE.FindAllStringSubmatchIndex(body, -1) {
		if strings.EqualFold(body[m[2]:m[3]], label) {
			rest := body[m[1]:]
			if end := pamBulletEndRE.FindStringIndex(rest); end != nil {
				rest = rest[:end[0]]
			}
			raw := strings.TrimSpace(collapseSpaceRE.ReplaceAllString(rest, " "))
			if raw == "" {
				return ""
			}
			return SanitizeHTML(RenderWikilinks(raw, ctx), false)
		}
	}
	return ""
}

// Emphasis turns *text* into <em>text</em> in sanitised HTML without touching
// anything inside HTML tags or attributes (matching app.py's _emphasis()).
func Emphasis(htmlStr string) string {
	locs := htmlTagRE.FindAllStringIndex(htmlStr, -1)
	if len(locs) == 0 {
		return emphasisRE.ReplaceAllString(htmlStr, "<em>$1</em>")
	}
	var out strings.Builder
	out.Grow(len(htmlStr) + 16)
	pos := 0
	for _, loc := range locs {
		if loc[0] > pos {
			out.WriteString(emphasisRE.ReplaceAllString(htmlStr[pos:loc[0]], "<em>$1</em>"))
		}
		out.WriteString(htmlStr[loc[0]:loc[1]])
		pos = loc[1]
	}
	if pos < len(htmlStr) {
		out.WriteString(emphasisRE.ReplaceAllString(htmlStr[pos:], "<em>$1</em>"))
	}
	return out.String()
}
