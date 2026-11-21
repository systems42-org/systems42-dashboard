package web

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"hash/crc32"
	"io"
	"io/fs"
	"log"
	"mime"
	"net"
	"net/http"
	"os"
	"path"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/session"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

const (
	fileCSP  = "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"
	introCSP = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; sandbox allow-scripts; frame-ancestors 'self'"
)

const pageCSPTemplate = "default-src 'self'; script-src 'self' 'nonce-%s'; " +
	"style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; " +
	"font-src 'self' data:; connect-src 'self'; frame-src 'self'; " +
	"object-src 'none'; base-uri 'none'; form-action 'self'; " +
	"frame-ancestors 'none'"

const introDoneScript = `<script>
(function () {
  function shown(el) { return !el.hidden && getComputedStyle(el).display !== "none"; }
  function check() {
    var parts = document.body.querySelectorAll(":scope > :not(style):not(script)");
    if (!Array.prototype.some.call(parts, shown)) parent.postMessage("brand-intro-done", "*");
  }
  new MutationObserver(check).observe(document.body, { childList: true });
  setTimeout(check, 100);
})();
</script>`

var themeTokensRE = regexp.MustCompile(`(?ms)^:root(?:\[data-theme="light"\])? \{.*?^\}`)

func init() {
	_ = mime.AddExtensionType(".webp", "image/webp")
}

// Options configures a dashboard HTTP Server.
type Options struct {
	Paths       wiki.Paths
	StaticFS    fs.FS
	TemplatesFS fs.FS
	BrandsFS    fs.FS
	Version     string
	DisplayTZ   string
	PublicURL   string
	Logger      *log.Logger
	Now         func() time.Time
	OnShutdown  func(reason string)
}

// Server serves the Systems42 dashboard over net/http.
type Server struct {
	Paths      wiki.Paths
	Store      *wiki.Store
	Metamodel  *metamodel.Reader
	Session    *session.Tracker
	Templates  *Engine
	StaticFS   fs.FS
	BrandsFS   fs.FS
	Version    string
	DisplayTZ  string
	PublicURL  string
	Logger     *log.Logger
	Now        func() time.Time
	OnShutdown func(reason string)

	staticHashes map[string]string
	themeTokens  string

	warnMu sync.Mutex
	warned map[string]bool

	viewMu     sync.RWMutex
	viewHidden []string
}

// NewServer initializes a Server with embedded assets and template engine.
func NewServer(opts Options) *Server {
	logger := opts.Logger
	if logger == nil {
		logger = log.New(os.Stderr, "", log.LstdFlags)
	}
	nowFn := opts.Now
	if nowFn == nil {
		nowFn = time.Now
	}

	s := &Server{
		Paths:        opts.Paths,
		Store:        wiki.NewStore(opts.Paths),
		Metamodel:    metamodel.NewReader(opts.Paths.MetamodelDir, opts.Paths.NotationsDir, opts.Paths.AnchorsDir),
		Session:      session.NewTracker(session.Options{Now: nowFn}),
		StaticFS:     opts.StaticFS,
		BrandsFS:     opts.BrandsFS,
		Version:      strings.TrimSpace(opts.Version),
		DisplayTZ:    opts.DisplayTZ,
		PublicURL:    strings.TrimSpace(opts.PublicURL),
		Logger:       logger,
		Now:          nowFn,
		OnShutdown:   opts.OnShutdown,
		staticHashes: computeStaticHashes(opts.StaticFS),
		themeTokens:  extractThemeTokens(opts.StaticFS),
		warned:       map[string]bool{},
	}

	s.Templates = NewEngine(opts.TemplatesFS, EngineFuncs{
		StaticURL: s.staticURL,
		ListSpec:  s.listSpec,
	})
	return s
}

func computeStaticHashes(fsys fs.FS) map[string]string {
	out := map[string]string{}
	if fsys == nil {
		return out
	}
	_ = fs.WalkDir(fsys, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if b, err := fs.ReadFile(fsys, p); err == nil {
			out[p] = fmt.Sprintf("%08x", crc32.ChecksumIEEE(b))
		}
		return nil
	})
	return out
}

func extractThemeTokens(fsys fs.FS) string {
	if fsys == nil {
		return ""
	}
	b, err := fs.ReadFile(fsys, "style.css")
	if err != nil {
		return ""
	}
	return strings.Join(themeTokensRE.FindAllString(string(b), -1), "\n")
}

