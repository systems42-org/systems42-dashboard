package render

import (
	"strings"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func emptyCtx() LinkContext {
	return LinkContext{
		Titles: map[string]string{},
		Links:  map[string]wiki.PageRef{},
	}
}

func TestMarkdownUnwrapAndLists(t *testing.T) {
	ctx := emptyCtx()

	// Hard-wrapped prose becomes one paragraph without <br>
	got := RenderMarkdown("First line of a\nwrapped paragraph.\n\nSecond.", ctx)
	if strings.Contains(got, "<br") || !strings.Contains(got, "<p>First line of a wrapped paragraph.</p>") {
		t.Fatalf("hard-wrapped prose failed: %s", got)
	}

	// List directly after prose renders as <ul>
	got = RenderMarkdown("**Goals.** PAM (light)\n- one thing\n- two things", ctx)
	if !strings.Contains(got, "<ul>") || !strings.Contains(got, "<li>one thing</li>") {
		t.Fatalf("list after prose failed: %s", got)
	}

	// Wrapped list item stays one tight <li>
	got = RenderMarkdown("- Replace the ad-hoc\n  coordination.\n- Second item", ctx)
	if strings.Count(got, "<li>") != 2 || strings.Contains(got, "<li><p>") {
		t.Fatalf("wrapped tight list failed: %s", got)
	}
	if !strings.Contains(strings.ReplaceAll(got, "\n", " "), "ad-hoc coordination") {
		t.Fatalf("wrapped list text missing: %s", got)
	}

	// Explicit two-space break kept
	got = RenderMarkdown("roses are red  \nviolets are blue", ctx)
	if !strings.Contains(got, "<br") {
		t.Fatalf("explicit two-space break lost: %s", got)
	}

	// Spaced pipe in prose still joined
	got = RenderMarkdown("See the linked feature for\ndetails: a | b here.", ctx)
	if !strings.Contains(got, "feature for details: a | b here.") {
		t.Fatalf("spaced pipe broke prose unwrap: %s", got)
	}

	// Prose starting with wikilink is joined
	got = RenderMarkdown("[[STK-001]] wants faster\nonboarding.", ctx)
	if !strings.Contains(got, "wants faster onboarding.") {
		t.Fatalf("prose starting with wikilink not joined: %s", got)
	}

	// Python-Markdown 4-space nested list & sane_lists parity
	got = RenderMarkdown("- **Response.**\n  1. One\n  2. Two\n- **Measure.** Done", ctx)
	if strings.Contains(got, "<ol>") || !strings.Contains(got, "1. One") || !strings.Contains(got, "2. Two") {
		t.Fatalf("2-space ol under ul should stay literal text: %s", got)
	}
	got = RenderMarkdown("- **Response.**\n    1. One\n    2. Two\n- **Measure.** Done", ctx)
	if !strings.Contains(got, "<ol>") || !strings.Contains(got, "<li>One</li>") {
		t.Fatalf("4-space ol under ul should nest: %s", got)
	}
	got = RenderMarkdown("- Outer\n  - Inner2\n- Next", ctx)
	if strings.Count(got, "<ul>") != 1 || strings.Count(got, "<li>") != 3 {
		t.Fatalf("2-space ul under ul should stay sibling: %s", got)
	}
	got = RenderMarkdown("- Outer\n    - Inner4\n- Next", ctx)
	if strings.Count(got, "<ul>") != 2 {
		t.Fatalf("4-space ul under ul should nest: %s", got)
	}
}

func TestMarkdownTablesFencesFootnotesCallouts(t *testing.T) {
	ctx := emptyCtx()

	// Headerless and leading-pipe tables wrapped in table-scroll and idempotent under sanitizer
	got := RenderMarkdown("Header1 | Header2\n--- | ---\na | b", ctx)
	if !strings.Contains(got, `<div class="table-scroll"><table>`) {
		t.Fatalf("headerless table failed: %s", got)
	}

	got = RenderMarkdown("| a | b |\n|:--|--:|\n| 1 | 2 |\n\nText.\n\n| c |\n|---|\n| 3 |", ctx)
	if strings.Count(got, `<div class="table-scroll"><table>`) != 2 || strings.Count(got, "</table></div>") != 2 {
		t.Fatalf("table wrapper count mismatch: %s", got)
	}
	if !strings.Contains(got, `style="text-align:left"`) || !strings.Contains(got, `style="text-align:right"`) {
		t.Fatalf("table alignment lost: %s", got)
	}
	if SanitizeHTML(got, false) != got {
		t.Fatalf("second sanitizer pass changed output:\n1: %s\n2: %s", got, SanitizeHTML(got, false))
	}

	rawTable := RenderMarkdown(`<table class="fbtn"><tr><td>x</td></tr></table>`, ctx)
	if !strings.Contains(rawTable, `<div class="table-scroll"><table><tbody><tr><td>x</td></tr></tbody></table></div>`) {
		t.Fatalf("raw HTML table wrapper/tbody mismatch: %s", rawTable)
	}

	// Tilde fences untouched
	got = RenderMarkdown("Before.\n\n~~~\nline one\nline two\n~~~\nAfter the fence.", ctx)
	if !strings.Contains(got, "<pre><code>line one\nline two\n</code></pre>") || strings.Contains(got, "~~~") || !strings.Contains(got, "<p>After the fence.</p>") {
		t.Fatalf("tilde fence failed: %s", got)
	}

	// Wikilinks inside inline code and fences stay literal
	got = RenderMarkdown("Quote `[[FR-001]]` as written.", ctx)
	if !strings.Contains(got, "<code>[[FR-001]]</code>") || strings.Contains(got, `class="wl"`) {
		t.Fatalf("inline code wikilink escaped wrongly: %s", got)
	}
	got = RenderMarkdown("```yaml\nrelated: [\"[[FR-001]]\"]\n```", ctx)
	if strings.Contains(got, `class="wl"`) || !strings.Contains(got, `[[FR-001]]`) {
		t.Fatalf("backtick fence wikilink failed: %s", got)
	}
	got = RenderMarkdown("~~~\nrelated: [\"[[FR-001]]\"]\n~~~", ctx)
	if strings.Contains(got, `class="wl"`) || !strings.Contains(got, `[[FR-001]]`) {
		t.Fatalf("tilde fence wikilink failed: %s", got)
	}
	got = RenderMarkdown("See [[FR-002|the export]] and `[[FR-001]]`.", ctx)
	if !strings.Contains(got, `<span class="wl">the export</span>`) || !strings.Contains(got, "<code>[[FR-001]]</code>") {
		t.Fatalf("wikilink next to code failed: %s", got)
	}

	// Footnotes preserve id="fn:1", id="fnref:1", class="footnote", footnote-ref, footnote-backref
	got = RenderMarkdown("Text[^1].\n\n[^1]: The note.", ctx)
	for _, want := range []string{`id="fn:1"`, `id="fnref:1"`, `class="footnote"`, `class="footnote-ref"`, `class="footnote-backref"`} {
		if !strings.Contains(got, want) {
			t.Fatalf("footnote missing %s: %s", want, got)
		}
	}

	// Callouts with and without title (test_callouts.py)
	got = RenderMarkdown("> [!note]\n> The target is a proposal.\n", ctx)
	if !strings.Contains(got, "<strong>Note</strong>") || !strings.Contains(got, "The target is a proposal.") || strings.Contains(got, "&gt; The target") {
		t.Fatalf("untitled callout failed: %s", got)
	}
	got = RenderMarkdown("> [!note] Open points\n> None.\n", ctx)
	if !strings.Contains(got, "<strong>Open points</strong>") || !strings.Contains(got, "None.") {
		t.Fatalf("titled callout failed: %s", got)
	}
}

func TestSanitizeHTMLRules(t *testing.T) {
	// Control IDs dropped; footnote IDs kept
	for _, taken := range []string{"settings-dialog", "search-index", "brand-intro", "fn1", "x"} {
		if out := SanitizeHTML(`<p id="`+taken+`">a</p>`, false); strings.Contains(out, "id=") {
			t.Fatalf("disallowed id %q survived: %s", taken, out)
		}
	}
	for _, own := range []string{"fn:1", "fnref:1", "fnref2:1", "fn:note-a"} {
		if out := SanitizeHTML(`<p id="`+own+`">a</p>`, false); !strings.Contains(out, `id="`+own+`"`) {
			t.Fatalf("footnote id %q dropped: %s", own, out)
		}
	}

	// Per-token class allow-list
	got := SanitizeHTML(`<a class="fbtn wl sresult layer-btn language-python">a</a>`, false)
	if !strings.Contains(got, `class="wl language-python"`) {
		t.Fatalf("class filtering failed: %s", got)
	}
	if strings.Contains(SanitizeHTML(`<p class="fbtn">a</p>`, false), "class=") {
		t.Fatalf("disallowed class survived")
	}

	// Remote images lose src; local images keep src
	for _, remote := range []string{
		"https://evil.example/p.gif", "http://evil.example/p.gif",
		"//evil.example/p.gif", `/\evil.example/p.gif`, `\\evil.example/p.gif`,
		" https://evil.example/p.gif", "ht\ttps://evil.example/p.gif",
		"HTTPS://evil.example/p.gif", "data:image/gif;base64,AAAA",
	} {
		out := SanitizeHTML(`<img src="`+remote+`" alt="pixel">`, false)
		if strings.Contains(out, "src=") || !strings.Contains(out, `alt="pixel"`) {
			t.Fatalf("remote image %q not stripped: %s", remote, out)
		}
	}
	for _, local := range []string{"/about/files/a.png", "a.png", "img/a.png", "../a.png", "/static/x.svg?v=1"} {
		out := SanitizeHTML(`<img src="`+local+`" alt="a">`, false)
		if !strings.Contains(out, `src="`+local+`"`) {
			t.Fatalf("local image %q stripped: %s", local, out)
		}
	}

	// External links kept; javascript: stripped
	if out := SanitizeHTML(`<a href="https://example.org/x">x</a>`, false); !strings.Contains(out, `href="https://example.org/x"`) {
		t.Fatalf("external link lost: %s", out)
	}
	if out := SanitizeHTML(`<a href="javascript:alert(1)">x</a>`, false); strings.Contains(out, "javascript:") {
		t.Fatalf("javascript: href survived: %s", out)
	}

	// About styles cannot fetch; wiki pages keep no layout styles
	for _, bad := range []string{
		"background:url(https://evil.example/p.gif)",
		"background: URL( 'https://evil.example/p.gif' )",
		`background:u\72l(https://evil.example/p.gif)`,
		"background:image-set('https://evil.example/p.gif' 1x)",
		"background:-webkit-image-set(url(https://evil.example/p.gif) 1x)",
		"background:image('https://evil.example/p.gif')",
	} {
		out := SanitizeHTML(`<div style="color:red;`+bad+`;padding:4px">a</div>`, true)
		if strings.Contains(out, "evil.example") || !strings.Contains(out, "color:red") || !strings.Contains(out, "padding:4px") {
			t.Fatalf("about style filter failed on %q: %s", bad, out)
		}
	}
	if strings.Contains(SanitizeHTML(`<div style="background:#123456">a</div>`, false), "style=") {
		t.Fatalf("wiki page kept layout style")
	}
}

func TestExtractLabeledPAMAndEmphasis(t *testing.T) {
	ctx := LinkContext{
		Titles: map[string]string{"GLO-001-term": "Term"},
		Links:  map[string]wiki.PageRef{"GLO-001-term": {Folder: "glossary", Stem: "GLO-001-term"}},
	}

	body := "# Heading\n\n**Definition.** First line\nsecond line referencing [[GLO-001-term]] and <script>x</script>.\n\n**Notes.** Ignored."
	got := ExtractLabeled(body, "Definition", ctx)
	if !strings.Contains(got, `href="/page/glossary/GLO-001-term"`) || strings.Contains(got, "<script>") || strings.Contains(got, "Ignored") {
		t.Fatalf("ExtractLabeled unexpected: %s", got)
	}
	if ExtractLabeled(body, "Missing", ctx) != "" {
		t.Fatal("expected empty string for missing label")
	}

	qrBody := "## Scenario\n- **Source.** Any user\n  on mobile.\n- **Measure.** Under *200 ms* via <a href=\"/x*y\">link</a>.\n\n## Next\n"
	src := ExtractPAMBullet(qrBody, "Source", ctx)
	if src != "Any user on mobile." {
		t.Fatalf("ExtractPAMBullet(Source) = %q", src)
	}
	meas := Emphasis(ExtractPAMBullet(qrBody, "Measure", ctx))
	if !strings.Contains(meas, "<em>200 ms</em>") || !strings.Contains(meas, `href="/x*y"`) {
		t.Fatalf("Emphasis broke link or missed italic: %s", meas)
	}

	inline := RenderMarkdownInline("One `[[literal]]` and [[target]].", func(s string) string {
		return ReplaceWikilinks(s, func(target, alias string) string {
			return `<a class="wl" href="#` + target + `">` + target + `</a>`
		})
	})
	if strings.HasPrefix(inline, "<p>") || !strings.Contains(inline, "<code>[[literal]]</code>") || !strings.Contains(inline, `href="#target"`) {
		t.Fatalf("RenderMarkdownInline unexpected: %s", inline)
	}
}
