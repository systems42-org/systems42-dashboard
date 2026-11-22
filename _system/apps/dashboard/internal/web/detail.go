package web

import (
	"fmt"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/project"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	leadingH1RE = regexp.MustCompile(`^\s*#\s+.*(?:\n|$)`)
	adrStemRE   = regexp.MustCompile(`^(\d{4})-(.+)$`)
)

var addressableFolders = map[string]bool{
	"goals":                   true,
	"functional-requirements": true,
	"quality-requirements":    true,
	"constraints":             true,
	"activity-models":         true,
}

// realizableFolders are the folders a runtime scenario's `realizes:` may name (rel-realizes).
var realizableFolders = map[string]bool{
	"functional-requirements": true,
	"activity-models":         true,
}

type issueVocab struct {
	status   map[string]bool
	severity map[string]bool
	kind     map[string]bool
	category map[string]bool
}

func toSet(items []string) map[string]bool {
	m := make(map[string]bool, len(items))
	for _, s := range items {
		m[s] = true
	}
	return m
}

func (s *Server) loadIssueVocab() issueVocab {
	return issueVocab{
		status:   toSet(s.Metamodel.Lifecycle("issue")),
		severity: toSet(s.Metamodel.FieldValues("issue", "severity")),
		kind:     toSet(s.Metamodel.FieldValues("issue", "kind")),
		category: toSet(s.Metamodel.FieldValues("issue", "category")),
	}
}

func (s *Server) linkContext(sn *requestSnapshot) render.LinkContext {
	if sn.anchors == nil {
		sn.anchors = metamodel.AnchorIndex(s.Metamodel.MethodAnchors())
	}
	return render.LinkContext{
		Titles:  sn.titleIndex(),
		Links:   sn.linkIndex(),
		Sources: sn.sourceIndex(),
		Anchors: sn.anchors,
	}
}

func (sn *requestSnapshot) byStem() map[string]*wiki.Page {
	if sn.pagesByStem == nil {
		all := sn.all()
		m := make(map[string]*wiki.Page, len(all))
		for _, p := range all {
			m[p.Stem] = p
		}
		sn.pagesByStem = m
	}
	return sn.pagesByStem
}

func (sn *requestSnapshot) sourceIndex() map[string]*wiki.Page {
	if sn.srcIndex == nil {
		sn.srcIndex = wiki.SourceIndex(sn.loadSources())
	}
	return sn.srcIndex
}

func provenanceChips(page *wiki.Page, srcIdx map[string]*wiki.Page) []map[string]any {
	rows := []map[string]any{}
	for _, ref := range page.AsList("sources") {
		base := wiki.StemFromRef(ref)
		if base == "" {
			continue
		}
		if src, ok := srcIdx[base]; ok && src != nil {
			rows = append(rows, map[string]any{
				"id":       src.ID(),
				"title":    src.Title(),
				"stem":     src.Stem,
				"type":     src.MetaString("source-type"),
				"origin":   src.MetaString("origin"),
				"captured": src.MetaString("captured"),
				"url":      "/source/" + src.Stem,
			})
		} else {
			rows = append(rows, map[string]any{
				"id":       base,
				"title":    base,
				"stem":     base,
				"type":     "",
				"origin":   "",
				"captured": "",
				"url":      nil,
			})
		}
	}
	return rows
}

func linkGroups(stems []string, byStem map[string]*wiki.Page) []map[string]any {
	buckets := map[string][]map[string]any{}
	var extraOrder []string
	inRelOrder := map[string]bool{}
	for _, t := range wiki.RelTypeOrder {
		inRelOrder[t] = true
	}
	for _, st := range stems {
		p := byStem[st]
		if p == nil {
			continue
		}
		tp := wiki.TypeOf(st)
		if _, exists := buckets[tp]; !exists && !inRelOrder[tp] {
			extraOrder = append(extraOrder, tp)
		}
		buckets[tp] = append(buckets[tp], map[string]any{
			"id":    p.ID(),
			"label": p.Title(),
			"type":  tp,
			"url":   wiki.PageURL(p.Folder, st),
		})
	}
	order := append(append([]string{}, wiki.RelTypeOrder...), extraOrder...)
	out := []map[string]any{}
	for _, tp := range order {
		links, ok := buckets[tp]
		if !ok {
			continue
		}
		lbl := wiki.TypeLabel[tp]
		if lbl == "" {
			lbl = tp
		}
		out = append(out, map[string]any{
			"type":  tp,
			"label": lbl,
			"links": links,
		})
	}
	return out
}

