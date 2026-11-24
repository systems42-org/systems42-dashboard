package project

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	visionHeadingRE = regexp.MustCompile(`##\s+Vision\b[^\n]*\n+`)
	nextH2RE        = regexp.MustCompile(`\n##\s`)
	boldRE          = regexp.MustCompile(`\*\*([^*]+)\*\*`)
)

var (
	visionSkipPrefixes = []string{">", "<!--", "**Objectives.**", "*Optional:*"}
	enablerLanes       = map[string]bool{"platform": true, "display": true}
	agileLevels        = map[string]bool{"epic": true, "feature": true, "story": true}
	ucRefinableLevels  = map[string]bool{"sea": true, "fish": true}
)

// GoalsData holds everything /goals and the goal-epic hierarchy map need.
type GoalsData struct {
	Vision     *wiki.Page
	Objectives []*wiki.Page
	Coverage   map[string][]*wiki.Page
	Enablers   []*wiki.Page
	Untraced   []*wiki.Page
	FRs        []*wiki.Page
	UCs        []*wiki.Page
}

// FRNotation returns lower-cased frontmatter notation: without any fallback.
func FRNotation(p *wiki.Page) string {
	return strings.ToLower(strings.TrimSpace(p.MetaString("notation")))
}

// FRLevel returns lower-cased frontmatter level:.
func FRLevel(p *wiki.Page) string {
	return strings.ToLower(strings.TrimSpace(p.MetaString("level")))
}

func frFirstParent(p *wiki.Page, index map[string]*wiki.Page) string {
	for _, ref := range p.AsList("parent") {
		if st := wiki.LinkStem(ref, index); st != "" {
			return st
		}
	}
	return ""
}

func frOrder(p *wiki.Page) int {
	v, ok := p.Meta["order"]
	if !ok || v == nil {
		return 9999
	}
	switch x := v.(type) {
	case int:
		return x
	case int64:
		return int(x)
	case uint64:
		return int(x)
	case float64:
		return int(x)
	case string:
		if n, err := strconv.Atoi(strings.TrimSpace(x)); err == nil {
			return n
		}
	}
	return 9999
}

func sortFRPages(pages []*wiki.Page) []*wiki.Page {
	cp := make([]*wiki.Page, len(pages))
	copy(cp, pages)
	sort.SliceStable(cp, func(i, j int) bool {
		oi, oj := frOrder(cp[i]), frOrder(cp[j])
		if oi != oj {
			return oi < oj
		}
		return cp[i].ID() < cp[j].ID()
	})
	return cp
}

func inEnablerLane(fr *wiki.Page) bool {
	return enablerLanes[strings.ToLower(strings.TrimSpace(fr.MetaString("lane")))]
}

