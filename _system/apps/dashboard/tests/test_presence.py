"""Multi-client presence tracking and the "Yoda" facilitator.

Covers the addendum to DR-022: presence moved from a single "last seen"
scalar to a per-client_id dict; the facilitator ("Yoda") is whichever
currently-connected client connected first — no token, no cookie, just
connection order (see `_facilitator_client_id` in app.py). Names and the
role are sticky for the session: a name never changes, and the role passes
on only once its holder is gone, never back.

Run from the dashboard dir:
    .venv/bin/python tests/test_presence.py
"""
import json
import os
import signal
import sys
import tempfile
import time
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _ping(client, client_id, **kw):
    return client.post("/ping", data=json.dumps({"client_id": client_id}),
                        content_type="application/json", **kw)


def _reset_presence():
    """Presence state is module-global (mirrors production); each test
    starts from a clean slate rather than depending on run order."""
    with app._lifecycle_lock:
        app._clients.clear()
        app._leaving.clear()
        app._first_seen.clear()
        app._user_agents.clear()
        app._names.clear()
        app._facilitator = None


def test_ping_without_a_body_does_not_500():
    # Real pages always send a client_id, but a bare POST (curl, a stale
    # client) must not crash the presence dict.
    _reset_presence()
    client = app.app.test_client()
    resp = client.post("/ping")
    assert resp.status_code == 200
    assert resp.get_json()["nickname"]


def test_presence_count_reflects_distinct_clients():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "alice")
    _ping(client, "bob")
    _ping(client, "alice")  # a second tab load from the same tab: no double count
    resp = client.get("/presence/count")
    assert resp.status_code == 200
    assert resp.get_json()["count"] == 2, resp.get_json()  # alice (Yoda) and bob


def test_presence_count_excludes_clients_outside_the_active_window():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "carol")
    with app._lifecycle_lock:
        app._clients["carol"] = app.time.monotonic() - (app._PRESENCE_WINDOW + 5)
    assert client.get("/presence/count").get_json()["count"] == 0


def test_leaving_then_repinging_the_same_client_cancels_the_leave():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "dana")
    client.post("/leaving", data=json.dumps({"client_id": "dana"}),
                content_type="application/json")
    _ping(client, "dana")  # same tab, in-page navigation
    with app._lifecycle_lock:
        assert "dana" not in app._leaving


def test_first_client_is_the_facilitator_not_the_second():
    # The bug report this fixes: every localhost tab used to get the
    # "Disconnect all" button (a shared token, claimed by any tab that ever
    # loaded the link). Now only the earliest-still-connected client is.
    _reset_presence()
    client = app.app.test_client()
    first = _ping(client, "yoda").get_json()
    second = _ping(client, "luke").get_json()
    assert first["is_facilitator"] is True
    assert second["is_facilitator"] is False


def test_the_facilitator_is_literally_named_yoda_not_a_random_nickname():
    _reset_presence()
    client = app.app.test_client()
    first = _ping(client, "first-in").get_json()
    second = _ping(client, "second-in").get_json()
    assert first["nickname"] == "Yoda"
    assert second["nickname"] != "Yoda" and second["nickname"]


def test_a_stale_earliest_client_does_not_block_the_facilitator_role():
    # Regression: a tab past the heartbeat grace that the watchdog has not
    # evicted yet must not hold the role, or the genuinely active client
    # never passes `cid == _facilitator_client_id()` and nobody gets the
    # button.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "long-gone")  # first ever, but about to go stale
    _go_stale("long-gone")
    resp = _ping(client, "yoda").get_json()  # the only *currently* connected client
    assert resp["is_facilitator"] is True


def test_facilitator_role_transfers_when_yoda_disconnects():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    with app._lifecycle_lock:
        app._forget_client("yoda")  # yoda's tab is gone (evicted by the watchdog)
    resp = _ping(client, "luke").get_json()
    assert resp["is_facilitator"] is True


