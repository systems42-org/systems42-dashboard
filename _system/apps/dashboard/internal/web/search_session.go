package web

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/metamodel"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/render"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/search"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/session"
	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

var (
	aboutAttrURLRE = regexp.MustCompile(`(\s(?:src|href)=")([^"]+)"`)
	uriSchemeRE    = regexp.MustCompile(`^[a-z][a-z0-9+.-]*:`)
)

// --- Phase 4: Search (/search, /search.json) -------------------------------

func (s *Server) buildSearchIndex(sn *requestSnapshot) map[string]any {
	return search.BuildIndex(
		sn.all(),
		sn.folder("domain-terms"),
		sn.folder("glossary"),
		sn.titleIndex(),
		sn.linkIndex(),
		sn.sourceIndex(),
	)
}

func (s *Server) handleSearchJSON(w http.ResponseWriter, r *http.Request) {
	sn := newSnapshot(s.Store)
	writeJSON(w, r, http.StatusOK, s.buildSearchIndex(sn))
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	sn := newSnapshot(s.Store)
	idx := s.buildSearchIndex(sn)
	records := idx["records"].([]map[string]any)

	s.renderHTML(w, r, http.StatusOK, "search.html", cat, map[string]any{
		"index":   idx,
		"total":   len(records),
		"facets":  search.Facets(records),
		"filters": search.Filters(sn.all()),
	}, now)
}

// --- Phase 5: /join, /who, /help, /about, /about/files/, /settings ---------

func (s *Server) handleJoin(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	joinURL := s.publicURL(r)
	joinQR, err := QRSVG(joinURL, 10)
	if err != nil {
		s.Logger.Printf("WARNING: QR generation failed for %q: %v", joinURL, err)
		joinQR = ""
	}
	s.renderHTML(w, r, http.StatusOK, "join.html", cat, map[string]any{
		"join_url": joinURL,
		"join_qr":  joinQR,
	}, now)
}

func (s *Server) handleWho(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	s.renderHTML(w, r, http.StatusOK, "who.html", cat, nil, now)
}

func (s *Server) handleHelp(w http.ResponseWriter, r *http.Request) {
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	text := s.HelpMD
	if text == "" {
		text = "# Help\n\nhelp.md is missing from the image."
	}
	img := fmt.Sprintf(
		`<figure class="help-diagram"><img src="%s" alt="Systems42 sections: req42, arc42 and Common" width="660" height="608"></figure>`,
		s.staticURL("systems42-sections.svg"),
	)
	rendered := render.RenderHelpMarkdown(strings.ReplaceAll(text, "{{DIAGRAM}}", img))
	s.renderHTML(w, r, http.StatusOK, "help.html", cat, map[string]any{
		"html": rendered,
	}, now)
}

func escapePosixPath(rel string) string {
	parts := strings.Split(rel, "/")
	for i, seg := range parts {
		parts[i] = url.PathEscape(seg)
	}
	return strings.Join(parts, "/")
}

func aboutURL(docsDir, pagePath, rawURL string) string {
	idx := strings.IndexAny(rawURL, "?#")
	target := rawURL
	suffix := ""
	if idx >= 0 {
		target = rawURL[:idx]
		suffix = rawURL[idx:]
	}
	if target == "" {
		return rawURL
	}
	root, err := filepath.EvalSymlinks(docsDir)
	if err != nil {
		root, _ = filepath.Abs(docsDir)
	}
	unesc, err := url.PathUnescape(target)
	if err != nil {
		unesc = target
	}
	candidate := filepath.Join(filepath.Dir(pagePath), filepath.FromSlash(unesc))
	resolved, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		parentRes, perr := filepath.EvalSymlinks(filepath.Dir(pagePath))
		if perr != nil {
			parentRes = filepath.Dir(pagePath)
		}
		resolved = filepath.Clean(filepath.Join(parentRes, filepath.FromSlash(unesc)))
	}
	if resolved == root || !wiki.Inside(root, resolved) {
		return rawURL
	}
	rel, err := filepath.Rel(root, resolved)
	if err != nil {
		return rawURL
	}
	return "/about/files/" + escapePosixPath(filepath.ToSlash(rel)) + suffix
}

func (s *Server) handleAbout(w http.ResponseWriter, r *http.Request) {
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	if cfg.AboutPath == "" {
		s.handleNotFound(w, r)
		return
	}
	raw, err := os.ReadFile(cfg.AboutPath)
	if err != nil {
		s.handleNotFound(w, r)
		return
	}
	rendered := render.RenderAboutMarkdown(wiki.SanitizeUTF8(raw))
	rendered = aboutAttrURLRE.ReplaceAllStringFunc(rendered, func(match string) string {
		sub := aboutAttrURLRE.FindStringSubmatch(match)
		prefix, val := sub[1], sub[2]
		if strings.HasPrefix(val, "/") || strings.HasPrefix(val, "#") || uriSchemeRE.MatchString(val) {
			return match
		}
		return prefix + aboutURL(s.Paths.DocsDir, cfg.AboutPath, val) + `"`
	})
	now := s.Now()
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	s.renderHTML(w, r, http.StatusOK, "about.html", cat, map[string]any{
		"html":  rendered,
		"title": cfg.AboutLabel,
	}, now)
}