func (s *Server) staticURL(filename string) string {
	clean := strings.TrimPrefix(path.Clean("/"+filename), "/")
	u := "/static/" + clean
	if v, ok := s.staticHashes[clean]; ok {
		return u + "?v=" + v
	}
	return u
}

func (s *Server) listSpec(typeName string) map[string]any {
	raw := s.Metamodel.SortOrders(typeName)
	orders := make([]map[string]any, 0, len(raw))
	for _, o := range raw {
		orders = append(orders, map[string]any{
			"label": o.Label,
			"keys":  o.Keys,
		})
	}
	return map[string]any{
		"type":   typeName,
		"orders": orders,
	}
}

func (s *Server) warnOnce(msg string) {
	s.warnMu.Lock()
	already := s.warned[msg]
	s.warned[msg] = true
	s.warnMu.Unlock()
	if !already {
		s.Logger.Printf("WARNING: %s", msg)
	}
}

func (s *Server) location() *time.Location {
	if s.DisplayTZ != "" {
		if loc, err := time.LoadLocation(s.DisplayTZ); err == nil {
			return loc
		}
	}
	return time.Local
}

func (s *Server) isHidden(cat *metamodel.Catalog, keyOrID string) bool {
	s.viewMu.RLock()
	hidden := s.viewHidden
	s.viewMu.RUnlock()
	if len(hidden) == 0 {
		return false
	}
	set := make(map[string]bool, len(hidden))
	for _, k := range hidden {
		set[k] = true
	}
	if set[keyOrID] {
		return true
	}
	if sec, ok := cat.ByID[keyOrID]; ok {
		return set[sec.Area]
	}
	return false
}

// ServeHTTP dispatches all dashboard routes.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	p := r.URL.Path
	if r.Method == http.MethodPost {
		switch p {
		case "/ping":
			s.handlePing(w, r)
		case "/leaving":
			s.handleLeaving(w, r)
		case "/reload":
			s.handleReload(w, r)
		case "/disconnect-all":
			s.handleDisconnectAll(w, r)
		default:
			s.handleNotFound(w, r)
		}
		return
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		s.handleNotFound(w, r)
		return
	}
	switch {
	case p == "/":
		s.handleIndex(w, r)
	case p == "/req42":
		s.handleArea(w, r, "requirements")
	case p == "/arc42":
		s.handleArea(w, r, "architecture")
	case p == "/commons":
		s.handleArea(w, r, "commons")
	case p == "/req42/functional-requirements":
		s.handleFunctionalRequirements(w, r)
	case p == "/req42/backlog":
		s.redirect(w, r, "/req42/functional-requirements", http.StatusMovedPermanently)
	case strings.HasPrefix(p, "/req42/"):
		s.handleReq42Block(w, r)
	case strings.HasPrefix(p, "/functional-requirements/"):
		s.handleFRDetail(w, r)
	case p == "/goals":
		s.handleGoals(w, r)
	case p == "/entity-diagram":
		s.handleEntityDiagram(w, r)
	case p == "/data-model":
		s.handleLegacyRedirect(w, r, "/entity-diagram")
	case p == "/graph/domain-terms":
		s.handleGlossaryGraph(w, r)
	case p == "/graph/glossary":
		s.handleLegacyRedirect(w, r, "/graph/domain-terms")
	case p == "/arc42/building-blocks":
		s.handleBuildingBlocks(w, r)
	case p == "/arc42/concepts":
		s.handleConcepts(w, r)
	case p == "/arc42/runtime":
		s.handleRuntime(w, r)
	case p == "/arc42/deployment":
		s.handleDeployment(w, r)
	case strings.HasPrefix(p, "/section/"):
		s.handleSection(w, r)
	case p == "/metamodel":
		s.handleMetamodel(w, r)
	case p == "/method":
		s.handleMethod(w, r)
	case p == "/changes":
		s.handleChanges(w, r)
	case p == "/domain-terms":
		s.handleDomainTerms(w, r)
	case p == "/glossary":
		s.handleLegacyRedirect(w, r, "/domain-terms")
	case p == "/stakeholders":
		s.handleStakeholders(w, r)
	case p == "/decisions":
		s.handleDecisions(w, r)
	case p == "/adrs":
		s.redirect(w, r, "/decisions", http.StatusMovedPermanently)
	case p == "/issues":
		s.handleIssues(w, r)
	case strings.HasPrefix(p, "/page/"):
		s.handlePageDetail(w, r)
	case strings.HasPrefix(p, "/source/"):
		s.handleSourceDetail(w, r)
	case p == "/presence/count":
		s.handlePresenceCount(w, r)
	case p == "/presence/list":
		s.handlePresenceList(w, r)
	case strings.HasPrefix(p, "/static/"):
		s.handleStatic(w, r)
	case p == "/brand/intro.html":
		s.handleBrandIntro(w, r)
	case strings.HasPrefix(p, "/brand/") && !strings.Contains(strings.TrimPrefix(p, "/brand/"), "/"):
		s.handleBrandMark(w, r, strings.TrimPrefix(p, "/brand/"))
	default:
		s.handleNotFound(w, r)
	}
}

