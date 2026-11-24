"""Search and the session endpoints.

Owns the search page with its filters and the search index, the join page,
the heartbeat and presence endpoints, the "who's here" page, the reload of
the server-side caches, the View dialog's data and its saving, and
Disconnect all. The session state itself is in `session.py`: these
endpoints read the request and call it.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import time

from flask import Blueprint, abort, current_app, jsonify, make_response, render_template, request

import catalog  # the section catalog (DR-033)
import metamodel  # reader for _system/metamodel/ (DR-035)
import search  # search records
import session  # presence, the Keyholder role, the view and the lifecycle
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders
import web.common  # what several route groups share

bp = Blueprint("search_session", __name__)


@bp.route("/search.json")
def search_index():
    """The search index for the topbar's incremental search popup
    (static/search-popup.js); ranked client-side by static/search-rank.js,
    the same code the /search page uses."""
    return jsonify(search.build_search_index())


@bp.route("/search")
def search_view():
    """Global search across all wiki content. Results render once and are
    filtered incrementally client-side; type facets allow browsing by content type."""
    index = search.build_search_index()
    tally: dict[str, int] = {}
    for r in index["records"]:
        tally[r["type"]] = tally.get(r["type"], 0) + 1
    facets = sorted(tally.items(), key=lambda kv: (-kv[1], kv[0]))
    return render_template("search.html", index=index, total=len(index["records"]), facets=facets,
                           filters=_search_filters())


_PRIORITY_ORDER = ["must", "should", "could", "wont", "won't"]


def _search_filters() -> dict[str, list[dict]]:
    """The values offered by /search's status, priority and tag filters
    (FR-009): every value some page carries, as {value, label}. The value is
    lower-case, as the ranker compares it; the label is how the wiki writes
    it (the first spelling found)."""
    labels: dict[str, dict[str, str]] = {"status": {}, "priority": {}, "tags": {}}
    for p in wiki.load_all_pages():
        for key, seen in labels.items():
            raw = p.meta.get(key)
            for x in raw if isinstance(raw, list) else [raw]:
                written = str(x).strip() if x is not None else ""
                if written:
                    seen.setdefault(written.lower(), written)   # same value as _search_fields

    def opts(key, order=None):
        vals = labels[key]
        rank = (lambda v: (v not in order, order.index(v) if v in order else 0, v)) if order else None
        return [{"value": v, "label": vals[v]} for v in sorted(vals, key=rank)]
    return {"status": opts("status"), "priority": opts("priority", _PRIORITY_ORDER), "tag": opts("tags")}


@bp.route("/join")
def join_page():
    url = web.common.public_url()
    return render_template("join.html", join_url=url, join_qr=web.common.qr_svg(url, scale=10))


def _json_object(req) -> dict:
    """The JSON object in the body of a session request (/ping, /leaving,
    /settings, /disconnect-all). No body, an unreadable body and `null` count
    as an empty object. Any other JSON value (array, string, number, boolean)
    ends the request with a 400, before the endpoint touches session state."""
    try:
        data = req.get_json(silent=True, force=True)
    except Exception:
        data = None
    if data is None:
        return {}
    if not isinstance(data, dict):
        abort(make_response({"error": "not-an-object"}, 400))
    return data


def _client_id(req) -> str:
    """The per-tab id a page sends with /ping and /leaving (generated once in
    base.html, kept in sessionStorage so it survives in-tab navigation but
    not a closed tab). Defaulted and length-capped so a missing or malformed
    body can't wedge the presence dict."""
    cid = str(_json_object(req).get("client_id") or "").strip()[:64]
    return cid or "anon"


@bp.route("/ping", methods=["POST"])
def heartbeat_ping():
    """Lightweight sign of life from one open page. Updates that client_id's
    `last seen` timestamp and clears any pending "tab is leaving" signal for
    it (a live page pinging means no goodbye after all). Holds no thread —
    replies immediately with the two things the page needs back: this tab's
    name (for the header) and whether it is currently the facilitator (for
    the disconnect-all button — see `_facilitator_client_id`). The first
    facilitator is named "Yoda", everyone else gets a nickname; a name never
    changes once given (`_name_for`). Both are re-sent on every ping, so the
    button follows the role live if it ever transfers (Yoda's tab
    disappearing): the heir gets the button but keeps its own name."""
    cid = _client_id(request)
    ua = request.headers.get("User-Agent", "")[:200]
    with session._lifecycle_lock:
        session._record_ping(cid, ua)
        is_facilitator = cid == session._facilitator_client_id()
        nickname = session._name_for(cid)
    return {"nickname": nickname, "is_facilitator": is_facilitator}


