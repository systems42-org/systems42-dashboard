package web

import (
	"net/http"
	"regexp"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/project"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	sourceIDPrefixRE = regexp.MustCompile(`^[A-Z]+-\d+`)
	goalWLMatchRE    = regexp.MustCompile(`^\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]`)
)

var conceptCategories = [][2]string{
	{"domain", "Domain"},
	{"user-experience", "User experience"},
	{"safety-security", "Safety & security"},
	{"patterns", "Architecture & design patterns"},
	{"under-the-hood", "Under the hood"},
	{"development", "Development"},
	{"operations", "Operations"},
}

func archRow(p *wiki.Page, folder string) map[string]any {
	return map[string]any{
		"id":     p.ID(),
		"title":  p.Title(),
		"status": p.Status(),
		"state":  wiki.PageState(p),
		"url":    wiki.PageURL(folder, p.Stem),
	}
}

func nilIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func (s *Server) handleGoals(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)
	titles := sn.titleIndex()
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)

	data := project.LoadGoals(sn.folder("goals"), sn.folder("functional-requirements"), sn.byStem())
	vision, objectives := data.Vision, data.Objectives

	allGoals := make([]*wiki.Page, 0, len(objectives)+1)
	if vision != nil {
		allGoals = append(allGoals, vision)
	}
	allGoals = append(allGoals, objectives...)
	goalRows := make([]map[string]any, 0, len(allGoals))
	for _, g := range allGoals {
		goalRows = append(goalRows, map[string]any{
			"id":         g.ID(),
			"title":      g.Title(),
			"url":        wiki.PageURL(g.Folder, g.Stem),
			"stereotype": strings.ToLower(strings.TrimSpace(g.MetaString("stereotype"))),
			"horizon":    strings.TrimSpace(g.MetaString("horizon")),
			"status":     g.Status(),
		})
	}

	wikilinkList := func(items []any) []string {
		out := []string{}
		for _, x := range items {
			st := strings.TrimSpace(wiki.ScalarString(x))
			m := goalWLMatchRE.FindStringSubmatch(st)
			if m == nil {
				continue
			}
			target := strings.TrimSpace(m[1])
			alias := strings.TrimSpace(m[2])
			parts := strings.Split(target, "/")
			base := parts[len(parts)-1]
			if alias != "" {
				out = append(out, alias)
			} else if t, ok := titles[base]; ok {
				out = append(out, t)
			} else {
				out = append(out, base)
			}
		}
		return out
	}

	var visionCard map[string]any
	if vision != nil {
		var htmlBuf strings.Builder
		for _, p := range project.VisionParagraphs(vision, linkCtx) {
			htmlBuf.WriteString("<p>")
			htmlBuf.WriteString(p)
			htmlBuf.WriteString("</p>")
		}
		visionCard = map[string]any{
			"id":          vision.ID(),
			"title":       vision.Title(),
			"url":         wiki.PageURL(vision.Folder, vision.Stem),
			"stereotype":  "Vision",
			"maturity":    nil,
			"beneficiary": wikilinkList(vision.AsList("beneficiary")),
			"html":        htmlBuf.String(),
		}
	} else {
		visionCard = map[string]any{
			"id":          "",
			"title":       "No vision yet",
			"stereotype":  "Vision",
			"maturity":    nil,
			"beneficiary": []string{},
			"html":        "<p>No vision yet — capture a GOAL- page with <code>stereotype: vision</code>.</p>",
		}
	}

	inline := func(v string) string {
		return render.RenderWikilinksText(strings.TrimSpace(v), linkCtx)
	}

	frCols, matrixRows := project.GoalMatrix(data)

	objectiveCards := make([]map[string]any, 0, len(objectives))
	for _, o := range objectives {
		serving := data.Coverage[o.ID()]
		epics := make([]map[string]any, 0, len(serving))
		for _, p := range serving {
			epics = append(epics, map[string]any{
				"id":    p.ID(),
				"title": p.Title(),
				"url":   wiki.PageURL(p.Folder, p.Stem),
			})
		}
		objectiveCards = append(objectiveCards, map[string]any{
			"id":          o.ID(),
			"title":       o.Title(),
			"url":         wiki.PageURL(o.Folder, o.Stem),
			"stereotype":  "Goal",
			"purpose":     render.ExtractPAMBullet(o.Body, "Purpose", linkCtx),
			"advantage":   render.ExtractPAMBullet(o.Body, "Advantage", linkCtx),
			"metric":      inline(o.MetaString("metric")),
			"target":      inline(o.MetaString("target")),
			"baseline":    inline(o.MetaString("baseline")),
			"beneficiary": wikilinkList(o.AsList("beneficiary")),
			"epics":       epics,
		})
	}

	diagram := project.MermaidGoalTree(cfg.SystemName, vision, objectives)
	s.renderHTML(w, r, http.StatusOK, "goals.html", cat, map[string]any{
		"diagram":       nilIfEmpty(diagram),
		"vision":        visionCard,
		"objectives":    objectiveCards,
		"fr_cols":       frCols,
		"matrix_rows":   matrixRows,
		"needs_mermaid": diagram != "",
		"goal_rows":     goalRows,
	}, now)
}

