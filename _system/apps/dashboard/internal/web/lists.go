package web

import (
	"net/http"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/project"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

const clarifyIssueStem = "ISS-002-define-the-clarify-loop"

var (
	decisionKinds  = []string{"architecture", "business", "undefined"}
	decisionLabels = map[string]string{
		"architecture": "Architecture",
		"business":     "Business",
		"undefined":    "Undefined",
	}
	qrScenarioLabels = []string{"Source", "Stimulus", "Environment", "Response", "Measure"}
)

func (s *Server) isDirectlyHidden(id string) bool {
	s.viewMu.RLock()
	hidden := s.viewHidden
	s.viewMu.RUnlock()
	for _, h := range hidden {
		if h == id {
			return true
		}
	}
	return false
}

func (s *Server) handleArea(w http.ResponseWriter, r *http.Request, areaKey string) {
	area, ok := metamodel.AreaByKey[areaKey]
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)

	var tiles []map[string]any
	var pages []*wiki.Page
	for _, sec := range cat.SectionsOf(areaKey) {
		if s.isDirectlyHidden(sec.ID) {
			continue
		}
		tile := buildSectionTile(sn, sec)
		tiles = append(tiles, tile)
		if folders, ok := tile["folders"].([]string); ok {
			for _, f := range folders {
				pages = append(pages, sn.folder(f)...)
			}
		}
	}

	s.renderHTML(w, r, http.StatusOK, "area.html", cat, map[string]any{
		"area":          area.ToMap(),
		"tiles":         tiles,
		"count":         len(pages),
		"maturity":      wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
		"needs_mermaid": false,
	}, now)
}

func qrDetails(p *wiki.Page, linkCtx render.LinkContext) map[string]any {
	scenario := make([][]any, 0, len(qrScenarioLabels))
	for _, label := range qrScenarioLabels {
		if h := render.ExtractPAMBullet(p.Body, label, linkCtx); h != "" {
			scenario = append(scenario, []any{label, render.Emphasis(h)})
		}
	}
	rawDims := p.AsStringList("dimensions")
	dims := make([]string, 0, len(rawDims))
	for _, d := range rawDims {
		if t := strings.TrimSpace(d); t != "" {
			dims = append(dims, t)
		}
	}
	return map[string]any{
		"dimensions": dims,
		"priority":   strings.TrimSpace(p.MetaString("priority")),
		"scenario":   scenario,
	}
}

func (s *Server) renderBlockList(w http.ResponseWriter, r *http.Request, cat *metamodel.Catalog, block metamodel.Section, slug string) {
	now := s.Now()
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)

	var pages []*wiki.Page
	for _, folder := range metamodel.SectionFolders(block) {
		pages = append(pages, sn.folder(folder)...)
	}
	pages = sortedByID(pages)

	rows := make([]map[string]any, 0, len(pages))
	statuses := make([]string, 0, len(pages))
	for _, p := range pages {
		typeLabel := wiki.FolderLabels[p.Folder]
		if typeLabel == "" {
			typeLabel = p.Folder
		}
		row := map[string]any{
			"id":        p.ID(),
			"type":      typeLabel,
			"title":     p.Title(),
			"url":       wiki.PageURL(p.Folder, p.Stem),
			"status":    p.Status(),
			"relations": len(p.LinkTargets()),
		}
		if p.Folder == "quality-requirements" {
			for k, v := range qrDetails(p, linkCtx) {
				row[k] = v
			}
		}
		rows = append(rows, row)
		statuses = append(statuses, p.Status())
	}

	listType := "page"
	if len(block.Folders) > 0 {
		listType = s.Metamodel.TypeForFolder(block.Folders[0])
	}

	var contextDiagram any
	var contextFlows any
	diagramLinks := []map[string]any{}
	var entityDiagram any
	if slug == "scope" {
		cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
		eifs := sn.folder("external-interfaces")
		cd, dl := project.BuildContextDiagram(cfg.SystemName, eifs, sn.folder("stakeholders"))
		contextDiagram = nilIfEmpty(cd)
		if dl != nil {
			diagramLinks = dl
		}
		contextFlows = project.BuildContextFlows(eifs)
	}
	if slug == "models" {
		dm, dt, glo := sn.folder("data-models"), sn.folder("domain-terms"), sn.folder("glossary")
		nodes := project.DataModelNodes(dm, dt, glo)
		edges := project.DataModelEdges(dm, dt, glo)
		entityDiagram = nilIfEmpty(project.BuildDataModelFullDiagram(nodes, edges, "", ""))
	}

	s.renderHTML(w, r, http.StatusOK, "req42_block.html", cat, map[string]any{
		"block":           block.ToMap(),
		"rows":            rows,
		"total":           len(rows),
		"list_type":       listType,
		"context_diagram": contextDiagram,
		"context_flows":   contextFlows,
		"diagram_links":   diagramLinks,
		"entity_diagram":  entityDiagram,
		"needs_mermaid":   contextDiagram != nil || entityDiagram != nil,
		"maturity":        wiki.ComputeMaturity(statuses).ToMap(),
	}, now)
}

