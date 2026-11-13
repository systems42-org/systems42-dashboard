"""Sortable table headers and the clickable Domain Terms tile. No pytest.

Two halves: the templates declare which columns sort and by which key (checked
against the populated fixture vault), and static/list-view.js does the sorting
(checked under node when it is installed, on the same comparator the browser uses).

Run from the dashboard dir:
    .venv/bin/python tests/test_table_sort.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

_DASH = Path(__file__).resolve().parents[1]
os.environ["WIKI_DIR"] = str(_DASH / "tests" / "fixtures" / "wiki")
# own (absent) settings file: the project's _system/dashboard.yaml may hide sections
os.environ["DASHBOARD_CONFIG"] = str(_DASH / "tests" / "fixtures" / "dashboard-absent.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(_DASH))

import app  # noqa: E402

client = app.app.test_client()


def _headers(path):
    """[(label, attributes)] of the first table's header row on a page."""
    resp = client.get(path)
    assert resp.status_code == 200, path
    body = resp.get_data(as_text=True)
    head = body[body.index("<table"):]
    head = head[head.index("<thead"):head.index("</thead>")]
    return [(re.sub(r"<[^>]+>", "", label).replace("&amp;", "&").strip(), attrs)
            for attrs, label in re.findall(r"<th\b([^>]*)>(.*?)</th>", head, re.S)]


def _sortable(path):
    return [label for label, attrs in _headers(path) if "data-sort=" in attrs]


# FR-021: every single column sorts, free text included (was: free text stayed out)
def test_stakeholder_columns():
    assert _sortable("/stakeholders") == ["ID", "Stakeholder", "Snapshot & relations", "Influence", "Interest", "Status"]


def test_glossary_columns():
    assert _sortable("/glossary") == ["ID", "Term", "Definition", "Links", "Added", "Status"]


def test_decision_columns():
    assert _sortable("/decisions") == ["ID", "Title", "Kind", "Drivers", "Decided", "Status"]


def test_decision_titles_wrap():
    # a no-wrap title pushed the Status column, and its sort control, out of the card
    body = client.get("/decisions").get_data(as_text=True)
    assert '<td class="c-title"><span class="term">' in body


def test_block_columns():
    # quality and constraints share req42_block.html; a single-type block has a
    # constant Type column, so it is left out. Quality adds its priority.
    assert _sortable("/req42/quality") == ["ID", "Title", "Priority", "Status", "Links"]
    assert _sortable("/req42/constraints") == ["ID", "Title", "Status", "Links"]


def test_block_type_column_sorts_when_it_varies():
    # the scope block lists context pages and external interfaces together
    body = client.get("/req42/scope").get_data(as_text=True)
    assert re.search(r'<th class="c-status" data-sort="text" data-key="type">Type</th>', body), "Type not sortable on scope"


def test_context_flow_table_is_not_sortable():
    # rowspans: reordering its rows would tear the neighbour groups apart
    assert "data-sort" not in (_DASH / "templates" / "_context_flows.html").read_text(encoding="utf-8")


def test_initial_state_matches_server_order():
    def marked(path):
        return [label for label, attrs in _headers(path) if 'aria-sort="ascending"' in attrs]
    assert marked("/stakeholders") == ["ID"]
    assert marked("/decisions") == ["ID"]
    assert marked("/req42/quality") == ["ID"]
    assert marked("/glossary") == ["Term"]        # the view orders by title


def test_ratings_sort_by_rank_not_alphabet():
    body = client.get("/stakeholders").get_data(as_text=True)
    # high > medium > low, and the first click shows the highest first
    for label in ("Influence", "Interest"):
        assert re.search(r'<th class="c-status" data-sort="numeric" data-sort-first="desc"[^>]*>' + label, body), label
    cells = re.findall(r'<td class="c-status" data-sort-value="([^"]*)"><span class="lvl lvl-(\w+)"', body)
    assert cells, "no rating cells rendered"
    rank = {"low": "1", "medium": "2", "high": "3"}
    for value, level in cells:
        assert value == rank[level], (value, level)


