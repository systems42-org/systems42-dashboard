"""Specialized views read a type's folder from the repository's metamodel
(FR-044, CON-006, issue 180). On a repository whose metamodel moves domain
terms to `wiki/terms` and goals to `wiki/aims`, the tile count, the list, the
search, the detail page with its links and the projections (term network,
entity diagram, goal coverage) agree. A page's URL names the folder it lives
in: `/page/terms/<stem>`. An edit to the declaration shows on the next
request, and after `/reload`. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_moved_type_folder.py
"""
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
REPO = Path(__file__).resolve().parents[4]

_repo = Path(tempfile.mkdtemp())
_wiki = _repo / "wiki"
for _f in ("terms", "domain-terms", "aims", "functional-requirements", "stakeholders", "issues"):
    (_wiki / _f).mkdir(parents=True)
(_repo / "raw" / "sources").mkdir(parents=True)
(_repo / "_system").mkdir()
(_repo / "_system" / "wiki.yaml").write_text('system_name: "Demo"\n', encoding="utf-8")
_mm = _repo / "_system" / "metamodel"
shutil.copytree(REPO / "_system" / "metamodel", _mm)
shutil.copytree(REPO / "_system" / "anchors", _repo / "_system" / "anchors")

_term_type = _mm / "types" / "type-domain-term.md"
_goal_type = _mm / "types" / "type-goal.md"


