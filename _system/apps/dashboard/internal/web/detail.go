package web

import (
	"fmt"
	"net/http"
	"path"
	"regexp"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/project"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	leadingH1RE = regexp.MustCompile(`^\s*#\s+.*(?:\n|$)`)
)

// addressableTypes are the requirement types a `drivers:` link may point at (rel-drivers).
var addressableTypes = []string{"goal", "functional-requirement", "quality-requirement", "constraint", "activity-model"}

// realizableTypes are the types a runtime scenario's `realizes:` may name (rel-realizes).
var realizableTypes = []string{"functional-requirement", "activity-model"}

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

// deliveryLabels is how a delivery state reads on a badge and in the filter
// (FR-048), matching web/common.py's DELIVERY_LABELS. A state without an
// entry shows under its own name.
var deliveryLabels = map[string]string{
	"partial":     "partly implemented",
	"implemented": "implemented",
	"outdated":    "implementation outdated",
	"removed":     "implementation removed",
}

func deliveryLabel(state string) string {
	if label, ok := deliveryLabels[state]; ok {
		return label
	}
	return state
}

// loadDeliveryVocab reads what the metamodel allows for a requirement's
// delivery (CON-006).
func (s *Server) loadDeliveryVocab() project.DeliveryVocab {
	return project.BuildDeliveryVocab(
		s.Metamodel.FieldValues("functional-requirement", "delivery"), s.Metamodel.Notations())
}

// deliveryBadge matches web/common.py's delivery_badge(): a requirement's
// delivery status plus label, the state in plain words. A value the metamodel
// does not allow on the page keeps its own text.
func deliveryBadge(p *wiki.Page, vocab project.DeliveryVocab) map[string]any {
	d := project.FRDelivery(p, vocab)
	value, _ := d["value"].(string)
	d["label"] = value
	if known, _ := d["known"].(bool); known {
		d["label"] = deliveryLabel(value)
	}
	return d
}

