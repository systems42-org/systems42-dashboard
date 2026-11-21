package wiki

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	DefaultSystemName = "Requirements Wiki"
	DefaultBrand      = "systems42"
	BrandIntroFile    = "intro.html"
)

// BrandMarks are the three SVG marks every valid brand folder must provide.
var BrandMarks = []string{"mark-dark.svg", "mark-light.svg", "favicon.svg"}

// ShippedBrands are the brands bundled into the dashboard binary.
var ShippedBrands = map[string]bool{
	DefaultBrand: true,
}

// Config holds the live project identity read from _system/wiki.yaml.
type Config struct {
	Brand            string
	Intro            bool
	DashboardVersion string
	SystemName       string
	SystemNameSet    bool
	Tagline          string
	AboutHref        string
	AboutLabel       string
	DefaultNotation  string
}

func introOn(val any) bool {
	if val == nil {
		return true
	}
	if b, ok := val.(bool); ok {
		return b
	}
	switch strings.ToLower(strings.TrimSpace(scalarString(val))) {
	case "off", "false", "no", "0":
		return false
	default:
		return true
	}
}

// LoadConfig reads _system/wiki.yaml live (never cached) and falls back to
// safe defaults when the file is missing, empty, or malformed.
func LoadConfig(paths Paths, warn func(string)) Config {
	var data map[string]any
	if raw, err := os.ReadFile(paths.ConfigPath); err == nil {
		var parsed any
		if err := yaml.Unmarshal(raw, &parsed); err == nil {
			if m, ok := parsed.(map[string]any); ok {
				data = m
			}
		}
	}
	if data == nil {
		data = map[string]any{}
	}

	name := strings.TrimSpace(scalarString(data["system_name"]))
	effectiveName := name
	if effectiveName == "" {
		effectiveName = DefaultSystemName
	}

	aboutHref := ""
	if AboutDoc(paths.DocsDir, data["about"]) != "" {
		aboutHref = "/about"
	}
	aboutLabel := strings.TrimSpace(scalarString(data["about_label"]))
	if aboutLabel == "" {
		aboutLabel = "About " + effectiveName
	}

	var dashVersion string
	if v, ok := data["dashboard_version"]; ok && v != nil {
		if _, isStr := v.(string); !isStr && warn != nil {
			warn(fmt.Sprintf("dashboard_version: %v is not text, quote it, e.g. \"1.10.0\"", v))
		}
		dashVersion = strings.TrimSpace(scalarString(v))
	}

	brand := DefaultBrand
	if b, ok := data["brand"]; ok && b != nil {
		if bs, isStr := b.(string); isStr {
			if trimmed := strings.TrimSpace(bs); trimmed != "" {
				brand = trimmed
			}
		} else if warn != nil {
			warn(fmt.Sprintf("brand: %v: brand must be a name or a folder path, showing %s", b, DefaultBrand))
		}
	}

	defaultNotation := strings.ToLower(strings.TrimSpace(scalarString(data["default_notation"])))
	if defaultNotation == "" {
		defaultNotation = "agile"
	}

	return Config{
		Brand:            brand,
		Intro:            introOn(data["intro"]),
		DashboardVersion: dashVersion,
		SystemName:       effectiveName,
		SystemNameSet:    name != "",
		Tagline:          strings.TrimSpace(scalarString(data["tagline"])),
		AboutHref:        aboutHref,
		AboutLabel:       aboutLabel,
		DefaultNotation:  defaultNotation,
	}
}

// AboutDoc resolves `about:` (`docs/...`, vault-relative markdown) inside
// docsDir, returning "" if outside docsDir, missing, or not markdown.
func AboutDoc(docsDir string, value any) string {
	rel := strings.TrimLeft(strings.TrimSpace(scalarString(value)), "/")
	if !strings.HasPrefix(rel, "docs/") || !strings.HasSuffix(rel, ".md") {
		return ""
	}
	return DocsFile(docsDir, strings.TrimPrefix(rel, "docs/"))
}

