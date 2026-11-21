// Package session tracks connected browser tabs, sticky nicknames, and the
// facilitator ("Yoda") role for a running dashboard process (DR-022, FR-046).
package session

import (
	"context"
	"hash/crc32"
	"math"
	"sort"
	"strings"
	"sync"
	"time"
)

var (
	nicknameAdjectives = []string{
		"Curious", "Swift", "Quiet", "Bold", "Sunny", "Clever",
		"Gentle", "Brisk", "Merry", "Wandering", "Sharp", "Calm",
	}
	nicknameAnimals = []string{
		"Otter", "Falcon", "Fox", "Heron", "Lynx", "Puffin",
		"Badger", "Wren", "Marten", "Ibex", "Hare", "Tern",
	}
)

// Options tunes the presence and grace windows. Zero values default to app.py's
// constants (90s startup, 90s heartbeat, 5s leave, 30s presence window).
type Options struct {
	StartupGrace   time.Duration
	HeartbeatGrace time.Duration
	LeaveGrace     time.Duration
	PresenceWindow time.Duration
	Now            func() time.Time
}

// PingReply is the JSON response for POST /ping.
type PingReply struct {
	Nickname      string `json:"nickname"`
	IsFacilitator bool   `json:"is_facilitator"`
}

// ClientInfo is one entry in GET /presence/list.
type ClientInfo struct {
	Nickname         string `json:"nickname"`
	IsFacilitator    bool   `json:"is_facilitator"`
	Browser          string `json:"browser"`
	OS               string `json:"os"`
	ConnectedSeconds int    `json:"connected_seconds"`
}

// Tracker holds in-memory presence state for one dashboard process.
type Tracker struct {
	startupGrace   time.Duration
	heartbeatGrace time.Duration
	leaveGrace     time.Duration
	presenceWindow time.Duration
	now            func() time.Time
	startedAt      time.Time

	mu            sync.Mutex
	clients       map[string]time.Time
	leaving       map[string]time.Time
	firstSeen     map[string]time.Time
	userAgents    map[string]string
	names         map[string]string
	facilitator   string
	everConnected bool
}

// NewTracker initializes a presence Tracker with defaults matching app.py.
func NewTracker(opts Options) *Tracker {
	sg := opts.StartupGrace
	if sg <= 0 {
		sg = 90 * time.Second
	}
	hb := opts.HeartbeatGrace
	if hb <= 0 {
		hb = 90 * time.Second
	}
	lg := opts.LeaveGrace
	if lg <= 0 {
		lg = 5 * time.Second
	}
	pw := opts.PresenceWindow
	if pw <= 0 {
		pw = 30 * time.Second
	}
	nowFn := opts.Now
	if nowFn == nil {
		nowFn = time.Now
	}
	return &Tracker{
		startupGrace:   sg,
		heartbeatGrace: hb,
		leaveGrace:     lg,
		presenceWindow: pw,
		now:            nowFn,
		startedAt:      nowFn(),
		clients:        map[string]time.Time{},
		leaving:        map[string]time.Time{},
		firstSeen:      map[string]time.Time{},
		userAgents:     map[string]string{},
		names:          map[string]string{},
	}
}

// NormalizeClientID trims and caps a client_id to 64 bytes, defaulting to "anon".
func NormalizeClientID(raw string) string {
	s := strings.TrimSpace(raw)
	if len(s) > 64 {
		s = s[:64]
	}
	if s == "" {
		return "anon"
	}
	return s
}

func (t *Tracker) forgetLocked(cid string) {
	delete(t.clients, cid)
	delete(t.leaving, cid)
	delete(t.firstSeen, cid)
	delete(t.userAgents, cid)
}

func (t *Tracker) sweepLocked(now time.Time) {
	for cid, leftAt := range t.leaving {
		last, ok := t.clients[cid]
		if ok && last.After(leftAt) {
			delete(t.leaving, cid)
		} else if now.Sub(leftAt) > t.leaveGrace {
			t.forgetLocked(cid)
		}
	}
	for cid, last := range t.clients {
		if now.Sub(last) > t.heartbeatGrace {
			t.forgetLocked(cid)
		}
	}
}

func (t *Tracker) facilitatorLocked(now time.Time) string {
	active := map[string]time.Time{}
	for cid, fs := range t.firstSeen {
		if last, ok := t.clients[cid]; ok && now.Sub(last) <= t.heartbeatGrace {
			active[cid] = fs
		}
	}
	if t.facilitator != "" {
		if _, ok := active[t.facilitator]; ok {
			return t.facilitator
		}
	}
	var best string
	var bestTime time.Time
	for cid, fs := range active {
		if best == "" || fs.Before(bestTime) || (fs.Equal(bestTime) && cid < best) {
			best = cid
			bestTime = fs
		}
	}
	t.facilitator = best
	return t.facilitator
}

func (t *Tracker) nameForLocked(cid string, now time.Time) string {
	if n, ok := t.names[cid]; ok {
		return n
	}
	isFirst := len(t.names) == 0 && cid == t.facilitatorLocked(now)
	if isFirst {
		t.names[cid] = "Yoda"
	} else {
		t.names[cid] = Nickname(cid)
	}
	return t.names[cid]
}

