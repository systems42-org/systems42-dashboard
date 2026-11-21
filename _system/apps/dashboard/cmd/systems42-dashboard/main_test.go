package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "..", ".."))
}

func TestRunVersionAndUsage(t *testing.T) {
	var out, errBuf bytes.Buffer
	if rc := runWithIO([]string{"--version"}, &out, &errBuf); rc != 0 {
		t.Fatalf("--version exited %d, want 0", rc)
	}
	if strings.TrimSpace(out.String()) == "" {
		t.Fatalf("--version printed empty output")
	}
	if rc := runWithIO([]string{"--help"}, &out, &errBuf); rc != 1 {
		t.Fatalf("--help exited %d, want 1", rc)
	}
	if rc := runWithIO([]string{"a", "b"}, &out, &errBuf); rc != 1 {
		t.Fatalf("two args exited %d, want 1", rc)
	}
}

func TestRunPreflightRejectsNonSystems42Dir(t *testing.T) {
	empty := t.TempDir()
	// Ensure WIKI_DIR env var does not interfere.
	t.Setenv("WIKI_DIR", "")
	var out, errBuf bytes.Buffer
	if rc := runWithIO([]string{empty}, &out, &errBuf); rc != 1 {
		t.Fatalf("expected preflight exit 1 on %s, got %d", empty, rc)
	}
	// Verify CON-002: preflight wrote nothing to the directory.
	entries, err := os.ReadDir(empty)
	if err != nil || len(entries) != 0 {
		t.Fatalf("preflight should not create files, found %v (err=%v)", entries, err)
	}
}

func TestCheckFlagValidAndInvalid(t *testing.T) {
	t.Setenv("WIKI_DIR", "")

	// Valid Systems42 repository (this repo)
	var out, errBuf bytes.Buffer
	rc := runWithIO([]string{"--check", repoRoot(t)}, &out, &errBuf)
	if rc != 0 {
		t.Fatalf("--check on repo exited %d (out=%s err=%s)", rc, out.String(), errBuf.String())
	}
	var okReply struct {
		OK               bool   `json:"ok"`
		SystemName       string `json:"system_name"`
		DashboardVersion string `json:"dashboard_version"`
		OwnVersion       string `json:"own_version"`
	}
	if err := json.Unmarshal(out.Bytes(), &okReply); err != nil || !okReply.OK || okReply.SystemName == "" || okReply.OwnVersion == "" {
		t.Fatalf("unexpected --check valid JSON: %s (err=%v)", out.String(), err)
	}

	// Invalid folder
	out.Reset()
	errBuf.Reset()
	empty := t.TempDir()
	rc = runWithIO([]string{"--check", empty}, &out, &errBuf)
	if rc != 1 {
		t.Fatalf("--check on empty dir exited %d, want 1", rc)
	}
	var badReply struct {
		OK      bool     `json:"ok"`
		Missing []string `json:"missing"`
		Message string   `json:"message"`
	}
	if err := json.Unmarshal(out.Bytes(), &badReply); err != nil || badReply.OK || len(badReply.Missing) == 0 || badReply.Message == "" {
		t.Fatalf("unexpected --check invalid JSON: %s (err=%v)", out.String(), err)
	}
}