@bp.route("/leaving", methods=["POST"])
def heartbeat_leaving():
    """Beacon sent when one page is left (pagehide: tab closed OR navigated).
    Marks that client_id as possibly-gone; if the user was only navigating,
    the next page's immediate `/ping` (same client_id) clears the signal
    again before it expires."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        session._leaving[cid] = time.monotonic()
    return ("", 204)


@bp.route("/presence/count")
def presence_count():
    """How many distinct tabs have pinged within `_PRESENCE_WINDOW` — the
    number shown in the footer. Yoda's own tab counts like any other: the
    facilitator alone in the room reads "1 client", not "0 clients" beside
    "Welcome, Yoda" (an earlier version excluded Yoda; see DR-022's
    2026-09-08 note). Polled every few seconds; cheap (an in-memory dict
    scan, no I/O, no thread held)."""
    now = time.monotonic()
    with session._lifecycle_lock:
        count = sum(1 for last in session._clients.values()
                    if now - last <= session._PRESENCE_WINDOW)
    return {"count": count}


@bp.route("/presence/list")
def presence_list():
    """Per-client detail for the "who's here" page: a fun deterministic
    nickname, a coarse browser/OS, and how long they've been connected.
    Includes the facilitator, same as /presence/count, marked with
    `is_facilitator: true` so the page can mark the role. Shown to every
    viewer, not facilitator-gated — it's meant as a bit of a moment for
    everyone else, not an admin tool."""
    now = time.monotonic()
    with session._lifecycle_lock:
        yoda = session._facilitator_client_id()
        rows = []
        for cid, last in session._clients.items():
            if now - last > session._PRESENCE_WINDOW:
                continue
            browser, os_name = session._parse_user_agent(session._user_agents.get(cid, ""))
            rows.append({
                "nickname": session._name_for(cid),
                "is_facilitator": cid == yoda,
                "browser": browser,
                "os": os_name,
                "connected_seconds": round(now - session._first_seen.get(cid, last)),
            })
    rows.sort(key=lambda r: r["connected_seconds"], reverse=True)
    return {"clients": rows}


@bp.route("/who")
def who_page():
    """The "who's here" page itself — a live list rendered client-side from
    /presence/list (see who.html)."""
    return render_template("who.html")


# --- Reload ---------------------------------------------------------------
@bp.route("/reload", methods=["POST"])
def reload_caches():
    """Drop every server-side cache, so the next render re-reads the vault
    and recompiles the templates from disk. The footer button behind this
    posts here and then reloads the page.

    Most of the time nothing here is needed: `_parse` is keyed by (path,
    mtime_ns, size) and the folder listings are re-globbed per request, so a
    fresh ingest's new, edited and deleted pages already show up on an
    ordinary browser refresh. Two things do not, and they are why the button
    exists — a rewrite that lands on the same mtime and size (a restored file,
    a checkout, a timestamp-preserving copy) stays a cache hit forever, and Jinja compiles
    each template once per worker, so an edited template otherwise needs the
    process restarted. Clearing both costs one re-parse of the vault, which
    is milliseconds at workshop scale.

    Open to every viewer, unlike the facilitator-only controls below: it
    reads the same read-only files any page render already reads, and the
    worst a stranger can do with it is make one render slower.

    POST-only on purpose. A GET would let a prefetch or a crawler flush the
    cache on someone else's behalf."""
    _clear_caches()
    return {"ok": True}


def _clear_caches() -> None:
    """Drop the parsed wiki pages, the parsed metamodel and anchor pages, and
    Jinja's compiled templates. Used by /reload and by saving the view."""
    with wiki._PARSE_LOCK:
        wiki._PARSE_CACHE.clear()
    metamodel.clear_caches()
    if current_app.jinja_env.cache is not None:
        current_app.jinja_env.cache.clear()


@bp.route("/settings", methods=["GET"])
def settings_get():
    """The View dialog's data: the catalog grouped by area plus the
    current hide list. Open to every viewer (it is the same information the
    home page shows); saving is facilitator-only (POST below)."""
    cfg = settings.dashboard_config()
    return {
        "areas": [{"key": a["key"], "label": a["label"], "colors": a["colors"],
                   "sections": [{"id": s["id"], "title": s["title"], "colors": s["colors"],
                                 "scope": s["scope"]}
                                for s in catalog.sections_of(a["key"])]}
                  for a in catalog.AREAS],
        "hidden": cfg["hidden"],
    }


@bp.route("/settings", methods=["POST"])
def settings_post():
    """Facilitator-only: replace the view's hide list (in memory, FR-046).
    Same self-asserted client_id check as /disconnect-all — the facilitator is
    whoever connected first and is still here. Unknown IDs are a 400 and
    nothing changes; the dialog only ever sends catalog IDs, so a 400 here
    means a stale page or a hand-crafted request."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        if cid != session._facilitator_client_id():
            abort(403)
    data = _json_object(request)
    valid, unknown = session._validate_hidden(data.get("hidden"))
    if unknown or not isinstance(data.get("hidden"), list):
        return {"error": "unknown", "unknown": unknown}, 400
    session.set_view(valid)
    _clear_caches()
    return {"ok": True, "hidden": valid}


# --- Facilitator-only controls -------------------------------------------
#
# No token, no cookie, no `remote_addr` check (which can't work here anyway:
# under Docker Desktop's NAT, the facilitator's own `localhost:8080` request
# and a tunnel's forwarded client traffic arrive at the container
# looking identical). The facilitator is just "Yoda" — whoever connected
# first and is still here, or the heir once it left (`_facilitator_client_id`) — and the only shared
# secret involved is each tab's own random client_id, which is never shown
# to any other tab (nicknames on /who are derived from it, not equal to it).
# base.html only shows the "Disconnect all" button once a /ping response
# says `is_facilitator: true`; the server enforces the same check again here
# regardless of what the button shows, since the client_id in this POST body
# is otherwise just as self-asserted as a browser's own /ping.
@bp.route("/disconnect-all", methods=["POST"])
def disconnect_all():
    """Facilitator-only: end the session for every connected browser by
    shutting the server down outright (`session._shutdown`). Everyone else's
    next /ping then fails, which the footer script turns into a plain
    "session ended" notice (base.html)."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        if cid != session._facilitator_client_id():
            abort(403)
    session._shutdown("disconnect-all requested by facilitator")
    return ("", 204)
