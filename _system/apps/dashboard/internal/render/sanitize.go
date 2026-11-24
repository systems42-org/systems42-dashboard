// Package render turns wiki markdown and wikilinks into sanitised HTML
// matching the Python dashboard's rendering and nh3 allow-list (Phase 1, #80).
package render

import (
	"bytes"
	"regexp"
	"strings"

	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
)

var allowedTags = map[string]bool{
	"a": true, "abbr": true, "acronym": true, "area": true, "article": true,
	"aside": true, "b": true, "bdi": true, "bdo": true, "blockquote": true,
	"br": true, "caption": true, "center": true, "cite": true, "code": true,
	"col": true, "colgroup": true, "data": true, "dd": true, "del": true,
	"details": true, "dfn": true, "div": true, "dl": true, "dt": true,
	"em": true, "figcaption": true, "figure": true, "footer": true, "h1": true,
	"h2": true, "h3": true, "h4": true, "h5": true, "h6": true, "header": true,
	"hgroup": true, "hr": true, "i": true, "img": true, "ins": true, "kbd": true,
	"li": true, "map": true, "mark": true, "nav": true, "ol": true, "p": true,
	"pre": true, "q": true, "rp": true, "rt": true, "rtc": true, "ruby": true,
	"s": true, "samp": true, "small": true, "span": true, "strike": true,
	"strong": true, "sub": true, "summary": true, "sup": true, "table": true,
	"tbody": true, "td": true, "tfoot": true, "th": true, "thead": true,
	"time": true, "tr": true, "tt": true, "u": true, "ul": true, "var": true,
	"wbr": true,
}

// Tags whose entire subtree (including text content) is stripped, matching nh3
// plus defense-in-depth for raw-text and embedded-content elements.
var dropContentTags = map[string]bool{
	"script": true, "style": true, "iframe": true, "object": true,
	"embed": true, "applet": true, "noembed": true, "noframes": true,
	"noscript": true, "plaintext": true, "xmp": true, "textarea": true,
	"title": true, "svg": true, "math": true,
}

var tagAllowedAttrs = map[string]map[string]bool{
	"a":          {"href": true, "hreflang": true},
	"bdo":        {"dir": true},
	"blockquote": {"cite": true},
	"col":        {"align": true, "char": true, "charoff": true, "span": true},
	"colgroup":   {"align": true, "char": true, "charoff": true, "span": true},
	"del":        {"cite": true, "datetime": true},
	"hr":         {"align": true, "size": true, "width": true},
	"img":        {"align": true, "alt": true, "height": true, "src": true, "width": true},
	"ins":        {"cite": true, "datetime": true},
	"ol":         {"start": true},
	"q":          {"cite": true},
	"table":      {"align": true, "char": true, "charoff": true, "summary": true},
	"tbody":      {"align": true, "char": true, "charoff": true},
	"td":         {"align": true, "char": true, "charoff": true, "colspan": true, "headers": true, "rowspan": true, "style": true},
	"tfoot":      {"align": true, "char": true, "charoff": true},
	"th":         {"align": true, "char": true, "charoff": true, "colspan": true, "headers": true, "rowspan": true, "scope": true, "style": true},
	"thead":      {"align": true, "char": true, "charoff": true},
	"tr":         {"align": true, "char": true, "charoff": true},
}

var globalAllowedAttrs = map[string]bool{
	"class": true,
	"id":    true,
	"title": true,
}

var allowedURLSchemes = map[string]bool{
	"bitcoin": true, "ftp": true, "ftps": true, "geo": true, "http": true,
	"https": true, "im": true, "irc": true, "ircs": true, "magnet": true,
	"mailto": true, "mms": true, "mx": true, "news": true, "nntp": true,
	"openpgp4fpr": true, "sip": true, "sms": true, "smsto": true, "ssh": true,
	"tel": true, "url": true, "webcal": true, "wtai": true, "xmpp": true,
}

var defaultStyleProps = map[string]bool{
	"text-align": true,
}

var aboutStyleProps = map[string]bool{
	"text-align": true, "display": true, "gap": true, "flex": true,
	"flex-wrap": true, "align-items": true, "justify-content": true,
	"background": true, "background-color": true, "color": true,
	"padding": true, "margin": true, "border": true, "border-radius": true,
	"width": true, "max-width": true, "height": true,
}

var (
	contentIDRE    = regexp.MustCompile(`^fn(?:ref\d*)?:[\w.-]+$`)
	contentClassRE = regexp.MustCompile(`^(?:wl|wl-anchor|wl-term|mm-anchor|language-[\w+-]+|footnote(?:-ref|-backref)?|table-scroll)$`)
	urlSchemeRE    = regexp.MustCompile(`(?i)^([a-z][a-z0-9+.-]*):`)
	cssFetchRE     = regexp.MustCompile(`(?i)url\s*\(|image-set|image\s*\(|\\`)
)