func generateNonce() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	return base64.RawURLEncoding.EncodeToString(b[:])
}

func (s *Server) readBrandBytes(src wiki.BrandSource, name string) ([]byte, bool) {
	if src.ShippedName != "" {
		b, err := fs.ReadFile(s.BrandsFS, path.Join(src.ShippedName, name))
		if err != nil {
			return nil, false
		}
		return b, true
	}
	p := wiki.BrandFileOnDisk(src.Dir, name)
	if p == "" {
		return nil, false
	}
	b, err := os.ReadFile(p)
	if err != nil {
		return nil, false
	}
	return b, true
}

func (s *Server) brandURL(src wiki.BrandSource, name string) string {
	b, ok := s.readBrandBytes(src, name)
	if !ok {
		return "/brand/" + name
	}
	return fmt.Sprintf("/brand/%s?v=%08x", name, crc32.ChecksumIEEE(b))
}

func (s *Server) hasBrandFile(src wiki.BrandSource, name string) bool {
	_, ok := s.readBrandBytes(src, name)
	return ok
}

type navEntry struct {
	key   string
	href  string
	label string
}

func (s *Server) navEntries(cat *metamodel.Catalog) []navEntry {
	out := make([]navEntry, 0, 5)
	for _, key := range []string{"requirements", "architecture"} {
		a := metamodel.AreaByKey[key]
		out = append(out, navEntry{key: key, href: a.Href, label: a.Label})
	}
	for _, sid := range []string{"C5", "C7", "C6"} {
		if sec, ok := cat.ByID[sid]; ok && sec.Href != "" {
			out = append(out, navEntry{key: sid, href: sec.Href, label: sec.Title})
		}
	}
	return out
}

func (s *Server) navCurrent(cat *metamodel.Catalog, entries []navEntry, entry navEntry, reqPath string, area metamodel.Area, hasArea bool) bool {
	here, hasHere := cat.SectionForPath(reqPath)
	if _, isArea := metamodel.AreaByKey[entry.key]; isArea {
		own := false
		if hasHere {
			for _, e := range entries {
				if e.key == here.ID && !s.isHidden(cat, e.key) {
					own = true
					break
				}
			}
		}
		return hasArea && area.Key == entry.key && !own
	}
	return (hasHere && here.ID == entry.key) || strings.HasPrefix(reqPath, entry.href)
}