// Nickname computes the deterministic non-identifying nickname for clientID,
// matching app.py's _nickname().
func Nickname(clientID string) string {
	h := crc32.ChecksumIEEE([]byte(clientID))
	adj := nicknameAdjectives[int(h)%len(nicknameAdjectives)]
	ani := nicknameAnimals[(int(h)/len(nicknameAdjectives))%len(nicknameAnimals)]
	return adj + " " + ani
}

// Ping records a tab heartbeat and returns its sticky nickname and facilitator flag.
func (t *Tracker) Ping(rawID, userAgent string) PingReply {
	cid := NormalizeClientID(rawID)
	if len(userAgent) > 200 {
		userAgent = userAgent[:200]
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	if _, ok := t.clients[cid]; !ok {
		t.firstSeen[cid] = now
	}
	t.clients[cid] = now
	t.everConnected = true
	t.userAgents[cid] = userAgent
	delete(t.leaving, cid)
	isFac := cid == t.facilitatorLocked(now)
	name := t.nameForLocked(cid, now)
	return PingReply{Nickname: name, IsFacilitator: isFac}
}

// ShouldShutdown sweeps stale/leaving tabs and reports whether the server
// should shut down (FR-050): either no browser ever connected within
// StartupGrace, or every previously connected browser has now disconnected.
func (t *Tracker) ShouldShutdown() (bool, string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	if !t.everConnected {
		if now.Sub(t.startedAt) > t.startupGrace {
			return true, "no browser connected within startup grace"
		}
		return false, ""
	}
	if len(t.clients) == 0 {
		return true, "all clients disconnected"
	}
	return false, ""
}

// StartWatchdog polls ShouldShutdown every interval until ctx is cancelled or
// shutdown triggers, calling onShutdown once.
func (t *Tracker) StartWatchdog(ctx context.Context, interval time.Duration, onShutdown func(reason string)) {
	if interval <= 0 {
		interval = time.Second
	}
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if stop, reason := t.ShouldShutdown(); stop {
					if onShutdown != nil {
						onShutdown(reason)
					}
					return
				}
			}
		}
	}()
}

// Leaving records a pagehide beacon for rawID.
func (t *Tracker) Leaving(rawID string) {
	cid := NormalizeClientID(rawID)
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	t.leaving[cid] = now
}

// IsFacilitator reports whether rawID currently holds the facilitator role.
func (t *Tracker) IsFacilitator(rawID string) bool {
	cid := NormalizeClientID(rawID)
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	fac := t.facilitatorLocked(now)
	return fac != "" && cid == fac
}

// Count returns the number of distinct tabs seen within PresenceWindow.
func (t *Tracker) Count() int {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	count := 0
	for _, last := range t.clients {
		if now.Sub(last) <= t.presenceWindow {
			count++
		}
	}
	return count
}

// List returns per-client details for /presence/list, longest connected first.
func (t *Tracker) List() []ClientInfo {
	t.mu.Lock()
	defer t.mu.Unlock()
	now := t.now()
	t.sweepLocked(now)
	fac := t.facilitatorLocked(now)
	rows := make([]ClientInfo, 0, len(t.clients))
	for cid, last := range t.clients {
		if now.Sub(last) > t.presenceWindow {
			continue
		}
		browser, osName := ParseUserAgent(t.userAgents[cid])
		fs, ok := t.firstSeen[cid]
		if !ok {
			fs = last
		}
		rows = append(rows, ClientInfo{
			Nickname:         t.nameForLocked(cid, now),
			IsFacilitator:    cid == fac,
			Browser:          browser,
			OS:               osName,
			ConnectedSeconds: int(math.RoundToEven(now.Sub(fs).Seconds())),
		})
	}
	sort.SliceStable(rows, func(i, j int) bool {
		return rows[i].ConnectedSeconds > rows[j].ConnectedSeconds
	})
	return rows
}

// ParseUserAgent returns coarse browser and OS labels matching app.py.
func ParseUserAgent(ua string) (browser, osName string) {
	switch {
	case strings.Contains(ua, "Edg/"):
		browser = "Edge"
	case strings.Contains(ua, "OPR/") || strings.Contains(ua, "Opera"):
		browser = "Opera"
	case strings.Contains(ua, "Firefox/"):
		browser = "Firefox"
	case strings.Contains(ua, "CriOS") || (strings.Contains(ua, "Chrome/") && strings.Contains(ua, "Safari/")):
		browser = "Chrome"
	case strings.Contains(ua, "Safari/"):
		browser = "Safari"
	default:
		browser = "a browser"
	}

	switch {
	case strings.Contains(ua, "iPhone") || strings.Contains(ua, "iPad"):
		osName = "iOS"
	case strings.Contains(ua, "Android"):
		osName = "Android"
	case strings.Contains(ua, "Mac OS X"):
		osName = "macOS"
	case strings.Contains(ua, "Windows"):
		osName = "Windows"
	case strings.Contains(ua, "Linux"):
		osName = "Linux"
	default:
		osName = ""
	}
	return browser, osName
}
