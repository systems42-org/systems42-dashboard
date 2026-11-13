"""The /metamodel help page (DR-035): every cell comes from
`_system/metamodel/`, the examples from the live vault, and the graph is a
pure projection of the type and relation pages. No pytest dependency.

Run from the dashboard dir:
    .venv/bin/python tests/test_metamodel_page.py

WIKI_DIR points at tests/fixtures/wiki; the metamodel is the real one, since
the page's whole point is to agree with it. The anchors are a temporary
folder of their own (ANCHORS_DIR).
"""
import os
import sys
import tempfile
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASHBOARD_CONFIG"] = str(_FIXTURE.parent / "dashboard-absent.yaml")
# the anchors are the test's own, so the page check does not hang on the
# wording of _system/anchors/
_ANCHORS = Path(tempfile.mkdtemp())
(_ANCHORS / "pam.md").write_text(
    "---\ntype: anchor\ntitle: PAM\naliases: [PAM]\napplies-to: [goal]\n---\n\n# PAM\n\n"
    "Purpose, Advantage, Metric.\n", encoding="utf-8")
os.environ["ANCHORS_DIR"] = str(_ANCHORS)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402
import metamodel  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def test_loader_reads_every_construct():
    mm = metamodel.load()
    assert mm["present"]
    assert len(mm["types"]) == 18, [t["name"] for t in mm["types"]]
    assert mm["relations"] and mm["projections"] and mm["rules"] and mm["altitude"]
    assert [f["name"] for f in mm["frameworks"]] == ["req42", "commons", "arc42"]
    # types come in block order: goals (R1) first, the blockless source last
    assert mm["types"][0]["name"] == "goal" and mm["types"][-1]["name"] == "source"
    for t in mm["types"]:
        assert t["_summary"], t["name"]          # the definition column is never empty
    anchors = metamodel.anchors(mm)
    assert anchors["FR"] == "type-functional-requirement"
    assert anchors["rel-parent"] == "rel-parent" and anchors["goal"] == "type-goal"


def test_graph_is_a_projection_of_types_and_relations():
    mm = metamodel.load()
    g = app.build_metamodel_graph(mm)
    nodes = {n["data"]["id"]: n["data"] for n in g["nodes"]}
    type_ids = {t["name"] for t in mm["types"]}
    assert type_ids <= set(nodes)
    # every type with a block sits inside that block's compound node
    for t in mm["types"]:
        if t.get("block"):
            assert nodes[t["name"]]["parent"] == f"block:{t['block']}", t["name"]
            assert nodes[f"block:{t['block']}"]["is_block"] is True
        else:
            assert "parent" not in nodes[t["name"]]
    # every edge joins two real type nodes; `any` relations are listed, not drawn
    for e in g["edges"]:
        d = e["data"]
        assert d["source"] in type_ids and d["target"] in type_ids, d
        assert d["label"]
        if d["source"] == d["target"]:
            assert d["loop_dir"]
    assert {u["field"] for u in g["universal"]} == {"related", "sources", "ingested-pages"}
    # the two loops on data-model (parent, relationships) fan out differently
    dm_loops = [e["data"]["loop_dir"] for e in g["edges"]
                if e["data"]["source"] == "data-model" == e["data"]["target"]]
    assert len(dm_loops) == len(set(dm_loops)) >= 2, dm_loops


