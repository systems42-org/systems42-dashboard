"""The session: who is connected, who holds the Keyholder role, and the view.

Owns the view (the hide list and its validation), the grace periods from the
`DASH_*` settings, the presence state of the connected tabs with its lock, the
names of the clients and the facilitator role, and the server lifecycle: the
watchdog, the shutdown and the flags they keep.

The session endpoints stay in `app.py`: they read the request.

Standard library plus `catalog`, which says what the view may hide. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import logging
import os
import signal
import threading
import time
import zlib

import catalog  # the section catalog (DR-033)

log = logging.getLogger("systems42.session")


# The view (FR-046, DR-002): what the Keyholder hides for this session. A hide
# list of area keys / section IDs; everything is visible by default. It lives
# in this process only: no file holds it, and it ends when the dashboard
# stops. One gunicorn worker serves every request (Dockerfile), so this one
# list is the view for everyone.
_view_hidden: list[str] = []


def _valid_hide_keys() -> list[str]:
    return [a["key"] for a in catalog.AREAS] + [s["id"] for s in catalog.SECTIONS]


def _normalise_hide_entry(raw) -> str | None:
    """'c6' → 'C6', ' Architecture ' → 'architecture'; None if not in the catalog."""
    s = str(raw or "").strip()
    if not s:
        return None
    if s.lower() in catalog.AREA_BY_KEY:
        return s.lower()
    if s.upper() in catalog.SECTION_BY_ID:
        return s.upper()
    return None


def _validate_hidden(entries) -> tuple[list[str], list[str]]:
    """Split raw entries into (valid in catalog order, unknown as given)."""
    valid, unknown = set(), []
    if isinstance(entries, str):          # `hidden: C6` is a one-item list
        entries = [entries]
    for raw in entries if isinstance(entries, list) else []:
        key = _normalise_hide_entry(raw)
        if key:
            valid.add(key)
        else:
            unknown.append(str(raw))
    return [k for k in _valid_hide_keys() if k in valid], unknown


def set_view(hidden: list[str]) -> None:
    """Replace the view. Unknown entries are dropped. Nothing is written."""
    global _view_hidden
    _view_hidden, _ = _validate_hidden(list(hidden))


def _grace(env_name: str, default: float) -> float:
    """Grace period in seconds, overridable via env var (for tests/tuning)."""
    try:
        return float(os.environ.get(env_name, default))
    except (TypeError, ValueError):
        return default


# Shut down once no client has pinged for longer than this. Larger than the
# browser's background-tab throttling (~60 s), so a merely hidden tab does
# not falsely trigger a shutdown; only a genuinely closed tab drops out.
_HEARTBEAT_GRACE = _grace("DASH_HEARTBEAT_GRACE", 90.0)
# Grace period at startup, until the first heartbeat arrives (a slower first
# build / first render). If one never comes, the server shuts down afterwards
# instead of running on as an orphan.
_STARTUP_GRACE = _grace("DASH_STARTUP_GRACE", 90.0)
# Short grace period after a client's "tab is leaving" signal (`/leaving`,
# via a pagehide beacon) before dropping that client. On navigation the next
# page connects right away (`/ping` clears the signal); if none arrives (tab
# closed), the client is dropped after this — much faster than the heartbeat
# grace period.
_LEAVE_GRACE = _grace("DASH_LEAVE_GRACE", 5.0)
# How recently a client must have pinged to count as "connected" in the
# footer's live counter. Deliberately tighter than _HEARTBEAT_GRACE: the
# counter is a live-feeling UI nicety, not the shutdown trip wire, so it
# should not wait out the full 90 s tolerance built in for background-tab
# throttling.
_PRESENCE_WINDOW = _grace("DASH_PRESENCE_WINDOW", 30.0)

_lifecycle_lock = threading.Lock()
_clients: dict[str, float] = {}   # client_id -> monotonic time of last /ping
_leaving: dict[str, float] = {}   # client_id -> monotonic time /leaving arrived
_first_seen: dict[str, float] = {}   # client_id -> monotonic time of its first-ever /ping
_user_agents: dict[str, str] = {}    # client_id -> User-Agent header from its latest /ping
# Sticky identity for the whole dashboard session (= server lifetime): a
# client_id's name is fixed at its first /ping and never changes, and the
# facilitator role moves on only when its holder is gone — never back.
# Neither is cleared by `_forget_client`, so a tab that drops out and
# returns with the same client_id is still the same person.
_names: dict[str, str] = {}          # client_id -> name, fixed at first /ping
_facilitator: str | None = None      # client_id currently holding the role


def _forget_client(cid):
    """Drop a client_id from every presence structure at once — called from
    the watchdog's two eviction paths so none of them can go out of sync."""
    _clients.pop(cid, None)
    _leaving.pop(cid, None)
    _first_seen.pop(cid, None)
    _user_agents.pop(cid, None)


