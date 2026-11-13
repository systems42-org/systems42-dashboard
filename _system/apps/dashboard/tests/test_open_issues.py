""""Open" means one thing everywhere: every status except resolved and wontfix.
No pytest.

An issue with no status, or a status outside the issue lifecycle, stays
visible as open: on the section tile (FR-019), in the issue list and its
section filter (FR-025), on the first page and on the page it affects (FR-027).
Its status cell stays empty.

Run from the dashboard dir:
    .venv/bin/python tests/test_open_issues.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "quality-requirements"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _issue(stem, status_line):
    pid = "-".join(stem.split("-")[:2])
    (_wiki / "issues" / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: issue\ntitle: Frage {pid}\n{status_line}created: 2026-11-12\n"
        f'updated: 2026-11-12\nsources: []\nrelated: ["[[QR-001-schnell]]"]\ntags: []\n'
        f"severity: minor\nkind: question\ncategory: content\n---\n\n# Frage {pid}\n", encoding="utf-8")


(_wiki / "quality-requirements" / "QR-001-schnell.md").write_text(
    "---\nid: QR-001\ntype: quality-requirement\ntitle: Schnell\nstatus: draft\nrelated: []\n---\n\n# Schnell\n",
    encoding="utf-8")
_issue("ISS-001-ohne-status", "")
_issue("ISS-002-draft", "status: draft\n")
_issue("ISS-003-erledigt", "status: resolved\n")
_issue("ISS-004-offen", "status: open\n")

import app  # noqa: E402

client = app.app.test_client()
OPEN = ["ISS-001", "ISS-002", "ISS-004"]


def _get(path):
    resp = client.get(path)
    assert resp.status_code == 200, path
    return resp.get_data(as_text=True)


def _ids(q):
    return re.findall(r'<tr class="issue-row" data-id="([^"]+)"', _get("/issues" + q))


def test_one_helper():
    for s in ("", None, "open", "in-progress", "draft", "bogus", "Open"):
        assert app.is_open_issue(s), s
    for s in ("resolved", "wontfix", "Resolved", " wontfix "):
        assert not app.is_open_issue(s), s


def test_section_tile_and_section_filter_agree():
    commons = _get("/commons")
    tile = commons[commons.index('id="tile-c1"'):commons.index('id="tile-c2"')]
    assert "3 open issues" in tile, tile
    assert _ids("?section=C1") == OPEN


def test_issue_list_counts_and_filters_them_as_open():
    body = _get("/issues")
    assert re.search(r'<strong class="issue-open-count">3</strong> open of 4', body)
    assert _ids("?status=open") == OPEN
    assert _ids("?status=closed") == ["ISS-003"]
    assert _ids("?status=draft") == ["ISS-001", "ISS-002", "ISS-003", "ISS-004"]   # not a lifecycle value: ignored


def test_page_panel_shows_them_as_open():
    body = _get("/page/quality-requirements/QR-001-schnell")
    sec = re.search(r'<section class="page-issues"[^>]*>(.*?)</section>', body, re.S).group(1)
    assert "No open issues" not in sec
    closed = re.findall(r'<li class="page-issue page-issue-closed">.*?<code>([A-Z]+-\d+)</code>', sec, re.S)
    assert closed == ["ISS-003"], closed


def test_first_page_counts_them():
    home = _get("/")
    m = re.search(r'<h2 class="valley-h"><a href="[^"]*">Open issues</a> <span class="count-pill">(\d+)</span>', home)
    assert m and m.group(1) == "3", m and m.group(1)


if __name__ == "__main__":
    test_one_helper()
    test_section_tile_and_section_filter_agree()
    test_issue_list_counts_and_filters_them_as_open()
    test_page_panel_shows_them_as_open()
    test_first_page_counts_them()
    print("OK: open issues")