func (s *Server) handleAboutFile(w http.ResponseWriter, r *http.Request) {
	cfg := wiki.LoadConfig(s.Paths, s.warnOnce)
	if cfg.AboutPath == "" {
		s.handleNotFound(w, r)
		return
	}
	rel := strings.TrimPrefix(r.URL.Path, "/about/files/")
	if rel == "" || strings.Contains(rel, `\`) {
		s.handleNotFound(w, r)
		return
	}
	resolved := wiki.DocsFile(s.Paths.DocsDir, rel)
	if resolved == "" {
		s.handleNotFound(w, r)
		return
	}
	data, err := os.ReadFile(resolved)
	if err != nil {
		s.handleNotFound(w, r)
		return
	}
	st, _ := os.Stat(resolved)
	w.Header().Set("Content-Security-Policy", fileCSP)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if ct := mime.TypeByExtension(path.Ext(resolved)); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	var modTime = s.Now()
	if st != nil {
		modTime = st.ModTime()
	}
	http.ServeContent(w, r, filepath.Base(resolved), modTime, bytes.NewReader(data))
}

func (s *Server) getViewHidden() []string {
	s.viewMu.RLock()
	out := make([]string, len(s.viewHidden))
	copy(out, s.viewHidden)
	s.viewMu.RUnlock()
	return out
}

func (s *Server) setViewHidden(hidden []string) {
	cp := make([]string, len(hidden))
	copy(cp, hidden)
	s.viewMu.Lock()
	s.viewHidden = cp
	s.viewMu.Unlock()
}

func validateHidden(cat *metamodel.Catalog, raw any) (valid []string, unknown []string, isList bool) {
	list, ok := raw.([]any)
	if !ok {
		return nil, []string{}, false
	}
	validSet := map[string]bool{}
	unknown = []string{}
	for _, item := range list {
		txt := strings.TrimSpace(wiki.ScalarString(item))
		if txt == "" {
			unknown = append(unknown, wiki.ScalarString(item))
			continue
		}
		if _, ok := metamodel.AreaByKey[strings.ToLower(txt)]; ok {
			validSet[strings.ToLower(txt)] = true
			continue
		}
		if _, ok := cat.ByID[strings.ToUpper(txt)]; ok {
			validSet[strings.ToUpper(txt)] = true
			continue
		}
		unknown = append(unknown, wiki.ScalarString(item))
	}
	valid = []string{}
	for _, a := range metamodel.Areas {
		if validSet[a.Key] {
			valid = append(valid, a.Key)
		}
	}
	for _, sec := range cat.Sections {
		if validSet[sec.ID] {
			valid = append(valid, sec.ID)
		}
	}
	return valid, unknown, true
}

func (s *Server) handleSettingsGet(w http.ResponseWriter, r *http.Request) {
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	areas := make([]map[string]any, 0, len(metamodel.Areas))
	for _, a := range metamodel.Areas {
		secs := cat.SectionsOf(a.Key)
		secMaps := make([]map[string]any, 0, len(secs))
		for _, sec := range secs {
			colors := make([]string, len(sec.Colors))
			copy(colors, sec.Colors)
			secMaps = append(secMaps, map[string]any{
				"id":     sec.ID,
				"title":  sec.Title,
				"colors": colors,
				"scope":  sec.Scope,
			})
		}
		aColors := make([]string, len(a.Colors))
		copy(aColors, a.Colors)
		areas = append(areas, map[string]any{
			"key":      a.Key,
			"label":    a.Label,
			"colors":   aColors,
			"sections": secMaps,
		})
	}
	writeJSON(w, r, http.StatusOK, map[string]any{
		"areas":  areas,
		"hidden": s.getViewHidden(),
	})
}

func (s *Server) handleSettingsPost(w http.ResponseWriter, r *http.Request) {
	defer r.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	var payload map[string]any
	_ = json.Unmarshal(body, &payload)
	if payload == nil {
		payload = map[string]any{}
	}
	rawCID := ""
	if v, ok := payload["client_id"]; ok && v != nil {
		rawCID = fmt.Sprint(v)
	}
	cid := session.NormalizeClientID(rawCID)
	if !s.Session.IsFacilitator(cid) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	cat := metamodel.BuildCatalog(s.Metamodel.Blocks())
	valid, unknown, isList := validateHidden(cat, payload["hidden"])
	if len(unknown) > 0 || !isList {
		writeJSON(w, r, http.StatusBadRequest, map[string]any{
			"error":   "unknown",
			"unknown": unknown,
		})
		return
	}
	s.setViewHidden(valid)
	s.Store.ClearCache()
	s.Metamodel.ClearCaches()
	s.Templates.ClearCache()
	writeJSON(w, r, http.StatusOK, map[string]any{
		"ok":     true,
		"hidden": valid,
	})
}
