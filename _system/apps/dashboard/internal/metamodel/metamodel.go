package metamodel

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

// SupportedVersions lists the exact metamodel versions this release supports
// (FR-043). Matches metamodel.py.
var SupportedVersions = []string{"0.1"}

// VersionFiles are checked in order under the metamodel directory. The first
// file that exists supplies the declared version.
var VersionFiles = []string{"metamodel-version.md", "meta-metamodel.md"}

var (
	fmRE        = regexp.MustCompile(`(?s)^---\s*\n(.*?)\n---\s*\n?(.*)$`)
	h1RE        = regexp.MustCompile(`(?m)^#\s+.*$`)
	urlRE       = regexp.MustCompile(`https?://[^\s<>()\]]+`)
	slugRE      = regexp.MustCompile(`[^a-z0-9]+`)
	blankLineRE = regexp.MustCompile(`\n\s*\n`)
)

// Anchor is a methodological standard in _system/anchors/ (FR-035).
type Anchor struct {
	Name       string
	Slug       string
	ID         string
	Aliases    []string
	AppliesTo  []string
	Definition string
	Reference  string
	File       string
}

// VersionStatus describes how the wiki's metamodel version matches this release.
type VersionStatus struct {
	Version   string
	File      string
	Supported []string
	State     string // "supported", "unsupported", or "missing"
}

// ToMap converts VersionStatus to the dict shape expected by base.html and metamodel.html.
func (v VersionStatus) ToMap() map[string]any {
	sup := make([]string, len(v.Supported))
	copy(sup, v.Supported)
	return map[string]any{
		"version":   v.Version,
		"file":      v.File,
		"supported": sup,
		"state":     v.State,
	}
}

// Block is one framework block declared under _system/metamodel/frameworks/.
type Block struct {
	ID        string
	Title     string
	Framework string
	Area      string
	Scope     string
	Note      string
	Folders   []string
}

// SortOrder is one named list ordering declared on a metamodel type page.
type SortOrder struct {
	Label string
	Keys  []string
}

type cacheKey struct {
	path string
	kind string // "page" or "version"
}

type stamp struct {
	mtimeNs int64
	size    int64
}

type entry struct {
	stamp stamp
	data  map[string]any
}

type anchorEntry struct {
	stamp  stamp
	anchor *Anchor
}

// Reader parses _system/metamodel/ and _system/anchors/ pages and caches them
// by (mtime_ns, size).
type Reader struct {
	Dir          string
	NotationsDir string
	AnchorsDir   string

	mu          sync.RWMutex
	cache       map[cacheKey]entry
	anchorCache map[string]anchorEntry
}

// NewReader creates a metamodel Reader for the given directories.
func NewReader(dir, notationsDir, anchorsDir string) *Reader {
	return &Reader{
		Dir:          dir,
		NotationsDir: notationsDir,
		AnchorsDir:   anchorsDir,
		cache:        map[cacheKey]entry{},
		anchorCache:  map[string]anchorEntry{},
	}
}

// ClearCaches drops every cached metamodel and anchor parse.
func (r *Reader) ClearCaches() {
	r.mu.Lock()
	r.cache = map[cacheKey]entry{}
	r.anchorCache = map[string]anchorEntry{}
	r.mu.Unlock()
}

func (r *Reader) forgetMissing(folder string, present []string) {
	keep := make(map[string]struct{}, len(present))
	for _, p := range present {
		keep[p] = struct{}{}
	}
	r.mu.Lock()
	for k := range r.cache {
		if filepath.Dir(k.path) == folder {
			if _, ok := keep[k.path]; !ok {
				delete(r.cache, k)
			}
		}
	}
	r.mu.Unlock()
}

func (r *Reader) readCached(path, kind string, parse func(string) map[string]any) map[string]any {
	key := cacheKey{path: path, kind: kind}
	st, err := os.Stat(path)
	if err != nil {
		r.mu.Lock()
		delete(r.cache, key)
		r.mu.Unlock()
		return nil
	}
	cur := stamp{mtimeNs: st.ModTime().UnixNano(), size: st.Size()}
	r.mu.RLock()
	hit, ok := r.cache[key]
	r.mu.RUnlock()
	if !ok || hit.stamp != cur {
		hit = entry{stamp: cur, data: parse(path)}
		r.mu.Lock()
		r.cache[key] = hit
		r.mu.Unlock()
	}
	if hit.data == nil {
		return nil
	}
	cp := make(map[string]any, len(hit.data))
	for k, v := range hit.data {
		cp[k] = v
	}
	return cp
}

