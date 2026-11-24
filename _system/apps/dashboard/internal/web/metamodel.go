package web

import (
	"fmt"
	"net/http"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var mmDRRE = regexp.MustCompile(`^DR-\d{3}\b`)

var mmExampleRank = map[string]int{
	"accepted":    0,
	"review":      1,
	"draft":       2,
	"open":        0,
	"in-progress": 1,
	"resolved":    2,
	"wontfix":     3,
	"ingested":    0,
}

func mmRouteHref(impl string) string {
	if !strings.HasPrefix(impl, "/") {
		return ""
	}
	if len(impl) > 1 && (impl[1] == '/' || impl[1] == '\\') {
		return ""
	}
	end := strings.IndexAny(impl, " \t\r\n\f\v,;)")
	if end >= 0 {
		return impl[:end]
	}
	return impl
}

func mmDRLink(ref, label string, decisionStems map[string]bool) string {
	lbl := label
	if lbl == "" {
		lbl = ref
	}
	text := render.EscapeHTML(lbl)
	if decisionStems[ref] {
		return fmt.Sprintf(`<a class="wl" href="%s">%s</a>`, render.EscapeHTML(wiki.PageURL(metamodel.Folder("decision-record"), ref)), text)
	}
	return text
}

func mmWikilinks(text string, mmAnchors map[string]string, methodAnchorIdx map[string]metamodel.Anchor, decisionStems map[string]bool) string {
	return render.ReplaceWikilinks(text, func(target, alias string) string {
		parts := strings.Split(target, "/")
		base := parts[len(parts)-1]
		if anc, ok := mmAnchors[base]; ok && !strings.HasPrefix(anc, "fw-") {
			lbl := alias
			if lbl == "" {
				lbl = base
			}
			return fmt.Sprintf(`<a class="wl" href="#%s">%s</a>`, anc, render.EscapeHTML(lbl))
		}
		if a, ok := methodAnchorIdx[strings.ToLower(base)]; ok {
			lbl := alias
			if lbl == "" {
				lbl = a.Name
			}
			return fmt.Sprintf(`<a class="wl wl-anchor" href="#%s" title="%s">%s</a>`,
				a.ID, render.EscapeHTML(render.AnchorTitle(a)), render.EscapeHTML(lbl))
		}
		if anc, ok := mmAnchors[base]; ok {
			lbl := alias
			if lbl == "" {
				lbl = base
			}
			return fmt.Sprintf(`<a class="wl" href="#%s">%s</a>`, anc, render.EscapeHTML(lbl))
		}
		if mmDRRE.MatchString(base) {
			return mmDRLink(base, alias, decisionStems)
		}
		lbl := alias
		if lbl == "" {
			lbl = base
		}
		return fmt.Sprintf(`<span class="mm-anchor">%s</span>`, render.EscapeHTML(lbl))
	})
}

func mmInline(text string, mmAnchors map[string]string, methodAnchorIdx map[string]metamodel.Anchor, decisionStems map[string]bool) string {
	if text == "" {
		return ""
	}
	return render.RenderMarkdownInline(text, func(chunk string) string {
		return mmWikilinks(chunk, mmAnchors, methodAnchorIdx, decisionStems)
	})
}

func mmAnchorRef(name string, methodAnchorIdx map[string]metamodel.Anchor) map[string]any {
	a, ok := methodAnchorIdx[strings.ToLower(strings.TrimSpace(name))]
	if !ok {
		return map[string]any{"name": name, "href": "", "title": ""}
	}
	return map[string]any{
		"name":  a.Name,
		"href":  "#" + a.ID,
		"title": render.AnchorTitle(a),
	}
}

func mmTypeLabel(name any, byName map[string]map[string]any) string {
	s := metamodel.StrVal(name)
	if s == "any" {
		return "any page"
	}
	if t, ok := byName[s]; ok {
		if lbl := metamodel.StrVal(t["label"]); lbl != "" {
			return lbl
		}
	}
	return s
}

func mmStringSlice(v any) []string {
	switch x := v.(type) {
	case []string:
		cp := make([]string, len(x))
		copy(cp, x)
		return cp
	case []any:
		out := make([]string, 0, len(x))
		for _, item := range x {
			out = append(out, metamodel.StrVal(item))
		}
		return out
	default:
		return []string{}
	}
}

func mmExample(sn *requestSnapshot, t map[string]any) map[string]any {
	folder := metamodel.StrVal(t["folder"])
	var pages []*wiki.Page
	var urlFn func(*wiki.Page) string
	if strings.HasPrefix(folder, "raw/") {
		pages = sn.loadSources()
		urlFn = func(p *wiki.Page) string { return "/source/" + p.Stem }
	} else {
		name := filepath.Base(filepath.FromSlash(folder))
		pages = sn.folder(name)
		urlFn = func(p *wiki.Page) string { return wiki.PageURL(name, p.Stem) }
	}
	if len(pages) == 0 {
		return map[string]any{"count": 0}
	}
	rank := func(status string) int {
		if r, ok := mmExampleRank[status]; ok {
			return r
		}
		return 9
	}
	best := pages[0]
	for _, p := range pages[1:] {
		rp, rb := rank(p.Status()), rank(best.Status())
		if rp < rb || (rp == rb && p.ID() < best.ID()) {
			best = p
		}
	}
	return map[string]any{
		"count":      len(pages),
		"id":         best.ID(),
		"title":      best.Title(),
		"url":        urlFn(best),
		"status":     best.Status(),
		"stereotype": best.MetaString("stereotype"),
		"notation":   best.MetaString("notation"),
		"level":      best.MetaString("level"),
	}
}

func buildMetamodelGraph(mm *metamodel.Data) map[string]any {
	nodes := make([]map[string]any, 0)
	edges := make([]map[string]any, 0)
	byName := map[string]map[string]any{}
	usedBlocks := map[string]bool{}
	for _, t := range mm.Types {
		name := metamodel.StrVal(t["name"])
		byName[name] = t
		if b := metamodel.StrVal(t["block"]); b != "" {
			usedBlocks[b] = true
		}
	}
	for _, b := range mm.Blocks {
		bid := metamodel.StrVal(b["id"])
		if usedBlocks[bid] {
			nodes = append(nodes, map[string]any{
				"data": map[string]any{
					"id":       "block:" + bid,
					"label":    bid + " · " + metamodel.StrVal(b["title"]),
					"is_block": true,
					"area":     metamodel.StrVal(b["area"]),
				},
			})
		}
	}
	for _, t := range mm.Types {
		name := metamodel.StrVal(t["name"])
		lbl := metamodel.StrVal(t["label"])
		if lbl == "" {
			lbl = name
		}
		block := metamodel.StrVal(t["block"])
		d := map[string]any{
			"id":          name,
			"label":       lbl,
			"prefix":      metamodel.StrVal(t["prefix"]),
			"label_de":    metamodel.StrVal(t["label_de"]),
			"url":         "#type-" + name,
			"stereotypes": strings.Join(mmStringSlice(t["stereotypes"]), ", "),
			"block_id":    block,
		}
		if block != "" {
			d["parent"] = "block:" + block
		}
		nodes = append(nodes, map[string]any{"data": d})
	}

	universal := make([]map[string]any, 0)
	loops := map[string]int{}
	loopDirs := []string{"-45deg", "45deg", "135deg", "-135deg"}
	for _, r := range mm.Relations {
		field := metamodel.StrVal(r["field"])
		dir := metamodel.StrVal(r["direction"])
		sem := metamodel.StrVal(r["semantics"])
		rawEdges, _ := r["edges"].([]any)
		for _, item := range rawEdges {
			em, ok := item.(map[string]any)
			if !ok {
				continue
			}
			src := metamodel.StrVal(em["from"])
			tgt := metamodel.StrVal(em["to"])
			if src == "any" || tgt == "any" {
				universal = append(universal, map[string]any{
					"field":       field,
					"from":        src,
					"to":          tgt,
					"direction":   r["direction"],
					"cardinality": metamodel.StrVal(em["cardinality"]),
					"note":        metamodel.StrVal(em["note"]),
				})
				continue
			}
			if _, ok := byName[src]; !ok {
				continue
			}
			if _, ok := byName[tgt]; !ok {
				continue
			}
			d := map[string]any{
				"id":          fmt.Sprintf("e%d", len(edges)),
				"source":      src,
				"target":      tgt,
				"label":       field,
				"cardinality": metamodel.StrVal(em["cardinality"]),
				"semantics":   sem,
				"symmetric":   dir == "symmetric",
				"note":        metamodel.StrVal(em["note"]),
			}
			if src == tgt {
				k := loops[src]
				loops[src] = k + 1
				d["loop_dir"] = loopDirs[k%4]
			}
			edges = append(edges, map[string]any{"data": d})
		}
	}

	return map[string]any{
		"nodes":     nodes,
		"edges":     edges,
		"universal": universal,
	}
}

func buildMMAnchors(mm *metamodel.Data, methodAnchors []metamodel.Anchor, mmAnchors map[string]string, methodAnchorIdx map[string]metamodel.Anchor, decisionStems map[string]bool) []map[string]any {
	byName := map[string]map[string]any{}
	for _, t := range mm.Types {
		byName[metamodel.StrVal(t["name"])] = t
	}
	out := make([]map[string]any, 0, len(methodAnchors))
	for _, a := range methodAnchors {
		keys := map[string]bool{
			strings.ToLower(a.Name): true,
			a.Slug:                  true,
		}
		for _, x := range a.Aliases {
			keys[strings.ToLower(x)] = true
		}

		var typeNames []string
		seenType := map[string]bool{}
		for _, t := range mm.Types {
			tName := metamodel.StrVal(t["name"])
			for _, x := range mmStringSlice(t["anchors"]) {
				if keys[strings.ToLower(strings.TrimSpace(x))] {
					if !seenType[tName] {
						seenType[tName] = true
						typeNames = append(typeNames, tName)
					}
					break
				}
			}
		}
		var other []string
		for _, entry := range a.AppliesTo {
			ref := mmAnchors[entry]
			if strings.HasPrefix(ref, "type-") {
				tn := ref[5:]
				if !seenType[tn] {
					seenType[tn] = true
					typeNames = append(typeNames, tn)
				}
			} else {
				other = append(other, entry)
			}
		}

		var aliases []string
		for _, x := range a.Aliases {
			if !strings.EqualFold(x, a.Name) {
				aliases = append(aliases, x)
			}
		}
		typeRefs := make([]map[string]any, 0, len(typeNames))
		for _, tn := range typeNames {
			typeRefs = append(typeRefs, map[string]any{
				"label": mmTypeLabel(tn, byName),
				"href":  "#type-" + tn,
			})
		}

		out = append(out, map[string]any{
			"id":              a.ID,
			"name":            a.Name,
			"aliases":         aliases,
			"definition_html": mmInline(a.Definition, mmAnchors, methodAnchorIdx, decisionStems),
			"reference":       a.Reference,
			"show_reference":  a.Reference != "" && !strings.Contains(a.Definition, a.Reference),
			"types":           typeRefs,
			"other":           other,
		})
	}
	return out
}

func mmQualifier(ap map[string]any) string {
	var parts []string
	for _, key := range []string{"stereotype", "notation", "level"} {
		v := ap[key]
		if v == nil {
			continue
		}
		var vals []string
		switch x := v.(type) {
		case []any:
			for _, item := range x {
				if s := metamodel.StrVal(item); s != "" {
					vals = append(vals, s)
				}
			}
		case []string:
			for _, s := range x {
				if s != "" {
					vals = append(vals, s)
				}
			}
		default:
			if s := metamodel.StrVal(v); s != "" {
				vals = append(vals, s)
			}
		}
		if len(vals) > 0 {
			parts = append(parts, key+" "+strings.Join(vals, ", "))
		}
	}
	return strings.Join(parts, "; ")
}

func (s *Server) handleMetamodel(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	mm := s.Metamodel.Load()
	mmAnchors := metamodel.Anchors(mm)
	methodAnchors := s.Metamodel.MethodAnchors()
	methodAnchorIdx := metamodel.AnchorIndex(methodAnchors)

	decisionStems := map[string]bool{}
	for _, p := range sn.typed("decision-record") {
		decisionStems[p.Stem] = true
	}

	byName := map[string]map[string]any{}
	for _, t := range mm.Types {
		byName[metamodel.StrVal(t["name"])] = t
	}

	meta := mm.Meta
	var universalFields []map[string]any
	if rawUF, ok := meta["universal_fields"].([]any); ok {
		for _, item := range rawUF {
			fm, ok := item.(map[string]any)
			if !ok {
				continue
			}
			cp := make(map[string]any, len(fm)+1)
			for k, v := range fm {
				cp[k] = v
			}
			cp["doc_html"] = mmInline(metamodel.StrVal(fm["doc"]), mmAnchors, methodAnchorIdx, decisionStems)
			universalFields = append(universalFields, cp)
		}
	}

	types := make([]map[string]any, 0, len(mm.Types))
	nExamples := 0
	for _, t := range mm.Types {
		var fields []map[string]any
		if rawFields, ok := t["fields"].([]any); ok {
			for _, item := range rawFields {
				fm, ok := item.(map[string]any)
				if !ok {
					continue
				}
				req, _ := fm["required"].(bool)
				fields = append(fields, map[string]any{
					"name":     metamodel.StrVal(fm["name"]),
					"kind":     metamodel.StrVal(fm["kind"]),
					"values":   mmStringSlice(fm["values"]),
					"required": req,
					"relation": metamodel.StrVal(fm["relation"]),
					"doc":      mmInline(metamodel.StrVal(fm["doc"]), mmAnchors, methodAnchorIdx, decisionStems),
				})
			}
		}
		universal := true
		if u, ok := t["universal"]; ok {
			if b, ok := u.(bool); ok {
				universal = b
			}
		}
		var anchorRefs []map[string]any
		for _, a := range mmStringSlice(t["anchors"]) {
			anchorRefs = append(anchorRefs, mmAnchorRef(a, methodAnchorIdx))
		}
		name := metamodel.StrVal(t["name"])
		lbl := metamodel.StrVal(t["label"])
		if lbl == "" {
			lbl = name
		}
		ex := mmExample(sn, t)
		if cnt, _ := ex["count"].(int); cnt > 0 {
			nExamples++
		}
		types = append(types, map[string]any{
			"name":         name,
			"anchor":       "type-" + name,
			"prefix":       metamodel.StrVal(t["prefix"]),
			"label":        lbl,
			"label_de":     metamodel.StrVal(t["label_de"]),
			"block":        metamodel.StrVal(t["block"]),
			"block_title":  metamodel.StrVal(t["block_title"]),
			"folder":       metamodel.StrVal(t["folder"]),
			"template":     metamodel.StrVal(t["template"]),
			"lifecycle":    metamodel.StrVal(t["lifecycle"]),
			"stereotypes":  mmStringSlice(t["stereotypes"]),
			"naming":       metamodel.StrVal(t["naming"]),
			"universal":    universal,
			"fields":       fields,
			"anchors":      anchorRefs,
			"projections":  mmStringSlice(t["projections"]),
			"summary_html": mmInline(metamodel.StrVal(t["_summary"]), mmAnchors, methodAnchorIdx, decisionStems),
			"example":      ex,
		})
	}

	relations := make([]map[string]any, 0, len(mm.Relations))
	for _, rel := range mm.Relations {
		name := metamodel.StrVal(rel["name"])
		field := metamodel.StrVal(rel["field"])
		if field == "" {
			field = name
		}
		recip := metamodel.StrVal(rel["reciprocity"])
		if recip == "" {
			recip = "none"
		}
		invStored, _ := rel["inverse_stored"].(bool)
		var edges []map[string]any
		if rawEdges, ok := rel["edges"].([]any); ok {
			for _, item := range rawEdges {
				em, ok := item.(map[string]any)
				if !ok {
					continue
				}
				fromStr := metamodel.StrVal(em["from"])
				toStr := metamodel.StrVal(em["to"])
				edges = append(edges, map[string]any{
					"from":        mmTypeLabel(em["from"], byName),
					"to":          mmTypeLabel(em["to"], byName),
					"from_anchor": mmAnchors[fromStr],
					"to_anchor":   mmAnchors[toStr],
					"cardinality": metamodel.StrVal(em["cardinality"]),
					"note":        mmInline(metamodel.StrVal(em["note"]), mmAnchors, methodAnchorIdx, decisionStems),
				})
			}
		}
		relations = append(relations, map[string]any{
			"name":           name,
			"anchor":         "rel-" + name,
			"field":          field,
			"direction":      metamodel.StrVal(rel["direction"]),
			"semantics":      metamodel.StrVal(rel["semantics"]),
			"inverse":        metamodel.StrVal(rel["inverse"]),
			"inverse_stored": invStored,
			"inverse_field":  metamodel.StrVal(rel["inverse_field"]),
			"reciprocity":    recip,
			"edges":          edges,
			"summary_html":   mmInline(metamodel.StrVal(rel["_summary"]), mmAnchors, methodAnchorIdx, decisionStems),
		})
	}

	projections := make([]map[string]any, 0, len(mm.Projections))
	for _, pr := range mm.Projections {
		name := metamodel.StrVal(pr["name"])
		impl := metamodel.StrVal(pr["implemented"])
		if impl == "" {
			impl = "none"
		}
		var reads []map[string]any
		if rawReads, ok := pr["reads"].([]any); ok {
			for _, item := range rawReads {
				rd, ok := item.(map[string]any)
				if !ok {
					continue
				}
				typeStr := metamodel.StrVal(rd["type"])
				reads = append(reads, map[string]any{
					"type":        mmTypeLabel(rd["type"], byName),
					"type_anchor": mmAnchors[typeStr],
					"fields":      mmStringSlice(rd["fields"]),
				})
			}
		}
		var anchorRef any
		if anc := metamodel.StrVal(pr["anchor"]); anc != "" {
			anchorRef = mmAnchorRef(anc, methodAnchorIdx)
		}
		var decLinks []string
		for _, d := range strings.Split(metamodel.StrVal(pr["decision"]), ",") {
			d = strings.TrimSpace(d)
			if d != "" {
				decLinks = append(decLinks, mmDRLink(d, firstRunes(d, 6), decisionStems))
			}
		}
		projections = append(projections, map[string]any{
			"name":           name,
			"anchor":         "proj-" + name,
			"output":         metamodel.StrVal(pr["output"]),
			"reads":          reads,
			"implemented":    impl,
			"href":           mmRouteHref(impl),
			"anchor_ref":     anchorRef,
			"decisions_html": strings.Join(decLinks, ", "),
			"summary_html":   mmInline(metamodel.StrVal(pr["_summary"]), mmAnchors, methodAnchorIdx, decisionStems),
		})
	}

	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	defaultNotation := cfg.DefaultNotation
	sortedNotations := make([]map[string]any, len(mm.Notations))
	copy(sortedNotations, mm.Notations)
	sort.SliceStable(sortedNotations, func(i, j int) bool {
		ni := strings.ToLower(metamodel.StrVal(sortedNotations[i]["name"]))
		nj := strings.ToLower(metamodel.StrVal(sortedNotations[j]["name"]))
		di := ni != defaultNotation
		dj := nj != defaultNotation
		if di != dj {
			return !di
		}
		return ni < nj
	})
	notations := make([]map[string]any, 0, len(sortedNotations))
	for _, n := range sortedNotations {
		name := metamodel.StrVal(n["name"])
		title := metamodel.StrVal(n["title"])
		if title == "" {
			title = name
		}
		var nFields []map[string]any
		if rawF, ok := n["fields"].([]any); ok {
			for _, item := range rawF {
				if fm, ok := item.(map[string]any); ok {
					nFields = append(nFields, fm)
				}
			}
		}
		notations = append(notations, map[string]any{
			"name":         name,
			"anchor":       "notation-" + name,
			"title":        title,
			"default":      strings.ToLower(name) == defaultNotation,
			"levels":       mmStringSlice(n["levels"]),
			"sections":     n["_sections"],
			"fields":       nFields,
			"summary_html": mmInline(metamodel.StrVal(n["summary"]), mmAnchors, methodAnchorIdx, decisionStems),
		})
	}

	rules := make([]map[string]any, 0, len(mm.Rules))
	for _, ru := range mm.Rules {
		name := metamodel.StrVal(ru["name"])
		ap, _ := ru["applies_to"].(map[string]any)
		if ap == nil {
			ap = map[string]any{}
		}
		apTypeStr := metamodel.StrVal(ap["type"])
		rules = append(rules, map[string]any{
			"name":              name,
			"anchor":            "rule-" + name,
			"applies_type":      mmTypeLabel(ap["type"], byName),
			"applies_anchor":    mmAnchors[apTypeStr],
			"applies_qualifier": mmQualifier(ap),
			"check":             mmInline(metamodel.StrVal(ru["check"]), mmAnchors, methodAnchorIdx, decisionStems),
			"confidence":        metamodel.StrVal(ru["confidence"]),
			"action":            metamodel.StrVal(ru["action"]),
			"source":            metamodel.StrVal(ru["source"]),
			"summary_html":      mmInline(metamodel.StrVal(ru["_summary"]), mmAnchors, methodAnchorIdx, decisionStems),
		})
	}

	graph := buildMetamodelGraph(mm)
	nIn := 0
	for _, b := range mm.Blocks {
		if metamodel.StrVal(b["scope"]) == "in" {
			nIn++
		}
	}

	lifecycles, _ := meta["lifecycles"].(map[string]any)
	if lifecycles == nil {
		lifecycles = map[string]any{}
	}

	s.renderHTML(w, r, http.StatusOK, "metamodel.html", cat, map[string]any{
		"present":          mm.Present,
		"types":            types,
		"relations":        relations,
		"projections":      projections,
		"notations":        notations,
		"rules":            rules,
		"graph":            graph,
		"method_anchors":   buildMMAnchors(mm, methodAnchors, mmAnchors, methodAnchorIdx, decisionStems),
		"universal":        graph["universal"],
		"universal_fields": universalFields,
		"lifecycles":       lifecycles,
		"constructs":       mmStringSlice(meta["constructs"]),
		"field_kinds":      mmStringSlice(meta["field_kinds"]),
		"frameworks":       mm.Frameworks,
		"n_blocks_in":      nIn,
		"n_blocks":         len(mm.Blocks),
		"n_examples":       nExamples,
		"decision_html":    mmDRLink("DR-035-explicit-metamodel", "DR-035", decisionStems),
	}, now)
}