func sortedByID(pages []*wiki.Page) []*wiki.Page {
	cp := make([]*wiki.Page, len(pages))
	copy(cp, pages)
	sort.SliceStable(cp, func(i, j int) bool {
		return cp[i].ID() < cp[j].ID()
	})
	return cp
}

func containsStr(list []string, target string) bool {
	for _, s := range list {
		if s == target {
			return true
		}
	}
	return false
}

func buildTrace(sn *requestSnapshot, stem, folder string) map[string]any {
	byStem := sn.byStem()
	trace := map[string]any{
		"drivers":       []map[string]any{},
		"realizes":      []map[string]any{},
		"shaped_by":     []map[string]any{},
		"used_by":       []map[string]any{},
		"addressed_by":  []map[string]any{},
		"realized_by":   []map[string]any{},
		"replaced_by":   []map[string]any{},
		"replaces":      []map[string]any{},
		"applies_to":    []map[string]any{},
		"governed_by":   []map[string]any{},
		"hosts":         []map[string]any{},
		"deployed_on":   []map[string]any{},
		"takes_part_in": []map[string]any{},
	}

	var me *wiki.Page
	if wiki.IsArchFolder(folder) || folder == "decisions" {
		for _, p := range sn.folder(folder) {
			if p.Stem == stem {
				me = p
				break
			}
		}
		if p := byStem[stem]; p != nil && folder != "runtime-scenarios" {
			trace["drivers"] = linkGroups(wiki.LinksOf(p, "drivers", byStem), byStem)
		}
	}
	if folder == "runtime-scenarios" && me != nil {
		trace["realizes"] = linkGroups(wiki.LinksOf(me, "realizes", byStem), byStem)
	}
	if me != nil && folder != "decisions" {
		trace["shaped_by"] = linkGroups(wiki.LinksOf(me, "decisions", byStem), byStem)
	}
	if me != nil {
		trace["replaced_by"] = linkGroups(wiki.LinksOf(me, "superseded-by", byStem), byStem)
		var replaces []string
		for _, p := range sortedByID(sn.folder(folder)) {
			if containsStr(wiki.LinksOf(p, "superseded-by", byStem), stem) {
				replaces = append(replaces, p.Stem)
			}
		}
		trace["replaces"] = linkGroups(replaces, byStem)
	}
	if folder == "building-blocks" {
		var usedBy []string
		for _, p := range sortedByID(sn.folder(folder)) {
			if containsStr(wiki.LinksOf(p, "uses", byStem), stem) {
				usedBy = append(usedBy, p.Stem)
			}
		}
		trace["used_by"] = linkGroups(usedBy, byStem)

		var deployedOn []string
		for _, p := range sortedByID(sn.folder("deployment-nodes")) {
			if containsStr(wiki.LinksOf(p, "hosts", byStem), stem) {
				deployedOn = append(deployedOn, p.Stem)
			}
		}
		trace["deployed_on"] = linkGroups(deployedOn, byStem)
	}
	if folder == "building-blocks" || folder == "deployment-nodes" {
		var governedBy []string
		for _, p := range sortedByID(sn.folder("crosscutting-concepts")) {
			if containsStr(wiki.LinksOf(p, "applies-to", byStem), stem) {
				governedBy = append(governedBy, p.Stem)
			}
		}
		trace["governed_by"] = linkGroups(governedBy, byStem)
	}
	if folder == "building-blocks" || folder == "deployment-nodes" || folder == "external-interfaces" || folder == "stakeholders" {
		var takesPart []string
		for _, p := range sortedByID(sn.folder("runtime-scenarios")) {
			if containsStr(wiki.StructTargets(p, "steps", []string{"from", "to"}, byStem), stem) {
				takesPart = append(takesPart, p.Stem)
			}
		}
		trace["takes_part_in"] = linkGroups(takesPart, byStem)
	}
	if folder == "crosscutting-concepts" && me != nil {
		trace["applies_to"] = linkGroups(wiki.LinksOf(me, "applies-to", byStem), byStem)
	}
	if folder == "deployment-nodes" && me != nil {
		trace["hosts"] = linkGroups(wiki.LinksOf(me, "hosts", byStem), byStem)
	}
	if addressableFolders[folder] {
		var candidates []*wiki.Page
		for _, f := range wiki.DriverFolders {
			candidates = append(candidates, sortedByID(sn.folder(f))...)
		}
		var addressed []string
		for _, p := range candidates {
			if containsStr(wiki.LinksOf(p, "drivers", byStem), stem) {
				addressed = append(addressed, p.Stem)
			}
		}
		trace["addressed_by"] = linkGroups(addressed, byStem)
	}
	if realizableFolders[folder] {
		var realizedBy []string
		for _, p := range sortedByID(sn.folder("runtime-scenarios")) {
			if containsStr(wiki.LinksOf(p, "realizes", byStem), stem) {
				realizedBy = append(realizedBy, p.Stem)
			}
		}
		trace["realized_by"] = linkGroups(realizedBy, byStem)
	}
	return trace
}

