package wiki

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"gopkg.in/yaml.v3"
)

var (
	frontmatterRE   = regexp.MustCompile(`(?s)^---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n(.*))?$`)
	wikilinkRE      = regexp.MustCompile(`\[\[([^\]\|#]+)(?:#[^\]\|]+)?(?:\|([^\]]+))?\]\]`)
	refStartRE      = regexp.MustCompile(`^\[\[([^\]\|#]+)`)
	anyWikilinkRE   = regexp.MustCompile(`\[\[([^\]]+)\]\]`)
	inlineMDRE      = regexp.MustCompile(`\*\*([^*]+)\*\*|` + "`([^`]+)`" + `|\*([^*]+)\*`)
	visionHeadingRE = regexp.MustCompile(`##\s+Vision\b[^\n]*\n+`)
	nextH2RE        = regexp.MustCompile(`\n##\s`)
	whitespaceRE    = regexp.MustCompile(`\s+`)
)

// ArchFolders lists the four arc42 architecture content folders (A2-A5).
var ArchFolders = []string{"building-blocks", "concepts", "runtime-scenarios", "deployment-nodes"}

var archFolderSet = map[string]bool{
	"building-blocks":   true,
	"concepts":          true,
	"runtime-scenarios": true,
	"deployment-nodes":  true,
}

var validArchStates = map[string]bool{
	"outdated": true,
	"current":  true,
	"planned":  true,
	"target":   true,
}

// TypeFolder maps stem ID prefixes to their canonical wiki subfolder.
var TypeFolder = map[string]string{
	"DT": "domain-terms", "GLO": "glossary", "DM": "data-models", "STK": "stakeholders",
	"EIF": "external-interfaces", "GOAL": "goals", "CTX": "context",
	"FR": "functional-requirements", "CON": "constraints", "ISS": "issues",
	"UC": "functional-requirements", "ACT": "activity-models", "QR": "quality-requirements",
	"DR": "decisions", "BB": "building-blocks", "CC": "concepts",
	"RS": "runtime-scenarios", "DN": "deployment-nodes",
}

// TypeLabel maps stem ID prefixes to group labels for the relations and trace panels.
var TypeLabel = map[string]string{
	"DT": "Domain terms", "GLO": "Glossary", "STK": "Stakeholders", "DM": "Data models",
	"CTX": "Context", "EIF": "External interfaces", "GOAL": "Goals",
	"FR": "Functional requirements", "UC": "Use cases", "ACT": "Activity models",
	"QR": "Quality requirements", "CON": "Constraints", "DR": "Decisions",
	"BB": "Building blocks", "CC": "Concepts", "RS": "Runtime scenarios",
	"DN": "Deployment nodes", "ISS": "Issues",
}

// RelTypeOrder defines the group display order in relations and trace panels.
var RelTypeOrder = []string{
	"DT", "GLO", "STK", "DM", "CTX", "EIF", "GOAL", "FR", "UC", "ACT",
	"QR", "CON", "DR", "BB", "CC", "RS", "DN", "ISS",
}

// FolderLabels maps wiki subfolder names to display names, matching app.py.
var FolderLabels = map[string]string{
	"goals":                   "Goal",
	"context":                 "Context",
	"external-interfaces":     "External interface",
	"functional-requirements": "Functional requirement",
	"use-cases":               "Use case",
	"activity-models":         "Activity model",
	"data-models":             "Data model",
	"quality-requirements":    "Quality requirement",
	"constraints":             "Constraint",
	"glossary":                "Glossary term",
	"domain-terms":            "Domain term",
	"stakeholders":            "Stakeholder",
	"issues":                  "Issue",
	"decisions":               "Decision record",
	"building-blocks":         "Building block",
	"concepts":                "Crosscutting concept",
	"runtime-scenarios":       "Runtime scenario",
	"deployment-nodes":        "Deployment node",
}

// MaturityOrder is the four-step lifecycle order shown on every maturity bar.
var MaturityOrder = []string{"accepted", "review", "draft", "deprecated"}

