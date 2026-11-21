// Package dashboard embeds the shared static files, templates, shipped brand,
// help text and release number so the Go binary serves them without copies
// alongside the Python reference implementation (FR-055, DR-007).
package dashboard

import (
	"embed"
	"io/fs"
	"strings"
)

//go:embed static templates/*.html brands help.md VERSION
var Assets embed.FS

// Version returns the trimmed dashboard release number from VERSION.
func Version() string {
	b, err := Assets.ReadFile("VERSION")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// StaticFS returns the embedded static/ directory rooted at its contents.
func StaticFS() fs.FS {
	sub, err := fs.Sub(Assets, "static")
	if err != nil {
		panic(err)
	}
	return sub
}

// TemplatesFS returns the embedded templates/ directory rooted at its contents.
func TemplatesFS() fs.FS {
	sub, err := fs.Sub(Assets, "templates")
	if err != nil {
		panic(err)
	}
	return sub
}

// BrandsFS returns the embedded brands/ directory rooted at its contents.
func BrandsFS() fs.FS {
	sub, err := fs.Sub(Assets, "brands")
	if err != nil {
		panic(err)
	}
	return sub
}