func traceStems(trace map[string]any) map[string]bool {
	out := map[string]bool{}
	for _, rawGroups := range trace {
		groups, ok := rawGroups.([]map[string]any)
		if !ok {
			continue
		}
		for _, g := range groups {
			links, _ := g["links"].([]map[string]any)
			for _, l := range links {
				if u, ok := l["url"].(string); ok && u != "" {
					out[path.Base(u)] = true
				}
			}
		}
	}
	return out
}

func buildRelationsPanel(sn *requestSnapshot, stem string, exclude map[string]bool, vocab issueVocab) map[string]any {
	titles := sn.titleIndex()
	pages := sn.all()
	byStem := sn.byStem()

	info := func(st string) map[string]any {
		ntype := wiki.TypeOf(st)
		p := byStem[st]
		folder := wiki.TypeFolder[ntype]
		if p != nil {
			folder = p.Folder
		}
		url := wiki.PageURL(folder, st)
		id := st
		if p != nil {
			id = p.ID()
		}
		lbl := st
		if t, ok := titles[st]; ok {
			lbl = t
		}
		item := map[string]any{
			"id":     id,
			"label":  lbl,
			"url":    url,
			"type":   ntype,
			"status": "",
			"closed": false,
		}
		if p != nil && p.Folder == "issues" {
			stVal := p.Status()
			if vocab.status[stVal] {
				item["status"] = stVal
			}
			item["closed"] = !wiki.IsOpenIssue(stVal)
		}
		return item
	}

	var outbound []string
	outSet := map[string]bool{}
	if me := byStem[stem]; me != nil {
		for tgt := range me.LinkTargets() {
			if byStem[tgt] != nil && !exclude[tgt] {
				outbound = append(outbound, tgt)
				outSet[tgt] = true
			}
		}
	}
	sort.Strings(outbound)

	var inbound []string
	for _, q := range pages {
		if q.Stem == stem || outSet[q.Stem] || exclude[q.Stem] {
			continue
		}
		if _, ok := q.LinkTargets()[stem]; ok {
			inbound = append(inbound, q.Stem)
		}
	}
	sort.Strings(inbound)

	grouped := func(stems []string) []map[string]any {
		buckets := map[string][]map[string]any{}
		var extraOrder []string
		inOrder := map[string]bool{}
		for _, t := range wiki.RelTypeOrder {
			inOrder[t] = true
		}
		for _, st := range stems {
			it := info(st)
			tp := it["type"].(string)
			if _, exists := buckets[tp]; !exists && !inOrder[tp] {
				extraOrder = append(extraOrder, tp)
			}
			buckets[tp] = append(buckets[tp], it)
		}
		order := append(append([]string{}, wiki.RelTypeOrder...), extraOrder...)
		out := []map[string]any{}
		for _, tp := range order {
			links, ok := buckets[tp]
			if !ok {
				continue
			}
			lbl := wiki.TypeLabel[tp]
			if lbl == "" {
				lbl = tp
			}
			out = append(out, map[string]any{
				"type":  tp,
				"label": lbl,
				"links": links,
			})
		}
		return out
	}

	return map[string]any{
		"outbound": grouped(outbound),
		"inbound":  grouped(inbound),
	}
}