func (s *Server) baseContext(r *http.Request, cat *metamodel.Catalog, nonce string, now time.Time) map[string]any {
	loc := s.location()
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	brandSrc := wiki.ResolveBrand(s.Paths.RepoDir, cfg.Brand, s.warnOnce)

	introURL := ""
	if cfg.Intro && s.hasBrandFile(brandSrc, wiki.BrandIntroFile) {
		introURL = s.brandURL(brandSrc, wiki.BrandIntroFile)
	}

	differs := cfg.DashboardVersion != "" && cfg.DashboardVersion != "local" && cfg.DashboardVersion != s.Version

	area, hasArea := cat.AreaForPath(r.URL.Path)
	var currentArea any
	if hasArea && !s.isHidden(cat, area.Key) {
		currentArea = area.ToMap()
	}

	entries := s.navEntries(cat)
	navItems := make([][]any, 0, len(entries))
	for _, e := range entries {
		if s.isHidden(cat, e.key) {
			continue
		}
		navItems = append(navItems, []any{e.href, e.label, s.navCurrent(cat, entries, e, r.URL.Path, area, hasArea)})
	}

	return map[string]any{
		"request": map[string]any{"path": r.URL.Path},
		"csp_nonce": func() string {
			return nonce
		},
		"refreshed_at":              now.In(loc).Format("2006-01-02 15:04:05h"),
		"brand":                     cfg.Brand,
		"intro":                     cfg.Intro,
		"dashboard_version":         cfg.DashboardVersion,
		"dashboard_version_own":     s.Version,
		"dashboard_version_differs": differs,
		"system_name":               cfg.SystemName,
		"system_name_set":           cfg.SystemNameSet,
		"tagline":                   cfg.Tagline,
		"about_href":                cfg.AboutHref,
		"about_label":               cfg.AboutLabel,
		"default_notation":          cfg.DefaultNotation,
		"active_brand": map[string]any{
			"mark_dark":  s.brandURL(brandSrc, "mark-dark.svg"),
			"mark_light": s.brandURL(brandSrc, "mark-light.svg"),
			"favicon":    s.brandURL(brandSrc, "favicon.svg"),
			"intro_url":  introURL,
		},
		"metamodel_check": s.Metamodel.VersionCheck().ToMap(),
		"current_area":    currentArea,
		"nav_items":       navItems,
		"stack_badge": map[string]any{
			"label":      "Go",
			"title":      "Built with Go",
			"icon":       "go-logo.svg",
			"icon_class": "stack-icon-go",
			"width":      45,
			"height":     18,
		},
	}
}

