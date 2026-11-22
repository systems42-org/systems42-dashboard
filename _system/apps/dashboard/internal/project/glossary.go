package project

import (
	"fmt"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	namedGraphTypes = map[string]bool{
		"DM": true, "STK": true, "EIF": true, "GOAL": true, "BB": true,
	}
	egoTypes = map[string]bool{
		"GLO": true, "DM": true, "STK": true, "GOAL": true, "BB": true,
	}
)

type pairKey struct {
	a, b string
}

func makePair(x, y string) pairKey {
	if x < y {
		return pairKey{x, y}
	}
	return pairKey{y, x}
}

type structEdgeKey struct {
	src, tgt, kind, label, card string
}

// BuildGlossaryGraph projects the force-directed cytoscape term network
// (DR-023) from related: links and structured domain-model relationships.
func BuildGlossaryGraph(allPages, domainTerms, glossaryPages, dataModels []*wiki.Page, edgeFilter string) map[string]any {
	glossary := make([]*wiki.Page, 0, len(domainTerms)+len(glossaryPages))
	glossary = append(glossary, domainTerms...)
	glossary = append(glossary, glossaryPages...)

	gloStems := make(map[string]bool, len(glossary))
	gloDegree := make(map[string]int, len(glossary))
	for _, p := range glossary {
		gloStems[p.Stem] = true
		gloDegree[p.Stem] = 0
	}
	byStem := make(map[string]*wiki.Page, len(allPages))
	for _, p := range allPages {
		byStem[p.Stem] = p
	}

	seenPairs := map[pairKey]bool{}
	edges := make([]map[string]any, 0)
	neighbourStems := map[string]bool{}

	if edgeFilter != "structured" {
		for _, p := range glossary {
			src := p.Stem
			for _, raw := range p.AsList("related") {
				tgt := wiki.StemOfLink(raw)
				if tgt == "" || tgt == src || byStem[tgt] == nil {
					continue
				}
				pk := makePair(src, tgt)
				if seenPairs[pk] {
					continue
				}
				seenPairs[pk] = true
				cross := !gloStems[tgt]
				edge := map[string]any{
					"id":     fmt.Sprintf("e%d", len(edges)),
					"source": src,
					"target": tgt,
					"cross":  cross,
					"kind":   "related",
				}
				if cross {
					edge["ntype"] = wiki.TypeOf(tgt)
					neighbourStems[tgt] = true
				} else {
					gloDegree[src]++
					gloDegree[tgt]++
				}
				edges = append(edges, edge)
			}
		}
	}

	if edgeFilter != "related" {
		seenStruct := map[structEdgeKey]bool{}
		for _, rel := range DataModelEdges(dataModels, domainTerms, glossaryPages) {
			src, tgt := rel["source"].(string), rel["target"].(string)
			if !gloStems[src] || !gloStems[tgt] {
				continue
			}
			kind := rel["kind"].(string)
			verb := rel["verb"].(string)
			card := rel["cardinality"].(string)
			key := structEdgeKey{src, tgt, kind, verb, card}
			if seenStruct[key] {
				continue
			}
			seenStruct[key] = true
			lbl := verb
			if lbl == "" {
				lbl = kind
			}
			edges = append(edges, map[string]any{
				"id":     fmt.Sprintf("e%d", len(edges)),
				"source": src,
				"target": tgt,
				"cross":  false,
				"kind":   kind,
				"label":  lbl,
			})
			gloDegree[src]++
			gloDegree[tgt]++
		}
	}

	nodes := make([]map[string]any, 0, len(glossary)+len(neighbourStems))
	for _, p := range glossary {
		state := "draft"
		if p.Status() == "deprecated" {
			state = "deprecated"
		} else if agreed, ok := p.Meta["agreed"].(bool); ok && agreed {
			state = "agreed"
		}
		nodes = append(nodes, map[string]any{
			"id":         p.Stem,
			"label":      p.Title(),
			"type":       "GLO",
			"core":       true,
			"url":        "/page/" + p.Folder + "/" + p.Stem,
			"degree":     gloDegree[p.Stem],
			"state":      state,
			"assumption": strings.Contains(p.Body, "[!assumption]"),
			"aliases":    strings.Join(p.Aliases(), ", "),
		})
	}

	sortedNbrs := make([]string, 0, len(neighbourStems))
	for st := range neighbourStems {
		sortedNbrs = append(sortedNbrs, st)
	}
	sort.Strings(sortedNbrs)
	for _, st := range sortedNbrs {
		pg := byStem[st]
		ntype := wiki.TypeOf(st)
		node := map[string]any{
			"id":    st,
			"label": pg.Title(),
			"type":  ntype,
			"core":  false,
			"url":   "/page/" + pg.Folder + "/" + st,
		}
		if !namedGraphTypes[ntype] {
			node["rest"] = 1
		}
		nodes = append(nodes, node)
	}

	layerCounts := map[string]int{}
	for _, e := range edges {
		if cross, _ := e["cross"].(bool); cross {
			nt := e["ntype"].(string)
			layerCounts[nt]++
		}
	}

	wrappedNodes := make([]map[string]any, len(nodes))
	for i, n := range nodes {
		wrappedNodes[i] = map[string]any{"data": n}
	}
	wrappedEdges := make([]map[string]any, len(edges))
	for i, e := range edges {
		wrappedEdges[i] = map[string]any{"data": e}
	}

	return map[string]any{
		"nodes":        wrappedNodes,
		"edges":        wrappedEdges,
		"layer_counts": layerCounts,
	}
}

