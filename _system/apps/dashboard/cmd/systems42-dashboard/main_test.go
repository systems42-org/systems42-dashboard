package main

import (
	"os"
	"testing"
)

func TestRunVersionAndUsage(t *testing.T) {
	if rc := run([]string{"--version"}); rc != 0 {
		t.Fatalf("--version exited %d, want 0", rc)
	}
	if rc := run([]string{"--help"}); rc != 1 {
		t.Fatalf("--help exited %d, want 1", rc)
	}
	if rc := run([]string{"a", "b"}); rc != 1 {
		t.Fatalf("two args exited %d, want 1", rc)
	}
}

func TestRunPreflightRejectsNonSystems42Dir(t *testing.T) {
	empty := t.TempDir()
	// Ensure WIKI_DIR env var does not interfere.
	t.Setenv("WIKI_DIR", "")
	if rc := run([]string{empty}); rc != 1 {
		t.Fatalf("expected preflight exit 1 on %s, got %d", empty, rc)
	}
	// Verify CON-002: preflight wrote nothing to the directory.
	entries, err := os.ReadDir(empty)
	if err != nil || len(entries) != 0 {
		t.Fatalf("preflight should not create files, found %v (err=%v)", entries, err)
	}
}