def _facilitator_client_id():
    """The facilitator: the first client to connect ("Yoda"), and it keeps
    the role for as long as it is *currently connected*. No shared secret —
    just connection order. A reload/navigation keeps the same client_id
    (sessionStorage), so it doesn't cost the role.

    Sticky: the role is not recomputed per call. Only when its holder is
    no longer connected does it pass, once, to whoever is left with the
    earliest first_seen; it does not return when the old holder's tab
    reappears. Recomputing it on every call made the role (and with it the
    name "Yoda") flip back and forth between two tabs whenever the first
    one hovered around the presence window (reported 2026-10-28).

    "Currently connected" means the watchdog has not dropped the client:
    it is still in `_clients` and pinged within `_HEARTBEAT_GRACE`, the same
    bar the watchdog evicts on. A tab in the background pings only about
    once a minute, so the tighter `_PRESENCE_WINDOW` of the footer counter
    and /who would take the role from a holder who merely switched tabs
    (issue #56). The heir is picked by the same bar, so a background tab is
    not skipped either. The price: a crashed tab holds the role for up to
    `_HEARTBEAT_GRACE`. A closed tab sends /leaving and drops out after
    `_LEAVE_GRACE`. The grace check here, not only the eviction, keeps the
    answer independent of when the watchdog last ran.
    Call under `_lifecycle_lock`."""
    global _facilitator
    now = time.monotonic()
    active = {cid: fs for cid, fs in _first_seen.items()
              if cid in _clients and now - _clients[cid] <= _HEARTBEAT_GRACE}
    if _facilitator in active:
        return _facilitator
    _facilitator = min(active, key=active.get) if active else None
    return _facilitator


def _name_for(cid):
    """This client_id's name for the whole session, fixed on first call:
    "Yoda" for the very first facilitator, a random-looking nickname for
    everyone else. A client that later inherits the role keeps its own
    name. Call under `_lifecycle_lock`."""
    if cid not in _names:
        is_first = not _names and cid == _facilitator_client_id()
        _names[cid] = "Yoda" if is_first else _nickname(cid)
    return _names[cid]


_NICKNAME_ADJECTIVES = ["Curious", "Swift", "Quiet", "Bold", "Sunny", "Clever",
                         "Gentle", "Brisk", "Merry", "Wandering", "Sharp", "Calm"]
_NICKNAME_ANIMALS = ["Otter", "Falcon", "Fox", "Heron", "Lynx", "Puffin",
                      "Badger", "Wren", "Marten", "Ibex", "Hare", "Tern"]