func (s *Server) handleEntityDiagram(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)

	dmPages := sn.folder("data-models")
	dtPages := sn.folder("domain-terms")
	gloPages := sn.folder("glossary")

	nodes := project.DataModelNodes(dmPages, dtPages, gloPages)
	edges := project.DataModelEdges(dmPages, dtPages, gloPages)
	contexts := project.DataModelContexts(nodes)

	q := r.URL.Query()
	ctxFilter := q.Get("context")
	if !containsStr(contexts, ctxFilter) {
		ctxFilter = ""
	}

	focus := q.Get("focus")
	if focus != "" {
		foundKey := false
		for _, n := range nodes {
			if n["key"].(string) == focus {
				foundKey = true
				break
			}
		}
		if !foundKey {
			var matches []string
			for _, n := range nodes {
				if containsStr(n["aliases"].([]string), focus) {
					matches = append(matches, n["key"].(string))
				}
			}
			if len(matches) == 1 {
				focus = matches[0]
			} else {
				focus = ""
			}
		}
	}

	diagram := project.BuildDataModelFullDiagram(nodes, edges, ctxFilter, focus)
	crumb, crumbHref := sectionCrumb(cat, "data-models")

	stubs := make([]map[string]any, 0)
	for _, n := range nodes {
		if stub, _ := n["stub"].(bool); stub {
			stubs = append(stubs, n)
		}
	}

	s.renderHTML(w, r, http.StatusOK, "data_model.html", cat, map[string]any{
		"diagram":       nilIfEmpty(diagram),
		"crumb":         crumb,
		"crumb_href":    crumbHref,
		"entities":      project.DataModelEntities(dmPages, dtPages, linkCtx),
		"nodes":         nodes,
		"contexts":      contexts,
		"context":       nilIfEmpty(ctxFilter),
		"focus":         nilIfEmpty(focus),
		"stubs":         stubs,
		"needs_mermaid": true,
	}, now)
}

