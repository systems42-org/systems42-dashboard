package wiki

import (
	"os"
	"path/filepath"
	"strings"
)

// Paths locates every directory and file the dashboard reads from a Systems42
// wiki repository (FR-042, CON-005). Environment overrides match app.py and
// metamodel.py so fixture tests can point at individual folders.
type Paths struct {
	RepoDir      string
	WikiDir      string
	SourcesDir   string
	ConfigPath   string
	DocsDir      string
	MetamodelDir string
	NotationsDir string
	AnchorsDir   string
}

// ResolvePaths builds Paths from an optional CLI wiki argument and environment
// lookup function (typically os.Getenv).
func ResolvePaths(repoArg string, getenv func(string) string) (Paths, error) {
	if getenv == nil {
		getenv = os.Getenv
	}
	repo := strings.TrimSpace(repoArg)
	if repo == "" {
		repo = strings.TrimSpace(getenv("REPO_DIR"))
	}
	if repo == "" {
		repo = "."
	}
	absRepo, err := filepath.Abs(repo)
	if err != nil {
		return Paths{}, err
	}

	pick := func(envKey, fallback string) string {
		if v := strings.TrimSpace(getenv(envKey)); v != "" {
			if abs, err := filepath.Abs(v); err == nil {
				return abs
			}
			return v
		}
		return fallback
	}

	mmDir := pick("METAMODEL_DIR", filepath.Join(absRepo, "_system", "metamodel"))
	mmParent := filepath.Dir(mmDir)

	return Paths{
		RepoDir:      absRepo,
		WikiDir:      pick("WIKI_DIR", filepath.Join(absRepo, "wiki")),
		SourcesDir:   pick("RAW_SOURCES_DIR", filepath.Join(absRepo, "raw", "sources")),
		ConfigPath:   pick("WIKI_CONFIG", filepath.Join(absRepo, "_system", "wiki.yaml")),
		DocsDir:      pick("DOCS_DIR", filepath.Join(absRepo, "docs")),
		MetamodelDir: mmDir,
		NotationsDir: pick("NOTATIONS_DIR", filepath.Join(mmParent, "notations")),
		AnchorsDir:   pick("ANCHORS_DIR", filepath.Join(mmParent, "anchors")),
	}, nil
}

// Inside reports whether path equals root or lies below it lexically.
func Inside(root, path string) bool {
	root = filepath.Clean(root)
	path = filepath.Clean(path)
	if root == path {
		return true
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// ResolvesInside resolves all symlinks on root and target and returns true only
// when target exists and resolves to root or inside it. Broken symlinks,
// symlink loops and targets outside root return false.
func ResolvesInside(root, target string) bool {
	resolvedRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return false
	}
	resolvedTarget, err := filepath.EvalSymlinks(target)
	if err != nil {
		return false
	}
	return Inside(resolvedRoot, resolvedTarget)
}
