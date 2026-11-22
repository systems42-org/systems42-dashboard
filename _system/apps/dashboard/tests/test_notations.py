"""Requirement notations (DR-038): the notation files are both the definition
(levels, extra fields, anchors) and the page template, cut into blocks by
`<!-- levels: … -->` markers. The dashboard reads the shipped ones from
`_system/metamodel/notations/` and a project's own from `_system/notations/`
and shows them on /metamodel. No pytest dependency.

The test builds a metamodel of its own: a copy of the real one with the
notation files from tests/fixtures/notations/ in place of its own, plus one
project notation.

Run from the dashboard dir:
    .venv/bin/python tests/test_notations.py
"""
import os
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
_tmp = Path(tempfile.mkdtemp())
_mm = _tmp / "_system" / "metamodel"
shutil.copytree(REPO / "_system" / "metamodel", _mm)
shutil.copytree(HERE / "fixtures" / "notations", _mm / "notations", dirs_exist_ok=True)

_own = _tmp / "_system" / "notations"
_own.mkdir(parents=True)
(_own / "README.md").write_text("# Project notations\n\nNo frontmatter: not a notation.\n",
                                encoding="utf-8")
(_own / "notation-report-brief.md").write_text("""---
type: metamodel
construct: notation
name: ReportBrief
title: Report brief
summary: "An information need: who asks, which decision it serves."
extends: functional-requirement
levels: [brief, metric]
fields:
  - {name: audience, kind: link, required: true, doc: "who reads the report"}
anchors: []
---

# {{title}}

<!-- levels: brief, metric -->
## Information need

<!-- levels: metric -->
**Metric definition.** <formula>
""", encoding="utf-8")
(_own / "notation-nameless.md").write_text(
    "---\ntype: metamodel\nconstruct: notation\nlevels: [a]\n---\n\n# x\n", encoding="utf-8")

_cfg = _tmp / "wiki.yaml"
_cfg.write_text("system_name: Notations\n", encoding="utf-8")

os.environ["METAMODEL_DIR"] = str(_mm)
os.environ["NOTATIONS_DIR"] = str(_own)
os.environ["WIKI_DIR"] = str(HERE / "fixtures" / "wiki")
os.environ["WIKI_CONFIG"] = str(_cfg)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(HERE.parent))

import app  # noqa: E402
import metamodel  # noqa: E402


def _row(body: str, anchor: str) -> str:
    start = body.index(f'id="{anchor}"')
    return body[start:body.index("</tr>", start)]


def test_shipped_and_project_notations_are_read():
    names = [n["name"] for n in metamodel.load()["notations"]]
    # the README has no frontmatter, the nameless file defines nothing
    assert names == ["agile", "ears", "prose", "ReportBrief", "use-case"], names
    uc = next(n for n in metamodel.notations() if n["name"] == "use-case")
    assert uc["levels"] == ["kite", "sea", "fish"]
    assert [f["name"] for f in uc["fields"]] == ["primary-actor", "scope-building-block"]


def test_sections_come_from_the_level_markers():
    agile = next(n for n in metamodel.notations() if n["name"] == "agile")
    sections = {s["heading"]: s["levels"] for s in agile["_sections"]}
    assert sections["Story"] == ["epic", "feature", "story"], sections
    assert sections["Acceptance criteria"] == ["story"], sections   # a **Label.** block
    assert sections["PROBLEM / GOAL"] == ["epic", "feature"], sections
    own = next(n for n in metamodel.notations() if n["name"] == "ReportBrief")
    assert [(s["heading"], s["levels"]) for s in own["_sections"]] == [
        ("Information need", ["brief", "metric"]), ("Metric definition", ["metric"])]
    # text before the first marker is no section
    assert metamodel.notation_sections("# {{title}}\n\nno markers\n") == []


def test_anchors_name_notations_and_their_aliases():
    anchors = metamodel.anchors(metamodel.load())
    assert anchors["agile"] == "notation-agile"
    assert anchors["Cockburn"] == anchors["use-case"] == "notation-use-case"
    assert anchors["FR"] == "type-functional-requirement"   # types still win their names


def test_default_notation_is_agile_unless_wiki_yaml_names_one():
    assert app.wiki_config()["default_notation"] == "agile"
    body = app.app.test_client().get("/metamodel").get_data(as_text=True)
    assert body.index('id="notation-agile"') < body.index('id="notation-ears"')
    assert "default" in _row(body, "notation-agile")
    assert "default" not in _row(body, "notation-ears")
    _cfg.write_text("system_name: Notations\ndefault_notation: EARS\n", encoding="utf-8")
    try:
        assert app.wiki_config()["default_notation"] == "ears"
        body = app.app.test_client().get("/metamodel").get_data(as_text=True)
        # the default comes first, then the others by name
        order = [body.index(f'id="notation-{n}"') for n in ("ears", "agile", "prose", "ReportBrief", "use-case")]
        assert order == sorted(order), order
        assert "default" in _row(body, "notation-ears") and "default" not in _row(body, "notation-agile")
        # a project notation whose name has capitals is the default all the same
        _cfg.write_text("system_name: Notations\ndefault_notation: ReportBrief\n", encoding="utf-8")
        body = app.app.test_client().get("/metamodel").get_data(as_text=True)
        assert body.index('id="notation-ReportBrief"') < body.index('id="notation-agile"')
        assert "default" in _row(body, "notation-ReportBrief")
    finally:
        _cfg.write_text("system_name: Notations\n", encoding="utf-8")


def test_metamodel_page_shows_levels_fields_and_sections():
    r = app.app.test_client().get("/metamodel")
    assert r.status_code == 200
    body = r.get_data(as_text=True)
    assert 'href="#notations"' in body
    uc = _row(body, "notation-use-case")
    assert "kite → sea → fish" in uc
    assert "<code>scope-building-block</code> *" in uc
    assert "<code>Preconditions</code> <span class=\"aliases\">sea, fish</span>" in uc
    own = _row(body, "notation-ReportBrief")
    assert "brief → metric" in own and "<code>audience</code> *" in own
    # a rule narrowed by notation and level says so
    rule = _row(body, "rule-fr-traces-to-goal")
    assert "notation agile; level epic, feature" in rule, rule


def test_no_notations_folder_says_so():
    saved = metamodel.METAMODEL_DIR, metamodel.NOTATIONS_DIR
    empty = Path(tempfile.mkdtemp())
    try:
        metamodel.NOTATIONS_DIR = empty / "absent"
        shutil.rmtree(_mm / "notations")
        assert metamodel.load()["notations"] == []
        body = app.app.test_client().get("/metamodel").get_data(as_text=True)
        assert "No requirement notations declared" in body
    finally:
        shutil.copytree(HERE / "fixtures" / "notations", _mm / "notations")
        metamodel.METAMODEL_DIR, metamodel.NOTATIONS_DIR = saved


if __name__ == "__main__":
    test_shipped_and_project_notations_are_read()
    test_sections_come_from_the_level_markers()
    test_anchors_name_notations_and_their_aliases()
    test_default_notation_is_agile_unless_wiki_yaml_names_one()
    test_metamodel_page_shows_levels_fields_and_sections()
    test_no_notations_folder_says_so()
    print("ALL PASSED")
