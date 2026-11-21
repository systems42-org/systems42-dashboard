package project

import (
	"strings"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func mkPage(folder, stem string, meta map[string]any, body string) *wiki.Page {
	if meta == nil {
		meta = map[string]any{}
	}
	return &wiki.Page{
		Stem:   stem,
		Folder: folder,
		Meta:   meta,
		Body:   body,
	}
}

func TestContextDiagramAndFlows(t *testing.T) {
	eifs := []*wiki.Page{
		mkPage("external-interfaces", "EIF-001-erp", map[string]any{
			"id": "EIF-001", "title": "ERP System (legacy)", "short_title": "ERP", "tier": "supply",
			"partner": "Corporate ERP", "status": "accepted",
			"flows": []any{
				map[string]any{"direction": "inbound", "label": "Orders", "data": "Order list", "format": "JSON", "trigger": "daily"},
				map[string]any{"direction": "outbound", "label": "Invoices", "data": "Invoice batch", "format": "unknown"},
			},
		}, ""),
		mkPage("external-interfaces", "EIF-002-old", map[string]any{
			"id": "EIF-002", "title": "Deprecated", "status": "deprecated",
			"flows": []any{map[string]any{"direction": "inbound", "data": "ignored"}},
		}, ""),
	}
	stks := []*wiki.Page{
		mkPage("stakeholders", "STK-001-a", map[string]any{
			"id": "STK-001", "title": "Alice", "context_role": "Reader", "provides": []any{"Search query"},
		}, ""),
		mkPage("stakeholders", "STK-002-b", map[string]any{
			"id": "STK-002", "title": "Bob", "context_role": "Reader", "receives": []any{"Search results"},
		}, ""),
		mkPage("stakeholders", "STK-003-hidden", map[string]any{
			"id": "STK-003", "title": "Hidden", "context_role": "none", "provides": []any{"X"},
		}, ""),
		mkPage("stakeholders", "STK-004-org", map[string]any{
			"id": "STK-004", "title": "Auditor Org", "nature": "organization", "receives": []any{"Reports"},
		}, ""),
	}

	diag, links := BuildContextDiagram("Shop", eifs, stks)
	if !strings.Contains(diag, `subgraph supply["Supply"]`) ||
		!strings.Contains(diag, `EIF001 <-->|"Orders · Invoices"| CORE`) ||
		!strings.Contains(diag, `Reader(["Person · Reader"]):::actor`) ||
		!strings.Contains(diag, `AuditorOrg["Auditor Org"]:::system`) ||
		strings.Contains(diag, "Deprecated") || strings.Contains(diag, "Hidden") {
		t.Fatalf("unexpected context diagram:\n%s", diag)
	}
	if len(links) != 4 { // EIF-001 + STK-001 + STK-002 + STK-004
		t.Fatalf("expected 4 diagram links, got %d", len(links))
	}

	flows := BuildContextFlows(eifs)
	if len(flows) != 1 || flows[0]["label"] != "Orders · Invoices" {
		t.Fatalf("unexpected context flows: %+v", flows)
	}
	rows := flows[0]["rows"].([]map[string]any)
	if len(rows) != 2 || rows[1]["format"] != nil {
		t.Fatalf("expected 'unknown' format normalised to nil, got %+v", rows)
	}
}

func TestEntityDiagramUmlautsInheritanceAndFilters(t *testing.T) {
	dms := []*wiki.Page{
		mkPage("data-models", "DM-001-base", map[string]any{
			"id": "DM-001", "title": "Durchführungsart", "bounded-context": "Core",
			"stereotype": "sum-type", "attributes": []any{map[string]any{"name": "code"}},
		}, ""),
		mkPage("data-models", "DM-002-child", map[string]any{
			"id": "DM-002", "title": "Präsenz", "bounded-context": "Core",
			"parent": []any{"[[DM-001-base]]"},
			"relationships": []any{
				map[string]any{"to": "[[GLO-001-room]]", "kind": "association", "multiplicity": "1..*", "label": "uses"},
			},
		}, ""),
	}
	glos := []*wiki.Page{
		mkPage("glossary", "GLO-001-room", map[string]any{
			"id": "GLO-001", "title": "Room", "bounded-context": "Core", "stereotype": "entity",
		}, ""),
		mkPage("glossary", "GLO-002-plain", map[string]any{
			"id": "GLO-002", "title": "Plain Term",
		}, ""),
	}

	nodes := DataModelNodes(dms, nil, glos)
	if len(nodes) != 3 { // DM-001, DM-002, GLO-001 stub (GLO-002 excluded)
		t.Fatalf("expected 3 nodes, got %d", len(nodes))
	}
	edges := DataModelEdges(dms, nil, glos)
	diag := BuildDataModelFullDiagram(nodes, edges, "Core", "")
	for _, want := range []string{
		`class Durchfuehrungsart["Durchführungsart"] {`,
		`<<sum-type>>`,
		`+code`,
		`<<term>>`,
		`Durchfuehrungsart <|-- Praesenz`,
		`Praesenz --> "1..*" Room : uses`,
	} {
		if !strings.Contains(diag, want) {
			t.Errorf("entity diagram missing %q:\n%s", want, diag)
		}
	}
	if focused := BuildDataModelFullDiagram(nodes, edges, "", "GLO-001-room"); strings.Contains(focused, "Durchfuehrungsart") || !strings.Contains(focused, "Praesenz") {
		t.Errorf("focus filter failed:\n%s", focused)
	}
}

func TestGoalsFRHierarchyAndArchProjections(t *testing.T) {
	goals := []*wiki.Page{
		mkPage("goals", "GOAL-001-vis", map[string]any{"id": "GOAL-001", "title": "Vision", "stereotype": "vision"}, ""),
		mkPage("goals", "GOAL-002-fast", map[string]any{"id": "GOAL-002", "title": "Fast", "stereotype": "objective"}, ""),
	}
	frs := []*wiki.Page{
		mkPage("functional-requirements", "FR-001-epic", map[string]any{
			"id": "FR-001", "title": "Epic A", "notation": "agile", "level": "epic", "order": 1, "goal": []any{"[[GOAL-002-fast]]"},
		}, ""),
		mkPage("functional-requirements", "FR-002-enabler", map[string]any{
			"id": "FR-002", "title": "Platform", "notation": "agile", "level": "epic", "order": 2, "lane": "platform",
		}, ""),
		mkPage("functional-requirements", "FR-003-nogoal", map[string]any{
			"id": "FR-003", "title": "Untraced", "notation": "agile", "level": "epic", "order": 3,
		}, ""),
		mkPage("functional-requirements", "FR-004-feat", map[string]any{
			"id": "FR-004", "title": "Feat 1", "notation": "agile", "level": "feature", "parent": []any{"[[FR-001-epic]]"},
		}, ""),
		mkPage("functional-requirements", "FR-005-old", map[string]any{
			"id": "FR-005", "title": "Retired", "notation": "agile", "level": "epic", "status": "deprecated",
		}, ""),
	}
	byStem := map[string]*wiki.Page{}
	for _, p := range append(append([]*wiki.Page{}, goals...), frs...) {
		byStem[p.Stem] = p
	}

	gd := LoadGoals(goals, frs, byStem)
	if gd.Vision == nil || len(gd.Objectives) != 1 || len(gd.Enablers) != 1 || len(gd.Untraced) != 3 {
		t.Fatalf("LoadGoals unexpected: %+v", gd)
	}
	h := BuildFRHierarchy(frs)
	if h["total_epics"].(int) != 3 || h["total_features"].(int) != 1 {
		t.Fatalf("BuildFRHierarchy counts wrong: %+v", h)
	}
	mapDiag, _ := MermaidGoalEpicTree(gd, h)
	for _, want := range []string{"GOAL002", `ENABLER["Platform / Enabler"]`, `NOGOAL["No goal"]`} {
		if !strings.Contains(mapDiag, want) {
			t.Errorf("goal-epic map missing %q:\n%s", want, mapDiag)
		}
	}
	node, lvl := FRHierarchyNode(h, "FR-001-epic")
	if lvl != "epic" || !strings.Contains(MermaidFRSubtree(node), "FR004") {
		t.Fatalf("FR subtree failed: lvl=%q", lvl)
	}

	// Architecture projections: whitebox, sequence + hints, deployment + hints
	blocks := []*wiki.Page{
		mkPage("building-blocks", "BB-001-web", map[string]any{"id": "BB-001", "title": "Web", "state": "current", "uses": []any{"[[BB-002-db]]"}}, ""),
		mkPage("building-blocks", "BB-002-db", map[string]any{"id": "BB-002", "title": "DB", "state": "planned"}, ""),
	}
	scenarios := []*wiki.Page{
		mkPage("runtime-scenarios", "RS-001-flow", map[string]any{
			"id": "RS-001", "title": "Flow",
			"steps": []any{
				map[string]any{"from": "[[BB-002-db]]", "to": "[[BB-001-web]]", "message": "notify #1; ok"},
			},
		}, ""),
	}
	nodes := []*wiki.Page{
		mkPage("deployment-nodes", "DN-001-host", map[string]any{
			"id": "DN-001", "title": "Server", "technology": "Linux", "state": "current",
			"hosts": []any{"[[BB-001-web]]"},
		}, ""),
	}
	archByStem := map[string]*wiki.Page{}
	for _, p := range append(append(append([]*wiki.Page{}, blocks...), scenarios...), nodes...) {
		archByStem[p.Stem] = p
	}
	wb := BuildWhitebox("", blocks, nil, archByStem)
	if !strings.Contains(wb, "BB001 --> BB002") || !strings.Contains(wb, "stroke-dasharray:5 4") {
		t.Fatalf("BuildWhitebox unexpected:\n%s", wb)
	}
	seq := BuildSequenceDiagram("RS-001-flow", scenarios, archByStem)
	if !strings.Contains(seq, "notify #35;1#59; ok") {
		t.Fatalf("sequence escaping failed:\n%s", seq)
	}
	rh := RuntimeHints("RS-001-flow", scenarios, blocks, archByStem)
	if len(rh) != 1 || !strings.Contains(rh[0], "no uses: edge") {
		t.Fatalf("expected no uses: edge hint, got %+v", rh)
	}
	dep, depLinks := BuildDeploymentDiagram("", nodes, blocks, nil, archByStem)
	if !strings.Contains(dep, `subgraph DN001["DN-001 · Server (Linux)"]`) || !strings.Contains(dep, "DN001_BB001") || len(depLinks) != 2 {
		t.Fatalf("BuildDeploymentDiagram unexpected:\n%s (links=%d)", dep, len(depLinks))
	}
}
