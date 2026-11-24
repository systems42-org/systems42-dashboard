"""Plain-assert test for build_relations_panel() — no pytest dependency.

    .venv/bin/python tests/test_relations_panel.py

WIKI_DIR points at tests/fixtures/wiki, a small neutral vault, so the suite is
independent of whatever content this starter is filled with. Powers the
detail-page 'Links to' / 'Linked from' section.
"""
import os
import sys
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402


def _flat(groups):
    return [it for g in groups for it in g["links"]]


def test_relations_panel_outbound_inbound_and_dedup():
    with app.app.test_request_context("/"):
        rel = app.build_relations_panel("STK-001-librarian")

    out = _flat(rel["outbound"])
    inb = _flat(rel["inbound"])
    out_ids = {i["id"] for i in out}
    inb_ids = {i["id"] for i in inb}

    # a page that links here and is linked from here shows in both (FR-034)
    with app.app.test_request_context("/"):
        pages = {p.id: p for p in app.load_all_pages()}
        me = pages["STK-001"]
        both = {i for i in out_ids if app.links_to(pages[i], me)}
    assert out_ids & inb_ids == both, (out_ids & inb_ids, both)
    # never links to itself
    assert "STK-001" not in out_ids and "STK-001" not in inb_ids

    # outbound carries the domain terms this stakeholder relates to
    assert "DT-003" in out_ids, "domain term Member missing from outbound"
    assert "DT-002" in out_ids, "domain term Loan missing from outbound"
    # inbound surfaces where the role is used (functional requirements)
    assert any(i.startswith("FR-") for i in inb_ids), "no FR backlinks"

    # every link has a usable URL and a label
    for it in out + inb:
        assert it["url"].startswith(("/page/", "/functional-requirements/")), it
        assert it["label"], it
    # FR links route to the rich FR page, not the generic detail route
    for it in out + inb:
        if it["type"] == "FR":
            assert it["url"].startswith("/functional-requirements/"), it

    # groups are typed and ordered (DT before ISS per the catalog's group order)
    types = [g["type"] for g in rel["outbound"]]
    assert types == sorted(types, key=app.catalog.prefix_order().index), types

    print(f"OK: STK-001 → {len(out)} outbound, {len(inb)} inbound links")


if __name__ == "__main__":
    test_relations_panel_outbound_inbound_and_dedup()
    print("all relations-panel tests passed")
