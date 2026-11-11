"""Home page layout contract: two peaks (Requirements, Architecture), the
valley between them (status, latest changes, open issues), Commons below,
persistent nav. No pytest.

The home page is what a workshop sees on the projector first. Area tiles must
come in that order and link to their area pages, every page must carry the
same navigation bar, and the reader must be able to tell at a glance what
moved in the vault since they last looked.

Run from the dashboard dir:
    .venv/bin/python tests/test_home_layout.py
"""
import os
import re
import sys
import tempfile
import time
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
os.environ["DASHBOARD_CONFIG"] = str(_cfg)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402

QR = """---
id: QR-001
type: quality-requirement
title: Fast checkout
status: draft
created: 2026-09-07
updated: 2026-09-07
sources: []
related: []
tags: [quality-requirement]
---

# Fast checkout
"""
PAGE = """---
id: {id}
type: {type}
title: {title}
status: draft
created: 2026-09-07
updated: 2026-09-07
sources: []
related: []
tags: [{type}]
---

# {title}
"""

ORDER = ["area-tile-requirements", "valley", "area-tile-architecture", "area-tile-commons"]
NAV = ["Requirements", "Architecture", "Glossary", "Decisions", "Issues"]


def _home():
    app._PARSE_CACHE.clear()
    return app.app.test_client().get("/").get_data(as_text=True)


def test_home_shows_two_peaks_the_valley_and_commons_in_order():
    if _cfg.exists():
        _cfg.unlink()
    body = _home()
    positions = [body.index(k) for k in ORDER]
    assert positions == sorted(positions), positions
    for old in ("tile-r1", "tile-c6", "tile-adrs", "tile-changes", "tile-issues", 'class="tiles"'):
        assert old not in body, old
    for sub in ("goals, needs, constraints", "structure, interfaces, views", "shared by both peaks"):
        assert sub in body, sub


def test_area_tiles_link_to_area_pages_and_list_sections():
    body = _home()
    assert 'href="/req42"' in body and 'href="/arc42"' in body and 'href="/commons"' in body
    req = body[body.index("area-tile-requirements"):body.index("valley")]
    assert "R1" in req and "R3" in req and "R4" in req and "R2" in req
    com = body[body.index("area-tile-commons"):]
    for sid in ("C1", "C2", "C3", "C4", "C5", "C6"):
        assert sid in com, sid
    arc = body[body.index("area-tile-architecture"):body.index("area-tile-commons")]
    assert "A2" in arc and "Building Block View" in arc


def test_section_lines_link_to_their_pages_and_tiles_are_not_one_big_link():
    """The upper block of a home tile (head, count, maturity) is one link to the
    area page. R1/C1/... open that section's page; a section without a page of
    its own (R2, A1-A5) deep-links to its tile on the area page. The tile itself
    is a section element so these inner links are valid HTML (no <a> in <a>)."""
    body = _home()
    assert not re.search(r'<a class="area-tile[ "]', body), "the tile must not be one big link"
    req = body[body.index("area-tile-requirements"):body.index("valley")]
    top = req[req.index('<a class="area-tile-top" href="/req42">'):req.index("</a>")]
    for part in ('class="tile-title"', 'class="area-subtitle"', 'class="tile-count"'):
        assert part in top, part
    assert '<a class="area-section-link" href="/goals"><code class="ml-id">R1</code>' in req, req
    assert 'href="/req42/functional-requirements"><code class="ml-id">R3</code>' in req
    assert 'href="/req42#tile-r2"><code class="ml-id">R2</code>' in req
    arc = body[body.index("area-tile-architecture"):body.index("area-tile-commons")]
    assert 'href="/arc42#tile-a1"><code class="ml-id">A1</code>' in arc and 'href="/arc42/concepts"><code class="ml-id">A5</code>' in arc
    assert "tile-a6" not in arc, "A6 moved to Commons as C7 Decisions (FR-009)"
    com = body[body.index("area-tile-commons"):]
    for sid, href in (("C1", "/req42/quality"), ("C4", "/stakeholders"), ("C5", "/glossary"), ("C6", "/issues"),
                      ("C7", "/decisions")):
        assert f'href="{href}"><code class="ml-id">{sid}</code>' in com, sid
    assert 'class="area-tile-top" href="/commons"' in com and 'class="tile-cta" href="/commons"' in com
    assert 'href="None"' not in body
    arc_page = app.app.test_client().get("/arc42").get_data(as_text=True)
    assert 'id="tile-a1"' in arc_page and 'id="tile-a5"' in arc_page, "deep-link targets exist"