func issueOwner(p *wiki.Page, titles map[string]string, links map[string]wiki.PageRef) (key, label string, url any) {
	raw := strings.TrimSpace(wiki.ScalarString(wiki.Scalar(p.Meta["owner"])))
	switch strings.ToLower(raw) {
	case "", "none", "null":
		return "", "", nil
	}
	linked := strings.HasPrefix(raw, "[[") && strings.HasSuffix(raw, "]]")
	inner := raw
	if linked {
		inner = raw[2 : len(raw)-2]
	}
	target, alias, hasPipe := strings.Cut(inner, "|")
	target = strings.TrimSpace(target)
	alias = strings.TrimSpace(alias)
	if idx := strings.IndexByte(target, '#'); idx >= 0 {
		target = strings.TrimSpace(target[:idx])
	}
	if dest, ok := links[target]; ok {
		lbl := alias
		if lbl == "" {
			if t, ok := titles[dest.Stem]; ok {
				lbl = t
			} else {
				lbl = dest.Stem
			}
		}
		return dest.Stem, lbl, wiki.PageURL(dest.Folder, dest.Stem)
	}
	if linked || hasPipe {
		lbl := alias
		if lbl == "" {
			lbl = target
		}
		return raw, lbl, nil
	}
	return raw, raw, nil
}

func issueFields(p *wiki.Page, titles map[string]string, links map[string]wiki.PageRef, vocab issueVocab) map[string]any {
	known := func(field string, allowed map[string]bool) string {
		v := strings.TrimSpace(p.MetaString(field))
		if allowed[v] {
			return v
		}
		return ""
	}
	status := ""
	if vocab.status[p.Status()] {
		status = p.Status()
	}
	ownerKey, ownerLabel, ownerURL := issueOwner(p, titles, links)
	return map[string]any{
		"status":    status,
		"is_open":   wiki.IsOpenIssue(p.Status()),
		"severity":  known("severity", vocab.severity),
		"kind":      known("kind", vocab.kind),
		"category":  known("category", vocab.category),
		"owner":     ownerLabel,
		"owner_key": ownerKey,
		"owner_url": ownerURL,
	}
}