func (s *Server) handleGlossaryGraph(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)

	edgeFilter := r.URL.Query().Get("edges")
	if edgeFilter != "all" && edgeFilter != "related" && edgeFilter != "structured" {
		edgeFilter = "all"
	}

	graph := project.BuildGlossaryGraph(
		sn.all(),
		sn.folder("domain-terms"),
		sn.folder("glossary"),
		sn.folder("data-models"),
		edgeFilter,
	)
	counts := graph["layer_counts"].(map[string]int)

	namedSpec := [][2]string{
		{"DM", "Data model"},
		{"STK", "Stakeholder"},
		{"EIF", "Interface"},
		{"GOAL", "Goals"},
		{"BB", "Building block"},
	}
	namedKeys := map[string]bool{}
	namedLayers := make([]map[string]any, 0, len(namedSpec))
	for _, kv := range namedSpec {
		namedKeys[kv[0]] = true
		if c := counts[kv[0]]; c > 0 {
			namedLayers = append(namedLayers, map[string]any{
				"key":   kv[0],
				"label": kv[1],
				"count": c,
			})
		}
	}

	var restKeys []string
	restCount := 0
	for k, c := range counts {
		if !namedKeys[k] {
			restKeys = append(restKeys, k)
			restCount += c
		}
	}
	sort.Strings(restKeys)
	rest := map[string]any{
		"types": restKeys,
		"count": restCount,
	}

	rawNodes := graph["nodes"].([]map[string]any)
	nGlo := 0
	for _, n := range rawNodes {
		d := n["data"].(map[string]any)
		if d["type"] == "GLO" {
			nGlo++
		}
	}

	nodeLinks := func(wantCore bool) []map[string]any {
		var found []map[string]any
		for _, n := range rawNodes {
			d := n["data"].(map[string]any)
			core, _ := d["core"].(bool)
			if core == wantCore {
				found = append(found, d)
			}
		}
		sort.SliceStable(found, func(i, j int) bool {
			return strings.ToLower(found[i]["label"].(string)) < strings.ToLower(found[j]["label"].(string))
		})
		out := make([]map[string]any, 0, len(found))
		for _, d := range found {
			id := sourceIDPrefixRE.FindString(d["id"].(string))
			out = append(out, map[string]any{
				"id":    id,
				"title": d["label"].(string),
				"url":   d["url"].(string),
			})
		}
		return out
	}

	s.renderHTML(w, r, http.StatusOK, "graph.html", cat, map[string]any{
		"graph":        graph,
		"n_glo":        nGlo,
		"term_links":   nodeLinks(true),
		"nearby_links": nodeLinks(false),
		"named_layers": namedLayers,
		"rest":         rest,
		"edge_filter":  edgeFilter,
	}, now)
}

func (s *Server) handleFunctionalRequirements(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug["functional-requirements"]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sn := newSnapshot(s.Store)

	frs := sn.folder("functional-requirements")
	hierarchy := project.BuildFRHierarchy(frs)
	goals := project.LoadGoals(sn.folder("goals"), frs, sn.byStem())
	diagram, diagramLinks := project.MermaidGoalEpicTree(goals, hierarchy)
	if diagramLinks == nil {
		diagramLinks = []map[string]any{}
	}

	allFRPages := append([]*wiki.Page{}, frs...)
	if containsStr(block.Folders, "use-cases") {
		allFRPages = append(allFRPages, sn.folder("use-cases")...)
	}
	allFRPages = sortedByID(allFRPages)

	rows := make([]map[string]any, 0, len(allFRPages))
	for _, p := range allFRPages {
		frPage := p.Folder == "functional-requirements"
		url := wiki.PageURL(p.Folder, p.Stem)
		notation := "use-case"
		if frPage {
			url = "/functional-requirements/" + p.Stem
			notation = project.FRNotation(p)
		}
		rows = append(rows, map[string]any{
			"id":       p.ID(),
			"title":    p.Title(),
			"url":      url,
			"notation": notation,
			"level":    project.FRLevel(p),
			"priority": strings.TrimSpace(p.MetaString("priority")),
			"release":  strings.TrimSpace(p.MetaString("release")),
			"order":    strings.TrimSpace(p.MetaString("order")),
			"status":   p.Status(),
		})
	}

	s.renderHTML(w, r, http.StatusOK, "functional-requirements.html", cat, map[string]any{
		"hierarchy":     hierarchy,
		"diagram":       nilIfEmpty(diagram),
		"diagram_links": diagramLinks,
		"block":         block.ToMap(),
		"needs_mermaid": diagram != "",
		"rows":          rows,
	}, now)
}

