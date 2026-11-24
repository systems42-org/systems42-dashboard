"""The delivery status of a requirement: a badge on its page and a filter on
the requirement list (issue #91, FR-048). No pytest.

A requirement page with a `delivery:` value shows it as a badge in the page
head, next to the status, with the date of `delivery-checked`. The list of all
requirements gets a Delivery column and a filter, both only when at least one
requirement has a value. The allowed states come from the repository's
metamodel (CON-006), with the shipped defaults where it declares none.

Run from the dashboard dir:
    .venv/bin/python tests/test_delivery_status.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_DASH = Path(__file__).resolve().parents[1]
_system = Path(__file__).resolve().parents[3]
_repo = Path(tempfile.mkdtemp()) / "repo"
_wiki = _repo / "wiki"
_fr = _wiki / "functional-requirements"
_fr.mkdir(parents=True)
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
(_repo / "docs").mkdir()
_config = _repo / "_system" / "wiki.yaml"
_config.parent.mkdir(parents=True, exist_ok=True)
_config.write_text("system_name: Tracking\n", encoding="utf-8")
_mm = _repo / "_system" / "metamodel"
shutil.copytree(_system / "metamodel", _mm)
shutil.copytree(_system / "anchors", _repo / "_system" / "anchors")

HOSTILE = '"><script>alert(1)</script>'
STORY = "status: draft\nnotation: agile\nlevel: story\n"

PAGES = {
    "FR-001-implemented": "id: FR-001\ntitle: Implemented\nstatus: accepted\nnotation: agile\nlevel: story\n"
                          "delivery: implemented\ndelivery-checked: 2026-11-20T00:30:00+01:00",
    "FR-002-outdated": "id: FR-002\ntitle: Outdated\n" + STORY + "delivery: outdated\ndelivery-checked: 2026-10-01",
    "FR-003-removed": "id: FR-003\ntitle: Removed\n" + STORY
                      + "delivery: removed\ndelivery-checked: '2026-09-02T08:00:00Z'",
    "FR-004-no-record": "id: FR-004\ntitle: No record\n" + STORY,
    "FR-005-blank": "id: FR-005\ntitle: Blank\n" + STORY + "delivery:\ndelivery-checked:",
    # not a state of the metamodel
    "FR-006-unknown-state": "id: FR-006\ntitle: Unknown state\n" + STORY + "delivery: done",
    # an epic is not implemented directly, so it may not carry the field
    "FR-007-epic": "id: FR-007\ntitle: Epic\nstatus: draft\nnotation: agile\nlevel: epic\ndelivery: implemented",
    # `partial` belongs to use cases, the Agile notation does not allow it
    "FR-008-partial-story": "id: FR-008\ntitle: Partial story\n" + STORY + "delivery: partial",
    "FR-009-hostile": "id: FR-009\ntitle: Hostile\n" + STORY + f"delivery: '{HOSTILE}'\ndelivery-checked: '{HOSTILE}'",
    "FR-010-checked-only": "id: FR-010\ntitle: Checked only\n" + STORY + "delivery-checked: 2026-11-20",
    "FR-011-list-value": "id: FR-011\ntitle: List value\n" + STORY + "delivery: [implemented, outdated]",
    "UC-001-partial": "id: UC-001\ntitle: Partial use case\nstatus: draft\nnotation: use-case\nlevel: sea\n"
                      "delivery: partial",
    "UC-002-kite": "id: UC-002\ntitle: Kite use case\nstatus: draft\nnotation: use-case\nlevel: kite\n"
                   "delivery: implemented",
    # no notation: only the type's list of states applies
    "FR-012-no-notation": "id: FR-012\ntitle: No notation\nstatus: draft\ndelivery: partial",
}


def _write_pages(pages):
    for old in _fr.glob("*.md"):
        old.unlink()
    for stem, frontmatter in pages.items():
        (_fr / f"{stem}.md").write_text(f"---\n{frontmatter}\n---\n# T\n\nText.\n", encoding="utf-8")


_write_pages(PAGES)

os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_config)
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_repo / "docs")
os.environ["METAMODEL_DIR"] = str(_mm)
for _name in ("NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_name, None)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(_DASH))  # import app.py

import app  # noqa: E402

LIST = "/req42/functional-requirements"
_HEAD = re.compile(r'<div class="detail-head">.*?</div>', re.S)
_BADGE = re.compile(r'<span class="delivery[ "].*?</span>', re.S)
_CHECKED = re.compile(r'<span class="delivery-checked">(.*?)</span>', re.S)
_ROW = re.compile(r'<tr data-status="([^"]*)"( data-delivery="([^"]*)")?>\s*<td class="c-id"><code>([^<]*)</code>')
_NOT_ALLOWED = ' title="The metamodel does not allow this delivery value for this requirement"'


def _get(path):
    resp = app.app.test_client().get(path, follow_redirects=True)
    assert resp.status_code == 200, (path, resp.status_code)
    return resp.get_data(as_text=True)


def _head(stem):
    html = _get(f"/functional-requirements/{stem}")
    found = _HEAD.findall(html)
    assert len(found) == 1, (stem, found)
    # the badge shows in the page head and nowhere else on the page
    assert html.count('class="delivery') == found[0].count('class="delivery'), stem
    return found[0]


def _badge(stem):
    """(badge markup or None, checked date or None) in the head of a requirement page."""
    head = _head(stem)
    badges, checked = _BADGE.findall(head), _CHECKED.findall(head)
    assert len(badges) <= 1 and len(checked) <= 1, head
    return (badges[0] if badges else None), (checked[0] if checked else None)


def test_a_delivery_value_shows_as_a_badge_next_to_the_status():
    head = _head("FR-001-implemented")
    assert re.search(r'<span class="status status-accepted">accepted</span>\s*'
                     r'<span class="delivery delivery-implemented">implemented</span>\s*'
                     r'<span class="delivery-checked">checked 2026-11-20</span>', head), head
    # the generic address of a requirement leads to the same page
    assert _HEAD.findall(_get("/page/functional-requirements/FR-001-implemented")) == [head]


def test_each_state_reads_in_plain_words():
    assert _badge("FR-002-outdated") == (
        '<span class="delivery delivery-outdated">implementation outdated</span>', "checked 2026-10-01")
    assert _badge("FR-003-removed") == (
        '<span class="delivery delivery-removed">implementation removed</span>', "checked 2026-09-02")
    # a use case is built in slices, so it may be partial. No check date, no date shown
    assert _badge("UC-001-partial") == (
        '<span class="delivery delivery-partial">partly implemented</span>', None)


def test_no_value_no_badge():
    for stem in ("FR-004-no-record", "FR-005-blank", "FR-010-checked-only", "FR-011-list-value"):
        head = _head(stem)
        assert _badge(stem) == (None, None), stem
        assert "delivery" not in head and "checked" not in head and "None" not in head, (stem, head)


def test_a_value_that_is_not_allowed_shows_as_written_and_unstyled():
    for stem, text in (("FR-006-unknown-state", "done"), ("FR-007-epic", "implemented"),
                       ("FR-008-partial-story", "partial"), ("UC-002-kite", "implemented")):
        assert _badge(stem) == (f'<span class="delivery"{_NOT_ALLOWED}>{text}</span>', None), (stem, _badge(stem))
    # without a notation only the type's own list of states counts
    assert _badge("FR-012-no-notation") == (
        '<span class="delivery delivery-partial">partly implemented</span>', None)


def test_a_hostile_value_comes_out_escaped():
    html = _get("/functional-requirements/FR-009-hostile")
    assert "<script>alert(1)" not in html
    badge, checked = _badge("FR-009-hostile")
    assert badge == f'<span class="delivery"{_NOT_ALLOWED}>&#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt;</span>', badge
    assert checked == "checked &#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt;", checked
    listing = _get(LIST)
    assert "<script>alert(1)" not in listing
    assert 'data-delivery="&#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"' in listing


def _options(html):
    m = re.search(r"<select data-list-delivery>(.*?)</select>", html, re.S)
    return re.findall(r'<option value="([^"]*)">([^<]*)</option>', m.group(1)) if m else None


def _rows(html):
    """ID -> the row's delivery value (None when the row has no such attribute)."""
    return {m.group(4): (m.group(3) if m.group(2) else None) for m in _ROW.finditer(html)}


