package web_test

import (
	"bytes"
	"io/fs"
	"sort"
	"strings"
	"sync"
	"testing"

	dashboard "github.com/systems42-org/systems42-dashboard/_system/apps/dashboard"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/web"
)

// Phase 0 template spike tests (issue #80, question 2): proves the shared
// Jinja2 templates in templates/ parse and render cleanly through gonja/v2
// with our compatibility shims, covering all 40 templates and the three hard
// templates named in #80 (base.html, _macros.html, detail.html).

func newTestEngine() *web.Engine {
	return web.NewEngine(dashboard.TemplatesFS(), web.EngineFuncs{
		StaticURL: func(name string) string { return "/static/" + name + "?v=test" },
		ListSpec: func(typeName string) map[string]any {
			return map[string]any{
				"type":   typeName,
				"orders": []map[string]any{{"label": "By ID", "keys": []string{"id"}}},
			}
		},
	})
}

func TestSpikeAllTemplatesParse(t *testing.T) {
	eng := newTestEngine()
	entries, err := fs.ReadDir(dashboard.TemplatesFS(), ".")
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".html") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	if len(names) < 35 {
		t.Fatalf("expected ~40 templates (including _*.html partials), found %d", len(names))
	}
	for _, name := range names {
		if _, err := eng.Template(name); err != nil {
			t.Errorf("failed to parse %s: %v", name, err)
		}
	}
}

