package wiki

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Required lists what a Systems42 derivative repository holds relative to its
// root (CON-005). Matches preflight.py.
var Required = []string{
	"wiki/",
	"raw/",
	"_system/wiki.yaml",
	"_system/metamodel/",
	"_system/anchors/",
}

// Missing returns the entries from Required that repo lacks, in Required order.
// A file where a directory is expected (or vice versa) counts as missing.
func Missing(repo string) []string {
	var out []string
	for _, rel := range Required {
		wantDir := strings.HasSuffix(rel, "/")
		p := filepath.Join(repo, filepath.FromSlash(strings.TrimSuffix(rel, "/")))
		st, err := os.Stat(p)
		if err != nil {
			out = append(out, rel)
			continue
		}
		if wantDir && !st.IsDir() {
			out = append(out, rel)
		} else if !wantDir && !st.Mode().IsRegular() {
			out = append(out, rel)
		}
	}
	return out
}

// PreflightMessage formats the CON-005 startup error when parts are missing.
func PreflightMessage(repo string, parts []string) string {
	return fmt.Sprintf(
		"This is not a Systems42 wiki, so the dashboard cannot show it.\n"+
			"Missing in %s: %s.\n"+
			"Start the dashboard from the root of a repository created from Systems42.",
		repo, strings.Join(parts, ", "),
	)
}
