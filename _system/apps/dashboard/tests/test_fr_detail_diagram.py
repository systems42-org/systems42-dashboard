"""The detail diagram of a requirement (FR-047). No pytest.

Its own temporary vault: an epic with a feature and a story, a requirement
outside the hierarchy, and building blocks whose `drivers:` name some of them.
The diagram on a requirement's page draws exactly its children and its own
building blocks, and lists the same pages as text links (QR-001).

Run from the dashboard dir:
    .venv/bin/python tests/test_fr_detail_diagram.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("functional-requirements", "building-blocks", "decisions"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

HEAD = ("---\nid: {id}\ntype: {type}\ntitle: {title}\nstatus: draft\ncreated: 2026-11-21\n"
        "updated: 2026-11-21\nsources: []\nrelated: []\ntags: []\n{extra}---\n\n# {title}\n")


def _fr(stem, title, level, parent=""):
    extra = f"notation: agile\nlevel: {level}\npriority: Should\n"
    if parent:
        extra += f'parent: ["[[{parent}]]"]\n'
    (_wiki / "functional-requirements" / f"{stem}.md").write_text(
        HEAD.format(id=stem[:6], type="functional-requirement", title=title, extra=extra), encoding="utf-8")


def _driven(folder, type_, stem, title, drivers):
    links = ", ".join(f'"[[{d}]]"' for d in drivers)
    (_wiki / folder / f"{stem}.md").write_text(
        HEAD.format(id=stem[:6], type=type_, title=title, extra=f"drivers: [{links}]\n"), encoding="utf-8")


_fr("FR-001-lend-books", "Lend books", "epic")
_fr("FR-002-check-out", "Check out", "feature", "FR-001-lend-books")
_fr("FR-003-scan-a-book", "Scan a book", "story", "FR-002-check-out")
_fr("FR-004-remind-readers", "Remind readers", "feature", "FR-001-lend-books")
_fr("FR-005-print-a-label", "Print a label", "story")           # no parent: outside the hierarchy

_driven("building-blocks", "building-block", "BB-001-desk", "Desk", ["FR-001-lend-books"])
_driven("building-blocks", "building-block", "BB-002-scanner", "Scanner",
        ["FR-003-scan-a-book", "FR-001-lend-books"])
_driven("building-blocks", "building-block", "BB-003-printer", "Printer", ["FR-005-print-a-label"])
_driven("building-blocks", "building-block", "BB-004-archive", "Archive", [])
# a decision driven by the epic is no building block: it stays out of the diagram
_driven("decisions", "decision-record", "DR-001-one-desk", "One desk", ["FR-001-lend-books"])

import app  # noqa: E402

client = app.app.test_client()


def _page(stem):
    resp = client.get(f"/functional-requirements/{stem}")
    assert resp.status_code == 200, stem
    return resp.get_data(as_text=True)


def _diagram(body):
    m = re.search(r'<figure class="goals-diagram">\s*<pre class="mermaid">(.*?)</pre>', body, re.S)
    return m.group(1) if m else None


def _nodes(diagram):
    """The ids of every node the diagram links to a page."""
    return sorted(re.findall(r'click \w+ &#34;/[^&]*/((?:FR|BB|DR)-\d+)', diagram))


def _text_links(body):
    m = re.search(r'<details class="diagram-links">(.*?)</details>', body, re.S)
    return sorted(re.findall(r"<code>(.*?)</code>", m.group(1))) if m else []


def test_an_epic_shows_its_children_and_its_own_blocks():
    body = _page("FR-001-lend-books")
    dia = _diagram(body)
    # children and grandchildren, plus the two blocks driven by the epic itself
    assert _nodes(dia) == ["BB-001", "BB-002", "FR-002", "FR-003", "FR-004"], _nodes(dia)
    assert "DR-001" not in dia and "BB-004" not in dia
    assert "/page/building-blocks/BB-001-desk" in dia


def test_a_block_hangs_on_the_requirement_with_a_dashed_edge():
    dia = _diagram(_page("FR-001-lend-books"))
    assert re.search(r"FR001 -\.-&gt; BB001\[\[", dia), dia
    assert re.search(r"FR001 --&gt; FR002\[", dia), dia
    assert "classDef block" in dia


def test_a_feature_does_not_show_the_blocks_of_its_parent_or_its_children():
    body = _page("FR-002-check-out")
    assert _nodes(_diagram(body)) == ["FR-003"]


def test_a_story_without_children_shows_its_blocks():
    body = _page("FR-003-scan-a-book")
    assert _nodes(_diagram(body)) == ["BB-002"]


def test_a_requirement_with_neither_children_nor_blocks_has_no_diagram():
    body = _page("FR-004-remind-readers")
    assert _diagram(body) is None
    assert 'class="diagram-links"' not in body


def test_a_requirement_outside_the_hierarchy_shows_its_blocks():
    body = _page("FR-005-print-a-label")
    assert _nodes(_diagram(body)) == ["BB-003"]


def test_the_text_links_name_the_same_pages_as_the_diagram():
    for stem in ("FR-001-lend-books", "FR-002-check-out", "FR-003-scan-a-book", "FR-005-print-a-label"):
        body = _page(stem)
        assert _text_links(body) == _nodes(_diagram(body)), stem
    assert 'href="/page/building-blocks/BB-002-scanner"' in _page("FR-003-scan-a-book")


def test_the_blocks_come_from_the_drivers_of_the_block_only():
    # a `building-blocks:` field on the requirement is no second source
    path = _wiki / "functional-requirements" / "FR-004-remind-readers.md"
    old = path.read_text(encoding="utf-8")
    try:
        path.write_text(old.replace("priority: Should\n",
                                    'priority: Should\nbuilding-blocks: ["[[BB-004-archive]]"]\n'), encoding="utf-8")
        assert [b.id for b in app.fr_building_blocks("FR-004-remind-readers")] == []
    finally:
        path.write_text(old, encoding="utf-8")
    assert [b.id for b in app.fr_building_blocks("FR-001-lend-books")] == ["BB-001", "BB-002"]


if __name__ == "__main__":
    test_an_epic_shows_its_children_and_its_own_blocks()
    test_a_block_hangs_on_the_requirement_with_a_dashed_edge()
    test_a_feature_does_not_show_the_blocks_of_its_parent_or_its_children()
    test_a_story_without_children_shows_its_blocks()
    test_a_requirement_with_neither_children_nor_blocks_has_no_diagram()
    test_a_requirement_outside_the_hierarchy_shows_its_blocks()
    test_the_text_links_name_the_same_pages_as_the_diagram()
    test_the_blocks_come_from_the_drivers_of_the_block_only()
    print("OK fr detail diagram")