func (s *Server) renderHTML(w http.ResponseWriter, r *http.Request, status int, tplName string, cat *metamodel.Catalog, extra map[string]any, now time.Time) {
	nonce := generateNonce()
	ctx := s.baseContext(r, cat, nonce, now)
	for k, v := range extra {
		ctx[k] = v
	}
	var buf bytes.Buffer
	if err := s.Templates.Render(&buf, tplName, ctx); err != nil {
		s.Logger.Printf("ERROR rendering %s: %v", tplName, err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", fmt.Sprintf(pageCSPTemplate, nonce))
	w.Header().Set("X-Frame-Options", "DENY")
	w.WriteHeader(status)
	if r.Method != http.MethodHead {
		_, _ = w.Write(buf.Bytes())
	}
}

func (s *Server) redirect(w http.ResponseWriter, r *http.Request, target string, code int) {
	w.Header().Set("Content-Security-Policy", fmt.Sprintf(pageCSPTemplate, generateNonce()))
	w.Header().Set("X-Frame-Options", "DENY")
	http.Redirect(w, r, target, code)
}

func (s *Server) publicURL(r *http.Request) string {
	if s.PublicURL != "" {
		return strings.TrimRight(s.PublicURL, "/")
	}
	_, port, _ := net.SplitHostPort(r.Host)
	if ip := lanIP(); ip != "" {
		if port != "" {
			return fmt.Sprintf("http://%s:%s", ip, port)
		}
		return "http://" + ip
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	return strings.TrimRight(fmt.Sprintf("%s://%s", scheme, r.Host), "/")
}

func lanIP() string {
	conn, err := net.DialTimeout("udp", "10.255.255.255:1", 200*time.Millisecond)
	if err != nil {
		return ""
	}
	defer conn.Close()
	if addr, ok := conn.LocalAddr().(*net.UDPAddr); ok && addr.IP != nil {
		return addr.IP.String()
	}
	return ""
}

// --- Request snapshot (Tier 2 per-request cache, matching _request_cached) --

type requestSnapshot struct {
	store       *wiki.Store
	folders     map[string][]*wiki.Page
	allPages    []*wiki.Page
	allLoaded   bool
	sources     []*wiki.Page
	srcLoaded   bool
	pagesByStem map[string]*wiki.Page
	srcIndex    map[string]*wiki.Page
	anchors     map[string]metamodel.Anchor
	links       map[string]wiki.PageRef
	titles      map[string]string
	flags       map[string]map[string]struct{}
}

func newSnapshot(store *wiki.Store) *requestSnapshot {
	return &requestSnapshot{
		store:   store,
		folders: map[string][]*wiki.Page{},
	}
}

func (sn *requestSnapshot) folder(name string) []*wiki.Page {
	if pages, ok := sn.folders[name]; ok {
		return pages
	}
	pages := sn.store.LoadFolder(name)
	sn.folders[name] = pages
	return pages
}

func (sn *requestSnapshot) all() []*wiki.Page {
	if !sn.allLoaded {
		sn.allPages = sn.store.LoadAllPages()
		sn.allLoaded = true
	}
	return sn.allPages
}

func (sn *requestSnapshot) loadSources() []*wiki.Page {
	if !sn.srcLoaded {
		sn.sources = sn.store.LoadSources()
		sn.srcLoaded = true
	}
	return sn.sources
}

func (sn *requestSnapshot) titleIndex() map[string]string {
	if sn.titles == nil {
		sn.titles = wiki.TitleIndex(sn.all())
	}
	return sn.titles
}

func (sn *requestSnapshot) linkIndex() map[string]wiki.PageRef {
	if sn.links == nil {
		sn.links = wiki.LinkIndex(sn.all())
	}
	return sn.links
}

func (sn *requestSnapshot) openIssueCounts() map[string]map[string]struct{} {
	if sn.flags == nil {
		sn.flags = wiki.OpenIssueCounts(sn.folder("issues"), sn.linkIndex())
	}
	return sn.flags
}

func unionIssueCount(flags map[string]map[string]struct{}, folders []string, skipIssues bool) int {
	seen := map[string]struct{}{}
	for _, f := range folders {
		if skipIssues && f == "issues" {
			continue
		}
		for id := range flags[f] {
			seen[id] = struct{}{}
		}
	}
	return len(seen)
}

func statusesOf(pages []*wiki.Page) []string {
	out := make([]string, len(pages))
	for i, p := range pages {
		out[i] = p.Status()
	}
	return out
}

func buildSectionTile(sn *requestSnapshot, sec metamodel.Section) map[string]any {
	folders := metamodel.SectionFolders(sec)
	var hrefVal any
	if sec.Href != "" {
		hrefVal = sec.Href
	}
	t := map[string]any{
		"key":       strings.ToLower(sec.ID),
		"id":        sec.ID,
		"label":     sec.Title,
		"eyebrow":   fmt.Sprintf("%s · %s", sec.ID, sec.Title),
		"href":      hrefVal,
		"folders":   folders,
		"scope":     sec.Scope,
		"colors":    sec.Colors,
		"note":      sec.Note,
		"links":     []any{},
		"active":    sec.Scope == "in",
		"unit":      "page",
		"unit_many": nil,
		"count":     0,
	}
	if sec.Scope != "in" {
		t["maturity"] = wiki.ComputeMaturity(nil).ToMap()
		t["open_issues"] = 0
		return t
	}
	var pages []*wiki.Page
	for _, f := range folders {
		pages = append(pages, sn.folder(f)...)
	}
	flags := sn.openIssueCounts()
	t["count"] = len(pages)
	t["maturity"] = wiki.ComputeMaturity(statusesOf(pages)).ToMap()
	t["open_issues"] = unionIssueCount(flags, folders, false)
	t["open_issues_href"] = "/issues?section=" + sec.ID
	t["open_issues_title"] = "Show the open issues that point at pages of this section"

	switch sec.ID {
	case "R1":
		t["unit"] = "goal"
	case "R3":
		t["unit"] = "requirement"
	case "R4":
		t["unit"] = "model page"
		t["count"] = wiki.SupportingModelCount(
			sn.folder("data-models"),
			sn.folder("domain-terms"),
			sn.folder("activity-models"),
		)
	case "C1":
		t["unit"] = "scenario"
	case "C2":
		t["unit"] = "constraint"
	case "C3":
		t["unit"] = "external interface"
		t["count"] = len(sn.folder("external-interfaces"))
	case "C4":
		t["unit"] = "persona"
	case "C5":
		t["unit"] = "term"
		t["links"] = []map[string]any{
			{"label": "Table", "href": "/domain-terms"},
			{"label": "Term network", "href": "/graph/domain-terms"},
		}
	case "C6":
		openN := 0
		for _, p := range pages {
			if wiki.IsOpenIssue(p.Status()) {
				openN++
			}
		}
		t["unit"] = "issue"
		t["open_issues"] = openN
		t["open_issues_href"] = "/issues?status=open"
		t["open_issues_title"] = "Show the open issues"
	}
	return t
}

func (s *Server) buildAreaTile(sn *requestSnapshot, cat *metamodel.Catalog, area metamodel.Area) map[string]any {
	var sections []metamodel.Section
	for _, sec := range cat.SectionsOf(area.Key) {
		if !s.isHidden(cat, sec.ID) {
			sections = append(sections, sec)
		}
	}
	var folders []string
	var pages []*wiki.Page
	tiles := map[string]map[string]any{}
	allPlanned := true
	for _, sec := range sections {
		if sec.Scope != "planned" {
			allPlanned = false
		}
		for _, f := range metamodel.SectionFolders(sec) {
			folders = append(folders, f)
			pages = append(pages, sn.folder(f)...)
		}
		if sec.Scope == "in" {
			tiles[sec.ID] = buildSectionTile(sn, sec)
		}
	}
	flags := sn.openIssueCounts()

	secMaps := make([]map[string]any, 0, len(sections))
	for _, sec := range sections {
		var hrefVal any
		if sec.Href != "" {
			hrefVal = sec.Href
		}
		m := map[string]any{
			"id":    sec.ID,
			"title": sec.Title,
			"href":  hrefVal,
			"scope": sec.Scope,
		}
		if tile, ok := tiles[sec.ID]; ok {
			m["count"] = tile["count"]
			m["unit"] = tile["unit"]
			m["unit_many"] = tile["unit_many"]
		}
		secMaps = append(secMaps, m)
	}

	return map[string]any{
		"key":         area.Key,
		"label":       area.Label,
		"subtitle":    area.Subtitle,
		"href":        area.Href,
		"colors":      area.Colors,
		"count":       len(pages),
		"maturity":    wiki.ComputeMaturity(statusesOf(pages)).ToMap(),
		"open_issues": unionIssueCount(flags, folders, true),
		"sections":    secMaps,
		"planned":     len(sections) == 0 || allPlanned,
	}
}

var severityOrder = map[string]int{
	"blocker": 0,
	"major":   1,
	"minor":   2,
}

func severityKey(sev string) int {
	if r, ok := severityOrder[sev]; ok {
		return r
	}
	return 3
}

func (s *Server) buildValley(sn *requestSnapshot, now time.Time) map[string]any {
	loc := s.location()
	issues := sn.folder("issues")
	var open []*wiki.Page
	for _, iss := range issues {
		if wiki.IsOpenIssue(iss.Status()) {
			open = append(open, iss)
		}
	}
	sort.SliceStable(open, func(i, j int) bool {
		ri := severityKey(open[i].MetaString("severity"))
		rj := severityKey(open[j].MetaString("severity"))
		if ri != rj {
			return ri < rj
		}
		return open[i].ID() < open[j].ID()
	})
	limit := 5
	if len(open) < limit {
		limit = len(open)
	}
	openMaps := make([]map[string]any, 0, limit)
	for _, iss := range open[:limit] {
		openMaps = append(openMaps, map[string]any{
			"id":       iss.ID(),
			"title":    iss.Title(),
			"stem":     iss.Stem,
			"url":      wiki.PageURL("issues", iss.Stem),
			"severity": iss.MetaString("severity"),
		})
	}
	return map[string]any{
		"status":         wiki.VaultStatus(sn.all(), issues, sn.loadSources(), now, loc),
		"changes":        wiki.RecentChanges(sn.all(), 4, now, loc),
		"open_issues":    openMaps,
		"open_total":     len(open),
		"decision_count": len(sn.folder("decisions")),
	}
}

// --- Route handlers --------------------------------------------------------

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)

	areas := map[string]any{}
	for _, a := range metamodel.Areas {
		if !s.isHidden(cat, a.Key) {
			areas[a.Key] = s.buildAreaTile(sn, cat, a)
		}
	}

	joinURL := s.publicURL(r)
	joinQR, err := QRSVG(joinURL, 4)
	if err != nil {
		s.Logger.Printf("WARNING: QR generation failed for %q: %v", joinURL, err)
		joinQR = ""
	}

	vision := wiki.VisionSentence(wiki.VisionPage(sn.folder("goals")), sn.titleIndex())

	s.renderHTML(w, r, http.StatusOK, "index.html", cat, map[string]any{
		"areas":           areas,
		"valley":          s.buildValley(sn, now),
		"vision_sentence": vision,
		"join_url":        joinURL,
		"join_qr":         joinQR,
	}, now)
}

func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/static/")
	clean := strings.TrimPrefix(path.Clean("/"+rel), "/")
	if clean == "" || clean == "." {
		s.handleNotFound(w, r)
		return
	}
	info, err := fs.Stat(s.StaticFS, clean)
	if err != nil || info.IsDir() {
		s.handleNotFound(w, r)
		return
	}
	data, err := fs.ReadFile(s.StaticFS, clean)
	if err != nil {
		s.handleNotFound(w, r)
		return
	}
	if ct := mime.TypeByExtension(path.Ext(clean)); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	http.ServeContent(w, r, path.Base(clean), info.ModTime(), bytes.NewReader(data))
}