def _go_stale(client_id):
    """Push a client's last ping just past the heartbeat grace, as when its
    browser quits without a goodbye. The watchdog evicts it on its next
    tick, but the role must not wait for that."""
    with app._lifecycle_lock:
        app._clients[client_id] = app.time.monotonic() - (app._HEARTBEAT_GRACE + 5)


def _go_background(client_id):
    """Push a client's last ping just past the presence window, as when a
    background tab is throttled to about one ping a minute (issue #56)."""
    with app._lifecycle_lock:
        app._clients[client_id] = app.time.monotonic() - (app._PRESENCE_WINDOW + 5)


def _evict(client_id):
    """What the watchdog does to a tab that stayed silent past the grace."""
    _go_stale(client_id)
    with app._lifecycle_lock:
        app._forget_client(client_id)


def _post(client, path, client_id, **body):
    return client.post(path, data=json.dumps({"client_id": client_id, **body}),
                       content_type="application/json")


def test_a_holder_in_a_background_tab_keeps_the_role():
    # Issue #56: the holder's tab is throttled and its last ping is 35 s
    # old. The second tab's ping must not take the role, and the holder's
    # own rights stay intact. The footer counter still uses the 30 s window.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    _go_background("yoda")
    assert _ping(client, "luke").get_json()["is_facilitator"] is False
    assert _post(client, "/settings", "luke", hidden=[]).status_code == 403
    assert _post(client, "/disconnect-all", "luke").status_code == 403
    assert client.get("/presence/count").get_json()["count"] == 1
    assert _post(client, "/settings", "yoda", hidden=[]).status_code == 200
    assert _ping(client, "yoda").get_json()["is_facilitator"] is True


def test_the_role_passes_to_the_next_earliest_tab_once_the_holder_is_evicted():
    # The holder stays silent past the heartbeat grace and the watchdog
    # evicts it. The next-earliest tab inherits the role, even while that
    # tab is itself only in the background.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    _ping(client, "leia")
    _go_stale("yoda")
    with app._lifecycle_lock:
        app._forget_client("yoda")  # what the watchdog does on its next tick
    _go_background("luke")
    assert _ping(client, "leia").get_json()["is_facilitator"] is False
    assert _ping(client, "luke").get_json()["is_facilitator"] is True


def test_the_heir_keeps_the_role_when_the_old_holder_returns():
    # After the role passed on, the old holder's tab connects again with the
    # same client_id. The heir keeps the role while it is present, even in
    # the background, and the old holder keeps its name.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    _go_stale("yoda")
    with app._lifecycle_lock:
        app._forget_client("yoda")
    assert _ping(client, "luke").get_json()["is_facilitator"] is True
    back = _ping(client, "yoda").get_json()
    assert back["is_facilitator"] is False and back["nickname"] == "Yoda"
    _go_background("luke")
    assert _ping(client, "yoda").get_json()["is_facilitator"] is False
    assert _post(client, "/disconnect-all", "yoda").status_code == 403
    assert _ping(client, "luke").get_json()["is_facilitator"] is True


def test_a_returning_holder_queues_behind_the_tabs_that_were_there():
    # Issue #56, the rule Gernot Starke chose on 2026-11-21: when the holder
    # leaves, the earliest present tab gets the role. A former holder that
    # comes back counts as connected at its return, so it stands behind
    # every tab that was there then.
    _reset_presence()
    client = app.app.test_client()
    for cid in ("yoda", "luke", "leia"):
        _ping(client, cid)
    _evict("yoda")
    assert _ping(client, "luke").get_json()["is_facilitator"] is True
    _ping(client, "yoda")  # the first holder is back
    _evict("luke")
    assert _ping(client, "yoda").get_json()["is_facilitator"] is False
    assert _ping(client, "leia").get_json()["is_facilitator"] is True