def test_the_list_has_a_delivery_filter_and_a_column():
    html = _get(LIST)
    assert _options(html) == [("", "All"), ("partial", "partly implemented"), ("implemented", "implemented"),
                              ("outdated", "implementation outdated"), ("removed", "implementation removed"),
                              ("none", "No delivery record")], _options(html)
    assert '<th class="c-status" data-sort="text" data-key="delivery">Delivery</th>' in html
    rows = _rows(html)
    assert rows == {"FR-001": "implemented", "FR-002": "outdated", "FR-003": "removed", "FR-004": "",
                    "FR-005": "", "FR-006": "done", "FR-007": "implemented", "FR-008": "partial",
                    "FR-009": "&#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt;", "FR-010": "", "FR-011": "",
                    "FR-012": "partial", "UC-001": "partial", "UC-002": "implemented"}, rows
    # the same badge as on the page, as the cell's content and its sort value
    assert re.search(r'<td class="c-status" data-sort-value="implemented">\s*'
                     r'<span class="delivery delivery-implemented">implemented</span>\s*</td>', html)
    assert re.search(r'<td class="c-status" data-sort-value="done">\s*'
                     rf'<span class="delivery"{_NOT_ALLOWED}>done</span>\s*</td>', html)
    assert re.search(r'<td class="c-status" data-sort-value="">\s*</td>', html)
    assert "delivery-checked" not in html