// LoadGoals builds the goals, coverage, enablers, and untraced sets matching
// app.py's load_goals().
func LoadGoals(goals, frs []*wiki.Page, byStem map[string]*wiki.Page) *GoalsData {
	sortedGoals := SortedByID(goals)
	vision := wiki.VisionPage(sortedGoals)
	objectives := make([]*wiki.Page, 0, len(sortedGoals))
	objectiveByStem := map[string]*wiki.Page{}
	coverage := map[string][]*wiki.Page{}
	for _, g := range sortedGoals {
		if g == vision {
			continue
		}
		objectives = append(objectives, g)
		objectiveByStem[g.Stem] = g
		coverage[g.ID()] = []*wiki.Page{}
	}

	allFRs := SortedByID(frs)
	var ucs, nonUCs []*wiki.Page
	ucByStem := map[string]*wiki.Page{}
	for _, p := range allFRs {
		if FRNotation(p) == "use-case" {
			ucs = append(ucs, p)
			if ucRefinableLevels[FRLevel(p)] {
				ucByStem[p.Stem] = p
			}
		} else {
			nonUCs = append(nonUCs, p)
		}
	}

	served := func(p *wiki.Page) []string {
		var out []string
		for _, s := range wiki.LinksOf(p, "goal", byStem) {
			if obj, ok := objectiveByStem[s]; ok {
				out = append(out, obj.ID())
			}
		}
		return out
	}

	var enablers, untraced []*wiki.Page
	for _, fr := range nonUCs {
		gids := served(fr)
		if len(gids) == 0 && FRNotation(fr) == "agile" && (FRLevel(fr) == "feature" || FRLevel(fr) == "story") {
			if first := frFirstParent(fr, byStem); first != "" {
				if uc, ok := ucByStem[first]; ok {
					gids = served(uc)
				}
			}
		}
		if len(gids) == 0 && inEnablerLane(fr) {
			enablers = append(enablers, fr)
		} else if FRNotation(fr) == "agile" && (FRLevel(fr) == "epic" || FRLevel(fr) == "feature") && len(gids) == 0 && !inEnablerLane(fr) {
			untraced = append(untraced, fr)
		}
		for _, gid := range gids {
			coverage[gid] = append(coverage[gid], fr)
		}
	}
	for _, uc := range ucs {
		for _, gid := range served(uc) {
			already := false
			for _, cur := range coverage[gid] {
				if cur == uc {
					already = true
					break
				}
			}
			if !already {
				coverage[gid] = append(coverage[gid], uc)
			}
		}
	}

	return &GoalsData{
		Vision:     vision,
		Objectives: objectives,
		Coverage:   coverage,
		Enablers:   enablers,
		Untraced:   untraced,
		FRs:        nonUCs,
		UCs:        ucs,
	}
}

// VisionParagraphs returns every rendered prose paragraph under `## Vision`,
// matching app.py's _vision_paragraphs().
func VisionParagraphs(page *wiki.Page, linkCtx render.LinkContext) []string {
	if page == nil {
		return nil
	}
	body := strings.ReplaceAll(page.Body, "\r\n", "\n")
	loc := visionHeadingRE.FindStringIndex(body)
	if loc == nil {
		return nil
	}
	rest := body[loc[1]:]
	if end := nextH2RE.FindStringIndex(rest); end != nil {
		rest = rest[:end[0]]
	}
	var out []string
	for _, para := range strings.Split(rest, "\n\n") {
		para = strings.TrimSpace(para)
		if para == "" {
			continue
		}
		skip := false
		for _, pref := range visionSkipPrefixes {
			if strings.HasPrefix(para, pref) {
				skip = true
				break
			}
		}
		if skip {
			continue
		}
		para = collapseWSRE.ReplaceAllString(para, " ")
		para = render.RenderWikilinks(para, linkCtx)
		para = boldRE.ReplaceAllString(para, "<strong>$1</strong>")
		out = append(out, render.SanitizeHTML(para, false))
	}
	return out
}