func (s *Server) handleBrandIntro(w http.ResponseWriter, r *http.Request) {
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	if !cfg.Intro {
		s.handleNotFound(w, r)
		return
	}
	brandSrc := wiki.ResolveBrand(s.Paths.RepoDir, cfg.Brand, s.warnOnce)
	raw, ok := s.readBrandBytes(brandSrc, wiki.BrandIntroFile)
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	theme := ""
	if r.URL.Query().Get("theme") == "light" {
		theme = ` data-theme="light"`
	}
	doc := fmt.Sprintf(
		"<!doctype html>\n<html lang=\"en\"%s>\n<head>\n<meta charset=\"utf-8\">\n"+
			"<style>\n%s\nhtml, body { margin: 0; background: transparent; }\n</style>\n"+
			"</head>\n<body>\n%s\n%s\n</body>\n</html>\n",
		theme, s.themeTokens, string(raw), introDoneScript,
	)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", introCSP)
	w.Header().Set("X-Frame-Options", "SAMEORIGIN")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = io.WriteString(w, doc)
	}
}

func (s *Server) handleBrandMark(w http.ResponseWriter, r *http.Request, name string) {
	allowed := false
	for _, m := range wiki.BrandMarks {
		if m == name {
			allowed = true
			break
		}
	}
	if !allowed {
		s.handleNotFound(w, r)
		return
	}
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	brandSrc := wiki.ResolveBrand(s.Paths.RepoDir, cfg.Brand, s.warnOnce)
	data, ok := s.readBrandBytes(brandSrc, name)
	if !ok {
		s.handleNotFound(w, r)
		return
	}
	sum := fmt.Sprintf("%08x", crc32.ChecksumIEEE(data))
	if r.URL.Query().Get("v") == sum {
		w.Header().Set("Cache-Control", "public, max-age=31536000")
	} else {
		w.Header().Set("Cache-Control", "public, max-age=0")
	}
	w.Header().Set("Content-Type", "image/svg+xml")
	w.Header().Set("Content-Security-Policy", fileCSP)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		_, _ = w.Write(data)
	}
}