// deliveryOptions matches web/common.py's delivery_options(): the states the
// delivery filter of the requirement list offers.
func deliveryOptions(vocab project.DeliveryVocab) []map[string]any {
	out := make([]map[string]any, 0, len(vocab.States))
	for _, state := range vocab.States {
		out = append(out, map[string]any{"value": state, "label": deliveryLabel(state)})
	}
	return out
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
		// stems and IDs: the index wiki.ResolveLink reads
		sn.pagesByStem = wiki.PageIndex(sn.all())
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
	for _, t := range metamodel.PrefixOrder() {
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
	order := append(append([]string{}, metamodel.PrefixOrder()...), extraOrder...)
	out := []map[string]any{}
	for _, tp := range order {
		links, ok := buckets[tp]
		if !ok {
			continue
		}
		lbl := metamodel.GroupLabel(tp)
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
	if wiki.IsArchFolder(folder) || metamodel.IsType(folder, "decision-record") {
		for _, p := range sn.folder(folder) {
			if p.Stem == stem {
				me = p
				break
			}
		}
		if p := byStem[stem]; p != nil && !metamodel.IsType(folder, "runtime-scenario") {
			trace["drivers"] = linkGroups(wiki.LinksOf(p, "drivers", byStem), byStem)
		}
	}
	if metamodel.IsType(folder, "runtime-scenario") && me != nil {
		trace["realizes"] = linkGroups(wiki.LinksOf(me, "realizes", byStem), byStem)
	}
	if me != nil && !metamodel.IsType(folder, "decision-record") {
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
	if metamodel.IsType(folder, "building-block") {
		var usedBy []string
		for _, p := range sortedByID(sn.folder(folder)) {
			if containsStr(wiki.LinksOf(p, "uses", byStem), stem) {
				usedBy = append(usedBy, p.Stem)
			}
		}
		trace["used_by"] = linkGroups(usedBy, byStem)

		var deployedOn []string
		for _, p := range sortedByID(sn.typed("deployment-node")) {
			if containsStr(wiki.LinksOf(p, "hosts", byStem), stem) {
				deployedOn = append(deployedOn, p.Stem)
			}
		}
		trace["deployed_on"] = linkGroups(deployedOn, byStem)
	}
	if metamodel.IsType(folder, "building-block", "deployment-node") {
		var governedBy []string
		for _, p := range sortedByID(sn.typed("crosscutting-concept")) {
			if containsStr(wiki.LinksOf(p, "applies-to", byStem), stem) {
				governedBy = append(governedBy, p.Stem)
			}
		}
		trace["governed_by"] = linkGroups(governedBy, byStem)
	}
	if metamodel.IsType(folder, "building-block", "deployment-node", "external-interface", "stakeholder") {
		var takesPart []string
		for _, p := range sortedByID(sn.typed("runtime-scenario")) {
			if containsStr(wiki.StructTargets(p, "steps", []string{"from", "to"}, byStem), stem) {
				takesPart = append(takesPart, p.Stem)
			}
		}
		trace["takes_part_in"] = linkGroups(takesPart, byStem)
	}
	if metamodel.IsType(folder, "crosscutting-concept") && me != nil {
		trace["applies_to"] = linkGroups(wiki.LinksOf(me, "applies-to", byStem), byStem)
	}
	if metamodel.IsType(folder, "deployment-node") && me != nil {
		trace["hosts"] = linkGroups(wiki.LinksOf(me, "hosts", byStem), byStem)
	}
	if metamodel.IsType(folder, addressableTypes...) {
		var candidates []*wiki.Page
		for _, t := range wiki.DriverTypes {
			candidates = append(candidates, sortedByID(sn.typed(t))...)
		}
		var addressed []string
		for _, p := range candidates {
			if containsStr(wiki.LinksOf(p, "drivers", byStem), stem) {
				addressed = append(addressed, p.Stem)
			}
		}
		trace["addressed_by"] = linkGroups(addressed, byStem)
	}
	if metamodel.IsType(folder, realizableTypes...) {
		var realizedBy []string
		for _, p := range sortedByID(sn.typed("runtime-scenario")) {
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
		folder := metamodel.FolderForPrefix(ntype)
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
		if p != nil && metamodel.IsType(p.Folder, "issue") {
			stVal := p.Status()
			if vocab.status[stVal] {
				item["status"] = stVal
			}
			item["closed"] = !wiki.IsOpenIssue(stVal)
		}
		return item
	}

	var outbound []string
	var inbound []string
	if me := byStem[stem]; me != nil && me.Stem == stem {
		for tgt := range me.LinkedStems(byStem) {
			if byStem[tgt] != nil && !exclude[tgt] {
				outbound = append(outbound, tgt)
			}
		}
		// every page that links here, also one this page links to (FR-034)
		for _, q := range pages {
			if !exclude[q.Stem] && wiki.LinksTo(q, me, byStem) {
				inbound = append(inbound, q.Stem)
			}
		}
	}
	sort.Strings(outbound)
	sort.Strings(inbound)

	grouped := func(stems []string) []map[string]any {
		buckets := map[string][]map[string]any{}
		var extraOrder []string
		inOrder := map[string]bool{}
		for _, t := range metamodel.PrefixOrder() {
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
		order := append(append([]string{}, metamodel.PrefixOrder()...), extraOrder...)
		out := []map[string]any{}
		for _, tp := range order {
			links, ok := buckets[tp]
			if !ok {
				continue
			}
			lbl := metamodel.GroupLabel(tp)
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
	for _, iss := range sn.typed("issue") {
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
					"url":      wiki.PageURL(iss.Folder, iss.Stem),
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

// withPageHead adds created date, updated date and tags to a detail view's
// template data (FR-034), matching app.py's page_head(). Every detail view
// takes them from here and renders them with the page_meta macro.
func withPageHead(page *wiki.Page, data map[string]any) map[string]any {
	data["created"] = page.MetaString("created")
	data["updated"] = page.MetaString("updated")
	data["tags"] = page.AsStringList("tags")
	return data
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

	if metamodel.IsType(folder, "functional-requirement") {
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

	kind := metamodel.Label(folder)
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
	if metamodel.IsType(folder, "issue") {
		issueVal = issueFields(page, sn.titleIndex(), sn.linkIndex(), vocab)
	}

	byStem := sn.byStem()
	diagramLinks := []map[string]any{}
	var contextDiagram, contextFlows, whitebox, sequence, deployment, egoGraph, egoLayers any
	hints := []string{}

	switch metamodel.TypeOf(folder) {
	case "context":
		cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
		eifs := sn.typed("external-interface")
		cd, dl := project.BuildContextDiagram(cfg.SystemName, eifs, sn.typed("stakeholder"))
		contextDiagram = nilIfEmpty(cd)
		if dl != nil {
			diagramLinks = dl
		}
		contextFlows = project.BuildContextFlows(eifs)
	case "domain-term":
		eg := project.BuildGlossaryEgoGraph(sn.all(), sn.typed("domain-term"), stem)
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
	case "building-block":
		whitebox = nilIfEmpty(project.BuildWhitebox(stem, sn.typed("building-block"), sn.typed("external-interface"), byStem))
	case "runtime-scenario":
		scenarios := sn.typed("runtime-scenario")
		sequence = nilIfEmpty(project.BuildSequenceDiagram(stem, scenarios, byStem))
		hints = project.RuntimeHints(stem, scenarios, sn.typed("building-block"), byStem)
	case "deployment-node":
		nodes := sn.typed("deployment-node")
		blocks := sn.typed("building-block")
		dep, dl := project.BuildDeploymentDiagram(stem, nodes, blocks, sn.typed("external-interface"), byStem)
		deployment = nilIfEmpty(dep)
		if dl != nil {
			diagramLinks = dl
		}
		hints = project.DeploymentHints(stem, nodes, blocks, byStem)
	}

	var termVal any
	if metamodel.IsType(folder, "domain-term") {
		termVal = map[string]any{
			"kind":          project.TermKind(page),
			"aliases":       page.Aliases(),
			"attributes":    project.DMAttributes(page),
			"relationships": project.TermRelationships(page, sn.linkIndex(), byStem),
		}
	}

	needsMermaid := contextDiagram != nil || whitebox != nil || sequence != nil || deployment != nil || strings.Contains(bodyHTML, "language-mermaid")

	s.renderHTML(w, r, http.StatusOK, "detail.html", cat, withPageHead(page, map[string]any{
		"kind":            kind,
		"id":              page.ID(),
		"title":           page.Title(),
		"status":          page.Status(),
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
		"term":            termVal,
	}), now)
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

	s.renderHTML(w, r, http.StatusOK, "detail.html", cat, withPageHead(src, map[string]any{
		"kind":            "Source",
		"id":              src.ID(),
		"title":           src.Title(),
		"status":          src.Status(),
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
		"term":            nil,
	}), now)
}
