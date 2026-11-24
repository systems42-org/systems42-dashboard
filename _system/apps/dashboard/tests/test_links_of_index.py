"""A link field is resolved against the request's page index (issue #206).

`links_of()` built a set of every file name on each call, also for an empty
field. The block tree calls it once per block and the "Addressed by" list once
per decision record and architecture page, so a request walked the full page
list once per block. The page index already knows every file name, so the set
added nothing.

The first part counts how often a request walks the full page list, for a
wiki with 2 extra blocks and with 20. The second part checks that the result
is the one the old code gave, for every spelling a field may hold.

Run from the dashboard dir:
    .venv/bin/python tests/test_links_of_index.py
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues", "building-blocks", "decisions",
    "solution-strategy", "crosscutting-concepts", "runtime-scenarios", "deployment-nodes",
]

_system = Path(__file__).resolve().parents[3]
_repo = Path(tempfile.mkdtemp()) / "repo"
_wiki = _repo / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
(_repo / "docs").mkdir()
_config = _repo / "_system" / "wiki.yaml"
shutil.copytree(_system / "metamodel", _repo / "_system" / "metamodel")
shutil.copytree(_system / "anchors", _repo / "_system" / "anchors")
_config.write_text("system_name: Links of\n", encoding="utf-8")


def _write(folder, stem, type_name, extra="", id_=None):
    id_line = stem[:6] if id_ is None else id_
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {id_line}\ntype: {type_name}\ntitle: {stem}\nstatus: draft\n"
        f"created: 2026-11-24\nupdated: 2026-11-24\nsources: []\nrelated: []\ntags: []\n"
        f"{extra}---\n\n# {stem}\n", encoding="utf-8")


FAST = "QR-001-fast-search"          # the file name is longer than the ID
# Two pages carry the ID QR-DUP: the ID names the first of them.
_write("quality-requirements", FAST, "quality-requirement")
_write("quality-requirements", "QR-002-first-twin", "quality-requirement", id_="QR-DUP")
_write("quality-requirements", "QR-003-second-twin", "quality-requirement", id_="QR-DUP")
# This page's ID is the file name of QR-001: the name stays with QR-001.
_write("quality-requirements", "QR-004-shadow", "quality-requirement", id_=FAST)
_write("quality-requirements", "QR-005-unused", "quality-requirement")

_write("building-blocks", "BB-001-root", "building-block")
# every spelling, the same page twice in two spellings, and names no page has
_write("building-blocks", "BB-002-spellings", "building-block", extra=(
    'parent: "[[BB-001]]"\n'
    "drivers:\n"
    '  - "[[QR-005]]"\n'                                        # ID alone
    f'  - "[[{FAST}]]"\n'                                       # file name
    '  - "[[QR-001]]"\n'                                        # the same page again
    '  - "[[wiki/quality-requirements/QR-DUP#Measure|twin]]"\n'  # path, heading, alias
    '  - "[[QR-099]]"\n'                                        # no such page
    '  - "[[qr-005]]"\n'                                        # wrong case: no such page
    "  - QR-003-second-twin\n"                                  # no brackets
    "  - [[QR-004-shadow]]\n"                                   # YAML makes a nested list
    '  - "[[QR-002-first-twin|the twin again]]"\n'
    '  - ""\n'
    '  - "[[ ]]"\n'
    'uses: "[[BB-001-root]]"\n'                                 # a single value, no list
    "decisions: []\n"))
_write("building-blocks", "BB-003-empty", "building-block", extra="parent:\ndrivers:\nuses: []\n")
_write("decisions", "DR-001-choice", "decision-record", extra='drivers: ["[[QR-001]]"]\n')

os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_config)
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_repo / "docs")
os.environ["METAMODEL_DIR"] = str(_repo / "_system" / "metamodel")
for _name in ("NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_name, None)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import wiki  # noqa: E402
import links  # noqa: E402
import project.architecture  # noqa: E402

client = app.app.test_client()

SPELLINGS_DRIVERS = ["QR-005-unused", FAST, "QR-002-first-twin", "QR-003-second-twin", "QR-004-shadow"]


def _page(folder, stem):
    return next(p for p in wiki.load_folder(folder) if p.stem == stem)


# --- the result is the one the old code gave ---------------------------------

def _links_of_before(page, field):
    """`links_of()` as it was before #206: a value counts when the file name
    `_link_stem()` gives is in the set of all file names."""
    by_stem = {p.stem for p in wiki.load_all_pages()}
    out = []

    def walk(v):
        if isinstance(v, (list, tuple)):
            for x in v:
                walk(x)
            return
        s = links._link_stem(v) if v else ""
        if s and s in by_stem and s not in out:
            out.append(s)

    walk(page.meta.get(field))
    return out


def test_every_spelling_in_order_without_duplicates():
    with app.app.test_request_context("/"):
        bb = _page("building-blocks", "BB-002-spellings")
        assert links.links_of(bb, "drivers") == SPELLINGS_DRIVERS, links.links_of(bb, "drivers")
        assert links.links_of(bb, "parent") == ["BB-001-root"]
        assert links.links_of(bb, "uses") == ["BB-001-root"]
        assert links.links_of(bb, "decisions") == []
        assert links.links_of(bb, "no-such-field") == []
        empty = _page("building-blocks", "BB-003-empty")
        for field in ("parent", "drivers", "uses"):
            assert links.links_of(empty, field) == [], field
    print("OK: ID, file name, path, alias and heading resolve, in order, each page once")


def test_names_two_pages_could_claim():
    with app.app.test_request_context("/"):
        index = links.page_index()
        # an ID two pages carry names the first, and each file name its own page
        assert index["QR-DUP"].stem == "QR-002-first-twin"
        assert index["QR-003-second-twin"].stem == "QR-003-second-twin"
        # an ID that is another page's file name does not take that name
        assert index[FAST].stem == FAST
        assert index["QR-004-shadow"].stem == "QR-004-shadow"
        # whatever the index answers is the file name of a page that exists
        stems = {p.stem for p in wiki.load_all_pages()}
        assert {p.stem for p in index.values()} == stems
        assert stems <= set(index)
    print("OK: a shared ID and an ID that is a file name resolve as before")


def test_same_result_as_before_for_every_field_of_every_page():
    checked = 0
    with app.app.test_request_context("/"):
        for page in wiki.load_all_pages():
            for field in list(page.meta) + ["no-such-field"]:
                got, want = links.links_of(page, field), _links_of_before(page, field)
                assert got == want, (page.stem, field, got, want)
                checked += 1
    assert checked > 50, checked
    print(f"OK: {checked} fields give the same links as before")


# --- a request walks the full page list a fixed number of times --------------

class _Counted(list):
    """The full page list, counting how often it is walked from start to end."""
    walks = 0

    def __iter__(self):
        _Counted.walks += 1
        return super().__iter__()


def _walks(url):
    """The response text of one request and how often it walked all pages."""
    real = wiki.load_all_pages
    wiki.load_all_pages = lambda: _Counted(real())
    _Counted.walks = 0
    try:
        r = client.get(url)
    finally:
        wiki.load_all_pages = real
    assert r.status_code == 200, (url, r.status_code)
    return r.get_data(as_text=True), _Counted.walks


def _add_blocks(first, last):
    """Children of BB-001 that answer QR-001, the ID spelling in both fields."""
    for n in range(first, last + 1):
        _write("building-blocks", f"BB-{n:03d}-part", "building-block",
               extra='parent: "[[BB-001]]"\ndrivers: ["[[QR-001]]"]\nuses: ["[[BB-002]]"]\n')


TREE = "/arc42/building-blocks"
BLOCK = "/page/building-blocks/BB-001-root"
DRIVER = f"/page/quality-requirements/{FAST}"


def _addressed_by():
    with app.app.test_request_context("/"):
        groups = project.architecture.build_addressed_by(FAST)
        return {g["type"]: [it["id"] for it in g["links"]] for g in groups}


def _children():
    with app.app.test_request_context("/"):
        root = next(n for n in project.architecture.build_bb_tree() if n["id"] == "BB-001")
        return [c["id"] for c in root["children"]]


def test_page_walks_do_not_grow_with_the_blocks():
    _add_blocks(101, 102)
    few = {url: _walks(url) for url in (TREE, BLOCK, DRIVER)}
    assert _children() == ["BB-002", "BB-101", "BB-102"], _children()
    assert _addressed_by() == {"DR": ["DR-001"], "BB": ["BB-002", "BB-101", "BB-102"]}, _addressed_by()

    _add_blocks(103, 120)
    many = {url: _walks(url) for url in (TREE, BLOCK, DRIVER)}
    parts = [f"BB-{n}" for n in range(101, 121)]
    assert _children() == ["BB-002"] + parts, _children()
    assert _addressed_by() == {"DR": ["DR-001"], "BB": ["BB-002"] + parts}, _addressed_by()

    for url in (TREE, BLOCK, DRIVER):
        html, n = many[url]
        assert n == few[url][1], (url, "walks with 2 blocks", few[url][1], "with 20", n)
        assert n <= 20, (url, n)
    # the rendered pages show the projected children and the blocks a driver has
    for part in parts:
        assert f"/page/building-blocks/{part}-part" in many[TREE][0], part
        assert f"/page/building-blocks/{part}-part" in many[DRIVER][0], part
    assert len(re.findall(r"/page/building-blocks/BB-1\d\d-part", few[DRIVER][0])) >= 2
    print("OK: full page walks per request, 2 blocks and 20: "
          + ", ".join(f"{url} {few[url][1]} and {many[url][1]}" for url in (TREE, BLOCK, DRIVER)))


if __name__ == "__main__":
    test_every_spelling_in_order_without_duplicates()
    test_names_two_pages_could_claim()
    test_same_result_as_before_for_every_field_of_every_page()
    test_page_walks_do_not_grow_with_the_blocks()
    print("All links_of index tests passed.")