var maturityAliases = map[string]string{
	"proposed":    "review",
	"in-progress": "review",
	"resolved":    "accepted",
	"ingested":    "accepted",
	"open":        "draft",
	"superseded":  "deprecated",
	"rejected":    "deprecated",
	"wontfix":     "deprecated",
}

var closedStatuses = map[string]bool{
	"resolved": true,
	"wontfix":  true,
}

var domainModelStereotypes = map[string]bool{
	"entity":       true,
	"value-object": true,
	"sum-type":     true,
}

var visionSkipPrefixes = []string{">", "<!--", "**Objectives.**", "*Optional:*"}

// Page represents one parsed markdown page with YAML frontmatter.
type Page struct {
	Stem    string
	Meta    map[string]any
	Body    string
	Folder  string
	ModTime time.Time

	targetsOnce sync.Once
	targets     map[string]struct{}
}

// ID returns frontmatter id, falling back to Stem when absent or blank.
func (p *Page) ID() string {
	if s := scalarString(p.Meta["id"]); s != "" {
		return s
	}
	return p.Stem
}

// Title returns frontmatter title, falling back to Stem when absent or blank.
func (p *Page) Title() string {
	v, ok := p.Meta["title"]
	if !ok || v == nil {
		return p.Stem
	}
	if s := scalarString(v); s != "" {
		return s
	}
	return p.Stem
}

// Status returns frontmatter status as text, or "" when unset.
func (p *Page) Status() string {
	return scalarString(p.Meta["status"])
}

// MetaString returns a frontmatter field as text, or "" when unset.
func (p *Page) MetaString(key string) string {
	return scalarString(p.Meta[key])
}

// AsList returns a list-valued frontmatter field as a slice, wrapping a single
// scalar value in a 1-element slice and treating nil or "" as empty.
func (p *Page) AsList(field string) []any {
	v, ok := p.Meta[field]
	if !ok || v == nil {
		return []any{}
	}
	if s, isStr := v.(string); isStr && s == "" {
		return []any{}
	}
	if list, isList := v.([]any); isList {
		return list
	}
	return []any{v}
}

// AsStringList returns AsList(field) with each item converted to text.
func (p *Page) AsStringList(field string) []string {
	raw := p.AsList(field)
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		out = append(out, scalarString(item))
	}
	return out
}