func (s *Server) handleReq42Block(w http.ResponseWriter, r *http.Request) {
	slug := strings.TrimPrefix(r.URL.Path, "/req42/")
	if slug == "" || strings.Contains(slug, "/") {
		s.handleNotFound(w, r)
		return
	}
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.BySlug[slug]
	if !ok || block.Href != "/req42/"+slug {
		s.handleNotFound(w, r)
		return
	}
	s.renderBlockList(w, r, cat, block, slug)
}

func (s *Server) handleSection(w http.ResponseWriter, r *http.Request) {
	sid := strings.TrimPrefix(r.URL.Path, "/section/")
	if sid == "" || strings.Contains(sid, "/") {
		s.handleNotFound(w, r)
		return
	}
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	block, ok := cat.ByID[sid]
	if !ok {
		block, ok = cat.ByID[strings.ToUpper(sid)]
	}
	if !ok || block.Href == "" {
		s.handleNotFound(w, r)
		return
	}
	if block.Href != "/section/"+block.ID {
		s.redirect(w, r, block.Href, http.StatusFound)
		return
	}
	s.renderBlockList(w, r, cat, block, "")
}

func (s *Server) handleMethod(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)

	var clarify any
	for _, p := range sn.folder("issues") {
		if p.Stem == clarifyIssueStem && wiki.IsOpenIssue(p.Status()) {
			clarify = map[string]any{
				"id":    p.ID(),
				"title": p.Title(),
				"url":   wiki.PageURL("issues", p.Stem),
			}
			break
		}
	}
	s.renderHTML(w, r, http.StatusOK, "method.html", cat, map[string]any{
		"clarify_issue": clarify,
	}, now)
}

func (s *Server) handleChanges(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)

	s.renderHTML(w, r, http.StatusOK, "changes.html", cat, map[string]any{
		"changes": wiki.RecentChanges(sn.all(), 0, now, s.location()),
	}, now)
}

func (s *Server) handleLegacyRedirect(w http.ResponseWriter, r *http.Request, destination string) {
	if r.URL.RawQuery != "" {
		destination += "?" + r.URL.RawQuery
	}
	s.redirect(w, r, destination, http.StatusMovedPermanently)
}

func (s *Server) handleDomainTerms(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)

	pages := append(append([]*wiki.Page{}, sn.folder("domain-terms")...), sn.folder("glossary")...)
	rows := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		rows = append(rows, map[string]any{
			"id":         p.ID(),
			"stem":       p.Stem,
			"folder":     p.Folder,
			"title":      p.Title(),
			"aliases":    p.Aliases(),
			"definition": render.ExtractLabeled(p.Body, "Definition", linkCtx),
			"relations":  len(p.LinkTargets()),
			"status":     p.Status(),
			"created":    p.MetaString("created"),
			"updated":    p.MetaString("updated"),
			"assumption": strings.Contains(p.Body, "[!assumption]"),
		})
	}
	sort.SliceStable(rows, func(i, j int) bool {
		return strings.ToLower(rows[i]["title"].(string)) < strings.ToLower(rows[j]["title"].(string))
	})

	s.renderHTML(w, r, http.StatusOK, "glossary.html", cat, map[string]any{
		"rows":     rows,
		"total":    len(rows),
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
	}, now)
}

