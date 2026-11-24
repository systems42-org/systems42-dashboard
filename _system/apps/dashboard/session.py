"""The session: who is connected, who holds the Keyholder role, and the view.

Owns the view (the hide list and its validation), the grace periods from the
`DASH_*` settings, the presence state of the connected tabs with its lock, the
names of the clients and the facilitator role.

The watchdog, the shutdown and the session endpoints stay in `app.py`: they
log through the Flask app and read the request.

Standard library plus `catalog`, which says what the view may hide. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import os
import threading
import time
import zlib

import catalog  # the section catalog (DR-033)


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