def _nickname(client_id: str) -> str:
    """A stable, fun, non-identifying label for a client_id, for the "who's
    here" page — deterministic (the same tab always gets the same nickname
    across polls) but derived from nothing more than the random id the tab
    already generated itself, so there's no real identity behind it."""
    h = zlib.crc32(client_id.encode("utf-8"))
    adjective = _NICKNAME_ADJECTIVES[h % len(_NICKNAME_ADJECTIVES)]
    animal = _NICKNAME_ANIMALS[(h // len(_NICKNAME_ADJECTIVES)) % len(_NICKNAME_ANIMALS)]
    return f"{adjective} {animal}"


def _parse_user_agent(ua: str) -> tuple[str, str]:
    """Coarse browser/OS labels for the "who's here" page. Good enough for
    the handful of browsers a workshop room actually shows up with — not a
    real user-agent-parsing library, and doesn't need to be."""
    ua = ua or ""
    if "Edg/" in ua:
        browser = "Edge"
    elif "OPR/" in ua or "Opera" in ua:
        browser = "Opera"
    elif "Firefox/" in ua:
        browser = "Firefox"
    elif "CriOS" in ua or ("Chrome/" in ua and "Safari/" in ua):
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    else:
        browser = "a browser"

    if "iPhone" in ua or "iPad" in ua:
        os_name = "iOS"
    elif "Android" in ua:
        os_name = "Android"
    elif "Mac OS X" in ua:
        os_name = "macOS"
    elif "Windows" in ua:
        os_name = "Windows"
    elif "Linux" in ua:
        os_name = "Linux"
    else:
        os_name = ""
    return browser, os_name


def _record_ping(cid: str, ua: str) -> None:
    """Record one /ping of a client: when it was seen, its User-Agent, and
    that a page has connected. A pending "tab is leaving" signal is cleared.
    Call under `_lifecycle_lock`."""
    global _ever_connected
    now = time.monotonic()
    if cid not in _clients:
        _first_seen[cid] = now
    _clients[cid] = now
    _user_agents[cid] = ua
    _leaving.pop(cid, None)
    _ever_connected = True


# ---------------------------------------------------------------------------
# Server lifecycle: self-shutdown as soon as no browser is watching anymore.
# Multiple browsers (workshop clients) may watch at once, so presence is
# tracked per client (a random id each tab generates once, in base.html)
# rather than as a single "is anyone home" flag.
#
# Every open page sends a lightweight heartbeat (`POST /ping`) every few
# seconds, tagged with its client_id. As long as any client keeps pinging,
# the server keeps running; once the last one goes quiet, the watchdog shuts
# it down after a grace period — a closed browser window leaves no orphaned
# container behind. A page additionally reports via a pagehide beacon
# `POST /leaving` that it is going away: if it was just navigation, the next
# page's `/ping` (same client_id, carried via sessionStorage) immediately
# clears the signal; if the tab is really closed, that client is dropped
# after `_LEAVE_GRACE` (~5 s) instead of waiting out the full heartbeat grace
# period.
#
# Deliberately NO long-lived open connection (an earlier iteration used an
# SSE/events stream): that tied up a worker thread for a tab's entire
# lifetime, and clicking through subpages piled these up until the thread
# pool was exhausted and even /stop stopped being served. A /ping is instead
# an immediate request that holds no thread — the problem disappears
# entirely. The grace period is generous so a tab throttled in the background
# (browsers throttle timers to ~1x/min) stays alive; only a genuinely closed
# tab stops pinging altogether. A single worker keeps the state
# process-coherent (Dockerfile: --workers 1). See DR-022 and its addendum.
# ---------------------------------------------------------------------------

_ever_connected = False
_shutting_down = False
_watchdog_started = False
_server_started = time.monotonic()
# The pid of the Gunicorn master, once gunicorn.conf.py has reported it
# (`start_lifecycle`). None everywhere else: under the development server, in
# the site export and in tests the parent is a shell or a test runner.
_gunicorn_master: int | None = None


def _shutdown(reason):
    """Cleanly shut down the server. Under gunicorn, the master is terminated
    via SIGTERM, so all workers exit and the container's PID 1 returns — with
    `restart: no` the container then stays down. The master is the pid that
    gunicorn.conf.py handed to `start_lifecycle`, never a guess from the
    parent pid. Everywhere else we only terminate ourselves (NOT the parent —
    that is a shell or a test runner) via SIGTERM: a SIGINT sent from a
    background thread to our own process is swallowed by the Werkzeug dev
    server (Werkzeug 3.x), whereas SIGTERM is reliably handled via the default
    signal action."""
    global _shutting_down
    with _lifecycle_lock:
        if _shutting_down:
            return
        _shutting_down = True
    log.info("dashboard shutdown: %s", reason)

    def _terminate():
        time.sleep(0.4)  # let the HTTP response / beacon flush first
        if _gunicorn_master is not None:
            try:
                os.kill(_gunicorn_master, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
        os.kill(os.getpid(), signal.SIGTERM)

    threading.Thread(target=_terminate, daemon=True).start()


def _watchdog_pass(auto_stop: bool) -> bool:
    """One pass of the watchdog: drop the clients that are gone, then stop the
    server when nobody is left and `auto_stop` is on. Returns True when the
    watchdog has nothing more to do."""
    with _lifecycle_lock:
        if _shutting_down:
            return True
        now = time.monotonic()
        # A client said goodbye and never pinged again: drop it (fast
        # path on tab close). A fresher ping after the goodbye cancels it
        # (was just in-page navigation).
        for cid, left_at in list(_leaving.items()):
            last = _clients.get(cid)
            if last is not None and last > left_at:
                _leaving.pop(cid, None)
            elif now - left_at > _LEAVE_GRACE:
                _forget_client(cid)
        # A client simply went stale (no goodbye, no more pings either).
        for cid, last in list(_clients.items()):
            if now - last > _HEARTBEAT_GRACE:
                _forget_client(cid)
        anyone_left = bool(_clients)
        ever = _ever_connected
    if not auto_stop:
        return False
    if not ever:
        # Nobody has ever pinged -> startup grace period.
        if now - _server_started > _STARTUP_GRACE:
            _shutdown("no browser heartbeat within the startup grace period")
            return True
    elif not anyone_left:
        _shutdown("no more browser heartbeat (all tabs closed)")
        return True
    return False


def _watchdog(auto_stop: bool):
    while not _watchdog_pass(auto_stop):
        time.sleep(1.0)


def start_lifecycle(gunicorn_master: int | None = None) -> None:
    """Start the watchdog. Only a server entry point calls this: the Gunicorn
    hook in gunicorn.conf.py, which passes the master's pid, and `python
    app.py`. Importing this module starts nothing, so the site export and the
    tests can use the Flask test client for as long as they need (issue #182).

    DASH_NO_SHUTDOWN, set to anything, switches the automatic stop off
    (FR-050): the watchdog still drops clients that are gone, and "Disconnect
    all" still stops the server. The Go dashboard reads the same variable."""
    global _watchdog_started, _gunicorn_master, _server_started
    with _lifecycle_lock:
        if _watchdog_started:
            return
        _watchdog_started = True
        _gunicorn_master = gunicorn_master
        _server_started = time.monotonic()   # the startup grace starts here
    auto_stop = not os.environ.get("DASH_NO_SHUTDOWN", "").strip()
    threading.Thread(target=_watchdog, args=(auto_stop,), daemon=True,
                     name="dashboard-watchdog").start()
