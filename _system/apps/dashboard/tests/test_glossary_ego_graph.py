"""Plain-assert test for build_glossary_ego_graph() — no pytest dependency.

The per-term ego snippet on a domain term's detail page (DR-023): a 1-hop slice of
build_glossary_graph() around one focal term. Run like the sibling test:
    .venv/bin/python tests/test_glossary_ego_graph.py

WIKI_DIR points at tests/fixtures/wiki, a small neutral vault, so the suite is
independent of whatever content this starter is filled with.
"""
import os
import sys
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import project.terms  # noqa: E402


def test_ego_is_a_valid_1hop_slice():
    full = project.terms.build_glossary_graph()
    full_ids = {n["data"]["id"] for n in full["nodes"]}

    # focal-term neighbours straight from the full edge set, for the oracle below
    def full_neighbours(stem):
        out = set()
        for e in full["edges"]:
            d = e["data"]
            if d["source"] == stem:
                out.add(d["target"])
            elif d["target"] == stem:
                out.add(d["source"])
        return out

    type_of = {n["data"]["id"]: n["data"]["type"] for n in full["nodes"]}

    checked = 0
    for stem in sorted(full_ids):
        if type_of[stem] != "DT":
            continue
        ego = project.terms.build_glossary_ego_graph(stem)
        assert ego is not None, stem
        ids = {n["data"]["id"] for n in ego["nodes"]}

        # focal node present, flagged, and the only one flagged
        assert stem in ids, stem
        focus = [n["data"]["id"] for n in ego["nodes"] if n["data"].get("focus")]
        assert focus == [stem], (stem, focus)

        # node set == focal + neighbours of type DT/STK/GOAL/BB (1-hop, type-filtered)
        expected = {stem} | {n for n in full_neighbours(stem)
                             if type_of.get(n) in project.terms._EGO_TYPES}
        assert ids == expected, (stem, ids ^ expected)
        assert all(type_of[i] in project.terms._EGO_TYPES for i in ids), stem

        # induced subgraph: every edge stays inside the ego, no dangling endpoints
        for e in ego["edges"]:
            d = e["data"]
            assert d["source"] in ids and d["target"] in ids, (stem, d)

        # layer_counts == STK/GOAL/BB cross edges actually present in the slice
        tally = {}
        for e in ego["edges"]:
            d = e["data"]
            if d.get("cross") and d.get("ntype") in project.terms._EGO_TYPES:
                tally[d["ntype"]] = tally.get(d["ntype"], 0) + 1
        assert ego["layer_counts"] == tally, (stem, ego["layer_counts"], tally)
        checked += 1

    assert checked, "no domain terms found"

    # an unknown stem yields no snippet
    assert project.terms.build_glossary_ego_graph("does-not-exist") is None

    # DT-004-shelf: exactly one term-to-term edge (to DT-001-book), and no
    # cross-type relations of its own, so its ego graph offers no layer buttons.
    shelf = project.terms.build_glossary_ego_graph("DT-004-shelf")
    assert shelf is not None
    glo_internal = [e for e in shelf["edges"] if e["data"].get("cross") is False]
    assert len(glo_internal) == 1, "DT-004-shelf should have exactly one term-to-term edge"
    assert shelf["layer_counts"] == {}, \
        "DT-004-shelf has no cross-type relations, so no layer buttons"

    print(f"OK: ego graphs valid for {checked} terms; "
          f"DT-004-shelf layers={shelf['layer_counts']}")


if __name__ == "__main__":
    test_ego_is_a_valid_1hop_slice()
    print("all glossary-ego-graph tests passed")
