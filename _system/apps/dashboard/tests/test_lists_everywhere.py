"""Every section list uses the shared list layer (FR-021, FR-022). No pytest.

Its own temporary vault with two pages per folder, one accepted and one draft.
Per section route: one table[data-list], a sort-order picker with exactly the
metamodel's orders for that type, every header sortable, every row linking
its page and carrying its status. Bad query strings show the list, never a 500.

Run from the dashboard dir:
    .venv/bin/python tests/test_lists_everywhere.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# folder -> (prefix, type, extra frontmatter)
FOLDERS = {
    "goals": ("GOAL", "goal", "stereotype: objective\nhorizon: 2027\n"),
    "glossary": ("GLO", "glossary-term", ""),
    "stakeholders": ("STK", "stakeholder", "influence: high\ninterest: low\n"),
    "decisions": ("DR", "decision-record", "kind: business\ndecided: 2026-11-01\n"),
    "issues": ("ISS", "issue", "severity: major\nkind: question\ncategory: content\n"),
    "quality-requirements": ("QR", "quality-requirement", "priority: must\ndimensions: [usable]\n"),
    "constraints": ("CON", "constraint", ""),
    "context": ("CTX", "context", ""),
    "external-interfaces": ("EIF", "external-interface", ""),
    "activity-models": ("ACT", "activity-model", ""),
    "data-models": ("DM", "data-model", ""),
    "functional-requirements": ("FR", "functional-requirement",
                                "stereotype: epic\npriority: Must\nrelease: R1\norder: 2\n"),
    "use-cases": ("UC", "use-case", "priority: Should\n"),
    "building-blocks": ("BB", "building-block", "state: current\n"),
    "deployment-nodes": ("DN", "deployment-node", "state: planned\nstereotype: host\n"),
    "runtime-scenarios": ("RS", "runtime-scenario", "state: current\n"),
    "concepts": ("CC", "concept", "state: current\ncategory: operations\n"),
}
for folder, (prefix, typ, extra) in FOLDERS.items():
    (_wiki / folder).mkdir(parents=True)
    for n, status in ((1, "accepted"), (2, "draft")):
        if folder == "issues":
            status = "open" if n == 1 else "resolved"
        pid = f"{prefix}-00{n}"
        (_wiki / folder / f"{pid}-page-{n}.md").write_text(
            f"---\nid: {pid}\ntype: {typ}\ntitle: Seite {n}\nstatus: {status}\n"
            f"created: 2026-11-0{n}\nupdated: 2026-11-0{n}\nsources: []\nrelated: []\ntags: []\n"
            f"{extra}---\n\n# Seite {n}\n", encoding="utf-8")

# one vision, one objective
_g = _wiki / "goals" / "GOAL-001-page-1.md"
_g.write_text(_g.read_text(encoding="utf-8").replace("stereotype: objective", "stereotype: vision"), encoding="utf-8")

import app  # noqa: E402
import metamodel  # noqa: E402

client = app.app.test_client()

# route -> the type its list is declared as
ROUTES = {
    "/goals": "goal",
    "/glossary": "glossary-term",
    "/stakeholders": "stakeholder",
    "/decisions": "decision-record",
    "/issues": "issue",
    "/req42/quality": "quality-requirement",
    "/req42/constraints": "constraint",
    "/req42/scope": "context",
    "/req42/models": "activity-model",
    "/req42/functional-requirements": "functional-requirement",
    "/data-model": "data-model",
    "/arc42/building-blocks": "building-block",
    "/arc42/deployment": "deployment-node",
    "/arc42/runtime": "runtime-scenario",
    "/arc42/concepts": "concept",
}
# lists whose status is the issue lifecycle filter their status on the server
NO_AGREED_FILTER = {"/issues"}


def _get(path):
    resp = client.get(path)
    assert resp.status_code == 200, (path, resp.status_code)
    return resp.get_data(as_text=True)


def _list_table(body, path):
    tables = re.findall(r'<table\b[^>]*\bdata-list="([^"]+)"[^>]*>(.*?)</table>', body, re.S)
    assert len(tables) == 1, (path, [t[0] for t in tables])
    return tables[0]


def test_one_list_table_per_section():
    for path, typ in ROUTES.items():
        declared, _ = _list_table(_get(path), path)
        assert declared == typ, (path, declared)


def test_picker_offers_the_metamodels_orders():
    for path, typ in ROUTES.items():
        body = _get(path)
        m = re.search(r'<div class="list-controls" data-list-controls="' + typ + r'"[^>]*>(.*?)</div>\s*(?=<div class="table-card)',
                      body, re.S)
        assert m, (path, "no list controls")
        labels = [re.sub(r"<[^>]+>", "", o).strip().replace("&amp;", "&")
                  for o in re.findall(r'<option value="[^"]+">(.*?)</option>', m.group(1), re.S)]
        want = [o["label"] for o in metamodel.sort_orders(typ)]
        assert labels == want, (path, labels, want)
        # the table carries the same orders for the script
        assert re.search(r'<table\b[^>]*data-sort-orders=\'\[', body), path


def test_every_header_sorts():
    for path in ROUTES:
        _, table = _list_table(_get(path), path)
        heads = re.findall(r"<th\b([^>]*)>", table)
        assert heads, path
        for attrs in heads:
            assert "data-sort=" in attrs, (path, attrs)


def test_every_row_links_its_page_and_carries_its_status():
    for path in ROUTES:
        _, table = _list_table(_get(path), path)
        rows = re.findall(r"<tr\b([^>]*)>(.*?)</tr>", table[table.index("<tbody"):], re.S)
        assert len(rows) >= 2, (path, len(rows))
        for attrs, row in rows:
            assert re.search(r'href="/(page/[^"/]+|functional-requirements)/[A-Z]+-\d+', row), (path, row[:300])
            assert re.search(r'data-status="[a-z-]+"', attrs), (path, attrs)


def test_agreed_only_filter():
    for path in ROUTES:
        body = _get(path)
        has = 'data-list-status="accepted"' in body
        assert has == (path not in NO_AGREED_FILTER), path
        if has:
            assert ">Agreed only<" in body, path


def test_goal_list_without_a_vision():
    # no vision yet: the page shows its empty state, and still lists the goals
    _g.write_text(_g.read_text(encoding="utf-8").replace("stereotype: vision", "stereotype: objective"),
                  encoding="utf-8")
    app._PARSE_CACHE.clear()
    try:
        _, table = _list_table(_get("/goals"), "/goals")
        assert "GOAL-001" in table and "GOAL-002" in table
    finally:
        _g.write_text(_g.read_text(encoding="utf-8").replace("stereotype: objective", "stereotype: vision"),
                      encoding="utf-8")
        app._PARSE_CACHE.clear()


def test_bad_query_strings_show_the_list():
    for q in ("?sort=nosuchcol:asc", "?sort=<x>", "?status=bogus", "?sort=title:sideways&status=accepted"):
        _list_table(_get("/req42/quality" + q), q)


if __name__ == "__main__":
    test_one_list_table_per_section()
    test_picker_offers_the_metamodels_orders()
    test_every_header_sorts()
    test_every_row_links_its_page_and_carries_its_status()
    test_agreed_only_filter()
    test_goal_list_without_a_vision()
    test_bad_query_strings_show_the_list()
    print("OK: lists everywhere")