def test_a_former_holder_can_hold_the_role_again_when_it_is_the_earliest_left():
    # The same rule from the other side: there is always a Keyholder. A
    # former holder gets the role again once every tab that was there at
    # its return is gone, also ahead of a tab that joined after it.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    _evict("yoda")
    assert _ping(client, "luke").get_json()["is_facilitator"] is True
    _ping(client, "yoda")
    _ping(client, "leia")  # joins after yoda's return
    _evict("luke")
    assert _ping(client, "leia").get_json()["is_facilitator"] is False
    assert _ping(client, "yoda").get_json()["is_facilitator"] is True
    assert _post(client, "/settings", "yoda", hidden=[]).status_code == 200
    assert _post(client, "/settings", "leia", hidden=[]).status_code == 403


def test_the_role_does_not_flip_back_when_the_old_yoda_reappears():
    # Regression (2026-10-28): the role was recomputed on every call, so
    # with Yoda's tab hovering around the presence window the second client
    # was "Yoda", then itself again, then "Yoda" again.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    _ping(client, "luke")
    _go_stale("yoda")
    assert _ping(client, "luke").get_json()["is_facilitator"] is True
    back = _ping(client, "yoda").get_json()   # old tab pings again
    assert back["is_facilitator"] is False
    assert _ping(client, "luke").get_json()["is_facilitator"] is True


def test_names_are_sticky_across_a_role_transfer():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    luke_name = _ping(client, "luke").get_json()["nickname"]
    assert luke_name != "Yoda"
    _go_stale("yoda")
    heir = _ping(client, "luke").get_json()
    assert heir["is_facilitator"] is True and heir["nickname"] == luke_name
    assert _ping(client, "yoda").get_json()["nickname"] == "Yoda"
    rows = client.get("/presence/list").get_json()["clients"]
    assert sorted(r["nickname"] for r in rows) == sorted(["Yoda", luke_name]), rows


def test_a_name_survives_eviction_and_return():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    name = _ping(client, "mickey").get_json()["nickname"]
    with app._lifecycle_lock:
        app._forget_client("mickey")
    assert _ping(client, "mickey").get_json()["nickname"] == name


def test_presence_count_includes_the_current_facilitator():
    # Yoda's own tab is a client like any other: a facilitator alone in the
    # room must see "1 client", not "0 clients" next to "Welcome, Yoda"
    # (reported 2026-09-08; reverses the earlier exclusion in DR-022).
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")             # connects first -> becomes facilitator
    assert client.get("/presence/count").get_json()["count"] == 1
    _ping(client, "alice")
    _ping(client, "bob")
    assert client.get("/presence/count").get_json()["count"] == 3


def test_presence_list_reports_nickname_browser_and_duration():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")  # connects first -> facilitator, listed as "Yoda"
    _ping(client, "erin",
          headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                                  "Chrome/120.0 Safari/537.36"})
    resp = client.get("/presence/list").get_json()
    assert len(resp["clients"]) == 2, resp
    p = next(c for c in resp["clients"] if not c["is_facilitator"])
    assert p["browser"] == "Chrome" and p["os"] == "macOS", p
    assert isinstance(p["connected_seconds"], int)
    assert p["nickname"] and p["nickname"] != "Yoda"  # non-empty, stable for the same client_id


def test_nickname_is_stable_for_the_same_client_id():
    assert app._nickname("same-id") == app._nickname("same-id")


def test_presence_list_shows_the_facilitator_as_yoda():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")   # connects first -> the only client -> facilitator
    _ping(client, "erin")
    rows = client.get("/presence/list").get_json()["clients"]
    yodas = [r for r in rows if r["is_facilitator"]]
    assert len(yodas) == 1 and yodas[0]["nickname"] == "Yoda", rows
    assert rows[0] is not None and rows[0]["nickname"] == "Yoda", "longest-connected first"


