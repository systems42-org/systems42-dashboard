"""Catalog contract: three areas, eighteen sections from the Systems42
sections diagram, every wiki folder owned by exactly one section. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_catalog.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import catalog  # noqa: E402

WIKI_FOLDERS = [
    "glossary", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "use-cases", "functional-requirements",
    "quality-requirements", "constraints", "issues", "decisions", "building-blocks",
    "deployment-nodes", "runtime-scenarios", "concepts",
]


def test_three_areas_in_diagram_order():
    assert [a["key"] for a in catalog.AREAS] == ["requirements", "architecture", "commons"]
    assert [a["href"] for a in catalog.AREAS] == ["/req42", "/arc42", "/commons"]
    for a in catalog.AREAS:
        assert a["subtitle"] and 1 <= len(a["colors"]) <= 2


def test_eighteen_sections_with_diagram_ids():
    ids = [s["id"] for s in catalog.SECTIONS]
    assert ids == ["R1", "R2", "R3", "R4", "R5", "R6",
                   "A1", "A2", "A3", "A4", "A5",
                   "C1", "C2", "C3", "C4", "C5", "C6", "C7"], ids
    assert len(set(ids)) == 18
    for s in catalog.SECTIONS:
        assert s["area"] in catalog.AREA_BY_KEY, s["id"]
        assert s["scope"] in ("in", "out", "planned"), s["id"]
        assert set(s["colors"]) <= {"req", "arc", "org"} and s["colors"], s["id"]


def test_every_wiki_folder_belongs_to_exactly_one_section():
    owners = {}
    for s in catalog.SECTIONS:
        for f in s["folders"]:
            owners.setdefault(f, []).append(s["id"])
    for f in WIKI_FOLDERS:
        assert owners.get(f) and len(owners[f]) == 1, (f, owners.get(f))
    assert set(owners) == set(WIKI_FOLDERS), set(owners) ^ set(WIKI_FOLDERS)


def test_architecture_a2_to_a5_live_and_a1_planned():
    live = {"A2": (["building-blocks"], "/arc42/building-blocks"),
            "A3": (["deployment-nodes"], "/arc42/deployment"),
            "A4": (["runtime-scenarios"], "/arc42/runtime"),
            "A5": (["concepts"], "/arc42/concepts")}
    for s in catalog.sections_of("architecture"):
        if s["id"] in live:
            folders, href = live[s["id"]]
            assert s["scope"] == "in" and s["folders"] == folders, s
            assert s["href"] == href, s
        else:
            assert s["scope"] == "planned" and s["folders"] == [] and s["href"] is None, s["id"]


def test_out_of_scope_sections_have_no_folders_or_route():
    for sid in ("R2", "R5", "R6"):
        s = catalog.SECTION_BY_ID[sid]
        assert s["scope"] == "out" and s["folders"] == [] and s["href"] is None and s["note"]


def test_routes_are_unchanged():
    by_id = catalog.SECTION_BY_ID
    assert by_id["R1"]["href"] == "/goals"
    assert by_id["R3"]["href"] == "/req42/functional-requirements" and by_id["R3"]["slug"] == "functional-requirements"
    assert by_id["R4"]["href"] == "/req42/models" and by_id["R4"]["slug"] == "models"
    assert by_id["C1"]["href"] == "/req42/quality" and by_id["C1"]["slug"] == "quality"
    assert by_id["C2"]["href"] == "/req42/constraints" and by_id["C2"]["slug"] == "constraints"
    assert by_id["C3"]["href"] == "/req42/scope" and by_id["C3"]["slug"] == "scope"
    assert by_id["C4"]["href"] == "/stakeholders"
    assert by_id["C5"]["href"] == "/glossary"
    assert by_id["C6"]["href"] == "/issues"
    assert set(catalog.SECTION_BY_SLUG) == {"functional-requirements", "models", "quality", "constraints", "scope",
                                           "building-blocks", "deployment", "runtime", "concepts"}


def test_lookups():
    assert catalog.section_for_folder("stakeholders")["id"] == "C4"
    assert catalog.area_for_folder("external-interfaces")["key"] == "commons"
    assert catalog.area_for_folder("nope") is None
    assert catalog.area_for_path("/req42/functional-requirements")["key"] == "requirements"
    assert catalog.area_for_path("/req42/quality")["key"] == "commons"
    assert catalog.area_for_path("/req42")["key"] == "requirements"
    assert catalog.area_for_path("/arc42")["key"] == "architecture"
    assert catalog.area_for_path("/commons")["key"] == "commons"
    assert catalog.area_for_path("/page/glossary/GLO-001-x")["key"] == "commons"
    assert catalog.area_for_path("/functional-requirements/FR-001-x")["key"] == "requirements"
    assert catalog.area_for_path("/graph/glossary")["key"] == "commons"
    assert catalog.area_for_path("/data-model")["key"] == "requirements"
    assert catalog.area_for_path("/") is None
    assert catalog.area_for_path("/decisions")["key"] == "commons"
    assert catalog.area_for_path("/help") is None


if __name__ == "__main__":
    test_three_areas_in_diagram_order()
    test_eighteen_sections_with_diagram_ids()
    test_every_wiki_folder_belongs_to_exactly_one_section()
    test_architecture_a2_to_a5_live_and_a1_planned()
    test_out_of_scope_sections_have_no_folders_or_route()
    test_routes_are_unchanged()
    test_lookups()
    print("OK: catalog")