// GoalMatrix builds the (columns, rows) coverage matrix for /goals (FR-036).
func GoalMatrix(data *GoalsData) ([]map[string]any, []map[string]any) {
	enablerIDs := map[string]bool{}
	for _, fr := range data.Enablers {
		enablerIDs[fr.ID()] = true
	}
	untracedIDs := map[string]bool{}
	for _, fr := range data.Untraced {
		untracedIDs[fr.ID()] = true
	}
	var epics []*wiki.Page
	for _, fr := range data.FRs {
		if FRNotation(fr) == "agile" && FRLevel(fr) == "epic" {
			epics = append(epics, fr)
		}
	}

	col := func(p *wiki.Page) map[string]any {
		return map[string]any{
			"id":      p.ID(),
			"title":   p.Title(),
			"url":     wiki.PageURL(p.Folder, p.Stem),
			"status":  p.Status(),
			"enabler": enablerIDs[p.ID()],
			"nogoal":  untracedIDs[p.ID()],
		}
	}

	cols := make([]map[string]any, 0, len(epics)+len(data.UCs))
	for _, e := range epics {
		if !enablerIDs[e.ID()] {
			cols = append(cols, col(e))
		}
	}
	for _, uc := range data.UCs {
		cols = append(cols, col(uc))
	}
	for _, e := range epics {
		if enablerIDs[e.ID()] {
			cols = append(cols, col(e))
		}
	}

	colIDs := make(map[string]bool, len(cols))
	for _, c := range cols {
		colIDs[c["id"].(string)] = true
	}

	view := func(serving []*wiki.Page) map[string]any {
		groups := []map[string]any{}
		hasCol := false
		for _, p := range serving {
			if colIDs[p.ID()] {
				hasCol = true
				break
			}
		}
		if !hasCol {
			for _, kl := range [][2]string{{"feature", "features"}, {"story", "stories"}} {
				var links []map[string]any
				for _, p := range serving {
					if FRNotation(p) == "agile" && FRLevel(p) == kl[0] {
						links = append(links, map[string]any{
							"id":  p.ID(),
							"url": wiki.PageURL(p.Folder, p.Stem),
						})
					}
				}
				if len(links) > 0 {
					groups = append(groups, map[string]any{"label": kl[1], "links": links})
				}
			}
			var others []map[string]any
			for _, p := range serving {
				n := FRNotation(p)
				if n != "agile" && n != "use-case" {
					others = append(others, map[string]any{
						"id":  p.ID(),
						"url": wiki.PageURL(p.Folder, p.Stem),
					})
				}
			}
			if len(others) > 0 {
				groups = append(groups, map[string]any{"label": "other requirements", "links": others})
			}
		}
		return map[string]any{
			"gap":    len(serving) == 0,
			"served": groups,
		}
	}

	rows := make([]map[string]any, 0, len(data.Objectives))
	for _, o := range data.Objectives {
		serving := data.Coverage[o.ID()]
		covered := make(map[string]bool, len(serving))
		var accepted []*wiki.Page
		for _, p := range serving {
			covered[p.ID()] = true
			if p.Status() == "accepted" {
				accepted = append(accepted, p)
			}
		}
		cells := make([]bool, len(cols))
		for i, c := range cols {
			cells[i] = covered[c["id"].(string)]
		}
		rows = append(rows, map[string]any{
			"id":     o.ID(),
			"title":  o.Title(),
			"url":    wiki.PageURL(o.Folder, o.Stem),
			"status": o.Status(),
			"cells":  cells,
			"views": map[string]any{
				"all":      view(serving),
				"accepted": view(accepted),
			},
		})
	}
	return cols, rows
}

// MermaidGoalTree projects the Vision -> Objectives tree for /goals.
func MermaidGoalTree(systemName string, vision *wiki.Page, objectives []*wiki.Page) string {
	if vision == nil || len(objectives) == 0 {
		return ""
	}
	root := CleanLabel(systemName, false)
	lines := []string{
		"graph TD",
		fmt.Sprintf(`  V["Vision %s"]:::vision`, root),
		fmt.Sprintf(`  click V "/goals#%s"`, vision.ID()),
	}
	for _, o := range objectives {
		nid := DiagramNodeID(o.ID())
		label := CleanLabel(ShortTitle(o), true)
		lines = append(lines,
			fmt.Sprintf(`  V --> %s["%s<br/>%s"]:::goal`, nid, o.ID(), label),
			fmt.Sprintf(`  click %s "/goals#%s"`, nid, o.ID()),
		)
	}
	lines = append(lines,
		"  classDef vision fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
		"  classDef goal fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
	)
	return strings.Join(lines, "\n")
}

func frNode(p *wiki.Page) map[string]any {
	return map[string]any{
		"id":       p.ID(),
		"title":    p.Title(),
		"stem":     p.Stem,
		"priority": strings.TrimSpace(p.MetaString("priority")),
		"level":    FRLevel(p),
		"notation": FRNotation(p),
		"status":   p.Status(),
	}
}

