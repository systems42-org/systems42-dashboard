"""arc42 Building Block View (A2) and the `drivers` traceability link —
no pytest dependency.

Run from the dashboard dir:
    .venv/bin/python tests/test_building_blocks.py

WIKI_DIR points at tests/fixtures/arc42/wiki, a small vault of its own (no
context page, a parent cycle, dangling links), so the counts in the other
tests' fixture vault stay untouched.
"""
import os
import sys
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "arc42" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASHBOARD_CONFIG"] = str(_FIXTURE.parent / "dashboard-absent.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _flat(nodes):
    for n in nodes:
        yield n
        yield from _flat(n["children"])


def _page(folder, stem):
    return next(p for p in app.load_folder(folder) if p.stem == stem)


# --- projections -------------------------------------------------------------

def test_tree_levels():
    tree = app.build_bb_tree()
    roots = [n["id"] for n in tree]
    # BB-001 has no parent; BB-002's parent is a context page (missing here)
    assert "BB-001" in roots and "BB-002" in roots, roots
    bb1 = next(n for n in tree if n["id"] == "BB-001")
    assert [c["id"] for c in bb1["children"]] == ["BB-003", "BB-004"]
    assert bb1["url"] == "/page/building-blocks/BB-001-booking"
    assert bb1["title"] == "Buchung"


def test_tree_survives_parent_cycle():
    ids = [n["id"] for n in _flat(app.build_bb_tree())]
    assert sorted(ids) == ["BB-001", "BB-002", "BB-003", "BB-004", "BB-005", "BB-006", "BB-007-noid"], ids
    assert len(ids) == len(set(ids)), ids        # every block exactly once


def test_level_one_without_context():
    assert not (_FIXTURE / "context").exists()
    roots = [n["id"] for n in app.build_bb_tree()]
    assert "BB-002" in roots, roots


def test_whitebox_has_children_and_uses():
    mm = app.build_whitebox("BB-001-booking")
    assert mm and mm.startswith("flowchart")
    assert "BB003" in mm and "BB004" in mm, mm
    assert "BB003 --> BB004" in mm, mm           # BB-003 uses BB-004
    assert "EIF001" in mm and "Zahlungsdienst" in mm, mm   # BB-004 uses EIF-001


def test_whitebox_none_for_leaf():
    assert app.build_whitebox("BB-003-booking-ui") is None


def test_whitebox_level_one():
    mm = app.build_whitebox(None)
    assert "BB001 --> BB002" in mm, mm


def test_driver_link_forms():
    # quoted wikilink with alias, quoted wikilink, bare stem, unquoted [[x]] (YAML nested list)
    assert app.links_of(_page("building-blocks", "BB-001-booking"), "drivers") == [
        "QR-001-fast-search", "UC-001-find-course", "FR-001-search"]
    assert app.links_of(_page("building-blocks", "BB-004-booking-core"), "drivers") == ["QR-001-fast-search"]
    assert app.links_of(_page("building-blocks", "BB-004-booking-core"), "parent") == ["BB-001-booking"]


def test_dangling_links_are_skipped():
    assert app.links_of(_page("building-blocks", "BB-002-catalog"), "uses") == ["EIF-001-payment"]
    assert app.links_of(_page("decisions", "DR-001-modular-monolith"), "drivers") == ["QR-001-fast-search"]
    assert app.links_of(_page("building-blocks", "BB-004-booking-core"), "decisions") == []


def test_drivers_grouped_by_type():
    groups = app.build_drivers("BB-001-booking")
    assert [g["type"] for g in groups] == ["FR", "UC", "QR"], groups
    assert groups[2]["links"][0]["url"] == "/page/quality-requirements/QR-001-fast-search"


def test_addressed_by_lists_dr_and_bb():
    groups = app.build_addressed_by("QR-001-fast-search")
    got = {g["type"]: [l["id"] for l in g["links"]] for g in groups}
    assert got == {"DR": ["DR-001"], "BB": ["BB-001", "BB-004", "BB-007-noid"]}, got
    assert app.build_addressed_by("UC-001-find-course")[0]["links"][0]["id"] == "BB-001"
    assert app.build_addressed_by("GLO-001-booking") == []


# --- routes ------------------------------------------------------------------

def _get(url):
    r = app.app.test_client().get(url)
    return r.status_code, r.get_data(as_text=True)


def test_a2_route_renders_tree():
    code, body = _get("/arc42/building-blocks")
    assert code == 200
    for bid in ("BB-001", "BB-002", "BB-003", "BB-004", "BB-005", "BB-006"):
        assert bid in body, bid
    assert body.index("BB-001") < body.index("BB-003")      # child under its parent
    assert 'class="mermaid"' in body and "BB001 --&gt; BB002" in body