def _declare(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert f"folder: {old}\n" in text, (path.name, old)
    path.write_text(text.replace(f"folder: {old}\n", f"folder: {new}\n", 1), encoding="utf-8")


_declare(_term_type, "wiki/domain-terms", "wiki/terms")
_declare(_goal_type, "wiki/goals", "wiki/aims")


def _page(folder: str, stem: str, front: str, body: str = "") -> None:
    title = front.split("title: ", 1)[1].split("\n", 1)[0]
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\n{front}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


_page("terms", "DT-001-customer",
      "id: DT-001\ntype: domain-term\ntitle: Customer\nstatus: draft\nstereotype: entity\n"
      'related: ["[[DT-002-order]]", "[[STK-001-sales]]"]\n'
      "attributes:\n  - {name: number, type: string, identifier: true}\n"
      'relationships:\n  - {to: "[[DT-002-order]]", label: places, kind: association, multiplicity: "0..*"}',
      "**Definition.** Someone who buys. See [[DT-002-order]].")
_page("terms", "DT-002-order",
      "id: DT-002\ntype: domain-term\ntitle: Order\nstatus: draft\nstereotype: entity\n"
      'related: ["[[DT-001-customer]]"]',
      "**Definition.** What a [[DT-001-customer]] places.")
# a page left in the default folder: no domain term while the folder is moved
_page("domain-terms", "DT-009-leftover",
      "id: DT-009\ntype: domain-term\ntitle: Leftover\nstatus: draft\nrelated: []",
      "**Definition.** Stayed behind.")
_page("aims", "GOAL-001-vision",
      "id: GOAL-001\ntype: goal\ntitle: Sell online\nstatus: draft\nstereotype: vision\nrelated: []",
      "## Vision\n\nEvery customer orders online.")
_page("aims", "GOAL-002-faster",
      "id: GOAL-002\ntype: goal\ntitle: Faster checkout\nstatus: draft\nstereotype: objective\n"
      'parent: ["[[GOAL-001-vision]]"]\nrelated: []')
_page("functional-requirements", "FR-001-checkout",
      "id: FR-001\ntype: functional-requirement\ntitle: Checkout\nstatus: draft\nnotation: agile\n"
      'level: feature\npriority: Must\ngoal: ["[[GOAL-002-faster]]"]\n'
      'related: ["[[DT-002-order]]"]',
      "## Story\n\nAs a [[DT-001-customer]] I want to pay.")
_page("stakeholders", "STK-001-sales",
      'id: STK-001\ntype: stakeholder\ntitle: Sales\nstatus: draft\nrelated: ["[[DT-001-customer]]"]')
_page("issues", "ISS-001-who",
      "id: ISS-001\ntype: issue\ntitle: Who is a customer\nstatus: open\nseverity: major\n"
      'related: ["[[DT-001-customer]]"]')

for _var in ("WIKI_DIR", "RAW_SOURCES_DIR", "WIKI_CONFIG", "DOCS_DIR", "METAMODEL_DIR",
             "NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_var, None)
os.environ["REPO_DIR"] = str(_repo)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(HERE))
import app  # noqa: E402

client = app.app.test_client()

TERM = "/page/terms/DT-001-customer"
ORDER = "/page/terms/DT-002-order"


def _get(url):
    r = client.get(url)
    assert r.status_code == 200, (url, r.status_code)
    return r.get_data(as_text=True)


def _tile(sid):
    with app.app.test_request_context("/"):
        app.catalog.refresh()
        return app.build_section_tile(app.catalog.SECTION_BY_ID[sid])


def test_the_lookup_reads_the_declaration():
    app.catalog.refresh()
    assert app.catalog.folder("domain-term") == "terms"
    assert app.catalog.folder("goal") == "aims"
    assert app.catalog.type_of("terms") == "domain-term"
    assert app.catalog.type_of("domain-terms") is None
    # a type the declaration does not move keeps its folder
    assert app.catalog.folder("stakeholder") == "stakeholders"
    assert app.catalog.folder("no-such-type") == ""
    # label and ID prefix come with the type, wherever its folder is
    assert app.catalog.label("aims") == "Goal" and app.catalog.label("notes") == "notes"
    assert app.catalog.folder_for_prefix("DT") == "terms"
    assert app.catalog.folder_for_prefix("UC") == "functional-requirements"
    assert app.catalog.group_label("UC") == "Use cases"
    assert app.catalog.prefix_order()[:7] == ["DT", "STK", "CTX", "EIF", "GOAL", "FR", "UC"]


def test_defaults_fill_what_a_type_page_leaves_out():
    types = app.catalog.build_types([
        {"name": "goal", "folder": "aims", "prefix": "", "label": ""},
        {"name": "risk", "folder": "risks", "prefix": "RSK", "label": ""},
    ])
    assert types["goal"] == {"name": "goal", "folder": "aims", "prefix": "GOAL", "label": "Goal"}
    assert types["risk"] == {"name": "risk", "folder": "risks", "prefix": "RSK", "label": "risk"}
    # a type no page declares keeps the Systems42 values
    assert types["domain-term"]["folder"] == "domain-terms"
    assert app.catalog.build_types([])["issue"] == \
        {"name": "issue", "folder": "issues", "prefix": "ISS", "label": "Issue"}


def test_tile_and_list_agree_for_domain_terms():
    assert _tile("C5")["count"] == 2
    body = _get("/domain-terms")
    assert f'href="{TERM}"' in body and f'href="{ORDER}"' in body, body
    assert "Leftover" not in body
    assert "/page/domain-terms/" not in body


def test_search_finds_the_moved_pages():
    records = json.loads(_get("/search.json"))["records"]
    by_id = {r["id"]: r for r in records}
    assert by_id["DT-001"]["url"] == TERM, by_id["DT-001"]
    assert by_id["DT-001"]["type"] == "Domain term", by_id["DT-001"]
    assert by_id["GOAL-002"]["url"] == "/page/aims/GOAL-002-faster"
    assert by_id["GOAL-002"]["type"] == "Goal"
    body = _get("/search?q=customer")
    assert f'href="{TERM}"' in body


def test_term_detail_page_and_its_links():
    body = _get(TERM)
    # the term's own fields and its ego graph: a domain-term detail page
    assert 'id="term-fields"' in body and 'id="term-attributes"' in body, body
    assert 'id="term-relationships"' in body and 'id="ego-cy"' in body, body
    # body link, relations panel and the issue that points here
    assert f'href="{ORDER}"' in body
    assert 'href="/page/stakeholders/STK-001-sales"' in body
    assert 'href="/page/issues/ISS-001-who"' in body
    assert "Domain term" in body
    assert "/page/domain-terms/" not in body
    # the old address names a folder that holds no such page
    assert client.get("/page/domain-terms/DT-001-customer").status_code == 404
    # pages of other types link to the term at its address
    assert f'href="{TERM}"' in _get("/page/stakeholders/STK-001-sales")
    assert f'href="{TERM}"' in _get("/functional-requirements/FR-001-checkout")
    assert f'href="{TERM}"' in _get("/stakeholders")


def test_term_projections_show_the_moved_pages():
    with app.app.test_request_context("/"):
        graph = app.build_glossary_graph()
    core = {n["data"]["id"]: n["data"] for n in graph["nodes"] if n["data"].get("core")}
    assert set(core) == {"DT-001-customer", "DT-002-order"}, core
    assert core["DT-001-customer"]["url"] == TERM
    assert "DT-001-customer" in _get("/graph/domain-terms")
    body = _get("/entity-diagram")
    assert "Customer" in body and "Order" in body and "places" in body, body
    assert TERM in body
    with app.app.test_request_context("/"):
        assert app.catalog.SECTION_BY_ID["R4"] and _tile("R4")["count"] == 2


def test_goals_agree():
    assert _tile("R1")["count"] == 2
    body = _get("/goals")
    assert "Sell online" in body and "Faster checkout" in body, body
    assert 'href="/page/aims/GOAL-002-faster"' in body
    # the coverage: the requirement that serves the objective
    assert "/functional-requirements/FR-001-checkout" in body
    assert 'href="/page/aims/GOAL-002-faster"' in _get("/functional-requirements/FR-001-checkout")
    goal = _get("/page/aims/GOAL-002-faster")
    assert "/functional-requirements/FR-001-checkout" in goal
    assert 'href="/page/aims/GOAL-001-vision"' in goal
    # the home page takes its vision from the moved folder
    assert "Every customer orders online." in _get("/")
    assert client.get("/page/goals/GOAL-002-faster").status_code == 404


def test_an_edited_declaration_shows_on_the_next_request():
    _declare(_term_type, "wiki/terms", "wiki/domain-terms")
    try:
        body = _get("/domain-terms")
        assert 'href="/page/domain-terms/DT-009-leftover"' in body, body
        assert "/page/terms/" not in body
        assert _tile("C5")["count"] == 1
        records = {r["id"]: r for r in json.loads(_get("/search.json"))["records"]}
        assert records["DT-009"]["type"] == "Domain term"
        # the pages left in wiki/terms are plain pages of an undeclared folder
        assert records["DT-001"]["type"] == "terms", records["DT-001"]
        plain = _get(TERM)
        assert 'id="term-fields"' not in plain and 'id="ego-cy"' not in plain
    finally:
        _declare(_term_type, "wiki/domain-terms", "wiki/terms")
    assert f'href="{TERM}"' in _get("/domain-terms")


def test_reload_follows_the_declaration():
    text = _term_type.read_text(encoding="utf-8")
    stat = _term_type.stat()
    assert _tile("C5")["count"] == 2
    # same size, same mtime: only /reload makes the reader look again
    changed = text.replace("folder: wiki/terms\n", "folder: wiki/terma\n", 1)
    assert len(changed) == len(text)
    try:
        _term_type.write_text(changed, encoding="utf-8")
        os.utime(_term_type, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        assert client.post("/reload").status_code == 200
        assert "DT-001-customer" not in _get("/domain-terms")
        assert _tile("C5")["count"] == 0
    finally:
        _term_type.write_text(text, encoding="utf-8")
        os.utime(_term_type, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        client.post("/reload")
    assert f'href="{TERM}"' in _get("/domain-terms")


def test_every_page_still_renders():
    for url in ("/", "/req42", "/arc42", "/commons", "/metamodel", "/issues", "/stakeholders",
                "/decisions", "/changes", "/req42/functional-requirements", "/req42/models",
                "/req42/scope", "/arc42/building-blocks", "/search?q=order", ORDER,
                "/page/issues/ISS-001-who"):
        _get(url)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("OK: moved type folders")
