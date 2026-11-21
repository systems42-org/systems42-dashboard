package session

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func TestTrackerYodaAndHandover(t *testing.T) {
	now := time.Date(2026, 11, 21, 15, 0, 0, 0, time.UTC)
	tr := NewTracker(Options{
		HeartbeatGrace: 90 * time.Second,
		LeaveGrace:     5 * time.Second,
		PresenceWindow: 30 * time.Second,
		Now:            func() time.Time { return now },
	})

	if tr.Count() != 0 {
		t.Fatalf("empty count = %d, want 0", tr.Count())
	}

	// First client becomes Yoda and facilitator
	r1 := tr.Ping("tab-1", "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Chrome/120.0 Safari/537.36")
	if r1.Nickname != "Yoda" || !r1.IsFacilitator {
		t.Fatalf("first ping = %+v, want Yoda facilitator", r1)
	}

	// Second client gets deterministic nickname and is not facilitator
	now = now.Add(2 * time.Second)
	r2 := tr.Ping("tab-2", "Mozilla/5.0 (iPhone) Safari/604.1")
	if r2.Nickname == "Yoda" || r2.IsFacilitator {
		t.Fatalf("second ping = %+v, want non-facilitator nickname", r2)
	}
	if tr.Count() != 2 {
		t.Fatalf("count = %d, want 2", tr.Count())
	}

	// First client leaves; after LeaveGrace, role transfers to tab-2 keeping its own nickname
	tr.Leaving("tab-1")
	now = now.Add(6 * time.Second)
	r2Again := tr.Ping("tab-2", "Mozilla/5.0 (iPhone) Safari/604.1")
	if !r2Again.IsFacilitator || r2Again.Nickname != r2.Nickname {
		t.Fatalf("handover failed: got %+v, want facilitator with nickname %q", r2Again, r2.Nickname)
	}
	if tr.Count() != 1 {
		t.Fatalf("count after leave = %d, want 1", tr.Count())
	}

	// List reports browser and OS
	list := tr.List()
	if len(list) != 1 || list[0].Browser != "Safari" || list[0].OS != "iOS" || !list[0].IsFacilitator {
		t.Fatalf("unexpected list: %+v", list)
	}
}

func TestLeavingCancelledByNextPing(t *testing.T) {
	now := time.Date(2026, 11, 21, 15, 0, 0, 0, time.UTC)
	tr := NewTracker(Options{Now: func() time.Time { return now }})

	tr.Ping("tab-1", "")
	now = now.Add(1 * time.Second)
	tr.Leaving("tab-1")
	now = now.Add(1 * time.Second)
	tr.Ping("tab-1", "")
	now = now.Add(10 * time.Second)
	if tr.Count() != 1 || !tr.IsFacilitator("tab-1") {
		t.Fatalf("in-tab navigation ping should cancel /leaving: count=%d fac=%v", tr.Count(), tr.IsFacilitator("tab-1"))
	}
}

func TestKeyholderReturnAndSelfShutdown(t *testing.T) {
	now := time.Date(2026, 11, 21, 16, 0, 0, 0, time.UTC)
	tr := NewTracker(Options{
		StartupGrace:   10 * time.Second,
		HeartbeatGrace: 30 * time.Second,
		LeaveGrace:     5 * time.Second,
		PresenceWindow: 15 * time.Second,
		Now:            func() time.Time { return now },
	})

	// Before any client connects: stays alive during startup grace, shuts down after.
	if stop, _ := tr.ShouldShutdown(); stop {
		t.Fatalf("ShouldShutdown triggered immediately at startup")
	}
	now = now.Add(11 * time.Second)
	if stop, reason := tr.ShouldShutdown(); !stop || reason == "" {
		t.Fatalf("ShouldShutdown after startup grace = (%v, %q), want true", stop, reason)
	}

	// Reset tracker to test keyholder handover, returning Yoda (issue #56), and disconnect shutdown.
	now = time.Date(2026, 11, 21, 16, 0, 0, 0, time.UTC)
	tr = NewTracker(Options{
		StartupGrace:   10 * time.Second,
		HeartbeatGrace: 30 * time.Second,
		LeaveGrace:     5 * time.Second,
		PresenceWindow: 15 * time.Second,
		Now:            func() time.Time { return now },
	})
	yoda := tr.Ping("tab-yoda", "")
	if yoda.Nickname != "Yoda" || !yoda.IsFacilitator {
		t.Fatalf("first client = %+v, want Yoda facilitator", yoda)
	}
	now = now.Add(2 * time.Second)
	heir := tr.Ping("tab-heir", "")
	if heir.IsFacilitator || heir.Nickname == "Yoda" {
		t.Fatalf("second client = %+v, want non-facilitator", heir)
	}

	// Yoda leaves and expires; heir inherits facilitator.
	tr.Leaving("tab-yoda")
	now = now.Add(6 * time.Second)
	if !tr.Ping("tab-heir", "").IsFacilitator {
		t.Fatalf("heir did not inherit facilitator after Yoda left")
	}

	// Yoda returns while heir is still alive: keeps name "Yoda" but does NOT take the keys back.
	now = now.Add(1 * time.Second)
	returned := tr.Ping("tab-yoda", "")
	if returned.Nickname != "Yoda" || returned.IsFacilitator {
		t.Fatalf("returning Yoda = %+v, want Yoda non-facilitator while heir lives", returned)
	}
	if !tr.IsFacilitator("tab-heir") {
		t.Fatalf("heir lost facilitator when Yoda returned")
	}

	// Heir leaves and expires; Yoda becomes facilitator again.
	tr.Leaving("tab-heir")
	now = now.Add(6 * time.Second)
	if !tr.IsFacilitator("tab-yoda") {
		t.Fatalf("Yoda did not inherit facilitator after heir left")
	}

	// Yoda also leaves and expires: all clients gone -> ShouldShutdown fires.
	tr.Leaving("tab-yoda")
	now = now.Add(6 * time.Second)
	if stop, reason := tr.ShouldShutdown(); !stop || reason == "" {
		t.Fatalf("ShouldShutdown after all clients left = (%v, %q), want true", stop, reason)
	}

	// Watchdog goroutine fires onShutdown promptly.
	var fired atomic.Int32
	done := make(chan string, 1)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	tr.StartWatchdog(ctx, 5*time.Millisecond, func(reason string) {
		fired.Add(1)
		done <- reason
	})
	select {
	case reason := <-done:
		if reason == "" {
			t.Fatalf("watchdog fired with empty reason")
		}
	case <-time.After(time.Second):
		t.Fatalf("watchdog did not fire within 1s")
	}
	if fired.Load() != 1 {
		t.Fatalf("watchdog fired %d times, want 1", fired.Load())
	}
}
