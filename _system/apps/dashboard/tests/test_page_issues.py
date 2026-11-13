"""Issues on the page they affect (FR-027). No pytest.

Its own temporary vault. Every page lists the issues that link to it, open
ones first and then by severity, each with status and severity and a link to
the issue. A page without an open issue says so.

Run from the dashboard dir:
    .venv/bin/python tests/test_page_issues.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "stakeholders", "functional-requirements", "quality-requirements"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _page(folder, stem, typ, title, status, extra="", related="", body=""):
    pid = "-".join(stem.split("-")[:2])
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: {typ}\ntitle: {title}\nstatus: {status}\n"
        f"created: 2026-11-12\nupdated: 2026-11-12\nsources: []\nrelated: [{related}]\ntags: []\n"
        f"{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


_page("stakeholders", "STK-001-aerztin", "stakeholder", "Ärztin", "draft")
_page("functional-requirements", "FR-001-suche", "functional-requirement", "Suche", "draft", "stereotype: feature\n")
_page("quality-requirements", "QR-001-ruhig", "quality-requirement", "Ruhig", "draft")
_page("issues", "ISS-001-im-text", "issue", "Im Text verlinkt", "open",
      "severity: major\nkind: question\n", body="Betrifft [[STK-001-aerztin]].")
_page("issues", "ISS-002-erledigt", "issue", "Erledigt", "resolved",
      "severity: blocker\nkind: gap\n", '"[[STK-001-aerztin]]"')
_page("issues", "ISS-003-nur-related", "issue", "Nur in related", "open",
      "severity: minor\nkind: gap\n", '"[[FR-001-suche]]"')
_page("issues", "ISS-004-blocker", "issue", "Der Blocker", "in-progress",
      "severity: blocker\nkind: risk\n", '"[[STK-001-aerztin]]"')
_page("issues", "ISS-005-erwaehnt", "issue", "Nur erwähnt", "open",
      "severity: blocker\nkind: risk\n", body="Erwähnt QR-001 ohne Link.")

import app  # noqa: E402

client = app.app.test_client()


def _section(path):
    resp = client.get(path)
    assert resp.status_code == 200, path
    body = resp.get_data(as_text=True)
    m = re.search(r'<section class="page-issues"[^>]*>(.*?)</section>', body, re.S)
    assert m, (path, "no page-issues section")
    return m.group(1)


def _listed(section):
    return re.findall(r'<li class="page-issue[^"]*">.*?<code>([A-Z]+-\d+)</code>', section, re.S)


def test_open_issues_for_orders_open_first_then_severity():
    got = app.open_issues_for("STK-001-aerztin")
    assert [i["id"] for i in got] == ["ISS-004", "ISS-001", "ISS-002"], got
    assert set(got[0]) >= {"id", "title", "status", "severity", "url"}, got[0]
    assert got[0]["url"] == "/page/issues/ISS-004-blocker"
    assert app.open_issues_for("QR-001-ruhig") == []


def test_stakeholder_page_lists_its_issues_with_status_and_severity():
    sec = _section("/page/stakeholders/STK-001-aerztin")
    assert _listed(sec) == ["ISS-004", "ISS-001", "ISS-002"], sec
    item = re.search(r'<li class="page-issue[^"]*">.*?ISS-004.*?</li>', sec, re.S).group(0)
    assert 'href="/page/issues/ISS-004-blocker"' in item
    assert ">in-progress<" in item and ">blocker<" in item
    assert "No open issues" not in sec


def test_fr_page_linked_only_from_related_shows_it():
    sec = _section("/functional-requirements/FR-001-suche")
    assert _listed(sec) == ["ISS-003"], sec


def test_page_without_issues_says_so():
    sec = _section("/page/quality-requirements/QR-001-ruhig")
    assert "No open issues" in sec
    assert _listed(sec) == []          # a mention without a link does not count


def test_closed_only_says_no_open_and_still_lists_it():
    (_wiki / "issues" / "ISS-001-im-text.md").unlink()
    (_wiki / "issues" / "ISS-004-blocker.md").unlink()
    app._PARSE_CACHE.clear()
    sec = _section("/page/stakeholders/STK-001-aerztin")
    assert "No open issues" in sec and _listed(sec) == ["ISS-002"], sec


if __name__ == "__main__":
    test_open_issues_for_orders_open_first_then_severity()
    test_stakeholder_page_lists_its_issues_with_status_and_severity()
    test_fr_page_linked_only_from_related_shows_it()
    test_page_without_issues_says_so()
    test_closed_only_says_no_open_and_still_lists_it()
    print("OK: page issues")