def test_bb_page_shows_whitebox_and_drivers():
    code, body = _get("/page/building-blocks/BB-001-booking")
    assert code == 200
    assert "White box" in body and "BB003 --&gt; BB004" in body
    drivers = body[body.index("Drivers"):]
    assert "QR-001" in drivers and "UC-001" in drivers and "FR-001" in drivers
    assert "Shaped by" in body and "DR-001" in body


def test_bb_page_with_dangling_links_renders():
    for stem in ("BB-002-catalog", "BB-004-booking-core", "BB-005-loop-a"):
        code, _ = _get(f"/page/building-blocks/{stem}")
        assert code == 200, stem


def test_bb_page_shows_used_by():
    code, body = _get("/page/building-blocks/BB-004-booking-core")
    assert "Used by" in body and "BB-003" in body[body.index("Used by"):]


def test_dr_page_shows_drivers():
    code, body = _get("/page/decisions/DR-001-modular-monolith")
    assert code == 200
    assert "Drivers" in body and "QR-001" in body[body.index("Drivers"):]


def test_qr_page_addressed_by():
    code, body = _get("/page/quality-requirements/QR-001-fast-search")
    assert code == 200
    part = body[body.index("Addressed by"):]
    assert "DR-001" in part and "BB-001" in part and "BB-004" in part


def test_fr_page_addressed_by():
    code, body = _get("/functional-requirements/FR-001-search")
    assert code == 200
    assert "Addressed by" in body and "BB-001" in body[body.index("Addressed by"):]


def test_addressed_by_not_duplicated():
    _, body = _get("/page/quality-requirements/QR-001-fast-search")
    assert body.count("<code>DR-001</code>") == 1, body.count("<code>DR-001</code>")


def test_glossary_term_links_back_to_block():
    _, body = _get("/page/glossary/GLO-001-booking")
    assert "BB-001" in body


def test_glossary_network_has_a_building_block_layer():
    g = app.build_glossary_graph()
    assert g["layer_counts"].get("BB") == 1, g["layer_counts"]
    bb = next(n["data"] for n in g["nodes"] if n["data"]["id"] == "BB-001-booking")
    assert "rest" not in bb and bb["url"] == "/page/building-blocks/BB-001-booking"
    assert app.build_glossary_ego_graph("GLO-001-booking")["layer_counts"].get("BB") == 1
    _, body = _get("/graph/glossary")
    assert 'data-layer="BB"' in body and "lg-BB" in body
    _, body = _get("/page/glossary/GLO-001-booking")
    assert 'data-layer="BB"' in body


# --- final-review fixes ------------------------------------------------------

def test_blank_id_falls_back_to_the_stem_and_never_500s():
    # BB-007-noid has `id:` blank; sorting None against str used to raise
    for url in ("/arc42/building-blocks", "/page/building-blocks/BB-001-booking",
                "/page/quality-requirements/QR-001-fast-search", "/search", "/metamodel"):
        code, _ = _get(url)
        assert code == 200, url
    assert "BB-007-noid" in [l["id"] for g in app.build_addressed_by("QR-001-fast-search") for l in g["links"]]


def test_decisions_list_shows_drivers():
    _, body = _get("/decisions")
    row = body[body.index('data-id="DR-001"'):body.index("</tr>", body.index('data-id="DR-001"'))]
    assert "Drivers" in body and "QR-001" in row, row


def test_whitebox_shows_outside_blocks_as_neighbours():
    # BB-003 (inside BB-001) uses BB-002, a level-1 block outside BB-001
    mm = app.build_whitebox("BB-001-booking")
    assert "BB003 --> BB002" in mm, mm
    assert 'BB002["BB-002 · Katalog"]:::outside' in mm, mm


if __name__ == "__main__":
    test_tree_levels()
    test_tree_survives_parent_cycle()
    test_level_one_without_context()
    test_whitebox_has_children_and_uses()
    test_whitebox_none_for_leaf()
    test_whitebox_level_one()
    test_driver_link_forms()
    test_dangling_links_are_skipped()
    test_drivers_grouped_by_type()
    test_addressed_by_lists_dr_and_bb()
    test_a2_route_renders_tree()
    test_bb_page_shows_whitebox_and_drivers()
    test_bb_page_with_dangling_links_renders()
    test_bb_page_shows_used_by()
    test_dr_page_shows_drivers()
    test_qr_page_addressed_by()
    test_fr_page_addressed_by()
    test_addressed_by_not_duplicated()
    test_glossary_term_links_back_to_block()
    test_glossary_network_has_a_building_block_layer()
    test_blank_id_falls_back_to_the_stem_and_never_500s()
    test_decisions_list_shows_drivers()
    test_whitebox_shows_outside_blocks_as_neighbours()
    print("OK: building blocks")