func openIssuesFor(sn *requestSnapshot, stem string, vocab issueVocab) []map[string]any {
	titles := sn.titleIndex()
	links := sn.linkIndex()
	out := []map[string]any{}
	for _, iss := range sn.folder("issues") {
		f := issueFields(iss, titles, links, vocab)
		seen := map[string]bool{}
		for tgt := range iss.LinkTargets() {
			if dest, ok := links[tgt]; ok && dest.Stem == stem && !seen[stem] {
				seen[stem] = true
				out = append(out, map[string]any{
					"id":       iss.ID(),
					"title":    iss.Title(),
					"status":   f["status"],
					"severity": f["severity"],
					"is_open":  f["is_open"],
					"url":      wiki.PageURL("issues", iss.Stem),
				})
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		oi := out[i]["is_open"].(bool)
		oj := out[j]["is_open"].(bool)
		if oi != oj {
			return oi
		}
		ri := severityKey(out[i]["severity"].(string))
		rj := severityKey(out[j]["severity"].(string))
		if ri != rj {
			return ri < rj
		}
		return out[i]["id"].(string) < out[j]["id"].(string)
	})
	return out
}

func sectionCrumb(cat *metamodel.Catalog, folder string) (crumb any, crumbHref any) {
	if sec, ok := cat.ByFolder[folder]; ok {
		return sec.Title, metamodel.SectionHref(sec)
	}
	return nil, nil
}

func (s *Server) handlePageDetail(w http.ResponseWriter, r *http.Request) {
	// Reject percent-encoded path separators inside segments (e.g. ..%2Foutside).
	if raw := r.URL.RawPath; raw != "" {
		low := strings.ToLower(raw)
		if strings.Contains(low, "%2f") || strings.Contains(low, "%5c") {
			s.handleNotFound(w, r)
			return
		}
	}
	rest := strings.TrimPrefix(r.URL.Path, "/page/")
	parts := strings.Split(rest, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		s.handleNotFound(w, r)
		return
	}
	folder, stem := parts[0], parts[1]

	if folder == "adr" {
		if m := adrStemRE.FindStringSubmatch(stem); m != nil {
			n, _ := strconv.Atoi(m[1])
			newStem := fmt.Sprintf("DR-%03d-%s", n, m[2])
			candidate := filepath.Join(s.Paths.WikiDir, "decisions", newStem+".md")
			if st, err := os.Stat(candidate); err == nil && st.Mode().IsRegular() && wiki.ResolvesInside(s.Paths.WikiDir, candidate) {
				s.redirect(w, r, wiki.PageURL("decisions", newStem), http.StatusMovedPermanently)
				return
			}
		}
		s.redirect(w, r, "/decisions", http.StatusMovedPermanently)
		return
	}

	if folder == "functional-requirements" {
		s.redirect(w, r, "/functional-requirements/"+stem, http.StatusFound)
		return
	}

	if !wiki.IsWikiFolder(s.Paths.WikiDir, folder) {
		s.handleNotFound(w, r)
		return
	}
	page := s.Store.LoadPage(folder, stem)
	if page == nil {
		s.handleNotFound(w, r)
		return
	}

	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	linkCtx := s.linkContext(sn)
	vocab := s.loadIssueVocab()

	kind := wiki.FolderLabels[folder]
	if kind == "" {
		kind = folder
	}
	body := leadingH1RE.ReplaceAllString(page.Body, "")
	bodyHTML := render.RenderMarkdown(body, linkCtx)
	trace := buildTrace(sn, stem, folder)
	relations := buildRelationsPanel(sn, stem, traceStems(trace), vocab)
	crumb, crumbHref := sectionCrumb(cat, folder)

	var stateVal any
	if wiki.IsArchFolder(folder) {
		stateVal = wiki.PageState(page)
	}
	var issueVal any
	if folder == "issues" {
		issueVal = issueFields(page, sn.titleIndex(), sn.linkIndex(), vocab)
	}

	byStem := sn.byStem()
	diagramLinks := []map[string]any{}
	var contextDiagram, contextFlows, whitebox, sequence, deployment, egoGraph, egoLayers any
	hints := []string{}

	switch folder {
	case "context":
		cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
		eifs := sn.folder("external-interfaces")
		cd, dl := project.BuildContextDiagram(cfg.SystemName, eifs, sn.folder("stakeholders"))
		contextDiagram = nilIfEmpty(cd)
		if dl != nil {
			diagramLinks = dl
		}
		contextFlows = project.BuildContextFlows(eifs)
	case "domain-terms":
		eg := project.BuildGlossaryEgoGraph(sn.all(), sn.folder("domain-terms"), stem)
		if eg != nil {
			egoGraph = eg
			counts := eg["layer_counts"].(map[string]int)
			layers := []map[string]any{}
			for _, kv := range [][2]string{{"STK", "Stakeholder"}, {"GOAL", "Goals"}, {"BB", "Building block"}} {
				if c := counts[kv[0]]; c > 0 {
					layers = append(layers, map[string]any{"key": kv[0], "label": kv[1], "count": c})
				}
			}
			egoLayers = layers
		}
	case "building-blocks":
		whitebox = nilIfEmpty(project.BuildWhitebox(stem, sn.folder("building-blocks"), sn.folder("external-interfaces"), byStem))
	case "runtime-scenarios":
		scenarios := sn.folder("runtime-scenarios")
		sequence = nilIfEmpty(project.BuildSequenceDiagram(stem, scenarios, byStem))
		hints = project.RuntimeHints(stem, scenarios, sn.folder("building-blocks"), byStem)
	case "deployment-nodes":
		nodes := sn.folder("deployment-nodes")
		blocks := sn.folder("building-blocks")
		dep, dl := project.BuildDeploymentDiagram(stem, nodes, blocks, sn.folder("external-interfaces"), byStem)
		deployment = nilIfEmpty(dep)
		if dl != nil {
			diagramLinks = dl
		}
		hints = project.DeploymentHints(stem, nodes, blocks, byStem)
	}

	needsMermaid := contextDiagram != nil || whitebox != nil || sequence != nil || deployment != nil || strings.Contains(bodyHTML, "language-mermaid")

	s.renderHTML(w, r, http.StatusOK, "detail.html", cat, map[string]any{
		"kind":            kind,
		"id":              page.ID(),
		"title":           page.Title(),
		"status":          page.Status(),
		"created":         page.MetaString("created"),
		"updated":         page.MetaString("updated"),
		"tags":            page.AsStringList("tags"),
		"body_html":       bodyHTML,
		"crumb":           crumb,
		"crumb_href":      crumbHref,
		"context_diagram": contextDiagram,
		"context_flows":   contextFlows,
		"relations":       relations,
		"trace":           trace,
		"whitebox":        whitebox,
		"state":           stateVal,
		"sequence":        sequence,
		"hints":           hints,
		"deployment":      deployment,
		"diagram_links":   diagramLinks,
		"ego_graph":       egoGraph,
		"ego_layers":      egoLayers,
		"needs_mermaid":   needsMermaid,
		"sources":         provenanceChips(page, sn.sourceIndex()),
		"issue":           issueVal,
		"page_issues":     openIssuesFor(sn, stem, vocab),
		"formats":         render.FormatLabels(page.Body, linkCtx),
	}, now)
}

func firstRunes(s string, max int) string {
	runes := []rune(s)
	if len(runes) <= max {
		return s
	}
	return string(runes[:max])
}

func (s *Server) handleSourceDetail(w http.ResponseWriter, r *http.Request) {
	if raw := r.URL.RawPath; raw != "" {
		low := strings.ToLower(raw)
		if strings.Contains(low, "%2f") || strings.Contains(low, "%5c") {
			s.handleNotFound(w, r)
			return
		}
	}
	stem := strings.TrimPrefix(r.URL.Path, "/source/")
	if stem == "" || stem == "." || stem == ".." || strings.ContainsAny(stem, `/\`) {
		s.handleNotFound(w, r)
		return
	}
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	src := sn.sourceIndex()[stem]
	if src == nil {
		s.handleNotFound(w, r)
		return
	}

	linkCtx := s.linkContext(sn)
	body := leadingH1RE.ReplaceAllString(src.Body, "")

	orDash := func(key string) string {
		if v := src.MetaString(key); v != "" {
			return v
		}
		return "—"
	}
	facts := [][2]string{
		{"Type", orDash("source-type")},
		{"Origin", orDash("origin")},
		{"Captured", orDash("captured")},
		{"Checksum", firstRunes(orDash("sha256"), 16)},
	}
	var factsHTML strings.Builder
	for _, kv := range facts {
		fmt.Fprintf(&factsHTML, "<dt>%s</dt><dd>%s</dd>", kv[0], render.EscapeHTML(kv[1]))
	}
	ingestedList := src.AsList("ingested-pages")
	ingestedParts := make([]string, 0, len(ingestedList))
	for _, ref := range ingestedList {
		ingestedParts = append(ingestedParts, render.RenderWikilinksText(wiki.ScalarString(ref), linkCtx))
	}
	ingested := strings.Join(ingestedParts, ", ")
	if ingested == "" {
		ingested = "—"
	}
	bodyHTML := fmt.Sprintf(`<dl class="source-facts">%s<dt>Ingested pages</dt><dd>%s</dd></dl>%s`,
		factsHTML.String(), ingested, render.RenderMarkdown(body, linkCtx))

	s.renderHTML(w, r, http.StatusOK, "detail.html", cat, map[string]any{
		"kind":            "Source",
		"id":              src.ID(),
		"title":           src.Title(),
		"status":          src.Status(),
		"created":         src.MetaString("created"),
		"updated":         src.MetaString("updated"),
		"tags":            src.AsStringList("tags"),
		"body_html":       bodyHTML,
		"crumb":           nil,
		"crumb_href":      nil,
		"context_diagram": nil,
		"context_flows":   nil,
		"relations":       nil,
		"trace":           nil,
		"whitebox":        nil,
		"state":           nil,
		"sequence":        nil,
		"hints":           []string{},
		"deployment":      nil,
		"diagram_links":   []any{},
		"ego_graph":       nil,
		"ego_layers":      nil,
		"needs_mermaid":   false,
		"sources":         nil,
		"issue":           nil,
		"formats":         nil,
	}, now)
}
