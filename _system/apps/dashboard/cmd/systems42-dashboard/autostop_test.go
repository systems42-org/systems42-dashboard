package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

// startDashboard runs the dashboard on a free port with short grace periods.
// It returns the port and a channel that gets the exit code.
func startDashboard(t *testing.T) (int, <-chan int) {
	t.Helper()
	t.Setenv("WIKI_DIR", "")
	t.Setenv("DASH_STARTUP_GRACE", "0.2")
	t.Setenv("DASH_LEAVE_GRACE", "0.2")
	pr, pw := io.Pipe()
	done := make(chan int, 1)
	go func() {
		done <- runWithIO([]string{"--host", "127.0.0.1", "--port", "0", "--ready-json", repoRoot(t)}, pw, io.Discard)
		pw.Close()
	}()
	ready := make(chan int, 1)
	go func() {
		sc := bufio.NewScanner(pr)
		for sc.Scan() {
			if line, ok := strings.CutPrefix(sc.Text(), "READY "); ok {
				var reply struct {
					Port int `json:"port"`
				}
				_ = json.Unmarshal([]byte(line), &reply)
				ready <- reply.Port
			}
		}
	}()
	select {
	case port := <-ready:
		return port, done
	case rc := <-done:
		t.Fatalf("dashboard ended before it was ready, exit %d", rc)
	case <-time.After(10 * time.Second):
		t.Fatal("dashboard did not become ready")
	}
	return 0, nil
}

func post(t *testing.T, port int, route, body string) int {
	t.Helper()
	resp, err := http.Post(fmt.Sprintf("http://127.0.0.1:%d%s", port, route), "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatalf("POST %s: %v", route, err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

func stillRunning(done <-chan int, wait time.Duration) bool {
	select {
	case <-done:
		return false
	case <-time.After(wait):
		return true
	}
}

// FR-050: a dashboard that no page ever connects to stops after the startup
// grace. The watchdog looks once a second.
func TestAutomaticStopAfterTheStartupGrace(t *testing.T) {
	t.Setenv("DASH_NO_SHUTDOWN", "")
	_, done := startDashboard(t)
	select {
	case rc := <-done:
		if rc != 0 {
			t.Fatalf("exit %d, want 0", rc)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("dashboard still runs 10 s after a startup grace of 0.2 s")
	}
}

// FR-050: started with DASH_NO_SHUTDOWN, the dashboard keeps running past
// the startup grace and after the last page has closed. "Disconnect all"
// still stops it.
func TestDashNoShutdownSwitchesTheAutomaticStopOff(t *testing.T) {
	t.Setenv("DASH_NO_SHUTDOWN", "1")
	port, done := startDashboard(t)
	if !stillRunning(done, 2500*time.Millisecond) {
		t.Fatal("stopped after the startup grace although DASH_NO_SHUTDOWN is set")
	}
	if rc := post(t, port, "/ping", `{"client_id":"tab"}`); rc != http.StatusOK {
		t.Fatalf("POST /ping = %d", rc)
	}
	if rc := post(t, port, "/leaving", `{"client_id":"tab"}`); rc != http.StatusNoContent {
		t.Fatalf("POST /leaving = %d", rc)
	}
	if !stillRunning(done, 2500*time.Millisecond) {
		t.Fatal("stopped after the last page closed although DASH_NO_SHUTDOWN is set")
	}
	if rc := post(t, port, "/ping", `{"client_id":"yoda"}`); rc != http.StatusOK {
		t.Fatalf("POST /ping = %d", rc)
	}
	if rc := post(t, port, "/disconnect-all", `{"client_id":"yoda"}`); rc != http.StatusNoContent {
		t.Fatalf("POST /disconnect-all = %d", rc)
	}
	select {
	case rc := <-done:
		if rc != 0 {
			t.Fatalf("exit %d, want 0", rc)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Disconnect all did not stop the dashboard")
	}
}