// DocsFile resolves rel inside docsDir after symlink resolution and returns ""
// unless it resolves to a regular file strictly inside docsDir.
func DocsFile(docsDir, rel string) string {
	resolvedRoot, err := filepath.EvalSymlinks(docsDir)
	if err != nil {
		return ""
	}
	candidate := filepath.Join(resolvedRoot, filepath.FromSlash(rel))
	resolvedPath, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return ""
	}
	if resolvedPath == resolvedRoot || !Inside(resolvedRoot, resolvedPath) {
		return ""
	}
	st, err := os.Stat(resolvedPath)
	if err != nil || !st.Mode().IsRegular() {
		return ""
	}
	return resolvedPath
}

// BrandSource identifies where the active brand is loaded from: either a
// shipped embedded brand (ShippedName != "") or a validated folder inside
// RepoDir (Dir != "").
type BrandSource struct {
	ShippedName string
	Dir         string
}

// ResolveBrand resolves `brand:` from wiki.yaml. A shipped brand name wins;
// any other value is a repository-relative folder that must stay inside
// repoDir and contain all three BrandMarks. Invalid values fall back to
// DefaultBrand and call warn once.
func ResolveBrand(repoDir, value string, warn func(string)) BrandSource {
	name := strings.TrimSpace(value)
	if name == "" {
		name = DefaultBrand
	}
	if ShippedBrands[name] {
		return BrandSource{ShippedName: name}
	}
	fallback := BrandSource{ShippedName: DefaultBrand}
	resolvedRoot, err := filepath.EvalSymlinks(repoDir)
	if err != nil {
		if warn != nil {
			warn(fmt.Sprintf("brand: %q is outside the wiki repository, showing %s", name, DefaultBrand))
		}
		return fallback
	}
	// Reject absolute paths before joining, matching Path(root / name).resolve()
	// where an absolute `name` replaces `root`.
	var candidate string
	if filepath.IsAbs(name) {
		candidate = name
	} else {
		candidate = filepath.Join(resolvedRoot, filepath.FromSlash(name))
	}
	resolvedPath, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		// Check lexical boundary first so a non-existent path outside repo reports "outside".
		lex := filepath.Clean(candidate)
		if !Inside(resolvedRoot, lex) {
			if warn != nil {
				warn(fmt.Sprintf("brand: %q is outside the wiki repository, showing %s", name, DefaultBrand))
			}
			return fallback
		}
		if warn != nil {
			warn(fmt.Sprintf("brand: %q is no folder in the wiki repository, showing %s", name, DefaultBrand))
		}
		return fallback
	}
	if !Inside(resolvedRoot, resolvedPath) {
		if warn != nil {
			warn(fmt.Sprintf("brand: %q is outside the wiki repository, showing %s", name, DefaultBrand))
		}
		return fallback
	}
	st, err := os.Stat(resolvedPath)
	if err != nil || !st.IsDir() {
		if warn != nil {
			warn(fmt.Sprintf("brand: %q is no folder in the wiki repository, showing %s", name, DefaultBrand))
		}
		return fallback
	}
	var missing []string
	for _, mark := range BrandMarks {
		if BrandFileOnDisk(resolvedPath, mark) == "" {
			missing = append(missing, mark)
		}
	}
	if len(missing) > 0 {
		if warn != nil {
			warn(fmt.Sprintf("brand: %q lacks %s, showing %s", name, strings.Join(missing, ", "), DefaultBrand))
		}
		return fallback
	}
	return BrandSource{Dir: resolvedPath}
}

// BrandFileOnDisk returns folder/name when it resolves to a regular file whose
// resolved parent is the resolved folder itself.
func BrandFileOnDisk(folder, name string) string {
	resolvedFolder, err := filepath.EvalSymlinks(folder)
	if err != nil {
		return ""
	}
	resolvedPath, err := filepath.EvalSymlinks(filepath.Join(resolvedFolder, name))
	if err != nil {
		return ""
	}
	if filepath.Dir(resolvedPath) != resolvedFolder {
		return ""
	}
	st, err := os.Stat(resolvedPath)
	if err != nil || !st.Mode().IsRegular() {
		return ""
	}
	return resolvedPath
}