// BuildFRHierarchy projects the Epic -> Feature -> Story story map (DR-038).
func BuildFRHierarchy(frs []*wiki.Page, index map[string]*wiki.Page) map[string]any {
	allPages := make([]*wiki.Page, 0, len(frs))
	for _, p := range frs {
		if p.Status() != "deprecated" {
			allPages = append(allPages, p)
		}
	}

	var pages []*wiki.Page
	byStem := map[string]*wiki.Page{}
	ucByStem := map[string]*wiki.Page{}
	for _, p := range allPages {
		not, lvl := FRNotation(p), FRLevel(p)
		if not == "agile" && agileLevels[lvl] {
			pages = append(pages, p)
			byStem[p.Stem] = p
		} else if not == "use-case" && ucRefinableLevels[lvl] {
			ucByStem[p.Stem] = p
		}
	}

	children := map[string][]*wiki.Page{}
	for _, p := range pages {
		if ps := frFirstParent(p, index); ps != "" {
			children[ps] = append(children[ps], p)
		}
	}
	kids := func(stem, level string) []*wiki.Page {
		var out []*wiki.Page
		for _, c := range children[stem] {
			if FRLevel(c) == level {
				out = append(out, c)
			}
		}
		return sortFRPages(out)
	}

	breakdown := func(root *wiki.Page) (nFeat, nStory int, featRows, directStories []map[string]any) {
		feats := kids(root.Stem, "feature")
		featRows = make([]map[string]any, 0, len(feats))
		storyTotal := 0
		for _, f := range feats {
			stList := kids(f.Stem, "story")
			stories := make([]map[string]any, 0, len(stList))
			for _, s := range stList {
				stories = append(stories, frNode(s))
			}
			storyTotal += len(stories)
			fn := frNode(f)
			fn["stories"] = stories
			featRows = append(featRows, fn)
		}
		directList := kids(root.Stem, "story")
		directStories = make([]map[string]any, 0, len(directList))
		for _, s := range directList {
			directStories = append(directStories, frNode(s))
		}
		return len(feats), len(directStories) + storyTotal, featRows, directStories
	}

	var rawEpics []*wiki.Page
	for _, p := range pages {
		if FRLevel(p) == "epic" {
			rawEpics = append(rawEpics, p)
		}
	}
	epics := sortFRPages(rawEpics)
	epicRows := make([]map[string]any, 0, len(epics))
	totalFeatures, totalStories := 0, 0
	for _, e := range epics {
		nf, ns, feats, direct := breakdown(e)
		totalFeatures += nf
		totalStories += ns
		row := frNode(e)
		row["release"] = strings.TrimSpace(e.MetaString("release"))
		row["n_features"] = nf
		row["n_stories"] = ns
		row["features"] = feats
		row["direct_stories"] = direct
		epicRows = append(epicRows, row)
	}

	ucValues := make([]*wiki.Page, 0, len(ucByStem))
	for _, u := range ucByStem {
		ucValues = append(ucValues, u)
	}
	ucRows := make([]map[string]any, 0)
	placed := make(map[string]bool, len(byStem))
	for st := range byStem {
		placed[st] = true
	}
	for _, u := range sortFRPages(ucValues) {
		if len(kids(u.Stem, "feature")) == 0 && len(kids(u.Stem, "story")) == 0 {
			continue
		}
		nf, ns, feats, direct := breakdown(u)
		totalFeatures += nf
		totalStories += ns
		row := frNode(u)
		row["url"] = wiki.PageURL("functional-requirements", u.Stem)
		row["n_features"] = nf
		row["n_stories"] = ns
		row["features"] = feats
		row["direct_stories"] = direct
		ucRows = append(ucRows, row)
		placed[u.Stem] = true
	}

	// A parent that exists does not place a page: only a root shows features,
	// and only a root or a feature shows stories. A feature no root shows is an
	// orphan and keeps its stories, so every story of a feature shows once.
	levelOf := func(stem string) string {
		if p := byStem[stem]; p != nil {
			return FRLevel(p)
		}
		return ""
	}
	orphans := make([]map[string]any, 0)
	for _, p := range pages {
		lvl := FRLevel(p)
		ps := frFirstParent(p, index)
		underRoot := ucByStem[ps] != nil || levelOf(ps) == "epic"
		if lvl == "feature" && !underRoot {
			stList := kids(p.Stem, "story")
			stories := make([]map[string]any, 0, len(stList))
			for _, s := range stList {
				stories = append(stories, frNode(s))
			}
			fn := frNode(p)
			fn["stories"] = stories
			orphans = append(orphans, fn)
			totalFeatures++
			totalStories += len(stories)
		} else if lvl == "story" && !underRoot && levelOf(ps) != "feature" {
			orphans = append(orphans, frNode(p))
			totalStories++
		}
	}

	otherNotations := make([]map[string]any, 0)
	for _, p := range allPages {
		if !placed[p.Stem] {
			otherNotations = append(otherNotations, frNode(p))
		}
	}
	sort.SliceStable(otherNotations, func(i, j int) bool {
		return otherNotations[i]["id"].(string) < otherNotations[j]["id"].(string)
	})

	return map[string]any{
		"epics":           epicRows,
		"use_cases":       ucRows,
		"total_epics":     len(epics),
		"total_features":  totalFeatures,
		"total_stories":   totalStories,
		"orphans":         orphans,
		"other_notations": otherNotations,
	}
}