func stripURLControls(val string) string {
	var b strings.Builder
	for i := 0; i < len(val); i++ {
		c := val[i]
		if c == '\t' || c == '\n' || c == '\r' {
			continue
		}
		b.WriteByte(c)
	}
	return strings.TrimFunc(b.String(), func(r rune) bool { return r <= 32 })
}

func isLocalURL(val string) bool {
	u := stripURLControls(val)
	if urlSchemeRE.MatchString(u) || strings.Contains(u, `\`) || strings.HasPrefix(u, "//") {
		return false
	}
	return true
}

func isSafeURL(val string) bool {
	u := stripURLControls(val)
	m := urlSchemeRE.FindStringSubmatch(u)
	if m == nil {
		return true // relative URL
	}
	return allowedURLSchemes[strings.ToLower(m[1])]
}

func sanitizeStyle(val string, allowedProps map[string]bool) (string, bool) {
	var kept []string
	for _, decl := range strings.Split(val, ";") {
		decl = strings.TrimSpace(decl)
		if decl == "" || cssFetchRE.MatchString(decl) {
			continue
		}
		colon := strings.IndexByte(decl, ':')
		if colon <= 0 {
			continue
		}
		prop := strings.ToLower(strings.TrimSpace(decl[:colon]))
		propVal := strings.TrimSpace(decl[colon+1:])
		if propVal == "" || !allowedProps[prop] {
			continue
		}
		kept = append(kept, prop+":"+propVal)
	}
	if len(kept) == 0 {
		return "", false
	}
	return strings.Join(kept, ";"), true
}

func filterAttr(tag, name, val string, about bool) (string, bool) {
	name = strings.ToLower(name)
	allowed := globalAllowedAttrs[name] || (tagAllowedAttrs[tag] != nil && tagAllowedAttrs[tag][name]) || (about && name == "style")
	if !allowed {
		return "", false
	}
	switch name {
	case "id":
		if !contentIDRE.MatchString(val) {
			return "", false
		}
		return val, true
	case "class":
		var kept []string
		for _, tok := range strings.Fields(val) {
			if contentClassRE.MatchString(tok) {
				kept = append(kept, tok)
			}
		}
		if len(kept) == 0 {
			return "", false
		}
		return strings.Join(kept, " "), true
	case "src":
		if !isLocalURL(val) {
			return "", false
		}
		return val, true
	case "href", "cite":
		if !isSafeURL(val) {
			return "", false
		}
		return val, true
	case "style":
		props := defaultStyleProps
		if about {
			props = aboutStyleProps
		}
		return sanitizeStyle(val, props)
	default:
		return val, true
	}
}

// SanitizeHTML strips scripts, event handlers, unsafe URL schemes, disallowed
// tags/attributes, non-content ids/classes, remote image sources and remote CSS
// fetches from an HTML fragment, matching app.py's sanitize_html().
func SanitizeHTML(raw string, about bool) string {
	ctx := &html.Node{
		Type:     html.ElementNode,
		DataAtom: atom.Div,
		Data:     "div",
	}
	nodes, err := html.ParseFragment(strings.NewReader(raw), ctx)
	if err != nil {
		return ""
	}
	var out bytes.Buffer
	for _, n := range nodes {
		renderClean(&out, n, about)
	}
	return out.String()
}

func renderClean(out *bytes.Buffer, n *html.Node, about bool) {
	switch n.Type {
	case html.TextNode:
		out.WriteString(html.EscapeString(n.Data))
	case html.CommentNode, html.DoctypeNode:
		return
	case html.ElementNode:
		tag := strings.ToLower(n.Data)
		if dropContentTags[tag] {
			return
		}
		if !allowedTags[tag] {
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				renderClean(out, c, about)
			}
			return
		}
		var attrs []html.Attribute
		seen := map[string]bool{}
		for _, a := range n.Attr {
			if a.Namespace != "" {
				continue
			}
			k := strings.ToLower(a.Key)
			if seen[k] {
				continue
			}
			if cleaned, ok := filterAttr(tag, k, a.Val, about); ok {
				seen[k] = true
				attrs = append(attrs, html.Attribute{Key: k, Val: cleaned})
			}
		}
		cleanNode := &html.Node{
			Type:     html.ElementNode,
			DataAtom: n.DataAtom,
			Data:     tag,
			Attr:     attrs,
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			var childBuf bytes.Buffer
			renderClean(&childBuf, c, about)
			if childBuf.Len() > 0 {
				cleanNode.AppendChild(&html.Node{
					Type: html.RawNode,
					Data: childBuf.String(),
				})
			}
		}
		_ = html.Render(out, cleanNode)
	}
}