def test_status_sorts_by_lifecycle():
    body = client.get("/stakeholders").get_data(as_text=True)
    cells = re.findall(r'<td class="c-status" data-sort-value="([^"]*)"><span class="status status-(\w+)"', body)
    assert cells, "no status cells rendered"
    rank = {"draft": "1", "review": "2", "accepted": "3", "deprecated": "4"}
    for value, status in cells:
        assert value == rank[status], (value, status)


def test_title_cells_sort_on_the_title_alone():
    # the cell also holds role/alias text, which must not decide the order
    body = client.get("/stakeholders").get_data(as_text=True)
    assert re.search(r'<td class="c-term" data-sort-value="[^"]+">\s*<a class="term term-link"', body)
    body = client.get("/glossary").get_data(as_text=True)
    assert re.search(r'<td class="c-term" data-sort-value="[^"]+">\s*<a class="term term-link"', body)


def test_script_comes_from_base_once():
    for path in ("/stakeholders", "/glossary", "/decisions", "/req42/quality", "/data-model"):
        body = client.get(path).get_data(as_text=True)
        assert len(re.findall(r'<script src="[^"]*list-view\.js', body)) == 1, path
    # the data-model page uses the shared script instead of its former inline copy
    assert "getElementById('dm-summary-table')" not in (_DASH / "templates" / "data_model.html").read_text(encoding="utf-8")


def test_domain_terms_tile_is_clickable():
    body = client.get("/commons").get_data(as_text=True)
    start = body.index('id="tile-c5"')
    tile = body[body.rfind("<", 0, start):body.rfind("<", 0, body.index('id="tile-c6"'))]
    assert re.match(r'<div id="tile-c5" class="tile tile-link', tile), tile[:120]
    # a stretched link over the whole tile, and the term network still reachable
    assert re.search(r'<a class="tile-stretch" href="/glossary">', tile), tile[:400]
    assert 'href="/graph/glossary"' in tile
    # no anchor nested in an anchor: the outer element stays a div
    assert tile.count("<a ") == tile.count("</a>")


def _run_node(body):
    js = (_DASH / "static" / "list-view.js").read_text(encoding="utf-8")
    out = subprocess.run(["node", "-e", "var window = {};\n" + js + "\n" + body],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_comparator():
    if not shutil.which("node"):
        print("skip: node not installed")
        return
    def order(values, numeric=False, asc=True):
        return _run_node("var v = " + json.dumps(values) + ";\n"
                         "v.sort(function (a, b) { return window.S42List.compare(a, b, "
                         + json.dumps(numeric) + ", " + json.dumps(asc) + "); });\n"
                         "console.log(JSON.stringify(v));")
    # IDs in natural order, not 1, 10, 2
    assert order(["STK-10", "STK-2", "STK-1"]) == ["STK-1", "STK-2", "STK-10"]
    assert order(["STK-10", "STK-2", "STK-1"], asc=False) == ["STK-10", "STK-2", "STK-1"]
    # German titles: umlauts beside their base letter, case does not split the list
    assert order(["Zertifikat", "Ärztin", "anbieter", "Betrieb"]) == ["anbieter", "Ärztin", "Betrieb", "Zertifikat"]
    # numbers by value
    assert order(["10", "9", "1"], numeric=True) == ["1", "9", "10"]
    assert order(["10", "9", "1"], numeric=True, asc=False) == ["10", "9", "1"]
    # an empty cell is missing data: last in either direction
    assert order(["", "2", "1"], numeric=True) == ["1", "2", ""]
    assert order(["", "2", "1"], numeric=True, asc=False) == ["2", "1", ""]
    assert order(["", "b", "a"], asc=False) == ["b", "a", ""]
    # ISO dates
    assert order(["2026-10-16", "", "2026-10-12"], asc=False) == ["2026-10-16", "2026-10-12", ""]


if __name__ == "__main__":
    test_stakeholder_columns()
    test_glossary_columns()
    test_decision_columns()
    test_decision_titles_wrap()
    test_block_columns()
    test_block_type_column_sorts_when_it_varies()
    test_context_flow_table_is_not_sortable()
    test_initial_state_matches_server_order()
    test_ratings_sort_by_rank_not_alphabet()
    test_status_sorts_by_lifecycle()
    test_title_cells_sort_on_the_title_alone()
    test_script_comes_from_base_once()
    test_domain_terms_tile_is_clickable()
    test_comparator()
    print("OK: table sort")
