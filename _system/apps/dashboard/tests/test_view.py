"""The view (FR-046): what the Keyholder hides for one session. It lives in
the running dashboard only and is written to no file. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_view.py
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "glossary", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

# A whole repository, so the tests can show that nothing in it changes.
_repo = Path(tempfile.mkdtemp())
for _f in WIKI_FOLDERS:
    (_repo / "wiki" / _f).mkdir(parents=True)
(_repo / "raw" / "sources").mkdir(parents=True)
(_repo / "_system").mkdir()
(_repo / "_system" / "wiki.yaml").write_text('system_name: "Demo"\n', encoding="utf-8")
for _var in ("WIKI_DIR", "RAW_SOURCES_DIR", "WIKI_CONFIG", "DOCS_DIR"):
    os.environ.pop(_var, None)
os.environ["REPO_DIR"] = str(_repo)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))  # import app.py

import app  # noqa: E402


def _reset_presence():
    with app._lifecycle_lock:
        app._clients.clear()
        app._leaving.clear()
        app._first_seen.clear()
        app._user_agents.clear()


def _ping(client, cid):
    return client.post("/ping", data=json.dumps({"client_id": cid}),
                       content_type="application/json")


def _post_view(client, cid, hidden):
    return client.post("/settings", data=json.dumps({"client_id": cid, "hidden": hidden}),
                       content_type="application/json")


def _snapshot():
    """Every file of the repository with its content hash."""
    return {str(p.relative_to(_repo)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(_repo.rglob("*")) if p.is_file()}


def test_nothing_is_hidden_at_the_start():
    app.set_view([])
    assert app.dashboard_config() == {"hidden": []}
    assert [a["key"] for a in app.visible_areas()] == ["requirements", "architecture", "commons"]
    assert len(app.visible_sections("commons")) == 7


def test_the_view_is_normalised_and_ordered():
    app.set_view(["C6", "bogus", "architecture", "C6", "r2"])
    try:
        assert app.dashboard_config()["hidden"] == ["architecture", "R2", "C6"]  # catalog order, deduped
        assert app.is_hidden("C6") and app.is_hidden("A3") and app.is_hidden("architecture")
        assert not app.is_hidden("C1")
        assert [a["key"] for a in app.visible_areas()] == ["requirements", "commons"]
        assert [s["id"] for s in app.visible_sections("requirements")] == ["R1", "R3", "R4", "R5", "R6"]
    finally:
        app.set_view([])


def test_the_dialog_lists_the_catalog_and_the_view():
    app.set_view(["R2"])
    try:
        data = app.app.test_client().get("/settings").get_json()
    finally:
        app.set_view([])
    assert [a["key"] for a in data["areas"]] == ["requirements", "architecture", "commons"]
    assert [s["id"] for s in data["areas"][2]["sections"]] == ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]
    assert data["hidden"] == ["R2"]
    # the dialog colours itself from the catalog: every area and section carries its colours
    assert data["areas"][0]["colors"] == ["req"] and data["areas"][2]["colors"] == ["req", "arc"]
    c3 = next(s for s in data["areas"][2]["sections"] if s["id"] == "C3")
    assert c3["colors"] == ["req", "arc"] and c3["scope"] == "in"


def test_only_the_keyholder_changes_the_view():
    _reset_presence()
    app.set_view([])
    c = app.app.test_client()
    _ping(c, "yoda")            # first connected: holds the keys
    _ping(c, "padawan")
    assert _post_view(c, "padawan", ["C1"]).status_code == 403
    assert app.dashboard_config()["hidden"] == []
    r = _post_view(c, "yoda", ["C1", "A2"])
    assert r.status_code == 200 and r.get_json() == {"ok": True, "hidden": ["A2", "C1"]}
    assert app.dashboard_config()["hidden"] == ["A2", "C1"]
    app.set_view([])


def test_unknown_ids_are_refused_and_change_nothing():
    _reset_presence()
    app.set_view(["C1"])
    c = app.app.test_client()
    _ping(c, "yoda")
    r = _post_view(c, "yoda", ["C1", "nope"])
    assert r.status_code == 400 and r.get_json()["unknown"] == ["nope"]
    assert app.dashboard_config()["hidden"] == ["C1"]
    assert c.post("/settings").status_code in (400, 403)   # no body: no error page
    app.set_view([])


def test_hidden_section_and_area_leave_the_top_bar():
    app.set_view(["C4", "commons"])
    try:
        html = app.app.test_client().get("/issues").get_data(as_text=True)
    finally:
        app.set_view([])
    nav = re.search(r'<nav class="mainnav"[^>]*>(.*?)</nav>', html, re.S).group(1)
    assert re.findall(r">([^<]+)</a>", nav) == ["Requirements", "Architecture"], nav
    assert 'href="/commons"' not in html and 'href="/req42"' in html


def test_three_devices_share_the_view_and_no_file_changes():
    """The success metric of FR-046: three devices join, the Keyholder hides a
    section, it is gone from the home page on all three after a reload, and
    the wiki's repository holds no changed file."""
    _reset_presence()
    app.set_view([])
    before = _snapshot()
    devices = {cid: app.app.test_client() for cid in ("yoda", "second", "third")}
    for cid, client in devices.items():
        assert _ping(client, cid).status_code == 200
    shown = 'href="/stakeholders"'              # section C4 on the home page
    for client in devices.values():
        assert shown in client.get("/").get_data(as_text=True)
    assert _post_view(devices["yoda"], "yoda", ["C4"]).status_code == 200
    try:
        for cid, client in devices.items():
            assert shown not in client.get("/").get_data(as_text=True), f"{cid} still sees C4"
        # hidden, not gone: the address still answers
        assert devices["third"].get("/stakeholders").status_code == 200
    finally:
        app.set_view([])
    assert _snapshot() == before, "the dashboard changed a file in the repository"


def test_a_restart_shows_everything_again():
    """A view does not outlive the dashboard: a fresh process hides nothing,
    even where a settings file of an older release hides a section."""
    old = _repo / "_system" / "dashboard.yaml"
    old.write_text("hidden: [C1, architecture]\n", encoding="utf-8")
    try:
        out = subprocess.run([sys.executable, "-c", "import app; print(app.dashboard_config())"],
                             cwd=HERE, env=dict(os.environ), capture_output=True, text=True)
    finally:
        old.unlink()
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "{'hidden': []}", out.stdout


def test_the_dialog_is_called_view():
    html = app.app.test_client().get("/").get_data(as_text=True)
    assert ">View…<" in html and '<h2 id="settings-title">View</h2>' in html
    assert "Configure" not in html and "dashboard.yaml" not in html


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: view")