func parseMetamodelPage(path string) map[string]any {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	m := fmRE.FindStringSubmatch(text)
	if m == nil {
		return nil
	}
	var parsed any
	if err := yaml.Unmarshal([]byte(m[1]), &parsed); err != nil {
		return nil
	}
	meta, ok := parsed.(map[string]any)
	if !ok || strVal(meta["type"]) != "metamodel" {
		return nil
	}
	meta["_body"] = strings.TrimSpace(m[2])
	meta["_file"] = filepath.Base(path)
	return meta
}

// parseVersion reads `version:` as raw text via yaml.Node so `0.10` stays
// `"0.10"`, matching PyYAML's BaseLoader in metamodel.py.
func parseVersion(path string) map[string]any {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	m := fmRE.FindStringSubmatch(text)
	if m == nil {
		return map[string]any{"version": ""}
	}
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(m[1]), &doc); err != nil {
		return map[string]any{"version": ""}
	}
	if doc.Kind != yaml.DocumentNode || len(doc.Content) == 0 {
		return map[string]any{"version": ""}
	}
	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return map[string]any{"version": ""}
	}
	for i := 0; i+1 < len(root.Content); i += 2 {
		k, v := root.Content[i], root.Content[i+1]
		if k.Kind == yaml.ScalarNode && k.Value == "version" {
			if v.Kind == yaml.ScalarNode && v.Tag != "!!null" {
				return map[string]any{"version": strings.TrimSpace(v.Value)}
			}
			return map[string]any{"version": ""}
		}
	}
	return map[string]any{"version": ""}
}

// VersionCheck compares the repository's metamodel version against SupportedVersions.
func (r *Reader) VersionCheck() VersionStatus {
	var version, file string
	for _, name := range VersionFiles {
		p := filepath.Join(r.Dir, name)
		st, err := os.Stat(p)
		if err == nil && st.Mode().IsRegular() {
			file = name
			if d := r.readCached(p, "version", parseVersion); d != nil {
				version = strVal(d["version"])
			}
			break
		}
	}
	state := "missing"
	if version != "" {
		state = "unsupported"
		for _, sup := range SupportedVersions {
			if version == sup {
				state = "supported"
				break
			}
		}
	}
	sup := make([]string, len(SupportedVersions))
	copy(sup, SupportedVersions)
	return VersionStatus{
		Version:   version,
		File:      file,
		Supported: sup,
		State:     state,
	}
}

func (r *Reader) load(folder, construct string) []map[string]any {
	d := filepath.Join(r.Dir, folder)
	entries, err := os.ReadDir(d)
	var paths []string
	if err == nil {
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".md") {
				paths = append(paths, filepath.Join(d, e.Name()))
			}
		}
		sort.Strings(paths)
	}
	r.forgetMissing(d, paths)
	var out []map[string]any
	for _, p := range paths {
		fm := r.readCached(p, "page", parseMetamodelPage)
		if fm != nil && strVal(fm["construct"]) == construct {
			out = append(out, fm)
		}
	}
	return out
}