// FRHierarchyNode finds stem within BuildFRHierarchy's tree and returns
// (node, level). An orphan is found too, with its stories if it is a feature.
func FRHierarchyNode(hierarchy map[string]any, stem string) (map[string]any, string) {
	epics, _ := hierarchy["epics"].([]map[string]any)
	ucs, _ := hierarchy["use_cases"].([]map[string]any)
	checkRoot := func(root map[string]any, isUC bool) (map[string]any, string) {
		if root["stem"].(string) == stem {
			if isUC {
				return root, root["level"].(string)
			}
			return root, "epic"
		}
		feats, _ := root["features"].([]map[string]any)
		for _, f := range feats {
			if f["stem"].(string) == stem {
				return f, "feature"
			}
			stories, _ := f["stories"].([]map[string]any)
			for _, s := range stories {
				if s["stem"].(string) == stem {
					return s, "story"
				}
			}
		}
		direct, _ := root["direct_stories"].([]map[string]any)
		for _, s := range direct {
			if s["stem"].(string) == stem {
				return s, "story"
			}
		}
		return nil, ""
	}
	for _, e := range epics {
		if n, lvl := checkRoot(e, false); n != nil {
			return n, lvl
		}
	}
	for _, u := range ucs {
		if n, lvl := checkRoot(u, true); n != nil {
			return n, lvl
		}
	}
	orphans, _ := hierarchy["orphans"].([]map[string]any)
	for _, o := range orphans {
		if o["stem"].(string) == stem {
			return o, o["level"].(string)
		}
		stories, _ := o["stories"].([]map[string]any)
		for _, s := range stories {
			if s["stem"].(string) == stem {
				return s, "story"
			}
		}
	}
	return nil, ""
}