def test_disconnect_all_rejects_a_non_facilitator():
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    resp = client.post("/disconnect-all", data=json.dumps({"client_id": "luke"}),
                        content_type="application/json")
    assert resp.status_code == 403
    with app._lifecycle_lock:
        assert app._shutting_down is False


def test_disconnect_all_accepts_the_facilitator():
    # The real shutdown SIGTERMs this process *and its parent* 0.4 s later
    # (`_shutdown` → `_terminate`): under a test runner or a CI shell that
    # parent is the runner itself. Record the signals instead of sending
    # them, and wait for every one so none can fire after the restore.
    _reset_presence()
    client = app.app.test_client()
    _ping(client, "yoda")
    sent = []
    real_kill = app.os.kill
    app.os.kill = lambda pid, sig: sent.append((pid, sig))
    try:
        resp = client.post("/disconnect-all", data=json.dumps({"client_id": "yoda"}),
                            content_type="application/json")
        assert resp.status_code == 204
        with app._lifecycle_lock:
            assert app._shutting_down is True
        # Outside the dev server `_terminate` signals the parent (gunicorn's
        # master) and then this process: wait for BOTH, or the second could
        # land after the restore below and hit the real os.kill.
        expected = [(os.getppid(), signal.SIGTERM), (os.getpid(), signal.SIGTERM)]
        deadline = time.monotonic() + 3
        while len(sent) < len(expected) and time.monotonic() < deadline:
            time.sleep(0.05)
        assert sent == expected, sent
    finally:
        app.os.kill = real_kill
        # undo, so later tests in this process aren't affected by the shutdown flag
        app._shutting_down = False


def test_a_page_restored_from_the_bfcache_pings_again():
    # Regression (Firefox): Back/Forward restores a page from the bfcache
    # without reloading it, so base.html's load-time ping never runs — while
    # the page just left has already sent /leaving. The server then dropped
    # the only tab after the ~5s leave grace and shut down with the page
    # still open. A `pageshow` with `persisted` must ping straight away.
    # Required by QR-004 (current browser support).
    base = (Path(app.__file__).parent / "templates" / "base.html").read_text(encoding="utf-8")
    i = base.find('addEventListener("pageshow"')
    assert i != -1, "base.html has no pageshow handler"
    handler = base[i:base.find("});", i)]
    assert "persisted" in handler and "ping()" in handler, handler


if __name__ == "__main__":
    test_ping_without_a_body_does_not_500()
    test_presence_count_reflects_distinct_clients()
    test_presence_count_excludes_clients_outside_the_active_window()
    test_leaving_then_repinging_the_same_client_cancels_the_leave()
    test_first_client_is_the_facilitator_not_the_second()
    test_the_facilitator_is_literally_named_yoda_not_a_random_nickname()
    test_a_stale_earliest_client_does_not_block_the_facilitator_role()
    test_facilitator_role_transfers_when_yoda_disconnects()
    test_a_holder_in_a_background_tab_keeps_the_role()
    test_the_role_passes_to_the_next_earliest_tab_once_the_holder_is_evicted()
    test_the_heir_keeps_the_role_when_the_old_holder_returns()
    test_a_returning_holder_queues_behind_the_tabs_that_were_there()
    test_a_former_holder_can_hold_the_role_again_when_it_is_the_earliest_left()
    test_the_role_does_not_flip_back_when_the_old_yoda_reappears()
    test_names_are_sticky_across_a_role_transfer()
    test_a_name_survives_eviction_and_return()
    test_presence_count_includes_the_current_facilitator()
    test_presence_list_reports_nickname_browser_and_duration()
    test_nickname_is_stable_for_the_same_client_id()
    test_presence_list_shows_the_facilitator_as_yoda()
    test_disconnect_all_rejects_a_non_facilitator()
    test_disconnect_all_accepts_the_facilitator()
    test_a_page_restored_from_the_bfcache_pings_again()
    print("all presence/disconnect-all tests passed")