// Blocks returns every framework block in framework-filename then block order,
// resolving each listed type name to its wiki subfolder via types/*.md.
func (r *Reader) Blocks() []Block {
	folderOf := map[string]string{}
	for _, t := range r.load("types", "type") {
		name := strVal(t["name"])
		folder := strVal(t["folder"])
		if name != "" && folder != "" {
			folderOf[name] = filepath.Base(filepath.FromSlash(folder))
		}
	}

	var out []Block
	for _, fw := range r.load("frameworks", "framework") {
		fwName := strVal(fw["name"])
		fwArea := strVal(fw["area"])
		rawBlocks, _ := fw["blocks"].([]any)
		for _, item := range rawBlocks {
			bm, ok := item.(map[string]any)
			if !ok {
				continue
			}
			id := strings.TrimSpace(strVal(bm["id"]))
			if id == "" {
				continue
			}
			var typeNames []string
			switch tv := bm["types"].(type) {
			case string:
				if tv != "" {
					typeNames = []string{tv}
				}
			case []any:
				for _, tn := range tv {
					if s := strVal(tn); s != "" {
						typeNames = append(typeNames, s)
					}
				}
			}
			folders := make([]string, 0, len(typeNames))
			for _, tn := range typeNames {
				if f, ok := folderOf[tn]; ok {
					folders = append(folders, f)
				}
			}
			title := strVal(bm["title"])
			if title == "" {
				title = id
			}
			scope := strVal(bm["scope"])
			if scope == "" {
				scope = "in"
			}
			out = append(out, Block{
				ID:        id,
				Title:     title,
				Framework: fwName,
				Area:      fwArea,
				Scope:     scope,
				Note:      strVal(bm["note"]),
				Folders:   folders,
			})
		}
	}
	return out
}

// SortOrders returns the declared sort orders for a metamodel type name.
func (r *Reader) SortOrders(typeName string) []SortOrder {
	for _, t := range r.load("types", "type") {
		if strVal(t["name"]) != typeName {
			continue
		}
		rawOrders, _ := t["sort_orders"].([]any)
		var out []SortOrder
		for _, item := range rawOrders {
			m, ok := item.(map[string]any)
			if !ok {
				continue
			}
			label := strVal(m["label"])
			rawKeys, _ := m["keys"].([]any)
			if label == "" || len(rawKeys) == 0 {
				continue
			}
			keys := make([]string, 0, len(rawKeys))
			for _, k := range rawKeys {
				keys = append(keys, strVal(k))
			}
			out = append(out, SortOrder{Label: label, Keys: keys})
		}
		return out
	}
	return nil
}

func (r *Reader) typePage(typeName string) map[string]any {
	for _, t := range r.load("types", "type") {
		if strVal(t["name"]) == typeName {
			return t
		}
	}
	return nil
}

// FieldValues returns the closed enum list a type's field allows, or nil.
func (r *Reader) FieldValues(typeName, field string) []string {
	tp := r.typePage(typeName)
	if tp == nil {
		return nil
	}
	fields, _ := tp["fields"].([]any)
	for _, item := range fields {
		fm, ok := item.(map[string]any)
		if !ok || strVal(fm["name"]) != field {
			continue
		}
		rawVals, _ := fm["values"].([]any)
		out := make([]string, 0, len(rawVals))
		for _, v := range rawVals {
			out = append(out, strVal(v))
		}
		return out
	}
	return nil
}

// Lifecycle returns the status values a type's lifecycle allows, or nil.
func (r *Reader) Lifecycle(typeName string) []string {
	meta := r.readCached(filepath.Join(r.Dir, "meta-metamodel.md"), "page", parseMetamodelPage)
	tp := r.typePage(typeName)
	if meta == nil || tp == nil {
		return nil
	}
	lcName := strVal(tp["lifecycle"])
	lifecycles, _ := meta["lifecycles"].(map[string]any)
	rawVals, _ := lifecycles[lcName].([]any)
	out := make([]string, 0, len(rawVals))
	for _, v := range rawVals {
		out = append(out, strVal(v))
	}
	return out
}

func anchorDefinition(body string) string {
	for _, para := range blankLineRE.Split(body, -1) {
		head := strings.TrimLeft(para, " \t\r\n")
		if head == "" {
			continue
		}
		if strings.HasPrefix(head, ">") || strings.HasPrefix(head, "-") ||
			strings.HasPrefix(head, "*") || strings.HasPrefix(head, "|") ||
			strings.HasPrefix(head, "#") || strings.HasPrefix(head, "<!--") {
			continue
		}
		var lines []string
		for _, l := range strings.Split(strings.TrimSpace(para), "\n") {
			lines = append(lines, strings.TrimSpace(l))
		}
		return strings.Join(lines, " ")
	}
	return ""
}

