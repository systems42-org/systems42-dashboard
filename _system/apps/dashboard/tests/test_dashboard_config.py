"""Visibility configuration (_system/dashboard.yaml) — the one file the
dashboard writes. Hide list semantics, facilitator-only saving, in-place
writes (a bind-mounted file must keep its inode). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_dashboard_config.py
"""
import json
import os
import re
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "glossary", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "use-cases", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
(_tmp / "sources").mkdir()
_cfg = _tmp / "dashboard.yaml"
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_cfg)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

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


def _post_settings(client, cid, hidden):
    return client.post("/settings", data=json.dumps({"client_id": cid, "hidden": hidden}),
                       content_type="application/json")


def test_missing_file_hides_nothing():
    if _cfg.exists():
        _cfg.unlink()
    cfg = app.dashboard_config()
    assert cfg == {"hidden": [], "unknown": []}, cfg
    assert [a["key"] for a in app.visible_areas()] == ["requirements", "architecture", "commons"]
    assert len(app.visible_sections("commons")) == 7


def test_malformed_file_hides_nothing():
    _cfg.write_text("hidden: {not: [a list", encoding="utf-8")
    assert app.dashboard_config()["hidden"] == []
    _cfg.write_text("hidden: notalist\n", encoding="utf-8")
    assert app.dashboard_config()["hidden"] == []
    _cfg.write_text("hidden: c6\n", encoding="utf-8")
    assert app.dashboard_config()["hidden"] == ["C6"]     # scalar = one-item list
    _cfg.write_text("hidden: 5\n", encoding="utf-8")
    assert app.dashboard_config()["hidden"] == []


def test_hide_list_is_validated_normalised_and_ordered():
    _cfg.write_text("hidden: [C6, bogus, architecture, C6, r2]\n", encoding="utf-8")
    cfg = app.dashboard_config()
    assert cfg["hidden"] == ["architecture", "R2", "C6"], cfg   # catalog order, deduped, case-folded IDs
    assert cfg["unknown"] == ["bogus"], cfg
    assert app.is_hidden("C6") and app.is_hidden("A3") and app.is_hidden("architecture")
    assert not app.is_hidden("C1")
    assert [a["key"] for a in app.visible_areas()] == ["requirements", "commons"]
    assert [s["id"] for s in app.visible_sections("requirements")] == ["R1", "R3", "R4", "R5", "R6"]
    assert [s["id"] for s in app.visible_sections("commons")] == ["C1", "C2", "C3", "C4", "C5", "C7"]


def test_write_is_in_place_and_round_trips():
    _cfg.write_text("hidden: []\n", encoding="utf-8")
    inode_before = _cfg.stat().st_ino
    app.write_dashboard_config(["C2", "architecture"])
    assert _cfg.stat().st_ino == inode_before, "must rewrite in place (bind-mounted file)"
    text = _cfg.read_text(encoding="utf-8")
    assert text.startswith("#"), text                     # comment header survives a rewrite
    assert app.dashboard_config()["hidden"] == ["architecture", "C2"]
    app.write_dashboard_config([])
    assert app.dashboard_config()["hidden"] == []


def test_get_settings_lists_catalog_and_hidden():
    _cfg.write_text("hidden: [R2]\n", encoding="utf-8")
    r = app.app.test_client().get("/settings")
    assert r.status_code == 200
    data = r.get_json()
    assert [a["key"] for a in data["areas"]] == ["requirements", "architecture", "commons"]
    assert [s["id"] for s in data["areas"][2]["sections"]] == ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]
    assert data["hidden"] == ["R2"]
    # the dialog colours itself from the catalog: every area and section carries its colours
    assert data["areas"][0]["colors"] == ["req"] and data["areas"][2]["colors"] == ["req", "arc"]
    c3 = next(s for s in data["areas"][2]["sections"] if s["id"] == "C3")
    assert c3["colors"] == ["req", "arc"] and c3["scope"] == "in"
    assert data["areas"][1]["sections"][0]["scope"] == "planned"


def test_post_settings_is_facilitator_only():
    _reset_presence()
    _cfg.write_text("hidden: []\n", encoding="utf-8")
    c = app.app.test_client()
    _ping(c, "yoda")            # first connected → facilitator
    _ping(c, "padawan")
    r = _post_settings(c, "padawan", ["C1"])
    assert r.status_code == 403, r.status_code
    assert app.dashboard_config()["hidden"] == []
    r = _post_settings(c, "yoda", ["C1", "A2"])
    assert r.status_code == 200 and r.get_json() == {"ok": True, "hidden": ["A2", "C1"]}
    assert app.dashboard_config()["hidden"] == ["A2", "C1"]


def test_post_settings_rejects_unknown_ids_without_writing():
    _reset_presence()
    _cfg.write_text("hidden: [C1]\n", encoding="utf-8")
    c = app.app.test_client()
    _ping(c, "yoda")
    r = _post_settings(c, "yoda", ["C1", "nope"])
    assert r.status_code == 400 and r.get_json()["unknown"] == ["nope"]
    assert _cfg.read_text(encoding="utf-8") == "hidden: [C1]\n"


def test_post_settings_without_body_does_not_500():
    _reset_presence()
    c = app.app.test_client()
    r = c.post("/settings")
    assert r.status_code in (400, 403), r.status_code


def test_hidden_section_and_area_leave_nav_and_footer():
    _cfg.write_text("hidden: [C4, commons]\n", encoding="utf-8")
    try:
        html = app.app.test_client().get("/issues").get_data(as_text=True)
    finally:
        _cfg.unlink()
    nav = re.search(r'<nav class="mainnav"[^>]*>(.*?)</nav>', html, re.S).group(1)
    assert re.findall(r">([^<]+)</a>", nav) == ["Goals", "Functional Reqs"], nav
    assert 'href="/commons"' not in html and 'href="/req42"' in html


if __name__ == "__main__":
    test_missing_file_hides_nothing()
    test_malformed_file_hides_nothing()
    test_hide_list_is_validated_normalised_and_ordered()
    test_write_is_in_place_and_round_trips()
    test_get_settings_lists_catalog_and_hidden()
    test_post_settings_is_facilitator_only()
    test_post_settings_rejects_unknown_ids_without_writing()
    test_post_settings_without_body_does_not_500()
    test_hidden_section_and_area_leave_nav_and_footer()
    print("OK: dashboard config")
