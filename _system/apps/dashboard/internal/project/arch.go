package project

import (
	"fmt"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

const (
	mermaidDashed = "stroke-dasharray:5 4"
	mermaidGreyed = "fill:#eceef2,stroke:#9aa3b2,color:#6b7280"
)

func isFutureLifecycle(lc string) bool {
	return lc == "planned" || lc == "target"
}

func isMixedLifecycle(pages []*wiki.Page) bool {
	hasFuture, hasOther := false, false
	for _, p := range pages {
		if isFutureLifecycle(Lifecycle(p)) {
			hasFuture = true
		} else {
			hasOther = true
		}
	}
	return hasFuture && hasOther
}

type markedEntry struct {
	key  string
	nid  string
	page *wiki.Page
}

func lifecycleLines(entries []markedEntry, byStem map[string]*wiki.Page) []string {
	pages := make([]*wiki.Page, len(entries))
	nidByKey := make(map[string]string, len(entries))
	for i, e := range entries {
		pages[i] = e.page
		nidByKey[e.key] = e.nid
	}
	mixed := isMixedLifecycle(pages)
	var lines []string
	for _, e := range entries {
		lc := Lifecycle(e.page)
		if lc == "outdated" {
			lines = append(lines, fmt.Sprintf("  style %s %s", e.nid, mermaidGreyed))
		} else if isFutureLifecycle(lc) && mixed {
			lines = append(lines, fmt.Sprintf("  style %s %s", e.nid, mermaidDashed))
		}
		for _, x := range wiki.LinksOf(e.page, "superseded-by", byStem) {
			if tgtNID, ok := nidByKey[x]; ok {
				lines = append(lines, fmt.Sprintf(`  %s -. "replaced by" .-> %s`, e.nid, tgtNID))
			}
		}
	}
	return lines
}

func lifecycleSuffix(p *wiki.Page, mixed bool, byStem map[string]*wiki.Page) string {
	lc := Lifecycle(p)
	if lc == "outdated" || (isFutureLifecycle(lc) && mixed) {
		return " · " + lc
	}
	if len(wiki.LinksOf(p, "superseded-by", byStem)) > 0 {
		return " · being replaced"
	}
	return ""
}

func levelTree(folder string, folderPages []*wiki.Page, byStem map[string]*wiki.Page) []map[string]any {
	pages := make(map[string]*wiki.Page, len(folderPages))
	for _, p := range folderPages {
		pages[p.Stem] = p
	}
	children := map[string][]string{}
	for _, p := range folderPages {
		parent := ""
		for _, x := range wiki.LinksOf(p, "parent", byStem) {
			if pages[x] != nil {
				parent = x
				break
			}
		}
		children[parent] = append(children[parent], p.Stem)
	}

	sortStemsByID := func(stems []string) []string {
		cp := make([]string, len(stems))
		copy(cp, stems)
		sort.SliceStable(cp, func(i, j int) bool {
			return pages[cp[i]].ID() < pages[cp[j]].ID()
		})
		return cp
	}

	seen := map[string]bool{}
	var buildNode func(s string) map[string]any
	buildNode = func(s string) map[string]any {
		seen[s] = true
		p := pages[s]
		var unvisited []string
		for _, k := range children[s] {
			if !seen[k] {
				unvisited = append(unvisited, k)
			}
		}
		kids := []map[string]any{}
		for _, k := range sortStemsByID(unvisited) {
			if !seen[k] {
				kids = append(kids, buildNode(k))
			}
		}
		return map[string]any{
			"stem":     s,
			"id":       p.ID(),
			"title":    p.Title(),
			"status":   p.Status(),
			"state":    wiki.PageState(p),
			"url":      wiki.PageURL(folder, s),
			"children": kids,
		}
	}

	roots := []map[string]any{}
	for _, s := range sortStemsByID(children[""]) {
		if !seen[s] {
			roots = append(roots, buildNode(s))
		}
	}
	var leftover []string
	for s := range pages {
		if !seen[s] {
			leftover = append(leftover, s)
		}
	}
	for _, s := range sortStemsByID(leftover) {
		if !seen[s] {
			roots = append(roots, buildNode(s))
		}
	}
	sort.SliceStable(roots, func(i, j int) bool {
		return roots[i]["id"].(string) < roots[j]["id"].(string)
	})
	return roots
}

func treeFind(nodes []map[string]any, stem string) map[string]any {
	for _, n := range nodes {
		if n["stem"].(string) == stem {
			return n
		}
		kids, _ := n["children"].([]map[string]any)
		if hit := treeFind(kids, stem); hit != nil {
			return hit
		}
	}
	return nil
}

// BuildBBTree projects the building-block hierarchy (A2).
func BuildBBTree(blocks []*wiki.Page, byStem map[string]*wiki.Page) []map[string]any {
	return levelTree("building-blocks", blocks, byStem)
}

// BuildWhitebox projects the Mermaid white-box diagram for stem ("" for level 1).
func BuildWhitebox(stem string, blocks, eifs []*wiki.Page, byStem map[string]*wiki.Page) string {
	tree := BuildBBTree(blocks, byStem)
	var kids []map[string]any
	if stem == "" {
		kids = tree
	} else {
		if me := treeFind(tree, stem); me != nil {
			kids, _ = me["children"].([]map[string]any)
		}
	}
	if len(kids) == 0 {
		return ""
	}

	inside := make(map[string]bool, len(kids))
	for _, n := range kids {
		inside[n["stem"].(string)] = true
	}
	blockByStem := make(map[string]*wiki.Page, len(blocks))
	for _, p := range blocks {
		blockByStem[p.Stem] = p
	}
	eifByStem := make(map[string]*wiki.Page, len(eifs))
	for _, p := range eifs {
		eifByStem[p.Stem] = p
	}

	kidPages := make([]*wiki.Page, len(kids))
	for i, n := range kids {
		kidPages[i] = blockByStem[n["stem"].(string)]
	}
	mixed := isMixedLifecycle(kidPages)

	lines := []string{"flowchart LR"}
	for _, n := range kids {
		p := blockByStem[n["stem"].(string)]
		sfx := lifecycleSuffix(p, mixed, byStem)
		lines = append(lines, fmt.Sprintf(`  %s["%s · %s%s"]:::block`,
			DiagramNodeID(n["id"].(string)), n["id"].(string), CleanLabel(n["title"].(string), true), sfx))
	}

	var neighbours []string
	nbrSet := map[string]bool{}
	var outside []string
	outSet := map[string]bool{}
	var edges []string
	for _, n := range kids {
		p := blockByStem[n["stem"].(string)]
		srcNID := DiagramNodeID(n["id"].(string))
		for _, t := range wiki.LinksOf(p, "uses", byStem) {
			if inside[t] {
				edges = append(edges, fmt.Sprintf("  %s --> %s", srcNID, DiagramNodeID(blockByStem[t].ID())))
			} else if bp := blockByStem[t]; bp != nil {
				if !outSet[t] {
					outSet[t] = true
					outside = append(outside, t)
				}
				edges = append(edges, fmt.Sprintf("  %s --> %s", srcNID, DiagramNodeID(bp.ID())))
			} else if ep := eifByStem[t]; ep != nil {
				if !nbrSet[t] {
					nbrSet[t] = true
					neighbours = append(neighbours, t)
				}
				edges = append(edges, fmt.Sprintf("  %s --> %s", srcNID, DiagramNodeID(ep.ID())))
			}
		}
	}

	for _, t := range outside {
		bp := blockByStem[t]
		lines = append(lines, fmt.Sprintf(`  %s["%s · %s%s"]:::outside`,
			DiagramNodeID(bp.ID()), bp.ID(), CleanLabel(bp.Title(), true), lifecycleSuffix(bp, mixed, byStem)))
	}
	for _, t := range neighbours {
		ep := eifByStem[t]
		lines = append(lines, fmt.Sprintf(`  %s["%s"]:::system`, DiagramNodeID(ep.ID()), CleanLabel(ep.Title(), true)))
	}
	lines = append(lines, edges...)

	marked := make([]markedEntry, 0, len(kids)+len(outside))
	for _, n := range kids {
		s := n["stem"].(string)
		marked = append(marked, markedEntry{key: s, nid: DiagramNodeID(blockByStem[s].ID()), page: blockByStem[s]})
	}
	for _, s := range outside {
		marked = append(marked, markedEntry{key: s, nid: DiagramNodeID(blockByStem[s].ID()), page: blockByStem[s]})
	}
	lines = append(lines, lifecycleLines(marked, byStem)...)
	lines = append(lines,
		"  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
		"  classDef outside fill:#e3ecf7,stroke:#2f6fb3,stroke-dasharray:4 3,color:#15202e;",
		"  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
	)
	return strings.Join(lines, "\n")
}

// --- Runtime scenarios (A4) ------------------------------------------------

func endpointStem(text string, byStem map[string]*wiki.Page) string {
	if strings.Contains(text, "[[") {
		return wiki.LinkStem(text, byStem)
	}
	// plain text names a page by its file name only: "BB-003" stays text
	if p := byStem[text]; p != nil && p.Stem == text {
		return text
	}
	if idx := strings.LastIndexByte(text, '/'); idx >= 0 {
		last := strings.TrimSpace(text[idx+1:])
		if p := byStem[last]; p != nil && p.Stem == last {
			return last
		}
	}
	return text
}

func resolveEndpoint(raw any, byStem map[string]*wiki.Page) (stem string, label string) {
	text := strings.TrimSpace(wiki.ScalarString(wiki.Scalar(raw)))
	st := ""
	if text != "" {
		st = endpointStem(text, byStem)
	}
	p := byStem[st]
	if p == nil || p.Stem != st {
		if st == "" {
			return "", "?"
		}
		return "", st
	}
	if p.Folder == "stakeholders" || p.Folder == "external-interfaces" {
		return st, CleanLabel(p.Title(), true)
	}
	return st, fmt.Sprintf("%s · %s", p.ID(), CleanLabel(p.Title(), true))
}

// StepsOf returns the valid mapping steps of a runtime scenario in order.
func StepsOf(p *wiki.Page, byStem map[string]*wiki.Page) []map[string]any {
	out := make([]map[string]any, 0)
	for i, item := range Entries(p, "steps") {
		e, ok := item.(map[string]any)
		if !ok {
			continue
		}
		fs, fl := resolveEndpoint(e["from"], byStem)
		ts, tl := resolveEndpoint(e["to"], byStem)
		out = append(out, map[string]any{
			"n":          i + 1,
			"from_stem":  fs,
			"from_label": fl,
			"to_stem":    ts,
			"to_label":   tl,
			"message":    wiki.ScalarString(e["message"]),
			"note":       wiki.ScalarString(e["note"]),
		})
	}
	return out
}

// BuildSequenceDiagram projects the Mermaid sequenceDiagram for a runtime scenario.
func BuildSequenceDiagram(stem string, scenarios []*wiki.Page, byStem map[string]*wiki.Page) string {
	var p *wiki.Page
	for _, q := range scenarios {
		if q.Stem == stem {
			p = q
			break
		}
	}
	if p == nil {
		return ""
	}
	steps := StepsOf(p, byStem)
	if len(steps) == 0 {
		return ""
	}

	type participant struct {
		nid   string
		label string
		kw    string
	}
	var order []participant
	nidOf := map[string]string{}
	partKey := func(sstem, label string) string {
		if sstem != "" {
			return "page:" + sstem
		}
		return "text:" + label
	}
	for _, st := range steps {
		ends := [][2]string{
			{st["from_stem"].(string), st["from_label"].(string)},
			{st["to_stem"].(string), st["to_label"].(string)},
		}
		for _, end := range ends {
			k := partKey(end[0], end[1])
			if _, exists := nidOf[k]; exists {
				continue
			}
			nid := fmt.Sprintf("L%d", len(nidOf)+1)
			nidOf[k] = nid
			kw := "participant"
			if end[0] != "" && byStem[end[0]] != nil && byStem[end[0]].Folder == "stakeholders" {
				kw = "actor"
			}
			order = append(order, participant{nid: nid, label: MMEscape(end[1]), kw: kw})
		}
	}

	lines := make([]string, 0, 1+len(order)+len(steps)*2)
	lines = append(lines, "sequenceDiagram")
	for _, pt := range order {
		lines = append(lines, fmt.Sprintf("  %s %s as %s", pt.kw, pt.nid, pt.label))
	}
	for _, st := range steps {
		a := nidOf[partKey(st["from_stem"].(string), st["from_label"].(string))]
		b := nidOf[partKey(st["to_stem"].(string), st["to_label"].(string))]
		msg := MMEscape(st["message"].(string))
		if msg == "" {
			msg = " "
		}
		lines = append(lines, fmt.Sprintf("  %s->>%s: %s", a, b, msg))
		if note := st["note"].(string); note != "" {
			lines = append(lines, fmt.Sprintf("  Note over %s: %s", b, MMEscape(note)))
		}
	}
	return strings.Join(lines, "\n")
}

func bbAncestors(stem string, blockByStem, byStem map[string]*wiki.Page) []string {
	var out []string
	seen := map[string]bool{}
	cur := stem
	for cur != "" && !seen[cur] && blockByStem[cur] != nil {
		seen[cur] = true
		out = append(out, cur)
		next := ""
		for _, s := range wiki.LinksOf(blockByStem[cur], "parent", byStem) {
			if blockByStem[s] != nil {
				next = s
				break
			}
		}
		cur = next
	}
	return out
}

// RuntimeHints returns advisory hints where a runtime scenario disagrees with
// building blocks or contains invalid step entries (rule-runtime-matches-uses).
func RuntimeHints(stem string, scenarios, blocks []*wiki.Page, byStem map[string]*wiki.Page) []string {
	var p *wiki.Page
	for _, q := range scenarios {
		if q.Stem == stem {
			p = q
			break
		}
	}
	if p == nil {
		return []string{}
	}
	blockByStem := make(map[string]*wiki.Page, len(blocks))
	for _, q := range blocks {
		blockByStem[q.Stem] = q
	}
	hints := []string{}
	hintSet := map[string]bool{}
	addHint := func(h string) {
		if !hintSet[h] {
			hintSet[h] = true
			hints = append(hints, h)
		}
	}

	for i, item := range Entries(p, "steps") {
		if _, ok := item.(map[string]any); !ok {
			hints = append(hints, fmt.Sprintf("step %d: not a {from, to, message} entry, not drawn", i+1))
		}
	}
	for _, st := range StepsOf(p, byStem) {
		n := st["n"].(int)
		for _, end := range []string{"from", "to"} {
			lbl := st[end+"_label"].(string)
			sstem := st[end+"_stem"].(string)
			if sstem == "" {
				if lbl == "?" {
					addHint(fmt.Sprintf("step %d: %s: is empty", n, end))
				} else {
					addHint(fmt.Sprintf("%s: no such page", lbl))
				}
			}
		}
		a, b := st["from_stem"].(string), st["to_stem"].(string)
		if blockByStem[a] != nil && blockByStem[b] != nil && a != b {
			targets := map[string]bool{}
			for _, t := range bbAncestors(b, blockByStem, byStem) {
				targets[t] = true
			}
			matched := false
			for _, x := range bbAncestors(a, blockByStem, byStem) {
				for _, u := range wiki.LinksOf(blockByStem[x], "uses", byStem) {
					if targets[u] {
						matched = true
						break
					}
				}
				if matched {
					break
				}
			}
			if !matched {
				addHint(fmt.Sprintf("%s → %s: no uses: edge", blockByStem[a].ID(), blockByStem[b].ID()))
			}
		}
	}
	return hints
}

// --- Deployment view (A3) --------------------------------------------------

// BuildNodeTree projects the deployment-node hierarchy (A3).
func BuildNodeTree(nodes []*wiki.Page, byStem map[string]*wiki.Page) []map[string]any {
	return levelTree("deployment-nodes", nodes, byStem)
}

// BuildDeploymentDiagram projects the Mermaid deployment flowchart for all
// nodes (root == "") or the subtree under root.
func BuildDeploymentDiagram(root string, nodes, blocks, eifs []*wiki.Page, byStem map[string]*wiki.Page) (string, []map[string]any) {
	tree := BuildNodeTree(nodes, byStem)
	if root != "" {
		me := treeFind(tree, root)
		if me == nil {
			return "", nil
		}
		tree = []map[string]any{me}
	}
	if len(tree) == 0 {
		return "", nil
	}

	nodeByStem := make(map[string]*wiki.Page, len(nodes))
	for _, p := range nodes {
		nodeByStem[p.Stem] = p
	}
	blockByStem := make(map[string]*wiki.Page, len(blocks))
	for _, p := range blocks {
		blockByStem[p.Stem] = p
	}
	eifByStem := make(map[string]*wiki.Page, len(eifs))
	for _, p := range eifs {
		eifByStem[p.Stem] = p
	}

	var inside []*wiki.Page
	var walk func(ns []map[string]any)
	walk = func(ns []map[string]any) {
		for _, n := range ns {
			inside = append(inside, nodeByStem[n["stem"].(string)])
			kids, _ := n["children"].([]map[string]any)
			walk(kids)
		}
	}
	walk(tree)
	nodeCount := len(inside)
	for i := 0; i < nodeCount; i++ {
		for _, b := range wiki.LinksOf(inside[i], "hosts", byStem) {
			if bp := blockByStem[b]; bp != nil {
				inside = append(inside, bp)
			}
		}
	}
	mixed := isMixedLifecycle(inside)

	shown := map[string]bool{}
	markedMap := map[string]markedEntry{}
	lines := []string{"flowchart TB"}

	var emit func(n map[string]any, depth int)
	emit = func(n map[string]any, depth int) {
		stem := n["stem"].(string)
		p := nodeByStem[stem]
		pad := strings.Repeat("  ", depth)
		nid := DiagramNodeID(p.ID())
		label := fmt.Sprintf("%s · %s", p.ID(), CleanLabel(p.Title(), true))
		if tech := CleanLabel(p.MetaString("technology"), true); tech != "" {
			label += " (" + tech + ")"
		}
		label += lifecycleSuffix(p, mixed, byStem)
		shown[stem] = true
		markedMap[stem] = markedEntry{key: stem, nid: nid, page: p}

		var hosted []string
		for _, b := range wiki.LinksOf(p, "hosts", byStem) {
			if blockByStem[b] != nil {
				hosted = append(hosted, b)
			}
		}
		kids, _ := n["children"].([]map[string]any)
		if len(kids) == 0 && len(hosted) == 0 {
			lines = append(lines, fmt.Sprintf(`%s%s["%s"]:::infra`, pad, nid, label))
			return
		}
		lines = append(lines, fmt.Sprintf(`%ssubgraph %s["%s"]`, pad, nid, label))
		for _, b := range hosted {
			bp := blockByStem[b]
			bid := fmt.Sprintf("%s_%s", nid, DiagramNodeID(bp.ID()))
			k := stem + "/" + b
			markedMap[k] = markedEntry{key: k, nid: bid, page: bp}
			lines = append(lines, fmt.Sprintf(`%s  %s["%s · %s%s"]:::block`,
				pad, bid, bp.ID(), CleanLabel(bp.Title(), true), lifecycleSuffix(bp, mixed, byStem)))
		}
		for _, c := range kids {
			emit(c, depth+1)
		}
		lines = append(lines, pad+"end")
	}

	for _, n := range tree {
		emit(n, 1)
	}

	shownSorted := make([]string, 0, len(shown))
	for s := range shown {
		shownSorted = append(shownSorted, s)
	}
	sort.SliceStable(shownSorted, func(i, j int) bool {
		return nodeByStem[shownSorted[i]].ID() < nodeByStem[shownSorted[j]].ID()
	})

	var neighbours []string
	nbrSet := map[string]bool{}
	var edges []string
	for _, s := range shownSorted {
		for _, item := range Entries(nodeByStem[s], "connects") {
			e, ok := item.(map[string]any)
			if !ok {
				continue
			}
			v := wiki.Scalar(e["to"])
			t := ""
			if v != nil && wiki.ScalarString(v) != "" {
				t = wiki.LinkStem(v, byStem)
			}
			var target string
			if shown[t] {
				target = DiagramNodeID(nodeByStem[t].ID())
			} else if ep := eifByStem[t]; ep != nil {
				target = DiagramNodeID(ep.ID())
				if !nbrSet[t] {
					nbrSet[t] = true
					neighbours = append(neighbours, t)
				}
			} else {
				continue
			}
			var protoParts []string
			if pt := EdgeText(wiki.ScalarString(e["protocol"])); pt != "" {
				protoParts = append(protoParts, pt)
			}
			if nt := EdgeText(wiki.ScalarString(e["note"])); nt != "" {
				protoParts = append(protoParts, nt)
			}
			proto := strings.Join(protoParts, " · ")
			arrow := " --> "
			if proto != "" {
				arrow = fmt.Sprintf(` -- "%s" --> `, proto)
			}
			edges = append(edges, fmt.Sprintf("  %s%s%s", DiagramNodeID(nodeByStem[s].ID()), arrow, target))
		}
	}
	for _, t := range neighbours {
		ep := eifByStem[t]
		lines = append(lines, fmt.Sprintf(`  %s["%s"]:::system`, DiagramNodeID(ep.ID()), CleanLabel(ep.Title(), true)))
	}
	lines = append(lines, edges...)

	var drawn []map[string]any
	hostedSet := map[string]bool{}
	for _, s := range shownSorted {
		drawn = append(drawn, NodeLink(nodeByStem[s]))
		for _, b := range wiki.LinksOf(nodeByStem[s], "hosts", byStem) {
			if blockByStem[b] != nil {
				hostedSet[b] = true
			}
		}
	}
	hostedSorted := make([]string, 0, len(hostedSet))
	for b := range hostedSet {
		hostedSorted = append(hostedSorted, b)
	}
	sort.SliceStable(hostedSorted, func(i, j int) bool {
		return blockByStem[hostedSorted[i]].ID() < blockByStem[hostedSorted[j]].ID()
	})
	for _, b := range hostedSorted {
		drawn = append(drawn, NodeLink(blockByStem[b]))
	}
	for _, t := range neighbours {
		drawn = append(drawn, NodeLink(eifByStem[t]))
	}

	markedSlice := make([]markedEntry, 0, len(markedMap))
	for _, e := range markedMap {
		markedSlice = append(markedSlice, e)
	}
	sort.SliceStable(markedSlice, func(i, j int) bool {
		if markedSlice[i].nid != markedSlice[j].nid {
			return markedSlice[i].nid < markedSlice[j].nid
		}
		return markedSlice[i].key < markedSlice[j].key
	})
	lines = append(lines, lifecycleLines(markedSlice, byStem)...)
	lines = append(lines,
		"  classDef infra fill:#e3ecf7,stroke:#2f6fb3,color:#15202e;",
		"  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
		"  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
	)
	return strings.Join(lines, "\n"), drawn
}

// DeploymentHints returns advisory hints for deployment nodes whose connects:
// or hosts: entries cannot be drawn.
func DeploymentHints(stem string, nodes, blocks []*wiki.Page, byStem map[string]*wiki.Page) []string {
	nodeByStem := make(map[string]*wiki.Page, len(nodes))
	for _, p := range nodes {
		nodeByStem[p.Stem] = p
	}
	blockByStem := make(map[string]*wiki.Page, len(blocks))
	for _, p := range blocks {
		blockByStem[p.Stem] = p
	}

	var stems []string
	if stem == "" {
		stems = make([]string, 0, len(nodes))
		for _, p := range SortedByID(nodes) {
			stems = append(stems, p.Stem)
		}
	} else {
		stems = []string{stem}
	}

	hints := []string{}
	for _, s := range stems {
		p := nodeByStem[s]
		if p == nil {
			continue
		}
		for i, item := range Entries(p, "connects") {
			e, ok := item.(map[string]any)
			if !ok {
				hints = append(hints, fmt.Sprintf("%s connects entry %d: not a {to, protocol} entry, not drawn", p.ID(), i+1))
				continue
			}
			v := wiki.Scalar(e["to"])
			t := ""
			if v != nil && wiki.ScalarString(v) != "" {
				t = wiki.LinkStem(v, byStem)
			}
			if t == "" {
				hints = append(hints, fmt.Sprintf("%s connects entry %d: to: is empty, not drawn", p.ID(), i+1))
			} else if byStem[t] == nil {
				hints = append(hints, fmt.Sprintf("%s connects %s: no such page", p.ID(), t))
			}
		}
		for _, b := range wiki.LinksOf(p, "hosts", byStem) {
			if blockByStem[b] == nil {
				hints = append(hints, fmt.Sprintf("%s hosts %s: not a building block, not drawn", p.ID(), b))
			}
		}
	}
	return hints
}