func parseAnchor(path string) *Anchor {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")
	m := fmRE.FindStringSubmatch(text)
	if m == nil {
		return nil
	}
	var parsed any
	if err := yaml.Unmarshal([]byte(m[1]), &parsed); err != nil {
		return nil
	}
	meta, ok := parsed.(map[string]any)
	if !ok || strVal(meta["type"]) != "anchor" {
		return nil
	}
	body := strings.TrimSpace(m[2])
	if loc := h1RE.FindStringIndex(body); loc != nil {
		body = strings.TrimSpace(body[:loc[0]] + body[loc[1]:])
	}
	stem := strings.TrimSuffix(filepath.Base(path), ".md")
	slug := strings.Trim(slugRE.ReplaceAllString(strings.ToLower(stem), "-"), "-")
	ref := ""
	if u := urlRE.FindString(body); u != "" {
		ref = strings.TrimRight(u, ".,;:")
	}
	name := strVal(meta["title"])
	if name == "" {
		name = stem
	}
	var aliases []string
	if rawA, ok := meta["aliases"].([]any); ok {
		for _, a := range rawA {
			if s := strVal(a); s != "" {
				aliases = append(aliases, s)
			}
		}
	}
	var applies []string
	switch rawAp := meta["applies-to"].(type) {
	case []any:
		for _, a := range rawAp {
			if s := strVal(a); s != "" {
				applies = append(applies, s)
			}
		}
	case string:
		if rawAp != "" {
			applies = []string{rawAp}
		}
	}
	return &Anchor{
		Name:       name,
		Slug:       slug,
		ID:         "anchor-" + slug,
		Aliases:    aliases,
		AppliesTo:  applies,
		Definition: anchorDefinition(body),
		Reference:  ref,
		File:       filepath.Base(path),
	}
}

func (r *Reader) forgetMissingAnchors(folder string, present []string) {
	keep := make(map[string]struct{}, len(present))
	for _, p := range present {
		keep[p] = struct{}{}
	}
	r.mu.Lock()
	for p := range r.anchorCache {
		if filepath.Dir(p) == folder {
			if _, ok := keep[p]; !ok {
				delete(r.anchorCache, p)
			}
		}
	}
	r.mu.Unlock()
}

// MethodAnchors loads every method anchor from AnchorsDir sorted by name,
// cached by (mtime_ns, size).
func (r *Reader) MethodAnchors() []Anchor {
	entries, err := os.ReadDir(r.AnchorsDir)
	var paths []string
	if err == nil {
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".md") {
				paths = append(paths, filepath.Join(r.AnchorsDir, e.Name()))
			}
		}
		sort.Strings(paths)
	}
	r.forgetMissingAnchors(r.AnchorsDir, paths)
	var out []Anchor
	for _, p := range paths {
		st, err := os.Stat(p)
		if err != nil {
			r.mu.Lock()
			delete(r.anchorCache, p)
			r.mu.Unlock()
			continue
		}
		cur := stamp{mtimeNs: st.ModTime().UnixNano(), size: st.Size()}
		r.mu.RLock()
		hit, ok := r.anchorCache[p]
		r.mu.RUnlock()
		if !ok || hit.stamp != cur {
			hit = anchorEntry{stamp: cur, anchor: parseAnchor(p)}
			r.mu.Lock()
			r.anchorCache[p] = hit
			r.mu.Unlock()
		}
		if hit.anchor != nil {
			out = append(out, *hit.anchor)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out
}

// AnchorIndex maps lower-cased anchor name, slug and aliases to the Anchor.
func AnchorIndex(found []Anchor) map[string]Anchor {
	idx := map[string]Anchor{}
	for _, a := range found {
		keys := make([]string, 0, 2+len(a.Aliases))
		keys = append(keys, a.Name, a.Slug)
		keys = append(keys, a.Aliases...)
		for _, k := range keys {
			norm := strings.ToLower(strings.TrimSpace(k))
			if norm == "" {
				continue
			}
			if _, exists := idx[norm]; !exists {
				idx[norm] = a
			}
		}
	}
	return idx
}

func strVal(v any) string {
	if v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	case int:
		return strconv.Itoa(x)
	case int64:
		return strconv.FormatInt(x, 10)
	case float64:
		return strconv.FormatFloat(x, 'g', -1, 64)
	case bool:
		if x {
			return "True"
		}
		return "False"
	default:
		return fmt.Sprint(x)
	}
}