def test_valley_carries_status_changes_issues_and_decisions_link():
    body = _home()
    valley = body[body.index('class="valley"'):body.index("area-tile-architecture")]
    assert 'class="vault-status"' in valley
    assert "open issue" in valley
    assert "Latest changes" in valley and "Open issues" in valley
    assert 'href="/decisions"' in valley


def test_hidden_area_and_section_leave_home():
    _cfg.write_text("hidden: [architecture, C6]\n", encoding="utf-8")
    try:
        body = _home()
        assert "area-tile-architecture" not in body
        com = body[body.index("area-tile-commons"):]
        assert "C6" not in com and "C5" in com
    finally:
        _cfg.unlink()


def test_area_with_every_section_hidden_reads_not_captured_yet():
    _cfg.write_text("hidden: [A1, A2, A3, A4, A5]\n", encoding="utf-8")
    try:
        body = _home()
        arc = body[body.index("area-tile-architecture"):body.index("area-tile-commons")]
        assert "Not captured yet" in arc and "0 pages" not in arc, arc
    finally:
        _cfg.unlink()


def test_unknown_hide_entry_is_a_warning_not_an_error():
    _cfg.write_text("hidden: [bogus]\n", encoding="utf-8")
    try:
        body = _home()
        assert 'class="config-warning"' in body and "bogus" in body
    finally:
        _cfg.unlink()
    assert 'class="config-warning"' not in _home()


def test_every_page_has_the_main_nav():
    c = app.app.test_client()
    for route in ("/", "/glossary", "/issues", "/req42/functional-requirements", "/arc42"):
        body = c.get(route).get_data(as_text=True)
        assert 'class="mainnav"' in body, route
        assert 'id="nav-search"' in body, route


def test_nav_is_short_and_brand_is_not_duplicated_on_home():
    c = app.app.test_client()
    home = c.get("/").get_data(as_text=True)
    sub = c.get("/issues").get_data(as_text=True)
    nav = re.search(r'<nav class="mainnav"[^>]*>(.*?)</nav>', home, re.S).group(1)
    assert re.findall(r">([^<]+)</a>", nav) == NAV, nav
    assert 'class="brand"' not in home and 'class="hero-mark' in home
    assert 'class="brand"' in sub
    for href in ('href="/req42"', 'href="/arc42"', 'href="/commons"', 'href="/glossary"', 'href="/decisions"'):
        assert href in home, href
    assert "e.key === \"k\"" in home and "e.key === \"/\"" not in home


def test_changes_lists_a_backdated_page_with_relative_time():
    f = _wiki / "quality-requirements" / "QR-001-fast-checkout.md"
    f.write_text(QR, encoding="utf-8")
    os.utime(f, (time.time() - 600, time.time() - 600))
    try:
        body = _home()
        valley = body[body.index('class="valley"'):body.index("area-tile-architecture")]
        assert "QR-001" in valley and "min ago" in valley
        q = _area("/commons")
        q = q[q.index("tile-c1"):q.index("tile-c2")]
        assert '<span class="num">1</span>' in q, q
    finally:
        f.unlink()


def _area(route):
    app._PARSE_CACHE.clear()
    return app.app.test_client().get(route).get_data(as_text=True)