func TestSpikeMacrosTemplate(t *testing.T) {
	eng := newTestEngine()
	src := `{% from "_macros.html" import noun, plural, status_rank, level_rank, severity_rank, issue_status_rank, priority_rank, format_labels %}` +
		`{{ noun(1, 'goal') }}|{{ noun(2, 'goal') }}|{{ noun(2, 'story', 'stories') }}|` +
		`{{ plural(1, 'page') }}|{{ plural(0, 'page') }}|{{ plural(3, 'entry', 'entries') }}|` +
		`{{ status_rank('accepted') }},{{ status_rank('unknown') }}|` +
		`{{ level_rank('high') }}|{{ severity_rank('blocker') }}|{{ issue_status_rank('in-progress') }}|` +
		`{{ priority_rank('Must') }},{{ priority_rank("Won't") }},{{ priority_rank(None) }}|` +
		`{{ format_labels(formats) }}`

	var buf bytes.Buffer
	err := eng.RenderSource(&buf, src, map[string]any{
		"formats": []map[string]any{
			{"label": "MADR", "url": "/metamodel#anchor-madr", "title": "MADR", "note": "v4"},
			{"label": "Untrusted <script>", "url": "", "title": "", "note": ""},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	wantPrefix := "goal|goals|stories|1 page|0 pages|3 entries|3,|3|3|2|1,4,|"
	if !strings.HasPrefix(out, wantPrefix) {
		t.Fatalf("unexpected macro output prefix:\ngot:  %s\nwant: %s", out, wantPrefix)
	}
	if !strings.Contains(out, `<a class="format-label" href="/metamodel#anchor-madr" title="MADR">Format: MADR</a>`) {
		t.Fatalf("format_labels link missing or double-escaped: %s", out)
	}
	if !strings.Contains(out, `Format: Untrusted &lt;script&gt;`) || strings.Contains(out, `<script>`) {
		t.Fatalf("format_labels failed to autoescape untrusted label: %s", out)
	}
}

func TestSpikeDetailAndBaseTemplate(t *testing.T) {
	eng := newTestEngine()
	data := map[string]any{
		"request":     map[string]any{"path": "/page/issues/ISS-001"},
		"csp_nonce":   func() string { return "NONCE123" },
		"system_name": "Systems42 <Test>",
		"active_brand": map[string]any{
			"mark_dark":  "/brand/mark-dark.svg?v=1",
			"mark_light": "/brand/mark-light.svg?v=1",
			"favicon":    "/brand/favicon.svg?v=1",
			"intro_url":  "",
		},
		"nav_items": [][]any{
			{"/req42", "Requirements", false},
			{"/arc42", "Architecture", false},
			{"/issues", "Issues", true},
		},
		"current_area": map[string]any{
			"key": "commons", "label": "Commons", "href": "/commons", "colors": []string{"req", "arc"},
		},
		"refreshed_at":              "2026-11-21 15:00:00h",
		"dashboard_version_own":     "0.12.0",
		"dashboard_version":         "0.11.0",
		"dashboard_version_differs": true,
		"metamodel_check": map[string]any{
			"state": "unsupported", "version": "0.2", "supported": []string{"0.1"},
		},
		"id": "ISS-001", "title": "A <script>alert(1)</script> Title",
		"kind": "Issue", "status": "open", "state": "current",
		"crumb": "Issues <x>", "crumb_href": "/issues",
		"formats": []map[string]any{{"label": "MADR", "url": "/metamodel#anchor-madr", "title": "MADR", "note": ""}},
		"issue": map[string]any{
			"category": "gap", "severity": "major", "kind": "question",
			"owner": "Alice", "owner_url": "/page/stakeholders/STK-001-alice",
		},
		"created": "2026-11-01", "updated": "2026-11-20", "tags": []string{"issue", "security"},
		"sources": []map[string]any{
			{"id": "SRC-001", "title": "Interview", "url": "/source/SRC-001", "type": "notes", "origin": "workshop"},
			{"id": "SRC-999", "title": "Missing", "url": nil, "type": "", "origin": ""},
		},
		"context_diagram": "flowchart LR\n  A --> B",
		"diagram_links":   []map[string]any{{"id": "EIF-001", "title": "GitHub", "url": "/page/external-interfaces/EIF-001"}},
		"context_flows": []map[string]any{
			{
				"id": "EIF-001", "stem": "EIF-001-gh", "name": "GitHub", "tier": "primary",
				"rows": []map[string]any{
					{"direction": "in", "data": "PRs", "format": "JSON", "trigger": "webhook"},
					{"direction": "out", "data": "Status", "format": "", "trigger": ""},
				},
			},
		},
		"ego_graph":  map[string]any{"nodes": []any{map[string]any{"id": "</script>'x"}}, "edges": []any{}},
		"ego_layers": []map[string]any{{"key": "related", "label": "Related", "count": 2}},
		"whitebox":   "flowchart TB\n  X --> Y",
		"sequence":   "sequenceDiagram\n  A->>B: hi",
		"hints":      []string{"Check X"},
		"deployment": "flowchart TB\n  N1",
		"page_issues": []map[string]any{
			{"id": "ISS-002", "title": "Open one", "url": "/page/issues/ISS-002", "status": "open", "severity": "minor", "is_open": true},
			{"id": "ISS-003", "title": "Closed one", "url": "/page/issues/ISS-003", "status": "resolved", "severity": "", "is_open": false},
		},
		"body_html": "<p>Safe <strong>body</strong></p>",
		"trace": map[string]any{
			"drivers": []map[string]any{
				{"label": "Functional requirements", "links": []map[string]any{{"id": "FR-001", "label": "Thing", "url": "/functional-requirements/FR-001"}}},
			},
		},
		"relations": map[string]any{
			"outbound": []map[string]any{
				{"label": "Goals", "links": []map[string]any{{"id": "GOAL-001", "label": "Vision", "url": "/page/goals/GOAL-001", "closed": false, "status": ""}}},
			},
			"inbound": []map[string]any{},
		},
		"needs_mermaid": true,
	}

	var buf bytes.Buffer
	if err := eng.Render(&buf, "detail.html", data); err != nil {
		t.Fatal(err)
	}
	out := buf.String()

	mustContain := []string{
		`A &lt;script&gt;alert(1)&lt;/script&gt; Title`,
		`<div class="crumbs-row"><nav class="crumbs"><a href="/">Home</a>`,
		`Issues &lt;x&gt;</a>`,
		`<article class="detail-pane"><p>Safe <strong>body</strong></p></article>`,
		`\u003c/script\u003e\u0027x`,
		`Format: MADR`,
		`class="detail-relations detail-trace"`,
		`<h2 class="rel-h">Drivers</h2>`,
		`<h2 class="rel-h">Links to</h2>`,
		`Issues that point at this page`,
		`page-issue-closed`,
		`rowspan="2"`,
		`Dashboard 0.12.0 supports 0.1.`,
		`nonce="NONCE123"`,
		`aria-current="page"`,
		`area-bar-2 area-bar-req area-bar-arc`,
	}
	for _, want := range mustContain {
		if !strings.Contains(out, want) {
			t.Errorf("detail.html missing expected substring: %s", want)
		}
	}
	if strings.Contains(out, "<script>alert(1)") {
		t.Error("detail.html rendered unescaped <script> tag from title")
	}
	if strings.Contains(out, "&lt;nav class=") {
		t.Error("crumbs_html block-set was double-escaped")
	}
}

func TestSpikeChainedAndRecursiveMacrosConcurrent(t *testing.T) {
	eng := newTestEngine()
	data := map[string]any{
		"request":     map[string]any{"path": "/arc42/building-blocks"},
		"csp_nonce":   func() string { return "N" },
		"system_name": "S42",
		"active_brand": map[string]any{
			"mark_dark": "/brand/mark-dark.svg", "mark_light": "/brand/mark-light.svg",
			"favicon": "/brand/favicon.svg", "intro_url": "",
		},
		"nav_items":                 [][]any{{"/arc42", "Architecture", true}},
		"current_area":              map[string]any{"key": "architecture", "label": "Architecture", "href": "/arc42", "colors": []string{"arc"}},
		"refreshed_at":              "2026-11-21 15:00:00h",
		"dashboard_version_own":     "0.12.0",
		"dashboard_version":         "0.12.0",
		"dashboard_version_differs": false,
		"metamodel_check":           map[string]any{"state": "supported", "version": "0.1", "supported": []string{"0.1"}},
		"block":                     map[string]any{"id": "A2", "title": "Building Block View"},
		"area":                      map[string]any{"label": "Architecture", "href": "/arc42"},
		"total":                     2,
		"maturity":                  map[string]any{"total": 2, "label": "2 draft", "segments": []map[string]any{{"status": "draft", "n": 2, "pct": 100}}},
		"diagram":                   "flowchart TB\n  A --> B",
		"diagram_links":             []any{},
		"tree": []map[string]any{
			{
				"id": "BB-001", "title": "Root", "url": "/page/building-blocks/BB-001", "state": "current", "status": "draft",
				"children": []map[string]any{
					{"id": "BB-002", "title": "Child", "url": "/page/building-blocks/BB-002", "state": "target", "status": "accepted", "children": []any{}},
				},
			},
		},
		"rows": []map[string]any{
			{"id": "BB-001", "title": "Root", "url": "/page/building-blocks/BB-001", "state": "current", "status": "draft", "level": 1, "drivers": []any{}},
		},
	}

	var wg sync.WaitGroup
	errs := make(chan error, 16)
	for g := 0; g < 16; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 4; i++ {
				var buf bytes.Buffer
				if err := eng.Render(&buf, "building_blocks.html", data); err != nil {
					errs <- err
					return
				}
				if !strings.Contains(buf.String(), "BB-002") || !strings.Contains(buf.String(), `data-sort-value="1"`) {
					errs <- fs.ErrInvalid
					return
				}
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent render failed: %v", err)
	}
}