func (s *Server) handleNotFound(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	s.renderHTML(w, r, http.StatusNotFound, "not_found.html", cat, nil, now)
}

func writeJSON(w http.ResponseWriter, r *http.Request, status int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if r.Method != http.MethodHead {
		_, _ = w.Write(b)
	}
}

func readClientID(r *http.Request) string {
	defer r.Body.Close()
	body, err := io.ReadAll(io.LimitReader(r.Body, 4096))
	if err != nil || len(body) == 0 {
		return "anon"
	}
	var payload struct {
		ClientID any `json:"client_id"`
	}
	if err := json.Unmarshal(body, &payload); err != nil || payload.ClientID == nil {
		return "anon"
	}
	return session.NormalizeClientID(fmt.Sprint(payload.ClientID))
}

func (s *Server) handlePing(w http.ResponseWriter, r *http.Request) {
	cid := readClientID(r)
	reply := s.Session.Ping(cid, r.UserAgent())
	writeJSON(w, r, http.StatusOK, reply)
}

func (s *Server) handleLeaving(w http.ResponseWriter, r *http.Request) {
	cid := readClientID(r)
	s.Session.Leaving(cid)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handlePresenceCount(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, http.StatusOK, map[string]int{"count": s.Session.Count()})
}

func (s *Server) handlePresenceList(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, r, http.StatusOK, map[string]any{"clients": s.Session.List()})
}

func (s *Server) handleReload(w http.ResponseWriter, r *http.Request) {
	s.Store.ClearCache()
	s.Metamodel.ClearCaches()
	s.Templates.ClearCache()
	writeJSON(w, r, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleDisconnectAll(w http.ResponseWriter, r *http.Request) {
	cid := readClientID(r)
	if !s.Session.IsFacilitator(cid) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	if s.OnShutdown != nil {
		go func() {
			time.Sleep(400 * time.Millisecond)
			s.OnShutdown("disconnect-all requested by facilitator")
		}()
	}
	w.WriteHeader(http.StatusNoContent)
}
