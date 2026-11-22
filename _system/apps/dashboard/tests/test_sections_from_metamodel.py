"""Sections come from the repository's metamodel (FR-044). On a repository
whose metamodel renames one section (C6) and adds one (A6, with a type of its
own), the dashboard shows both without a code change: home page, header, area
page, section route, page breadcrumb, issue filter, View dialog. An edit to a
framework file shows on the next request. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_sections_from_metamodel.py
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
REPO = Path(__file__).resolve().parents[4]

RENAMED = "Open Points"
ADDED = "Risks and Technical Debt"

_repo = Path(tempfile.mkdtemp())
for _f in ("issues", "risks", "goals", "functional-requirements"):
    (_repo / "wiki" / _f).mkdir(parents=True)
(_repo / "raw" / "sources").mkdir(parents=True)
(_repo / "_system").mkdir()
(_repo / "_system" / "wiki.yaml").write_text('system_name: "Demo"\n', encoding="utf-8")
_mm = _repo / "_system" / "metamodel"
shutil.copytree(REPO / "_system" / "metamodel", _mm)

# the rename: C6 gets the title req42 uses in German ("Offene Punkte")
_commons = _mm / "frameworks" / "fw-commons.md"
_text = _commons.read_text(encoding="utf-8")
assert 'title: "Issues"' in _text
_commons.write_text(_text.replace('title: "Issues"', f'title: "{RENAMED}"', 1), encoding="utf-8")

# the addition: arc42 section 11 as A6, holding a new type
_arc = _mm / "frameworks" / "fw-arc42.md"
_text = _arc.read_text(encoding="utf-8")
_a5 = re.search(r"^  - \{id: A5,.*\n", _text, re.MULTILINE)
_arc.write_text(_text[:_a5.end()] + f'  - {{id: A6, title: "{ADDED}", types: [risk], scope: in}}\n'
                + _text[_a5.end():], encoding="utf-8")
(_mm / "types" / "type-risk.md").write_text(
    "---\ntype: metamodel\nconstruct: type\nname: risk\nprefix: RSK\nfolder: wiki/risks\n"
    "label: Risk\nblock: A6\nlifecycle: content\nfields: []\n---\n\n# Type: risk\n\n"
    "A risk or a piece of technical debt.\n", encoding="utf-8")

for _n, _title in ((1, "Vendor lock-in"), (2, "No load tests")):
    (_repo / "wiki" / "risks" / f"RSK-00{_n}-r{_n}.md").write_text(
        f"---\nid: RSK-00{_n}\ntype: risk\ntitle: {_title}\nstatus: draft\n---\n\n# {_title}\n",
        encoding="utf-8")
(_repo / "wiki" / "issues" / "ISS-001-load.md").write_text(
    "---\nid: ISS-001\ntype: issue\ntitle: Who runs the load test\nstatus: open\n"
    'severity: major\nrelated: ["[[RSK-002-r2]]"]\n---\n\n# Who runs the load test\n',
    encoding="utf-8")

for _var in ("WIKI_DIR", "RAW_SOURCES_DIR", "WIKI_CONFIG", "DOCS_DIR", "METAMODEL_DIR",
             "NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_var, None)
os.environ["REPO_DIR"] = str(_repo)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(HERE))
import app  # noqa: E402

client = app.app.test_client()


def _get(url):
    r = client.get(url)
    assert r.status_code == 200, (url, r.status_code)
    return r.get_data(as_text=True)


def test_the_catalog_reads_both():
    ids = [s["id"] for s in app.catalog.sections_of("architecture")]
    assert ids == ["A1", "A2", "A3", "A4", "A5", "A6"], ids
    a6 = app.catalog.SECTION_BY_ID["A6"]
    # area from the framework file, colours from the area, the generic route
    assert (a6["title"], a6["area"], a6["folders"], a6["href"], a6["colors"]) == \
        (ADDED, "architecture", ["risks"], "/section/A6", ["arc"]), a6
    assert app.catalog.SECTION_BY_ID["C6"]["title"] == RENAMED


def test_home_page_lists_both():
    body = _get("/")
    assert f'href="/section/A6"><code class="ml-id">A6</code> {ADDED}<' in body, body
    assert f'<code class="ml-id">C6</code> {RENAMED}<' in body, body
    # the architecture peak counts the added section's pages and its open issue
    with app.app.test_request_context("/"):
        arch = app.build_area_tile(app.catalog.AREA_BY_KEY["architecture"])
    assert (arch["count"], arch["open_issues"]) == (2, 1), arch


def test_header_names_the_renamed_section():
    nav = re.search(r'<nav class="mainnav".*?</nav>', _get("/"), re.DOTALL).group(0)
    assert f'<a href="/issues">{RENAMED}</a>' in nav, nav
    assert ">Issues<" not in nav
    # the added section's pages mark their area current
    nav = re.search(r'<nav class="mainnav".*?</nav>', _get("/section/A6"), re.DOTALL).group(0)
    assert re.search(r'<a href="/arc42"[^>]*aria-current', nav), nav


def test_area_page_has_a_generic_tile_for_the_added_section():
    body = _get("/arc42")
    m = re.search(r'id="tile-a6".*?(?=id="tile-|</main>)', body, re.DOTALL)
    assert m, "no tile for A6"
    tile = m.group(0)
    assert f"A6 · {ADDED}" in tile, tile
    assert '<span class="num">2</span>' in tile, tile
    assert "Vendor lock-in" not in tile, tile   # count only, no page names (FR-019)
    assert "maturity" in tile, tile
    assert 'href="/issues?section=A6"' in tile and "1 open issue" in tile, tile
    assert 'href="/section/A6"' in tile, tile


def test_section_route_lists_the_pages():
    body = _get("/section/A6")
    assert ADDED in body and "RSK-001" in body and "RSK-002" in body
    assert 'href="/page/risks/RSK-001-r1"' in body
    # the section belongs to its area: breadcrumb and colour bar
    assert 'href="/arc42"' in body
    assert client.get("/section/a6").status_code == 200
    r = client.get("/section/C6")
    assert r.status_code == 302 and r.headers["Location"].endswith("/issues"), r.headers
    assert client.get("/section/Z1").status_code == 404
    # an out section has no route
    assert client.get("/section/R2").status_code == 404


def test_a_page_of_the_added_section_names_it():
    body = _get("/page/risks/RSK-002-r2")
    assert f'<a href="/section/A6">{ADDED}</a>' in body, body
    assert app.catalog.area_for_path("/page/risks/RSK-002-r2")["key"] == "architecture"
    assert app.catalog.area_for_path("/section/A6")["key"] == "architecture"


def test_lists_offer_both():
    body = _get("/issues")
    assert f">{ADDED}</option>" in body
    body = _get("/issues?section=A6")
    assert "ISS-001" in body
    data = client.get("/settings").get_json()
    arch = next(a for a in data["areas"] if a["key"] == "architecture")
    assert {"id": "A6", "title": ADDED, "colors": ["arc"], "scope": "in"} in arch["sections"]
    commons = next(a for a in data["areas"] if a["key"] == "commons")
    assert next(s for s in commons["sections"] if s["id"] == "C6")["title"] == RENAMED
    # the view can hide the added section
    app.set_view(["A6"])
    try:
        assert "A6" not in [s["id"] for s in app.visible_sections("architecture")]
    finally:
        app.set_view([])


def test_an_edit_shows_on_the_next_request():
    text = _arc.read_text(encoding="utf-8")
    try:
        _arc.write_text(text.replace(ADDED, "Risks"), encoding="utf-8")
        body = _get("/arc42")
        assert "A6 · Risks<" in body and ADDED not in body
    finally:
        _arc.write_text(text, encoding="utf-8")
    assert ADDED in _get("/arc42")



def test_every_page_still_renders():
    for url in ("/", "/req42", "/arc42", "/commons", "/metamodel", "/issues", "/search?q=risk"):
        _get(url)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: sections from the metamodel")
