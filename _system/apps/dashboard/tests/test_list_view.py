"""The shared list layer, static/list-view.js (FR-021, FR-022). No pytest.

The sorting and the address format run under node on the same code the browser
uses. Skips when node is not installed.

Run from the dashboard dir:
    .venv/bin/python tests/test_list_view.py
"""
import json
import shutil
import subprocess
from pathlib import Path

_DASH = Path(__file__).resolve().parents[1]
JS = _DASH / "static" / "list-view.js"


def _node(body):
    js = JS.read_text(encoding="utf-8")
    out = subprocess.run(["node", "-e", "var window = {};\n" + js + "\n" + body],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def _sort(rows, spec):
    """ids of `rows` (dicts) sorted by `spec` ([{key, dir, numeric}])."""
    return _node("var r = window.S42List.sortRows(" + json.dumps(rows) + ", " + json.dumps(spec) + ");\n"
                 "console.log(JSON.stringify(r.map(function (x) { return x.id; })));")


def test_two_key_sort_orders_ties_by_the_second_key():
    rows = [
        {"id": "FR-1", "priority": "2", "order": "3"},
        {"id": "FR-2", "priority": "1", "order": "9"},
        {"id": "FR-3", "priority": "2", "order": "1"},
        {"id": "FR-4", "priority": "1", "order": "2"},
    ]
    spec = [{"key": "priority", "dir": "asc", "numeric": True}, {"key": "order", "dir": "asc", "numeric": True}]
    assert _sort(rows, spec) == ["FR-4", "FR-2", "FR-3", "FR-1"]
    spec[1]["dir"] = "desc"
    assert _sort(rows, spec) == ["FR-2", "FR-4", "FR-1", "FR-3"]


def test_empty_cells_last_in_both_directions():
    rows = [{"id": "a", "v": ""}, {"id": "b", "v": "2"}, {"id": "c", "v": "1"}]
    assert _sort(rows, [{"key": "v", "dir": "asc", "numeric": True}]) == ["c", "b", "a"]
    assert _sort(rows, [{"key": "v", "dir": "desc", "numeric": True}]) == ["b", "c", "a"]
    assert _sort(rows, [{"key": "v", "dir": "desc"}]) == ["b", "c", "a"]


def test_aerztin_sorts_next_to_arzt():
    rows = [{"id": t, "title": t} for t in ("Zertifikat", "Ärztin", "Betrieb", "Arzt", "anbieter")]
    assert _sort(rows, [{"key": "title", "dir": "asc"}]) == ["anbieter", "Arzt", "Ärztin", "Betrieb", "Zertifikat"]


def test_unknown_sort_key_leaves_the_server_order():
    rows = [{"id": "3", "v": "a"}, {"id": "1", "v": "c"}, {"id": "2", "v": "b"}]
    assert _sort(rows, [{"key": "nosuchcol", "dir": "asc"}]) == ["3", "1", "2"]
    # an unknown key next to a known one is dropped, the known one still sorts
    assert _sort(rows, [{"key": "nosuchcol", "dir": "asc"}, {"key": "v", "dir": "asc"}]) == ["3", "2", "1"]


def _order(values, numeric, asc):
    return _node("var v = " + json.dumps(values) + ";\n"
                 "v.sort(function (a, b) { return window.S42List.compare(a, b, "
                 + json.dumps(numeric) + ", " + json.dumps(asc) + "); });\n"
                 "console.log(JSON.stringify(v));")


def test_non_numbers_in_a_numeric_column_sort_after_numbers():
    # Number("x") is NaN: compared as a number it broke the order
    assert _order(["10", "2", "", "x", "1"], True, True) == ["1", "2", "10", "x", ""]
    assert _order(["10", "2", "", "x", "1"], True, False) == ["10", "2", "1", "x", ""]
    assert _order(["b", "3", "", "a"], True, True) == ["3", "a", "b", ""]
    assert _order(["b", "3", "", "a"], True, False) == ["3", "b", "a", ""]
    # the same order from every starting order: the comparison is consistent
    base = ["10", "x", "2", "", "1", "b", "007"]
    seen = {json.dumps(_order(base[i:] + base[:i], True, True)) for i in range(len(base))}
    assert len(seen) == 1, seen


def test_each_cell_is_read_once_per_sort():
    out = _node(
        "var calls = 0, rows = [];\n"
        "for (var i = 0; i < 50; i++) rows.push({id: i, a: String(i % 5), b: String(50 - i)});\n"
        "var r = window.S42List.sortKeyed(rows, [{key: 'a', dir: 'asc', numeric: true}, {key: 'b', dir: 'asc', numeric: true}],\n"
        "  function (row, key) { calls++; return row[key]; });\n"
        "console.log(JSON.stringify({calls: calls, first: r.slice(0, 3).map(function (x) { return x.id; })}));")
    assert out["calls"] == 100, out          # 50 rows, 2 keys
    assert out["first"] == [45, 40, 35], out


def test_address_format():
    parsed = _node('console.log(JSON.stringify(window.S42List.parseSort("priority:asc,release:desc,order")));')
    assert parsed == [{"key": "priority", "dir": "asc"}, {"key": "release", "dir": "desc"}, {"key": "order"}]
    # junk is ignored, never thrown
    for junk in ("", "<script>", "a:sideways", ":asc", "a:asc,a:desc"):
        out = _node("console.log(JSON.stringify(window.S42List.parseSort(" + json.dumps(junk) + ")));")
        assert all(set(s) <= {"key", "dir"} for s in out), (junk, out)
    assert _node('console.log(JSON.stringify(window.S42List.parseSort("a:sideways")));') == []
    assert _node('console.log(JSON.stringify(window.S42List.parseSort("a:asc,a:desc")));') == [{"key": "a", "dir": "asc"}]
    fmt = _node('console.log(JSON.stringify(window.S42List.formatSort([{key: "status"}, {key: "severity", dir: "desc"}])));')
    assert fmt == "status:asc,severity:desc"


def test_agreed_only_keeps_accepted_rows():
    out = _node('var k = window.S42List.keepRow;\n'
                'console.log(JSON.stringify([k("accepted", "accepted"), k("draft", "accepted"), '
                'k(undefined, "accepted"), k("draft", "all")]));')
    assert out == [True, False, False, True]


def test_replaces_table_sort():
    assert not (_DASH / "static" / "table-sort.js").exists()
    base = (_DASH / "templates" / "base.html").read_text(encoding="utf-8")
    assert "list-view.js" in base and "table-sort.js" not in base


if __name__ == "__main__":
    if not shutil.which("node"):
        print("skip: node not installed")
    else:
        test_two_key_sort_orders_ties_by_the_second_key()
        test_empty_cells_last_in_both_directions()
        test_aerztin_sorts_next_to_arzt()
        test_unknown_sort_key_leaves_the_server_order()
        test_non_numbers_in_a_numeric_column_sort_after_numbers()
        test_each_cell_is_read_once_per_sort()
        test_address_format()
        test_agreed_only_keeps_accepted_rows()
    test_replaces_table_sort()
    print("OK: list view")
