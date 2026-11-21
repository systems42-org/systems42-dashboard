package project

import (
	"fmt"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

type tierBand struct {
	key   string
	label string
	side  string
}

var tierBands = []tierBand{
	{"supply", "Supply", "left"},
	{"support", "Support", "left"},
	{"demand", "Demand", "right"},
	{"core-operations", "Core operations", "right"},
}

var tierLabelMap = map[string]string{
	"supply":          "Supply",
	"support":         "Support",
	"demand":          "Demand",
	"core-operations": "Core operations",
}

func tierSide(tier string) string {
	for _, b := range tierBands {
		if b.key == tier {
			return b.side
		}
	}
	return "left"
}

func eifNodeLabel(p *wiki.Page) string {
	if s := p.MetaString("short_title"); s != "" {
		return CleanLabel(s, true)
	}
	if s := p.Title(); s != "" {
		return CleanLabel(s, true)
	}
	return CleanLabel(p.MetaString("partner"), true)
}

func flowEdgeLabel(flows []map[string]any) string {
	var seen []string
	seenSet := map[string]bool{}
	for _, f := range flows {
		lab := CleanLabel(wiki.ScalarString(f["label"]), true)
		if lab == "" {
			lab = CleanLabel(wiki.ScalarString(f["data"]), true)
			if runeLen(lab) > 24 {
				lab = strings.TrimRight(firstRunes(lab, 23), " \t\n\r") + "…"
			}
		}
		if lab != "" && !seenSet[lab] {
			seenSet[lab] = true
			seen = append(seen, lab)
		}
	}
	return strings.Join(seen, " · ")
}

func eifFlows(p *wiki.Page) (ins, outs, ordered []map[string]any) {
	for _, item := range p.AsList("flows") {
		f, ok := item.(map[string]any)
		if !ok {
			continue
		}
		ordered = append(ordered, f)
		dir := strings.ToLower(wiki.ScalarString(f["direction"]))
		if dir == "inbound" || dir == "bidirectional" {
			ins = append(ins, f)
		}
		if dir == "outbound" || dir == "bidirectional" {
			outs = append(outs, f)
		}
	}
	return ins, outs, ordered
}

type ctxNode struct {
	nid   string
	label string
	cls   string
}

// BuildContextDiagram projects the Mermaid system-context diagram from
// EIF.flows + STK.provides/receives (DR-013, DR-014, DR-026). Returns "" when
// no edges exist.
func BuildContextDiagram(systemName string, eifs, stakeholders []*wiki.Page) (string, []map[string]any) {
	center := CleanLabel(systemName, false)
	const core = "CORE"
	var drawn []map[string]any
	bands := map[string][]ctxNode{}
	var loose []ctxNode
	var edges []string

	addEdge := func(nid string, ins, outs []map[string]any, side string, ordered []map[string]any) {
		var lab, src, arrow, dst string
		switch {
		case len(ins) > 0 && len(outs) > 0:
			srcFlows := ordered
			if srcFlows == nil {
				srcFlows = append(append([]map[string]any{}, ins...), outs...)
			}
			lab = flowEdgeLabel(srcFlows)
			if side == "left" {
				src, arrow, dst = nid, "<-->", core
			} else {
				src, arrow, dst = core, "<-->", nid
			}
		case len(ins) > 0:
			lab, src, arrow, dst = flowEdgeLabel(ins), nid, "-->", core
		case len(outs) > 0:
			lab, src, arrow, dst = flowEdgeLabel(outs), core, "-->", nid
		default:
			return
		}
		if lab != "" {
			edges = append(edges, fmt.Sprintf(`  %s %s|"%s"| %s`, src, arrow, lab, dst))
		} else {
			edges = append(edges, fmt.Sprintf("  %s %s %s", src, arrow, dst))
		}
	}

	for _, p := range eifs {
		if p.Status() == "deprecated" {
			continue
		}
		ins, outs, ordered := eifFlows(p)
		if len(ins) == 0 && len(outs) == 0 {
			continue
		}
		nid := DiagramNodeID(p.ID())
		tier := strings.ToLower(strings.TrimSpace(p.MetaString("tier")))
		side := tierSide(tier)
		n := ctxNode{nid: nid, label: eifNodeLabel(p), cls: "system"}
		if _, ok := tierLabelMap[tier]; ok {
			bands[tier] = append(bands[tier], n)
		} else {
			loose = append(loose, n)
		}
		addEdge(nid, ins, outs, side, ordered)
		drawn = append(drawn, NodeLink(p))
	}

	type stkGroup struct {
		label string
		prov  []string
		recv  []string
		cls   string
	}
	groupByLabel := map[string]*stkGroup{}
	var groupOrder []*stkGroup
	unionStr := func(dst *[]string, items []any) {
		for _, item := range items {
			s := wiki.ScalarString(item)
			found := false
			for _, cur := range *dst {
				if cur == s {
					found = true
					break
				}
			}
			if !found {
				*dst = append(*dst, s)
			}
		}
	}

	for _, p := range stakeholders {
		prov := p.AsList("provides")
		recv := p.AsList("receives")
		if len(prov) == 0 && len(recv) == 0 {
			continue
		}
		rawRole := p.Meta["context_role"]
		if rs, ok := rawRole.(string); ok && strings.EqualFold(strings.TrimSpace(rs), "none") {
			continue
		}
		label := CleanLabel(p.Title(), true)
		if roleStr := wiki.ScalarString(rawRole); roleStr != "" {
			label = CleanLabel(roleStr, true)
		}
		nature := strings.ToLower(strings.TrimSpace(p.MetaString("nature")))
		isOrg := nature == "organization"
		g, ok := groupByLabel[label]
		if !ok {
			g = &stkGroup{label: label, cls: "actor"}
			groupByLabel[label] = g
			groupOrder = append(groupOrder, g)
		}
		if isOrg {
			g.cls = "system"
		}
		unionStr(&g.prov, prov)
		unionStr(&g.recv, recv)
		drawn = append(drawn, NodeLink(p))
	}

	for _, g := range groupOrder {
		nid := DiagramNodeID(g.label)
		loose = append(loose, ctxNode{nid: nid, label: g.label, cls: g.cls})
		ins := make([]map[string]any, len(g.prov))
		for i, x := range g.prov {
			ins[i] = map[string]any{"data": x}
		}
		outs := make([]map[string]any, len(g.recv))
		for i, x := range g.recv {
			outs[i] = map[string]any{"data": x}
		}
		addEdge(nid, ins, outs, "left", nil)
	}

	if len(edges) == 0 {
		return "", nil
	}

	nodeLine := func(n ctxNode) string {
		if n.cls == "actor" {
			return fmt.Sprintf(`  %s(["Person · %s"]):::actor`, n.nid, n.label)
		}
		return fmt.Sprintf(`  %s["%s"]:::%s`, n.nid, n.label, n.cls)
	}

	lines := []string{"flowchart LR"}
	for _, tb := range tierBands {
		bn := bands[tb.key]
		if len(bn) == 0 {
			continue
		}
		lines = append(lines, fmt.Sprintf(`  subgraph %s["%s"]`, DiagramNodeID(tb.key), tb.label))
		lines = append(lines, "    direction TB")
		for _, n := range bn {
			lines = append(lines, "  "+nodeLine(n))
		}
		lines = append(lines, "  end")
	}
	lines = append(lines, fmt.Sprintf(`  %s["%s"]:::core`, core, CleanLabel(center, true)))
	for _, n := range loose {
		lines = append(lines, nodeLine(n))
	}
	lines = append(lines, edges...)
	lines = append(lines,
		"  classDef core fill:#2f6fb3,stroke:#7fc0ff,stroke-width:2px,color:#ffffff,font-weight:bold;",
		"  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
		"  classDef actor fill:#f3f6fb,stroke:#aeb8c9,color:#15202e;",
	)
	return strings.Join(lines, "\n"), drawn
}

// BuildContextFlows returns the per-interface flow table beneath the context
// diagram (DR-026).
func BuildContextFlows(eifs []*wiki.Page) []map[string]any {
	cell := func(v any) any {
		s := CleanLabel(wiki.ScalarString(v), true)
		low := strings.ToLower(s)
		if s == "" || low == "unknown" || low == "n/a" || low == "none" {
			return nil
		}
		return s
	}
	groups := make([]map[string]any, 0)
	for _, p := range eifs {
		if p.Status() == "deprecated" {
			continue
		}
		ins, outs, ordered := eifFlows(p)
		if len(ins) == 0 && len(outs) == 0 {
			continue
		}
		rows := make([]map[string]any, 0, len(ins)+len(outs))
		addDir := func(flows []map[string]any, dir string) {
			for _, f := range flows {
				dataVal := cell(f["data"])
				if dataVal == nil {
					dataVal = "—"
				}
				rows = append(rows, map[string]any{
					"direction": dir,
					"data":      dataVal,
					"format":    cell(f["format"]),
					"trigger":   cell(f["trigger"]),
				})
			}
		}
		addDir(ins, "in")
		addDir(outs, "out")
		tier := strings.ToLower(strings.TrimSpace(p.MetaString("tier")))
		groups = append(groups, map[string]any{
			"id":      p.ID(),
			"stem":    p.Stem,
			"name":    eifNodeLabel(p),
			"partner": CleanLabel(p.MetaString("partner"), true),
			"tier":    tierLabelMap[tier],
			"label":   flowEdgeLabel(ordered),
			"rows":    rows,
		})
	}
	return groups
}
