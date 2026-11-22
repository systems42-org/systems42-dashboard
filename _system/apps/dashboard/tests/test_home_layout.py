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
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
(_tmp / "sources").mkdir()
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
NAV = ["Requirements", "Architecture", "Domain Terms", "Decisions", "Issues"]


def _home():
    app._PARSE_CACHE.clear()
    return app.app.test_client().get("/").get_data(as_text=True)


def test_home_shows_two_peaks_the_valley_and_commons_in_order():
    app.set_view([])
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
    assert 'href="/arc42/strategy"><code class="ml-id">A1</code>' in arc and 'href="/arc42/concepts"><code class="ml-id">A5</code>' in arc
    assert "tile-a6" not in arc, "A6 moved to Commons as C7 Decisions (FR-009)"
    com = body[body.index("area-tile-commons"):]
    for sid, href in (("C1", "/req42/quality"), ("C4", "/stakeholders"), ("C5", "/domain-terms"), ("C6", "/issues"),
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
    app.set_view(["architecture", "C6"])
    try:
        body = _home()
        assert "area-tile-architecture" not in body
        com = body[body.index("area-tile-commons"):]
        assert "C6" not in com and "C5" in com
    finally:
        app.set_view([])


def test_area_with_every_section_hidden_reads_not_captured_yet():
    app.set_view(["A1", "A2", "A3", "A4", "A5"])
    try:
        body = _home()
        arc = body[body.index("area-tile-architecture"):body.index("area-tile-commons")]
        assert "Not captured yet" in arc and "0 pages" not in arc, arc
    finally:
        app.set_view([])


def test_every_page_has_the_main_nav():
    c = app.app.test_client()
    for route in ("/", "/domain-terms", "/issues", "/req42/functional-requirements", "/arc42"):
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
    for href in ('href="/req42"', 'href="/arc42"', 'href="/commons"', 'href="/domain-terms"', 'href="/decisions"'):
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
    (_wiki / "domain-terms" / "DT-001-x.md").write_text(
        QR.replace("QR-001", "DT-001").replace("quality-requirement", "domain-term"),
        encoding="utf-8")
    try:
        app._PARSE_CACHE.clear()
        rows = app.recent_changes(5)
        assert rows and set(rows[0]) >= {"id", "title", "kind", "url", "when"}, rows
        assert rows[0]["url"] == "/page/domain-terms/DT-001-x"
    finally:
        (_wiki / "domain-terms" / "DT-001-x.md").unlink()


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
        assert "context described" not in scope, "count and bar only (FR-019)"
    finally:
        for f in written:
            f.unlink()


def test_supporting_models_count_model_pages():
    """R4 counts the structured domain terms and activity models
    (`supporting_model_count()`) and names none of them (FR-019)."""
    f = _write("activity-models", "ACT-001-borrow", id="ACT-001", type="activity-model", title="Borrow a book")
    try:
        body = _area("/req42")
        tile = body[body.index("tile-r4"):body.index("tile-r5")]
        with app.app.test_request_context("/req42"):
            n = app.supporting_model_count()
        assert n >= 1, n
        assert f'<span class="num">{n}</span><span class="unit">model page' in tile, tile
        assert "<ul" not in tile and "Borrow a book" not in tile, tile
    finally:
        f.unlink()


def test_use_cases_are_functional_requirements():
    """DR-038: a use case is a functional requirement in the use-case
    notation. It counts on the R3 tile, not R4, and counts once."""
    f = _write("functional-requirements", "UC-001-borrow", id="UC-001",
               type="functional-requirement", title="Borrow a book")
    f.write_text(f.read_text(encoding="utf-8").replace(
        "tags: [functional-requirement]\n", "tags: [functional-requirement]\nnotation: use-case\nlevel: sea\n"),
        encoding="utf-8")
    try:
        body = _area("/req42")
        r3 = body[body.index("tile-r3"):body.index("tile-r4")]
        r4 = body[body.index("tile-r4"):body.index("tile-r5")]
        # the headline counts all functional requirements; the tile names none (FR-019)
        n_fr = len(app.load_folder("functional-requirements"))
        assert f'<span class="num">{n_fr}</span>' in r3, r3
        assert ("requirement" if n_fr == 1 else "requirements") in r3, r3
        assert "UC-001" not in r3 and "use case" not in r3, r3
        assert "UC-001" not in r4 and "Use Cases" not in r4, r4
        page = app.app.test_client().get("/req42/functional-requirements").get_data(as_text=True)
        assert "UC-001" in page and "Borrow a book" in page
    finally:
        f.unlink()


VISION = """---
id: GOAL-007
type: goal
title: Answers for System X
status: draft
created: 2026-09-07
updated: 2026-09-07
sources: []
related: []
tags: [goal]
stereotype: vision
---

# Answers for System X

## Vision

> follows the Geoffrey Moore format

For **Role B**, [[GOAL-001-objective|System X]] answers e.g. any question about Entity A. A
second sentence the hero leaves out.

**Objectives.** See the `parent:` backlinks.
"""


def test_hero_shows_the_vision_sentence_or_the_tagline():
    """FR-018: the hero shows the vision in one sentence. The vision is the
    goal page with `stereotype: vision`, here GOAL-007 next to an objective
    GOAL-001. Without a vision the tagline stands in."""
    (_tmp / "wiki.yaml").write_text("system_name: System X\ntagline: Tagline of System X\n",
                                    encoding="utf-8")
    objective = _write("goals", "GOAL-001-objective", id="GOAL-001", type="goal", title="An objective")
    vision = _wiki / "goals" / "GOAL-007-answers.md"
    try:
        hero = _home().split('<header class="hero">')[1].split("</header>")[0]
        assert "Tagline of System X" in hero and "hero-vision" not in hero, hero
        vision.write_text(VISION, encoding="utf-8")
        hero = _home().split('<header class="hero">')[1].split("</header>")[0]
        sentence = "For Role B, System X answers e.g. any question about Entity A."
        assert f'<p class="lead hero-vision">{sentence}</p>' in hero, hero
        assert "second sentence" not in hero and "Tagline of System X" not in hero, hero
        assert "Take the guided path" not in hero, "/tour is not built yet (FR-012)"
    finally:
        for f in (objective, vision, _tmp / "wiki.yaml"):
            f.unlink(missing_ok=True)


def test_area_tiles_show_the_count_of_each_section():
    """FR-018: each area tile lists its sections with the count their section
    tile shows. A section that is not captured (R2, A1) shows none."""
    written = [_write("constraints", f"CON-00{n}-c", id=f"CON-00{n}", type="constraint", title=f"C {n}")
               for n in (1, 2)]
    try:
        body = _home()
        com = body[body.index("area-tile-commons"):]
        assert ('<code class="ml-id">C2</code> Constraints<span class="area-section-count" '
                'title="2 constraints">2</span>') in com, com
        assert 'title="0 terms">0</span>' in com, com
        req = body[body.index("area-tile-requirements"):body.index("valley")]
        r2 = req[req.index("tile-r2"):req.index("</li>", req.index("tile-r2"))]
        assert "area-section-count" not in r2, r2
        arc = body[body.index("area-tile-architecture"):body.index("area-tile-commons")]
        assert 'Building Block View<span class="area-section-count" title="0 pages">0</span>' in arc, arc
    finally:
        for f in written:
            f.unlink()


ISSUE = """---
id: {id}
type: issue
title: {title}
status: {status}
created: 2026-09-07
updated: 2026-09-07
sources: []
related: ["[[QR-001-fast-checkout]]"]
tags: [issue]
severity: minor
---

# {title}
"""


def test_section_tiles_show_count_bar_and_issue_link_only():
    """FR-019: count, maturity bar and the open-issue link, no page names. R1
    counts its goal pages. C6 counts every issue and flags the open ones."""
    written = [
        _wiki / "quality-requirements" / "QR-001-fast-checkout.md",
        _write("quality-requirements", "QR-002-slow", id="QR-002", type="quality-requirement",
               title="Slow report"),
        _wiki / "issues" / "ISS-001-open.md",
        _wiki / "issues" / "ISS-002-closed.md",
        _write("goals", "GOAL-001-vision", id="GOAL-001", type="goal", title="Vision of X"),
        _write("goals", "GOAL-002-objective", id="GOAL-002", type="goal", title="Objective of X"),
    ]
    written[0].write_text(QR.replace("status: draft", "status: accepted"), encoding="utf-8")
    written[2].write_text(ISSUE.format(id="ISS-001", title="Open question", status="open"), encoding="utf-8")
    written[3].write_text(ISSUE.format(id="ISS-002", title="Closed question", status="resolved"),
                          encoding="utf-8")
    try:
        body = _area("/commons")
        c1 = body[body.index('id="tile-c1"'):body.index('id="tile-c2"')]
        assert '<span class="num">2</span><span class="unit">scenarios</span>' in c1, c1
        assert 'maturity-accepted" style="flex-basis: 50%"' in c1, c1
        assert 'maturity-draft" style="flex-basis: 50%"' in c1, c1
        assert 'href="/issues?section=C1"' in c1 and "1 open issue<" in c1, c1
        assert 'class="tile-stretch" href="/req42/quality"' in c1, c1
        for gone in ("<ul", "Fast checkout", "Slow report", "QR-001"):
            assert gone not in c1, (gone, c1)
        c6 = body[body.index('id="tile-c6"'):body.index('id="tile-c7"')]
        assert '<span class="num">2</span><span class="unit">issues</span>' in c6, c6
        assert 'href="/issues?status=open"' in c6 and "1 open issue<" in c6, c6
        assert 'class="tile-stretch" href="/issues"' in c6, c6
        for gone in ("<ul", "Open question", "in total"):
            assert gone not in c6, (gone, c6)
        req = _area("/req42")
        r1 = req[req.index('id="tile-r1"'):req.index('id="tile-r2"')]
        assert '<span class="num">2</span><span class="unit">goals</span>' in r1, r1
        for gone in ("<ul", "Objective of X", "GOAL-002", "No objectives yet"):
            assert gone not in r1, (gone, r1)
    finally:
        for f in written:
            f.unlink()


if __name__ == "__main__":
    test_home_shows_two_peaks_the_valley_and_commons_in_order()
    test_area_tiles_link_to_area_pages_and_list_sections()
    test_section_lines_link_to_their_pages_and_tiles_are_not_one_big_link()
    test_valley_carries_status_changes_issues_and_decisions_link()
    test_hidden_area_and_section_leave_home()
    test_area_with_every_section_hidden_reads_not_captured_yet()
    test_every_page_has_the_main_nav()
    test_nav_is_short_and_brand_is_not_duplicated_on_home()
    test_changes_lists_a_backdated_page_with_relative_time()
    test_recent_changes_shape()
    test_scope_tile_counts_interfaces_not_the_context_page()
    test_supporting_models_count_model_pages()
    test_use_cases_are_functional_requirements()
    test_hero_shows_the_vision_sentence_or_the_tagline()
    test_area_tiles_show_the_count_of_each_section()
    test_section_tiles_show_count_bar_and_issue_link_only()
    print("OK: home layout, navigation and latest changes")
