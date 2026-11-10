"""Area pages (/req42, /arc42, /commons) and area-level breadcrumbs. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_areas.py
"""
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
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

STK = """---
id: STK-001
type: stakeholder
title: Shop owner
status: draft
created: 2026-10-11
updated: 2026-10-11
sources: []
related: []
tags: [stakeholder]
---

# Shop owner
"""


def _get(path):
    app._PARSE_CACHE.clear()
    r = app.app.test_client().get(path)
    return r.status_code, r.get_data(as_text=True)


def _tiles(body):
    return re.findall(r'class="tile(?: tile-link)? tile-([a-z]\d)', body)


def test_requirements_area_lists_its_sections_in_order():
    if _cfg.exists():
        _cfg.unlink()
    code, body = _get("/req42")
    assert code == 200
    assert _tiles(body) == ["r1", "r2", "r3", "r4", "r5", "r6"], _tiles(body)
    assert "goals, needs, constraints" in body
    assert "req42-block" not in body and "twelve building blocks" not in body


def test_architecture_area_has_a2_to_a5_live_and_a1_planned():
    code, body = _get("/arc42")
    assert code == 200
    assert _tiles(body) == ["a1", "a2", "a3", "a4", "a5"]
    assert body.count("Not captured yet") == 1      # A1 planned; A2-A5 live
    for href in ("/arc42/building-blocks", "/arc42/deployment", "/arc42/runtime", "/arc42/concepts"):
        assert f'href="{href}"' in body, href


def test_commons_area_lists_c1_to_c7():
    code, body = _get("/commons")
    assert code == 200
    assert _tiles(body) == ["c1", "c2", "c3", "c4", "c5", "c6", "c7"]


def test_hidden_section_drops_tile_but_route_stays():
    _cfg.write_text("hidden: [C4, R2]\n", encoding="utf-8")
    _, body = _get("/commons")
    assert "c4" not in _tiles(body) and "c1" in _tiles(body)
    _, body = _get("/req42")
    assert "r2" not in _tiles(body)
    code, _ = _get("/stakeholders")
    assert code == 200
    _cfg.unlink()


def test_hidden_area_page_still_renders_by_url():
    _cfg.write_text("hidden: [architecture]\n", encoding="utf-8")
    code, body = _get("/arc42")
    assert code == 200 and _tiles(body) == ["a1", "a2", "a3", "a4", "a5"]
    _cfg.unlink()


def test_breadcrumbs_carry_the_area():
    (_wiki / "stakeholders" / "STK-001-shop-owner.md").write_text(STK, encoding="utf-8")
    try:
        for path, area in (("/stakeholders", "Commons"), ("/goals", "Requirements"),
                           ("/req42/functional-requirements", "Requirements"), ("/req42/quality", "Commons"),
                           ("/glossary", "Commons"), ("/issues", "Commons"),
                           ("/page/stakeholders/STK-001-shop-owner", "Commons")):
            _, body = _get(path)
            crumbs = re.search(r'<nav class="crumbs">(.*?)</nav>', body, re.S)
            assert crumbs, path
            assert '<a href="/">Home</a>' in crumbs.group(1), path
            assert f">{area}</a>" in crumbs.group(1), (path, crumbs.group(1))
            assert "Overview" not in crumbs.group(1), path
    finally:
        (_wiki / "stakeholders" / "STK-001-shop-owner.md").unlink()


def test_unknown_area_404s():
    code, _ = _get("/nope42")
    assert code == 404


if __name__ == "__main__":
    test_requirements_area_lists_its_sections_in_order()
    test_architecture_area_has_a2_to_a5_live_and_a1_planned()
    test_commons_area_lists_c1_to_c7()
    test_hidden_section_drops_tile_but_route_stays()
    test_hidden_area_page_still_renders_by_url()
    test_breadcrumbs_carry_the_area()
    test_unknown_area_404s()
    print("OK: areas")