func (s *Server) handleStakeholders(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)
	byStem := sn.byStem()

	pages := sortedByID(sn.folder("stakeholders"))
	const relMax = 6
	rows := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		targets := make([]string, 0, len(p.LinkTargets()))
		for st := range p.LinkTargets() {
			targets = append(targets, st)
		}
		sort.Strings(targets)

		var rel []map[string]any
		for _, st := range targets {
			q := byStem[st]
			if q == nil {
				continue
			}
			tp := wiki.TypeOf(st)
			if tp != "DT" && tp != "GLO" && tp != "DM" {
				continue
			}
			rel = append(rel, map[string]any{
				"id":    q.ID(),
				"label": q.Title(),
				"type":  tp,
				"url":   "/page/" + q.Folder + "/" + st,
			})
		}
		sort.SliceStable(rel, func(i, j int) bool {
			ti := rel[i]["type"].(string)
			tj := rel[j]["type"].(string)
			gi := ti != "DT" && ti != "GLO"
			gj := tj != "DT" && tj != "GLO"
			if gi != gj {
				return !gi
			}
			return rel[i]["id"].(string) < rel[j]["id"].(string)
		})
		relShown := rel
		relMore := 0
		if len(rel) > relMax {
			relShown = rel[:relMax]
			relMore = len(rel) - relMax
		}
		rows = append(rows, map[string]any{
			"id":        p.ID(),
			"stem":      p.Stem,
			"title":     p.Title(),
			"role":      p.MetaString("role"),
			"snapshot":  render.ExtractLabeled(p.Body, "Snapshot", linkCtx),
			"influence": p.MetaString("influence"),
			"interest":  p.MetaString("interest"),
			"rel_links": relShown,
			"rel_more":  relMore,
			"status":    p.Status(),
		})
	}

	s.renderHTML(w, r, http.StatusOK, "stakeholders.html", cat, map[string]any{
		"rows":     rows,
		"total":    len(rows),
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
	}, now)
}

func (s *Server) handleDecisions(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)
	byStem := sn.byStem()

	pages := sortedByID(sn.folder("decisions"))
	items := make([]map[string]any, 0, len(pages))
	statuses := make([]string, 0, len(pages))
	counts := map[string]int{}

	for _, p := range pages {
		kind := strings.ToLower(strings.TrimSpace(p.MetaString("kind")))
		if kind != "architecture" && kind != "business" {
			kind = "undefined"
		}
		counts[kind]++

		decided := p.MetaString("decided")
		if decided == "" {
			decided = p.MetaString("created")
		}
		if decided == "" {
			decided = "—"
		}
		status := strings.ToLower(strings.TrimSpace(p.Status()))
		if status == "" {
			status = "draft"
		}
		statuses = append(statuses, status)

		var drivers []map[string]any
		for _, g := range linkGroups(wiki.LinksOf(p, "drivers", byStem), byStem) {
			if links, ok := g["links"].([]map[string]any); ok {
				drivers = append(drivers, links...)
			}
		}

		items = append(items, map[string]any{
			"id":      p.ID(),
			"stem":    p.Stem,
			"title":   wiki.StripInlineMarkdown(p.Title()),
			"status":  status,
			"kind":    kind,
			"decided": decided,
			"aliases": p.Aliases(),
			"url":     wiki.PageURL("decisions", p.Stem),
			"drivers": drivers,
			"html":    render.RenderMarkdown(p.Body, linkCtx),
		})
	}

	buckets := make([]map[string]any, 0, len(decisionKinds))
	for _, k := range decisionKinds {
		buckets = append(buckets, map[string]any{
			"key":   k,
			"label": decisionLabels[k],
			"count": counts[k],
		})
	}

	s.renderHTML(w, r, http.StatusOK, "decisions.html", cat, map[string]any{
		"items":    items,
		"total":    len(items),
		"buckets":  buckets,
		"maturity": wiki.ComputeMaturity(statuses).ToMap(),
	}, now)
}

