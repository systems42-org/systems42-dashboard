package session

import (
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