// FRAncestors walks the first-parent chain for an FR (root first, cycle-safe).
func FRAncestors(frs []*wiki.Page, stem string, index map[string]*wiki.Page) []map[string]any {
	byStem := make(map[string]*wiki.Page, len(frs))
	for _, p := range frs {
		byStem[p.Stem] = p
	}
	var out []map[string]any
	cur := byStem[stem]
	seen := map[string]bool{stem: true}
	for cur != nil {
		ps := frFirstParent(cur, index)
		if ps == "" || seen[ps] {
			break
		}
		seen[ps] = true
		parent := byStem[ps]
		if parent == nil {
			break
		}
		out = append(out, map[string]any{
			"id":    parent.ID(),
			"title": parent.Title(),
			"stem":  parent.Stem,
			"url":   "/functional-requirements/" + parent.Stem,
		})
		cur = parent
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// MermaidGoalEpicTree projects the Goal -> Epic / Use-Case overview map for
// /req42/functional-requirements.
func MermaidGoalEpicTree(goals *GoalsData, hierarchy map[string]any) (string, []map[string]any) {
	epics, _ := hierarchy["epics"].([]map[string]any)
	hasUC := false
	for _, ps := range goals.Coverage {
		for _, p := range ps {
			if FRNotation(p) == "use-case" {
				hasUC = true
				break
			}
		}
		if hasUC {
			break
		}
	}
	if len(epics) == 0 && !hasUC {
		return "", nil
	}
	epicByID := make(map[string]map[string]any, len(epics))
	for _, e := range epics {
		epicByID[e["id"].(string)] = e
	}

	lines := []string{"graph TD"}
	seen := map[string]bool{}
	var drawn []map[string]any

	epicEdge := func(parentNID string, e map[string]any) {
		eid := e["id"].(string)
		nid := DiagramNodeID(eid)
		if seen[eid] {
			lines = append(lines, fmt.Sprintf("  %s --> %s", parentNID, nid))
			return
		}
		label := CleanLabel(e["title"].(string), true)
		lines = append(lines,
			fmt.Sprintf(`  %s --> %s["%s<br/>%s"]:::epic`, parentNID, nid, eid, label),
			fmt.Sprintf(`  click %s "/functional-requirements/%s"`, nid, e["stem"].(string)),
		)
		drawn = append(drawn, map[string]any{
			"id":    eid,
			"title": e["title"].(string),
			"url":   "/functional-requirements/" + e["stem"].(string),
		})
		seen[eid] = true
	}

	ucEdge := func(parentNID string, uc *wiki.Page) {
		nid := DiagramNodeID(uc.ID())
		if seen[uc.ID()] {
			lines = append(lines, fmt.Sprintf("  %s --> %s", parentNID, nid))
			return
		}
		label := CleanLabel(uc.Title(), true)
		lines = append(lines,
			fmt.Sprintf(`  %s --> %s["%s<br/>%s"]:::usecase`, parentNID, nid, uc.ID(), label),
			fmt.Sprintf(`  click %s "%s"`, nid, wiki.PageURL(uc.Folder, uc.Stem)),
		)
		drawn = append(drawn, NodeLink(uc))
		seen[uc.ID()] = true
	}

	for _, o := range goals.Objectives {
		gid := DiagramNodeID(o.ID())
		glabel := CleanLabel(ShortTitle(o), true)
		lines = append(lines,
			fmt.Sprintf(`  %s["%s<br/>%s"]:::goal`, gid, o.ID(), glabel),
			fmt.Sprintf(`  click %s "/goals#%s"`, gid, o.ID()),
		)
		drawn = append(drawn, map[string]any{
			"id":    o.ID(),
			"title": o.Title(),
			"url":   "/goals#" + o.ID(),
		})
		for _, fr := range goals.Coverage[o.ID()] {
			if FRNotation(fr) == "use-case" {
				ucEdge(gid, fr)
				continue
			}
			if e, ok := epicByID[fr.ID()]; ok {
				epicEdge(gid, e)
			}
		}
	}

	var enablerEpics []map[string]any
	for _, fr := range goals.Enablers {
		if e, ok := epicByID[fr.ID()]; ok {
			enablerEpics = append(enablerEpics, e)
		}
	}
	if len(enablerEpics) > 0 {
		lines = append(lines, `  ENABLER["Platform / Enabler"]:::enabler`)
		for _, e := range enablerEpics {
			epicEdge("ENABLER", e)
		}
	}

	var untracedEpics []map[string]any
	for _, fr := range goals.Untraced {
		if e, ok := epicByID[fr.ID()]; ok && !seen[fr.ID()] {
			untracedEpics = append(untracedEpics, e)
		}
	}
	if len(untracedEpics) > 0 {
		lines = append(lines, `  NOGOAL["No goal"]:::nogoal`)
		for _, e := range untracedEpics {
			epicEdge("NOGOAL", e)
		}
	}

	lines = append(lines,
		"  classDef goal fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
		"  classDef enabler fill:#3a3f4b,stroke:#7a8497,color:#ffffff,font-weight:bold;",
		"  classDef epic fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
		"  classDef usecase fill:#eef1f6,stroke:#9aa3b2,color:#15202e,stroke-dasharray:4 3;",
		"  classDef nogoal fill:#5a3d0c,stroke:#ffb454,color:#ffffff,stroke-width:2px,font-weight:bold;",
	)
	return strings.Join(lines, "\n"), drawn
}

// FRBuildingBlocks returns building blocks whose `drivers:` list names stem,
// sorted by ID (FR-047, #66).
func FRBuildingBlocks(stem string, blocks []*wiki.Page, byStem map[string]*wiki.Page) []*wiki.Page {
	var out []*wiki.Page
	for _, p := range SortedByID(blocks) {
		for _, drv := range wiki.LinksOf(p, "drivers", byStem) {
			if drv == stem {
				out = append(out, p)
				break
			}
		}
	}
	return out
}

// MermaidFRSubtree projects one FR's own Feature -> Story breakdown plus its
// linked building blocks for /functional-requirements/<stem> (FR-047, #66).
func MermaidFRSubtree(node map[string]any, blocks []*wiki.Page) (string, []map[string]any) {
	if node == nil {
		return "", nil
	}
	feats, _ := node["features"].([]map[string]any)
	ownStories, _ := node["stories"].([]map[string]any)
	direct, _ := node["direct_stories"].([]map[string]any)
	if len(feats) == 0 && len(ownStories) == 0 && len(direct) == 0 && len(blocks) == 0 {
		return "", nil
	}
	rid := DiagramNodeID(node["id"].(string))
	lines := []string{
		"graph TD",
		fmt.Sprintf(`  %s["%s<br/>%s"]:::root`, rid, node["id"].(string), CleanLabel(node["title"].(string), true)),
	}
	drawn := make([]map[string]any, 0)
	child := func(parentNID string, rec map[string]any, css string) string {
		nid := DiagramNodeID(rec["id"].(string))
		label := CleanLabel(rec["title"].(string), true)
		url := "/functional-requirements/" + rec["stem"].(string)
		lines = append(lines,
			fmt.Sprintf(`  %s --> %s["%s<br/>%s"]:::%s`, parentNID, nid, rec["id"].(string), label, css),
			fmt.Sprintf(`  click %s "%s"`, nid, url),
		)
		drawn = append(drawn, map[string]any{
			"id":    rec["id"].(string),
			"title": rec["title"].(string),
			"url":   url,
		})
		return nid
	}
	for _, f := range feats {
		fid := child(rid, f, "feature")
		stories, _ := f["stories"].([]map[string]any)
		for _, s := range stories {
			child(fid, s, "story")
		}
	}
	for _, s := range ownStories {
		child(rid, s, "story")
	}
	for _, s := range direct {
		child(rid, s, "story")
	}
	for _, b := range blocks {
		nid := DiagramNodeID(b.ID())
		lines = append(lines,
			fmt.Sprintf(`  %s -.-> %s[["%s<br/>%s"]]:::block`, rid, nid, b.ID(), CleanLabel(b.Title(), true)),
			fmt.Sprintf(`  click %s "%s"`, nid, wiki.PageURL(b.Folder, b.Stem)),
		)
		drawn = append(drawn, NodeLink(b))
	}
	lines = append(lines,
		"  classDef root fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
		"  classDef feature fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
		"  classDef story fill:#f3f6fb,stroke:#c4ccd9,color:#15202e;",
		"  classDef block fill:#e3efe6,stroke:#6f9b7c,color:#15202e;",
	)
	return strings.Join(lines, "\n"), drawn
}