func (s *Server) handleIssues(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	titles := sn.titleIndex()
	links := sn.linkIndex()
	vocab := s.loadIssueVocab()

	pages := sortedByID(sn.folder("issues"))
	lifecycleValues := s.Metamodel.Lifecycle("issue")
	categories := s.Metamodel.FieldValues("issue", "category")
	severities := s.Metamodel.FieldValues("issue", "severity")

	folderSection := map[string]string{}
	for _, sec := range cat.Sections {
		if sec.ID == "C6" {
			continue
		}
		for _, f := range metamodel.SectionFolders(sec) {
			folderSection[f] = sec.ID
		}
	}

	items := make([]map[string]any, 0, len(pages))
	for _, p := range pages {
		secSet := map[string]bool{}
		for tgt := range p.LinkTargets() {
			if ref, ok := links[tgt]; ok {
				if sid, ok := folderSection[ref.Folder]; ok {
					secSet[sid] = true
				}
			}
		}
		secs := make([]string, 0, len(secSet))
		for sid := range secSet {
			secs = append(secs, sid)
		}
		sort.Strings(secs)

		it := issueFields(p, titles, links, vocab)
		it["id"] = p.ID()
		it["title"] = p.Title()
		it["sections"] = secs
		it["url"] = wiki.PageURL("issues", p.Stem)
		items = append(items, it)
	}

	ownerLabels := map[string]string{}
	ownerOrder := []string{}
	for _, it := range items {
		k := it["owner_key"].(string)
		if k == "" {
			continue
		}
		lbl := it["owner"].(string)
		if it["owner_url"] != nil {
			if t, ok := titles[k]; ok {
				lbl = t
			}
		}
		if _, seen := ownerLabels[k]; !seen {
			ownerOrder = append(ownerOrder, k)
		}
		ownerLabels[k] = lbl
	}
	sort.SliceStable(ownerOrder, func(i, j int) bool {
		return strings.ToLower(ownerLabels[ownerOrder[i]]) < strings.ToLower(ownerLabels[ownerOrder[j]])
	})
	owners := make([][]any, 0, len(ownerOrder))
	ownerSet := map[string]bool{"none": true}
	for _, k := range ownerOrder {
		owners = append(owners, []any{k, ownerLabels[k]})
		ownerSet[k] = true
	}

	var sectionOptions []map[string]any
	validSections := map[string]metamodel.Section{}
	for _, sec := range cat.Sections {
		if len(sec.Folders) > 0 && sec.ID != "C6" {
			sectionOptions = append(sectionOptions, sec.ToMap())
			validSections[sec.ID] = sec
		}
	}

	q := r.URL.Query()
	arg := func(name string) string { return strings.TrimSpace(q.Get(name)) }

	var chosenSection any
	chosenSectionID := ""
	if sec, ok := validSections[strings.ToUpper(arg("section"))]; ok {
		chosenSection = sec.ToMap()
		chosenSectionID = sec.ID
	}

	status := arg("status")
	if status == "" {
		status = arg("filter")
	}
	if !vocab.status[status] && status != "open" && status != "closed" && status != "all" {
		status = ""
	}
	if status == "" {
		if chosenSection != nil {
			status = "open"
		} else {
			status = "all"
		}
	}

	catArg := arg("category")
	if !vocab.category[catArg] {
		catArg = ""
	}
	sevArg := arg("severity")
	if !vocab.severity[sevArg] {
		sevArg = ""
	}
	ownerArg := arg("owner")
	if !ownerSet[ownerArg] {
		ownerArg = ""
	}

	chosen := map[string]any{
		"status":   status,
		"category": catArg,
		"severity": sevArg,
		"section":  chosenSectionID,
		"owner":    ownerArg,
	}

	keep := func(it map[string]any) bool {
		isOpen := it["is_open"].(bool)
		if (status == "open" && !isOpen) || (status == "closed" && isOpen) {
			return false
		}
		if status != "all" && status != "open" && status != "closed" && it["status"].(string) != status {
			return false
		}
		if catArg != "" && it["category"].(string) != catArg {
			return false
		}
		if sevArg != "" && it["severity"].(string) != sevArg {
			return false
		}
		if chosenSectionID != "" && !containsStr(it["sections"].([]string), chosenSectionID) {
			return false
		}
		if ownerArg != "" {
			wantOwner := ownerArg
			if ownerArg == "none" {
				wantOwner = ""
			}
			if it["owner_key"].(string) != wantOwner {
				return false
			}
		}
		return true
	}

	shown := make([]map[string]any, 0, len(items))
	openCount := 0
	for _, it := range items {
		if it["is_open"].(bool) {
			openCount++
		}
		if keep(it) {
			shown = append(shown, it)
		}
	}

	filtered := status != "all" || catArg != "" || sevArg != "" || chosenSectionID != "" || ownerArg != ""

	s.renderHTML(w, r, http.StatusOK, "issues.html", cat, map[string]any{
		"items":      shown,
		"total":      len(items),
		"shown":      len(shown),
		"filtered":   filtered,
		"open_count": openCount,
		"section":    chosenSection,
		"chosen":     chosen,
		"options": map[string]any{
			"status":   lifecycleValues,
			"category": categories,
			"severity": severities,
			"section":  sectionOptions,
			"owner":    owners,
		},
		"sort":     arg("sort"),
		"maturity": wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
	}, now)
}
