"""Sortable headers on the issues table. No pytest.

Its own temporary vault, because the shared fixture has no issues. The sorting
itself is static/table-sort.js, covered by test_table_sort.py.

Run from the dashboard dir:
    .venv/bin/python tests/test_issues_sort.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_issues = _tmp / "wiki" / "issues"
_issues.mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

CASES = [
    ("ISS-001", "open", "minor", "gap"),
    ("ISS-002", "in-progress", "major", "question"),
    ("ISS-003", "resolved", "blocker", "risk"),
    ("ISS-004", "wontfix", "", ""),
]
for _id, _status, _severity, _kind in CASES:
    (_issues / f"{_id}-x.md").write_text(
        f"---\nid: {_id}\ntype: issue\ntitle: Frage {_id}\nstatus: {_status}\n"
        f"created: 2026-11-08\nupdated: 2026-11-08\nsources: []\nrelated: []\ntags: [issue]\n"
        f"severity: {_severity}\nkind: {_kind}\n---\n\n# Frage {_id}\n",
        encoding="utf-8")

BODY = app.app.test_client().get("/issues").get_data(as_text=True)


def test_every_column_sorts_and_id_is_marked():
    head = BODY[BODY.index("<thead"):BODY.index("</thead>")]
    assert re.search(r'<th class="c-id" data-sort="text" aria-sort="ascending">ID</th>', head), head
    assert re.search(r'<th data-sort="text">Title</th>', head), head
    assert re.search(r'<th class="c-status" data-sort="text">Kind</th>', head), head
    assert re.search(r'<th class="c-status" data-sort="numeric" data-sort-first="desc">Severity</th>', head), head
    assert re.search(r'<th class="c-status" data-sort="numeric">Status</th>', head), head


def _row(issue_id):
    return re.search(r'<tr class="issue-row" data-id="' + issue_id + r'".*?</tr>', BODY, re.S).group(0)


def _cell_keys(row):
    """The three c-status sort keys: kind (none, its text sorts), severity, status."""
    return re.findall(r'<td class="c-status" data-sort-value="([^"]*)">', row)


def test_severity_sorts_by_rank():
    assert _cell_keys(_row("ISS-001"))[0] == "1"     # minor
    assert _cell_keys(_row("ISS-002"))[0] == "2"     # major
    assert _cell_keys(_row("ISS-003"))[0] == "3"     # blocker
    assert _cell_keys(_row("ISS-004"))[0] == ""      # none: sorts last


def test_status_sorts_by_issue_lifecycle():
    for issue_id, rank in (("ISS-001", "1"), ("ISS-002", "2"), ("ISS-003", "3"), ("ISS-004", "4")):
        assert _cell_keys(_row(issue_id))[1] == rank, issue_id


def test_titles_wrap():
    # a no-wrap title pushed the Status column, and its sort control, out of the card
    assert '<td class="c-title"><span class="term">' in BODY


if __name__ == "__main__":
    test_every_column_sorts_and_id_is_marked()
    test_severity_sorts_by_rank()
    test_status_sorts_by_issue_lifecycle()
    test_titles_wrap()
    print("OK: issues sort")