def _filter(search="", actions=()):
    """The requirement list as the server renders it, run through
    static/list-view.js under node: the IDs shown, the address, the picker."""
    html = _get(LIST)
    rows = [{"status": m.group(1), "kind": "", "delivery": (m.group(3) or "").replace("&#34;", '"'),
             "cells": [m.group(4)]} for m in _ROW.finditer(html)]
    spec = {"search": search, "list": "functional-requirement", "columns": [{"key": "id"}], "rows": rows,
            "kinds": [], "deliveries": [v for v, _ in _options(html)], "actions": list(actions)}
    out = subprocess.run(["node", str(_DASH / "tests" / "list_harness.js")], input=json.dumps(spec),
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_the_filter_shows_only_the_matching_requirements():
    everything = sorted(_rows(_get(LIST)))
    out = _filter()
    assert out["shown"] == everything and out["search"] == "" and out["delivery"] == ""
    out = _filter(actions=[{"delivery": "implemented"}])
    assert out["shown"] == ["FR-001", "FR-007", "UC-002"], out
    assert out["search"] == "?delivery=implemented" and not out["emptyHint"]
    out = _filter(actions=[{"delivery": "partial"}])
    assert out["shown"] == ["FR-008", "FR-012", "UC-001"], out
    # "No delivery record": the requirements without a value
    out = _filter(actions=[{"delivery": "none"}])
    assert out["shown"] == ["FR-004", "FR-005", "FR-010", "FR-011"], out
    assert out["search"] == "?delivery=none"
    # back to all: the parameter leaves the address
    out = _filter(actions=[{"delivery": "outdated"}, {"delivery": ""}])
    assert out["shown"] == everything and out["search"] == ""


def test_the_filter_combines_with_the_status_filter_the_sort_and_the_address():
    out = _filter(search="?delivery=implemented")
    assert out["shown"] == ["FR-001", "FR-007", "UC-002"] and out["delivery"] == "implemented", out
    out = _filter(search="?delivery=implemented", actions=[{"status": "accepted"}])
    assert out["shown"] == ["FR-001"] and out["search"] == "?delivery=implemented&status=accepted", out
    assert out["events"][-1] == {"status": "accepted", "kind": "", "delivery": "implemented"}, out["events"]
    out = _filter(search="?delivery=removed&status=accepted")
    assert out["shown"] == [] and out["emptyHint"], out
    out = _filter(search="?delivery=implemented&sort=id:desc")
    assert out["shown"] == ["UC-002", "FR-007", "FR-001"], out
    assert out["search"] == "?delivery=implemented&sort=id:desc"
    # a value the picker does not offer shows every requirement
    out = _filter(search="?delivery=done")
    assert len(out["shown"]) == len(PAGES) and out["delivery"] == "", out


def _edit(path, change):
    """Rewrite a metamodel file. The reader parses it again: its size changes."""
    text = path.read_text(encoding="utf-8")
    changed = change(text)
    assert changed != text, path.name
    path.write_text(changed, encoding="utf-8")
    return text


def test_the_states_come_from_the_metamodel():
    type_page = _mm / "types" / "type-functional-requirement.md"
    agile = _mm / "notations" / "notation-agile.md"
    was_type = _edit(type_page, lambda t: t.replace("values: [partial, implemented, outdated, removed]",
                                                    "values: [implemented, verified]"))
    was_agile = _edit(agile, lambda t: t.replace("delivery_states: [implemented, outdated, removed]",
                                                 "delivery_states: [implemented, verified, done]")
                      .replace("implementable_levels: [story]", "implementable_levels: [story, epic]"))
    (_fr / "FR-013-verified.md").write_text(
        f"---\nid: FR-013\ntitle: Verified\n{STORY}delivery: verified\n---\n# T\n", encoding="utf-8")
    try:
        # a state the dashboard has no words for shows under its own name
        assert _badge("FR-013-verified") == ('<span class="delivery delivery-verified">verified</span>', None)
        assert _badge("FR-007-epic") == ('<span class="delivery delivery-implemented">implemented</span>', None)
        # the type's list decides first: neither `outdated` nor the notation's `done` is in it
        assert _badge("FR-002-outdated")[0] == f'<span class="delivery"{_NOT_ALLOWED}>outdated</span>'
        assert _badge("FR-006-unknown-state")[0] == f'<span class="delivery"{_NOT_ALLOWED}>done</span>'
        assert _options(_get(LIST)) == [
            ("", "All"), ("implemented", "implemented"), ("verified", "verified"), ("none", "No delivery record")]
    finally:
        type_page.write_text(was_type, encoding="utf-8")
        agile.write_text(was_agile, encoding="utf-8")
        (_fr / "FR-013-verified.md").unlink()


def test_a_metamodel_without_the_declarations_gets_the_shipped_defaults():
    type_page = _mm / "types" / "type-functional-requirement.md"
    was = {type_page: _edit(type_page, lambda t: re.sub(r"^  - \{name: delivery,.*\n", "", t, flags=re.M))}
    for notation in sorted((_mm / "notations").glob("notation-*.md")):
        was[notation] = _edit(notation, lambda t: re.sub(r"^(implementable_levels|delivery_states):.*\n", "", t,
                                                         flags=re.M))
    try:
        test_a_delivery_value_shows_as_a_badge_next_to_the_status()
        test_each_state_reads_in_plain_words()
        test_a_value_that_is_not_allowed_shows_as_written_and_unstyled()
        test_the_list_has_a_delivery_filter_and_a_column()
    finally:
        for path, text in was.items():
            path.write_text(text, encoding="utf-8")


def test_a_wiki_without_delivery_values_looks_as_before():
    without = {stem: "\n".join(line for line in fm.splitlines() if not line.startswith("delivery"))
               for stem, fm in PAGES.items()}
    _write_pages(without)
    try:
        html = _get(LIST)
        assert "delivery" not in html.lower(), re.findall(r".{40}delivery.{40}", html, re.I | re.S)[:3]
        assert len(_rows(html)) == len(PAGES) and set(_rows(html).values()) == {None}
        assert "delivery" not in _get("/functional-requirements/FR-001-implemented").lower()
    finally:
        _write_pages(PAGES)


if __name__ == "__main__":
    _node = shutil.which("node")
    for _name, _fn in sorted(globals().items()):
        if _name.startswith("test_") and callable(_fn):
            if not _node and "filter_shows" in _name or not _node and "filter_combines" in _name:
                print(f"skip {_name}: node not installed")
                continue
            _fn()
            print(f"ok {_name}")
    print("✓ delivery status")