// Aliases returns non-empty alias strings from frontmatter.
func (p *Page) Aliases() []string {
	raw := p.AsList("aliases")
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		if s := scalarString(item); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// IsArchFolder reports whether folder is one of the four arc42 folders.
func IsArchFolder(folder string) bool {
	return archFolderSet[folder]
}

// PageState returns an architecture page's lifecycle state, defaulting to "target".
func PageState(p *Page) string {
	v := strings.ToLower(strings.TrimSpace(p.MetaString("state")))
	if validArchStates[v] {
		return v
	}
	return "target"
}

// TypeOf returns the ID prefix before the first '-', or stem itself.
func TypeOf(stem string) string {
	if i := strings.IndexByte(stem, '-'); i >= 0 {
		return stem[:i]
	}
	return stem
}

// Scalar unwraps nested lists produced by unquoted YAML `[[stem]]` links.
func Scalar(v any) any {
	for {
		list, ok := v.([]any)
		if !ok {
			return v
		}
		if len(list) == 0 {
			return ""
		}
		v = list[0]
	}
}

// ScalarString converts any YAML scalar to its display string (matching PyYAML).
func ScalarString(v any) string {
	return scalarString(v)
}

// StemFromRef extracts the page stem from '[[FR-009-foo]]' or a bare stem.
func StemFromRef(ref any) string {
	s := strings.TrimSpace(scalarString(ref))
	if m := refStartRE.FindStringSubmatch(s); m != nil {
		s = m[1]
	}
	parts := strings.Split(s, "/")
	return strings.TrimSpace(parts[len(parts)-1])
}

// StemOfLink extracts the target stem from a frontmatter link entry.
func StemOfLink(raw any) string {
	t := strings.TrimSpace(scalarString(raw))
	if m := anyWikilinkRE.FindStringSubmatch(t); m != nil {
		t = m[1]
	}
	if i := strings.IndexByte(t, '|'); i >= 0 {
		t = t[:i]
	}
	if i := strings.IndexByte(t, '#'); i >= 0 {
		t = t[:i]
	}
	t = strings.TrimSpace(t)
	parts := strings.Split(t, "/")
	return strings.TrimSpace(parts[len(parts)-1])
}

// LinksOf returns existing target stems referenced by page.Meta[field], in
// order without duplicates, handling unquoted YAML `[[stem]]` nested lists.
func LinksOf(page *Page, field string, byStem map[string]*Page) []string {
	var out []string
	seen := map[string]bool{}
	var walk func(v any)
	walk = func(v any) {
		if list, ok := v.([]any); ok {
			for _, x := range list {
				walk(x)
			}
			return
		}
		if v == nil {
			return
		}
		s := StemOfLink(v)
		if s != "" && byStem[s] != nil && !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	walk(page.Meta[field])
	return out
}

// StructTargets returns existing target stems named under keys in a
// structured-list field (such as steps: from/to), in order without duplicates.
func StructTargets(page *Page, field string, keys []string, byStem map[string]*Page) []string {
	entries, ok := page.Meta[field].([]any)
	if !ok {
		return nil
	}
	var out []string
	seen := map[string]bool{}
	for _, item := range entries {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		for _, k := range keys {
			v := Scalar(m[k])
			if v == nil {
				continue
			}
			s := StemOfLink(v)
			if s != "" && byStem[s] != nil && !seen[s] {
				seen[s] = true
				out = append(out, s)
			}
		}
	}
	return out
}

// IsWikiFolder reports whether folder is a direct, non-hidden subfolder of
// wikiDir whose resolved path stays inside wikiDir.
func IsWikiFolder(wikiDir, folder string) bool {
	if folder == "" || strings.HasPrefix(folder, ".") || strings.ContainsAny(folder, `/\`) {
		return false
	}
	d := filepath.Join(wikiDir, folder)
	st, err := os.Stat(d)
	if err != nil || !st.IsDir() {
		return false
	}
	return ResolvesInside(wikiDir, d)
}

// LoadPage reads and parses a single page wiki/<folder>/<stem>.md if it exists
// as a regular file and resolves inside WikiDir.
func (s *Store) LoadPage(folder, stem string) *Page {
	if stem == "" || stem == "." || stem == ".." || strings.ContainsAny(stem, `/\`) {
		return nil
	}
	p := filepath.Join(s.Paths.WikiDir, folder, stem+".md")
	st, err := os.Stat(p)
	if err != nil || !st.Mode().IsRegular() {
		return nil
	}
	return s.parse(p, folder)
}

// SourceIndex maps each source record's stem and ID to its Page (first wins).
func SourceIndex(sources []*Page) map[string]*Page {
	idx := make(map[string]*Page, len(sources)*2)
	for _, p := range sources {
		if _, exists := idx[p.Stem]; !exists {
			idx[p.Stem] = p
		}
		id := p.ID()
		if _, exists := idx[id]; !exists {
			idx[id] = p
		}
	}
	return idx
}

// LinkTargets returns distinct wiki page targets referenced in frontmatter or
// body, excluding self-references and raw/ or SRC- provenance links.
func (p *Page) LinkTargets() map[string]struct{} {
	p.targetsOnce.Do(func() {
		targets := map[string]struct{}{}
		scan := func(text string) {
			for _, m := range wikilinkRE.FindAllStringSubmatch(text, -1) {
				tgt := strings.TrimSpace(m[1])
				parts := strings.Split(tgt, "/")
				base := parts[len(parts)-1]
				if strings.HasPrefix(tgt, "raw/") || strings.HasPrefix(base, "SRC-") {
					continue
				}
				if base == p.Stem || base == p.ID() {
					continue
				}
				targets[base] = struct{}{}
			}
		}
		collectStrings(p.Meta, scan)
		scan(p.Body)
		p.targets = targets
	})
	return p.targets
}

func collectStrings(v any, fn func(string)) {
	switch x := v.(type) {
	case string:
		fn(x)
	case []any:
		for _, item := range x {
			collectStrings(item, fn)
		}
	case map[string]any:
		for _, item := range x {
			collectStrings(item, fn)
		}
	}
}

func scalarString(v any) string {
	if v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	case time.Time:
		if x.Hour() == 0 && x.Minute() == 0 && x.Second() == 0 && x.Nanosecond() == 0 && x.Location() == time.UTC {
			return x.Format("2006-01-02")
		}
		return x.Format(time.RFC3339)
	case bool:
		if x {
			return "True"
		}
		return "False"
	case int:
		return strconv.Itoa(x)
	case int64:
		return strconv.FormatInt(x, 10)
	case uint64:
		return strconv.FormatUint(x, 10)
	case float64:
		return strconv.FormatFloat(x, 'g', -1, 64)
	default:
		return fmt.Sprint(x)
	}
}

type fileStamp struct {
	mtimeNs int64
	size    int64
}

type cacheEntry struct {
	stamp fileStamp
	page  *Page
}

// Store reads wiki and source pages from disk and caches parsed pages keyed by
// (mtime_ns, size), matching app.py's _PARSE_CACHE.
type Store struct {
	Paths Paths

	mu    sync.RWMutex
	cache map[string]cacheEntry
}

// NewStore creates a Store for paths.
func NewStore(paths Paths) *Store {
	return &Store{
		Paths: paths,
		cache: map[string]cacheEntry{},
	}
}

// ClearCache drops every cached parsed page.
func (s *Store) ClearCache() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cache = map[string]cacheEntry{}
}

func (s *Store) forget(path string) {
	s.mu.Lock()
	delete(s.cache, path)
	s.mu.Unlock()
}

func (s *Store) forgetMissing(folder string, present []string) {
	keep := make(map[string]struct{}, len(present))
	for _, p := range present {
		keep[p] = struct{}{}
	}
	s.mu.Lock()
	for p := range s.cache {
		if filepath.Dir(p) == folder {
			if _, ok := keep[p]; !ok {
				delete(s.cache, p)
			}
		}
	}
	s.mu.Unlock()
}

func (s *Store) pageRoot(path string) string {
	absPath, _ := filepath.Abs(path)
	absSources, _ := filepath.Abs(s.Paths.SourcesDir)
	if Inside(absSources, absPath) {
		return s.Paths.SourcesDir
	}
	return s.Paths.WikiDir
}

func (s *Store) parse(path, folder string) *Page {
	// Checked before the cache: a symlink retargeted out of the wiki must not
	// keep serving what it pointed to before.
	if !ResolvesInside(s.pageRoot(path), path) {
		s.forget(path)
		return nil
	}
	st, err := os.Stat(path)
	if err != nil {
		s.forget(path)
		return nil
	}
	stamp := fileStamp{mtimeNs: st.ModTime().UnixNano(), size: st.Size()}

	s.mu.RLock()
	cached, ok := s.cache[path]
	s.mu.RUnlock()
	if ok && cached.stamp == stamp {
		return cached.page
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		s.forget(path)
		return nil
	}
	text := strings.ReplaceAll(sanitizeUTF8(raw), "\r\n", "\n")
	var page *Page
	if m := frontmatterRE.FindStringSubmatch(text); m != nil {
		meta := map[string]any{}
		var parsed any
		if err := yaml.Unmarshal([]byte(m[1]), &parsed); err == nil {
			if mm, ok := parsed.(map[string]any); ok {
				meta = mm
			}
		}
		stem := strings.TrimSuffix(filepath.Base(path), ".md")
		page = &Page{
			Stem:    stem,
			Meta:    meta,
			Body:    m[2],
			Folder:  folder,
			ModTime: st.ModTime(),
		}
	}

	s.mu.Lock()
	s.cache[path] = cacheEntry{stamp: stamp, page: page}
	s.mu.Unlock()
	return page
}

func sanitizeUTF8(b []byte) string {
	if utf8.Valid(b) {
		return string(b)
	}
	var out strings.Builder
	out.Grow(len(b))
	for len(b) > 0 {
		r, size := utf8.DecodeRune(b)
		out.WriteRune(r)
		b = b[size:]
	}
	return out.String()
}

func listMarkdownFiles(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var paths []string
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".md") {
			paths = append(paths, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(paths)
	return paths
}

// LoadFolder returns all valid parsed pages in wiki/<folder>, sorted by filename.
func (s *Store) LoadFolder(folder string) []*Page {
	d := filepath.Join(s.Paths.WikiDir, folder)
	var paths []string
	if st, err := os.Stat(d); err == nil && st.IsDir() && ResolvesInside(s.Paths.WikiDir, d) {
		paths = listMarkdownFiles(d)
	}
	s.forgetMissing(d, paths)
	out := make([]*Page, 0, len(paths))
	for _, p := range paths {
		if page := s.parse(p, folder); page != nil {
			out = append(out, page)
		}
	}
	return out
}

// LoadSources returns all valid provenance records from raw/sources/.
func (s *Store) LoadSources() []*Page {
	d := s.Paths.SourcesDir
	var paths []string
	if st, err := os.Stat(d); err == nil && st.IsDir() {
		paths = listMarkdownFiles(d)
	}
	s.forgetMissing(d, paths)
	out := make([]*Page, 0, len(paths))
	for _, p := range paths {
		if page := s.parse(p, "sources"); page != nil {
			out = append(out, page)
		}
	}
	return out
}

// LoadAllPages returns every valid wiki page across all sorted subfolders of WikiDir.
func (s *Store) LoadAllPages() []*Page {
	entries, err := os.ReadDir(s.Paths.WikiDir)
	if err != nil {
		return nil
	}
	var folders []string
	for _, e := range entries {
		p := filepath.Join(s.Paths.WikiDir, e.Name())
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			folders = append(folders, e.Name())
		}
	}
	sort.Strings(folders)
	var out []*Page
	for _, f := range folders {
		out = append(out, s.LoadFolder(f)...)
	}
	return out
}

// PageURL returns the canonical dashboard URL for a wiki page.
func PageURL(folder, stem string) string {
	if folder == "functional-requirements" {
		return "/functional-requirements/" + stem
	}
	return "/page/" + folder + "/" + stem
}

// IsOpenIssue reports whether status represents an open issue.
func IsOpenIssue(status string) bool {
	return !closedStatuses[strings.ToLower(strings.TrimSpace(status))]
}

// TitleIndex maps each page stem to its display title.
func TitleIndex(pages []*Page) map[string]string {
	idx := make(map[string]string, len(pages))
	for _, p := range pages {
		idx[p.Stem] = p.Title()
	}
	return idx
}

// PageRef identifies a wiki page by folder and stem.
type PageRef struct {
	Folder string
	Stem   string
}

// LinkIndex maps each page's stem and ID to its PageRef (first writer wins).
func LinkIndex(pages []*Page) map[string]PageRef {
	idx := make(map[string]PageRef, len(pages)*2)
	for _, p := range pages {
		ref := PageRef{Folder: p.Folder, Stem: p.Stem}
		if _, exists := idx[p.Stem]; !exists {
			idx[p.Stem] = ref
		}
		id := p.ID()
		if _, exists := idx[id]; !exists {
			idx[id] = ref
		}
	}
	return idx
}

// OpenIssueCounts maps wiki folder -> set of open issue IDs linking to pages in
// that folder, matching app.py's open_issue_counts().
func OpenIssueCounts(issues []*Page, links map[string]PageRef) map[string]map[string]struct{} {
	out := map[string]map[string]struct{}{}
	for _, iss := range issues {
		if !IsOpenIssue(iss.Status()) {
			continue
		}
		folders := map[string]struct{}{}
		for tgt := range iss.LinkTargets() {
			if ref, ok := links[tgt]; ok {
				folders[ref.Folder] = struct{}{}
			}
		}
		id := iss.ID()
		for f := range folders {
			if out[f] == nil {
				out[f] = map[string]struct{}{}
			}
			out[f][id] = struct{}{}
		}
	}
	return out
}

// MaturitySegment is one segment in the stacked maturity bar.
type MaturitySegment struct {
	Status string
	N      int
	Pct    int
}

// MaturitySummary holds total count, segments, and tooltip label.
type MaturitySummary struct {
	Total    int
	Segments []MaturitySegment
	Label    string
}

// ToMap converts MaturitySummary into the dict shape expected by _maturity.html.
func (m MaturitySummary) ToMap() map[string]any {
	segs := make([]map[string]any, 0, len(m.Segments))
	for _, s := range m.Segments {
		segs = append(segs, map[string]any{
			"status": s.Status,
			"n":      s.N,
			"pct":    s.Pct,
		})
	}
	return map[string]any{
		"total":    m.Total,
		"segments": segs,
		"label":    m.Label,
	}
}

// ComputeMaturity buckets statuses into MaturityOrder using round-half-to-even
// percentages, matching app.py's maturity().
func ComputeMaturity(statuses []string) MaturitySummary {
	counts := map[string]int{
		"accepted":   0,
		"review":     0,
		"draft":      0,
		"deprecated": 0,
	}
	for _, raw := range statuses {
		s := strings.ToLower(strings.TrimSpace(raw))
		if aliased, ok := maturityAliases[s]; ok {
			s = aliased
		}
		if _, ok := counts[s]; ok {
			counts[s]++
		} else {
			counts["draft"]++
		}
	}
	total := 0
	for _, n := range counts {
		total += n
	}
	var segs []MaturitySegment
	var parts []string
	for _, k := range MaturityOrder {
		n := counts[k]
		if n == 0 {
			continue
		}
		pct := int(math.RoundToEven(100.0 * float64(n) / float64(total)))
		segs = append(segs, MaturitySegment{Status: k, N: n, Pct: pct})
		parts = append(parts, fmt.Sprintf("%d %s", n, k))
	}
	label := "nothing yet"
	if len(parts) > 0 {
		label = strings.Join(parts, " · ")
	}
	return MaturitySummary{Total: total, Segments: segs, Label: label}
}

// RelativeWhen formats ts relative to now in loc, matching _relative_when().
func RelativeWhen(ts, now time.Time, loc *time.Location) string {
	if loc == nil {
		loc = time.Local
	}
	d := int(now.Sub(ts).Seconds())
	if d < 0 {
		d = 0
	}
	if d < 60 {
		return "just now"
	}
	if d < 3600 {
		return fmt.Sprintf("%d min ago", d/60)
	}
	if d < 86400 {
		return fmt.Sprintf("%d h ago", d/3600)
	}
	return ts.In(loc).Format("2006-01-02")
}

// RecentChanges returns the n most recently modified pages as template dicts.
func RecentChanges(pages []*Page, n int, now time.Time, loc *time.Location) []map[string]any {
	cp := make([]*Page, len(pages))
	copy(cp, pages)
	sort.SliceStable(cp, func(i, j int) bool {
		return cp[i].ModTime.After(cp[j].ModTime)
	})
	if n > 0 && len(cp) > n {
		cp = cp[:n]
	}
	out := make([]map[string]any, 0, len(cp))
	for _, p := range cp {
		kind := FolderLabels[p.Folder]
		if kind == "" {
			kind = p.Folder
		}
		out = append(out, map[string]any{
			"id":    p.ID(),
			"title": p.Title(),
			"kind":  kind,
			"url":   PageURL(p.Folder, p.Stem),
			"when":  RelativeWhen(p.ModTime, now, loc),
		})
	}
	return out
}

// VaultStatus builds the status strip summary for the home page valley.
func VaultStatus(allPages, issues, sources []*Page, now time.Time, loc *time.Location) map[string]any {
	openCount := 0
	for _, iss := range issues {
		if IsOpenIssue(iss.Status()) {
			openCount++
		}
	}
	var last time.Time
	for _, p := range allPages {
		if p.ModTime.After(last) {
			last = p.ModTime
		}
	}
	lastStr := "—"
	if !last.IsZero() {
		lastStr = RelativeWhen(last, now, loc)
	}
	return map[string]any{
		"pages":       len(allPages),
		"open_issues": openCount,
		"sources":     len(sources),
		"last_change": lastStr,
	}
}

// DataModelPages returns data-models/ plus structured domain-terms/ pages
// (stereotype entity | value-object | sum-type), sorted by ID.
func DataModelPages(dataModels, domainTerms []*Page) []*Page {
	out := make([]*Page, 0, len(dataModels))
	out = append(out, dataModels...)
	for _, p := range domainTerms {
		st := strings.ToLower(strings.TrimSpace(p.MetaString("stereotype")))
		if domainModelStereotypes[st] {
			out = append(out, p)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].ID() < out[j].ID()
	})
	return out
}

// SupportingModelCount returns the R4 tile headline count: data model pages
// plus activity model pages.
func SupportingModelCount(dataModels, domainTerms, activityModels []*Page) int {
	return len(DataModelPages(dataModels, domainTerms)) + len(activityModels)
}

// VisionPage returns the lowest-ID goal page with stereotype: vision, or nil.
func VisionPage(goals []*Page) *Page {
	cp := make([]*Page, len(goals))
	copy(cp, goals)
	sort.SliceStable(cp, func(i, j int) bool {
		return cp[i].ID() < cp[j].ID()
	})
	for _, p := range cp {
		if strings.ToLower(strings.TrimSpace(p.MetaString("stereotype"))) == "vision" {
			return p
		}
	}
	return nil
}

// StripInlineMarkdown removes **bold**, `code`, and *italic* wrappers.
func StripInlineMarkdown(text string) string {
	res := inlineMDRE.ReplaceAllStringFunc(text, func(match string) string {
		sub := inlineMDRE.FindStringSubmatch(match)
		if sub[1] != "" {
			return sub[1]
		}
		if sub[2] != "" {
			return sub[2]
		}
		return sub[3]
	})
	return strings.TrimSpace(res)
}

// VisionSentence extracts the first plain-text sentence under `## Vision`,
// matching app.py's vision_sentence().
func VisionSentence(page *Page, titles map[string]string) string {
	if page == nil {
		return ""
	}
	loc := visionHeadingRE.FindStringIndex(page.Body)
	if loc == nil {
		return ""
	}
	rest := page.Body[loc[1]:]
	if end := nextH2RE.FindStringIndex(rest); end != nil {
		rest = rest[:end[0]]
	}
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
		collapsed := whitespaceRE.ReplaceAllString(para, " ")
		resolved := wikilinkRE.ReplaceAllStringFunc(collapsed, func(match string) string {
			sub := wikilinkRE.FindStringSubmatch(match)
			if sub[2] != "" {
				return strings.TrimSpace(sub[2])
			}
			rawTarget := strings.TrimSpace(sub[1])
			parts := strings.Split(rawTarget, "/")
			base := parts[len(parts)-1]
			if title, ok := titles[base]; ok {
				return strings.TrimSpace(title)
			}
			return strings.TrimSpace(sub[1])
		})
		text := StripInlineMarkdown(resolved)
		return strings.TrimSpace(firstSentence(text))
	}
	return ""
}

// firstSentence matches Python's `^(.+?[.!?])(?=\s+[^a-z\s]|\s*$)`: a sentence
// ends at '.', '!' or '?' followed by end-of-string (ignoring trailing space)
// or by whitespace and a character that is not ASCII lowercase [a-z].
func firstSentence(text string) string {
	for i := 1; i < len(text); i++ {
		c := text[i]
		if c != '.' && c != '!' && c != '?' {
			continue
		}
		after := text[i+1:]
		trimmed := strings.TrimLeftFunc(after, unicode.IsSpace)
		if trimmed == "" {
			return text[:i+1]
		}
		if len(trimmed) < len(after) {
			r, _ := utf8.DecodeRuneInString(trimmed)
			if !(r >= 'a' && r <= 'z') {
				return text[:i+1]
			}
		}
	}
	return text
}