def test_page_renders_tables_graph_and_examples():
    with app.app.test_request_context("/metamodel"):
        r = app.app.test_client().get("/metamodel")
    assert r.status_code == 200
    body = r.get_data(as_text=True)
    for section in ("id=\"graph\"", "id=\"types\"", "id=\"relations\"", "id=\"projections\"",
                    "id=\"altitude\"", "id=\"rules\"", "id=\"language\""):
        assert section in body, section
    # one row per type, anchored by construct-prefixed ids
    for t in metamodel.load()["types"]:
        assert f'id="type-{t["name"]}"' in body, t["name"]
        assert t["label"] in body
    assert 'id="rel-parent"' in body and 'id="proj-story-map"' in body
    # live examples come from the fixture vault and link to the page views
    assert "/functional-requirements/FR-001" in body
    assert "/page/glossary/GLO-" in body
    # a type with no page in this vault says so instead of inventing one
    assert "none yet" in body
    # metamodel wikilinks resolve to in-page anchors, decision records to
    # their page (when the vault has it), method anchors to their entry (FR-035)
    assert 'href="#rel-parent"' in body
    with app.app.test_request_context("/metamodel"):
        assert 'href="/page/decisions/DR-001-carts-expire-after-a-day">DR-001</a>' in app._mm_wikilinks(
            "[[DR-001-carts-expire-after-a-day|DR-001]]", {})
    assert '<a class="mm-anchor" href="#anchor-pam"' in body and 'id="anchor-pam"' in body
    # the open altitude question is shown as such
    assert "mm-assign-open" in body and "use cases versus epics" in body.lower()
    # the graph script and data are on the page
    assert "metamodel-graph.js" in body and 'id="mm-graph-data"' in body


def test_non_universal_type_shows_all_its_fields():
    # Source is `universal: false`: it lists id, title, status … itself, and
    # the page must show them rather than drop them as "universal".
    body = app.app.test_client().get("/metamodel").get_data(as_text=True)
    start = body.index('id="type-source"')
    row = body[start:body.index("</tr>", start)]
    for name in ("id", "title", "status", "sha256", "ingested-pages"):
        assert f"<code>{name}</code>" in row, name
    assert "ingested" in row and "+ universal" not in row


def test_decision_records_link_only_to_the_exact_page():
    # The metamodel ships to every project, meta's decisions do not, and a
    # project numbers its own from DR-001. The fixture vault has its own
    # DR-001-carts-expire-after-a-day: an ID that collides with it must not
    # link there.
    with app.app.test_request_context("/metamodel"):
        exact = app._mm_dr_link("DR-001-carts-expire-after-a-day", "DR-001")
        assert 'href="/page/decisions/DR-001-carts-expire-after-a-day">DR-001</a>' in exact
        assert app._mm_dr_link("DR-001") == "DR-001"                        # bare ID: never linked
        assert app._mm_dr_link("DR-001-context-diagram") == "DR-001-context-diagram"  # same ID, other decision
        assert "href" not in app._mm_wikilinks("[[DR-001]]", {})
        assert "href" not in app._mm_wikilinks("[[DR-035-explicit-metamodel|DR-035]]", {})  # not in this vault
    # the page's own projections cite meta's decisions, which this vault lacks
    body = app.app.test_client().get("/metamodel").get_data(as_text=True)
    for meta_stem in ("DR-013-data-flows-as-edges-context-diagram-as-projection", "DR-035-explicit-metamodel"):
        assert f'href="/page/decisions/{meta_stem}"' not in body, meta_stem


def test_menu_and_help_link_to_it():
    body = app.app.test_client().get("/help").get_data(as_text=True)
    assert 'href="/metamodel"' in body
    assert 'role="menuitem">Metamodel</a>' in body


def test_every_type_has_a_colour_token_in_both_themes():
    css = (ROOT / "static" / "style.css").read_text(encoding="utf-8")
    dark = css[css.index(":root {"):css.index(':root[data-theme="light"]')]
    light = css[css.index(':root[data-theme="light"]'):css.index("* { box-sizing")]
    for t in metamodel.load()["types"]:
        tok = f"--layer-{t['prefix'].lower()}-ink:"
        assert tok in dark and tok in light, tok
        assert f".mm-dot-{t['prefix'].lower()} {{" in css, t["prefix"]


if __name__ == "__main__":
    test_loader_reads_every_construct()
    test_graph_is_a_projection_of_types_and_relations()
    test_page_renders_tables_graph_and_examples()
    test_non_universal_type_shows_all_its_fields()
    test_decision_records_link_only_to_the_exact_page()
    test_menu_and_help_link_to_it()
    test_every_type_has_a_colour_token_in_both_themes()
    print("OK: /metamodel")