// BuildGlossaryEgoGraph builds the 1-hop ego network for a single domain/glossary
// term page (DR-023), returning nil when stem is not in the glossary graph.
func BuildGlossaryEgoGraph(allPages, domainTerms, glossaryPages, dataModels []*wiki.Page, stem string) map[string]any {
	full := BuildGlossaryGraph(allPages, domainTerms, glossaryPages, dataModels, "all")
	fullNodes := full["nodes"].([]map[string]any)
	fullEdges := full["edges"].([]map[string]any)

	nodeByID := make(map[string]map[string]any, len(fullNodes))
	for _, n := range fullNodes {
		d := n["data"].(map[string]any)
		nodeByID[d["id"].(string)] = d
	}
	if _, ok := nodeByID[stem]; !ok {
		return nil
	}

	nbrs := map[string]bool{}
	for _, e := range fullEdges {
		d := e["data"].(map[string]any)
		src, tgt := d["source"].(string), d["target"].(string)
		if src == stem {
			nbrs[tgt] = true
		} else if tgt == stem {
			nbrs[src] = true
		}
	}

	egoIDs := map[string]bool{stem: true}
	for n := range nbrs {
		if d, ok := nodeByID[n]; ok && egoTypes[d["type"].(string)] {
			egoIDs[n] = true
		}
	}

	orderedIDs := make([]string, 0, len(egoIDs))
	for id := range egoIDs {
		orderedIDs = append(orderedIDs, id)
	}
	sort.Strings(orderedIDs)

	nodes := make([]map[string]any, 0, len(orderedIDs))
	for _, id := range orderedIDs {
		src := nodeByID[id]
		cp := make(map[string]any, len(src)+1)
		for k, v := range src {
			cp[k] = v
		}
		if id == stem {
			cp["focus"] = true
		}
		nodes = append(nodes, map[string]any{"data": cp})
	}

	edges := make([]map[string]any, 0)
	layerCounts := map[string]int{}
	for _, e := range fullEdges {
		d := e["data"].(map[string]any)
		if egoIDs[d["source"].(string)] && egoIDs[d["target"].(string)] {
			edges = append(edges, e)
			if cross, _ := d["cross"].(bool); cross {
				if nt, _ := d["ntype"].(string); egoTypes[nt] {
					layerCounts[nt]++
				}
			}
		}
	}

	return map[string]any{
		"nodes":        nodes,
		"edges":        edges,
		"layer_counts": layerCounts,
	}
}