func (s *Server) handleFRDetail(w http.ResponseWriter, r *http.Request) {
	if raw := r.URL.RawPath; raw != "" {
		low := strings.ToLower(raw)
		if strings.Contains(low, "%2f") || strings.Contains(low, "%5c") {
			s.handleNotFound(w, r)
			return
		}
	}
	stem := strings.TrimPrefix(r.URL.Path, "/functional-requirements/")
	if stem == "" || stem == "." || stem == ".." || strings.ContainsAny(stem, `/\`) {
		s.handleNotFound(w, r)
		return
	}
	page := s.Store.LoadPage("functional-requirements", stem)
	if page == nil {
		s.handleNotFound(w, r)
		return
	}

	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)
	vocab := s.loadIssueVocab()

	body := leadingH1RE.ReplaceAllString(page.Body, "")
	bodyHTML := render.RenderMarkdown(body, linkCtx)

	frs := sn.folder("functional-requirements")
	hierarchy := project.BuildFRHierarchy(frs)
	node, kind := project.FRHierarchyNode(hierarchy, stem)

	level := kind
	if level == "" {
		level = project.FRLevel(page)
	}
	feats := []map[string]any{}
	directStories := []map[string]any{}
	stories := []map[string]any{}
	nStories := 0
	if node != nil {
		if f, ok := node["features"].([]map[string]any); ok {
			feats = f
		}
		if d, ok := node["direct_stories"].([]map[string]any); ok {
			directStories = d
		}
		if st, ok := node["stories"].([]map[string]any); ok {
			stories = st
		}
		if ns, ok := node["n_stories"].(int); ok {
			nStories = ns
		} else {
			nStories = len(stories)
		}
	}

	fr := map[string]any{
		"id":             page.ID(),
		"title":          page.Title(),
		"stem":           stem,
		"notation":       project.FRNotation(page),
		"level":          level,
		"priority":       strings.TrimSpace(page.MetaString("priority")),
		"release":        strings.TrimSpace(page.MetaString("release")),
		"status":         page.Status(),
		"features":       feats,
		"direct_stories": directStories,
		"stories":        stories,
		"n_features":     len(feats),
		"n_stories":      nStories,
	}

	subtreeNode := node
	if subtreeNode == nil {
		subtreeNode = map[string]any{"id": page.ID(), "title": page.Title()}
	}
	frBlocks := project.FRBuildingBlocks(stem, sn.folder("building-blocks"), sn.byStem())
	diagram, diagramLinks := project.MermaidFRSubtree(subtreeNode, frBlocks)
	if diagramLinks == nil {
		diagramLinks = []map[string]any{}
	}
	trace := buildTrace(sn, stem, "functional-requirements")
	s.renderHTML(w, r, http.StatusOK, "fr.html", cat, map[string]any{
		"fr":            fr,
		"body_html":     bodyHTML,
		"diagram":       nilIfEmpty(diagram),
		"diagram_links": diagramLinks,
		"ancestors":     project.FRAncestors(frs, stem),
		"trace":         trace,
		"relations":     buildRelationsPanel(sn, stem, traceStems(trace), vocab),
		"needs_mermaid": diagram != "" || strings.Contains(bodyHTML, "language-mermaid"),
		"sources":       provenanceChips(page, sn.sourceIndex()),
		"page_issues":   openIssuesFor(sn, stem, vocab),
		"formats":       render.FormatLabels(page.Body, linkCtx),
	}, now)
}

func (s *Server) handleBuildingBlocks(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug["building-blocks"]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sn := newSnapshot(s.Store)
	pages := sn.folder("building-blocks")
	sorted := sortedByID(pages)
	rows := make([]map[string]any, 0, len(sorted))
	for _, p := range sorted {
		rows = append(rows, archRow(p, "building-blocks"))
	}
	byStem := sn.byStem()
	whitebox := project.BuildWhitebox("", pages, sn.folder("external-interfaces"), byStem)

	s.renderHTML(w, r, http.StatusOK, "building_blocks.html", cat, map[string]any{
		"block":    block.ToMap(),
		"tree":     project.BuildBBTree(pages, byStem),
		"total":    len(pages),
		"whitebox": nilIfEmpty(whitebox),
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
		"rows":     rows,
	}, now)
}

func (s *Server) handleConcepts(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug["concepts"]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sn := newSnapshot(s.Store)
	byStem := sn.byStem()
	pages := sortedByID(sn.folder("concepts"))

	known := make(map[string]string, len(conceptCategories))
	for _, kv := range conceptCategories {
		known[kv[0]] = kv[1]
	}

	allCats := append(append([][2]string{}, conceptCategories...), [2]string{"", "Uncategorised"})
	groups := make([]map[string]any, 0)
	for _, kv := range allCats {
		key, label := kv[0], kv[1]
		var rows []map[string]any
		for _, p := range pages {
			raw := strings.TrimSpace(p.MetaString("category"))
			low := strings.ToLower(raw)
			matchedKey := ""
			if _, ok := known[low]; ok {
				matchedKey = low
			}
			if matchedKey != key {
				continue
			}
			row := archRow(p, "concepts")
			if raw != "" && matchedKey == "" {
				row["unknown_category"] = raw
			} else {
				row["unknown_category"] = ""
			}
			row["applies_to"] = linkGroups(wiki.LinksOf(p, "applies-to", byStem), byStem)
			rows = append(rows, row)
		}
		if len(rows) > 0 {
			groups = append(groups, map[string]any{
				"label": label,
				"rows":  rows,
			})
		}
	}

	flat := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		row := archRow(p, "concepts")
		raw := strings.TrimSpace(p.MetaString("category"))
		if lbl, ok := known[strings.ToLower(raw)]; ok {
			row["category"] = lbl
		} else {
			row["category"] = raw
		}
		flat = append(flat, row)
	}

	s.renderHTML(w, r, http.StatusOK, "concepts.html", cat, map[string]any{
		"block":    block.ToMap(),
		"groups":   groups,
		"total":    len(pages),
		"rows":     flat,
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
	}, now)
}

func (s *Server) handleRuntime(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug["runtime"]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sn := newSnapshot(s.Store)
	byStem := sn.byStem()
	pages := sortedByID(sn.folder("runtime-scenarios"))

	rows := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		row := archRow(p, "runtime-scenarios")
		row["drivers"] = linkGroups(wiki.LinksOf(p, "drivers", byStem), byStem)
		row["steps"] = len(project.StepsOf(p, byStem))
		rows = append(rows, row)
	}

	s.renderHTML(w, r, http.StatusOK, "runtime.html", cat, map[string]any{
		"block":    block.ToMap(),
		"rows":     rows,
		"total":    len(pages),
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
	}, now)
}

func (s *Server) handleDeployment(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug["deployment"]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sn := newSnapshot(s.Store)
	byStem := sn.byStem()
	nodes := sn.folder("deployment-nodes")
	blocks := sn.folder("building-blocks")
	eifs := sn.folder("external-interfaces")

	sorted := sortedByID(nodes)
	rows := make([]map[string]any, 0, len(sorted))
	for _, p := range sorted {
		row := archRow(p, "deployment-nodes")
		row["stereotype"] = strings.TrimSpace(p.MetaString("stereotype"))
		rows = append(rows, row)
	}

	diagram, rawLinks := project.BuildDeploymentDiagram("", nodes, blocks, eifs, byStem)
	filteredLinks := make([]map[string]any, 0, len(rawLinks))
	for _, l := range rawLinks {
		if !strings.HasPrefix(l["url"].(string), "/page/deployment-nodes/") {
			filteredLinks = append(filteredLinks, l)
		}
	}

	s.renderHTML(w, r, http.StatusOK, "deployment.html", cat, map[string]any{
		"block":         block.ToMap(),
		"diagram":       nilIfEmpty(diagram),
		"diagram_links": filteredLinks,
		"hints":         project.DeploymentHints("", nodes, blocks, byStem),
		"rows":          rows,
		"tree":          project.BuildNodeTree(nodes, byStem),
		"total":         len(nodes),
		"maturity":      wiki.ComputeMaturity(statusesOf(nodes)).ToMap(),
	}, now)
}