def test_recent_changes_shape():
    (_wiki / "glossary" / "GLO-001-x.md").write_text(
        QR.replace("QR-001", "GLO-001").replace("quality-requirement", "glossary-term"),
        encoding="utf-8")
    try:
        app._PARSE_CACHE.clear()
        rows = app.recent_changes(5)
        assert rows and set(rows[0]) >= {"id", "title", "kind", "url", "when"}, rows
        assert rows[0]["url"] == "/page/glossary/GLO-001-x"
    finally:
        (_wiki / "glossary" / "GLO-001-x.md").unlink()


def _write(folder, stem, **kw):
    f = _wiki / folder / f"{stem}.md"
    f.write_text(PAGE.format(**kw), encoding="utf-8")
    return f


def test_scope_tile_counts_interfaces_not_the_context_page():
    """`folders` spans context + external-interfaces (Scope's maturity and
    issue flags need both), but the headline number must match its unit."""
    written = [
        _write("context", "CTX-001-system", id="CTX-001", type="context", title="System context"),
        _write("external-interfaces", "EIF-001-a", id="EIF-001",
               type="external-interface", title="Payment gateway"),
        _write("external-interfaces", "EIF-002-b", id="EIF-002",
               type="external-interface", title="Catalog service"),
    ]
    try:
        body = _area("/commons")
        scope = body[body.index("tile-c3"):body.index("tile-c4")]
        assert '<span class="num">2</span>' in scope, scope
        assert "context described" in scope, scope
    finally:
        for f in written:
            f.unlink()


def test_supporting_model_rows_say_pages_not_links():
    """`_supporting_model_entries()` reports pages per model type; only
    `len(page.link_targets())` may ever be labelled a link."""
    f = _write("activity-models", "ACT-001-borrow", id="ACT-001", type="activity-model", title="Borrow a book")
    try:
        body = _area("/req42")
        tile = body[body.index("tile-r4"):body.index("tile-r5")]
        rows = tile[tile.index("<ul"):tile.index("</ul>")]   # the wrapper is a .tile-link
        assert "1 page<" in rows, rows
        assert "link" not in rows, rows
    finally:
        f.unlink()


def test_use_cases_are_functional_requirements():
    """DR-011: a use case shows on the R3 tile, not R4, and its `goal:` list
    counts towards goal coverage."""
    f = _write("use-cases", "UC-001-borrow", id="UC-001", type="use-case", title="Borrow a book")
    try:
        body = _area("/req42")
        r3 = body[body.index("tile-r3"):body.index("tile-r4")]
        r4 = body[body.index("tile-r4"):body.index("tile-r5")]
        assert "UC-001" in r3 and "1 use case" in r3, r3
        # the headline counts all functional requirements; empty kinds are not named
        n_fr = len(app.load_folder("functional-requirements")) + len(app.load_folder("use-cases"))
        assert f'<span class="num">{n_fr}</span>' in r3, r3
        assert ("requirement" if n_fr == 1 else "requirements") in r3, r3
        if not app.build_fr_hierarchy()["total_epics"]:
            assert "0 epics" not in r3, r3
        assert "UC-001" not in r4 and "Use Cases" not in r4, r4
        page = app.app.test_client().get("/req42/functional-requirements").get_data(as_text=True)
        assert "UC-001" in page and "Borrow a book" in page
    finally:
        f.unlink()


if __name__ == "__main__":
    test_home_shows_two_peaks_the_valley_and_commons_in_order()
    test_area_tiles_link_to_area_pages_and_list_sections()
    test_section_lines_link_to_their_pages_and_tiles_are_not_one_big_link()
    test_valley_carries_status_changes_issues_and_decisions_link()
    test_hidden_area_and_section_leave_home()
    test_area_with_every_section_hidden_reads_not_captured_yet()
    test_unknown_hide_entry_is_a_warning_not_an_error()
    test_every_page_has_the_main_nav()
    test_nav_is_short_and_brand_is_not_duplicated_on_home()
    test_changes_lists_a_backdated_page_with_relative_time()
    test_recent_changes_shape()
    test_scope_tile_counts_interfaces_not_the_context_page()
    test_supporting_model_rows_say_pages_not_links()
    test_use_cases_are_functional_requirements()
    print("OK: home layout, navigation and latest changes")
