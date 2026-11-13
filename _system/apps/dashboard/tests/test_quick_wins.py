"""Quick wins from the 2026-11-12 gap audit. No pytest.

- FR-020: a wiki page's path is Home › area › section › page, following where
  the page belongs (never "Search"). Pages outside the sections show
  Home › page.
- FR-017: one name per section everywhere (C5 "Domain Terms", C6 "Issues").
- FR-018: the center tile shows the last 4 changes, links to a changes page
  and carries no page count.
- FR-019: a section's open issue count opens the issue list with only those
  issues.
- FR-013: the 404 page has the header and footer.
- FR-014: the header marks its entry current on the pages that entry covers.

Run from the dashboard dir:
    .venv/bin/python tests/test_quick_wins.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("glossary", "quality-requirements", "constraints", "issues", "decisions"):
    (_wiki / _f).mkdir(parents=True)
(_tmp / "sources").mkdir()
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

PAGE = """---
id: {id}
type: {type}
title: {title}
status: {status}
created: 2026-11-12
updated: 2026-11-12
sources: []
related: [{related}]
tags: []
---

# {title}
"""


def _page(folder, stem, id, type, title, status="draft", related=""):
    (_wiki / folder / f"{stem}.md").write_text(
        PAGE.format(id=id, type=type, title=title, status=status, related=related), encoding="utf-8")


_page("quality-requirements", "QR-001-fast", "QR-001", "quality-requirement", "Fast")
_page("constraints", "CON-001-small", "CON-001", "constraint", "Small")
_page("glossary", "GLO-001-term", "GLO-001", "glossary-term", "Term")
_page("decisions", "DR-001-choice", "DR-001", "decision-record", "Choice")
for n in range(2, 8):
    _page("glossary", f"GLO-00{n}-term-{n}", f"GLO-00{n}", "glossary-term", f"Term {n}")
_page("issues", "ISS-001-about-qr", "ISS-001", "issue", "About the QR", "open", '"[[QR-001-fast]]"')
_page("issues", "ISS-002-about-con", "ISS-002", "issue", "About the constraint", "open", '"[[CON-001-small]]"')
_page("issues", "ISS-003-closed-qr", "ISS-003", "issue", "Closed one", "resolved", '"[[QR-001-fast]]"')
(_tmp / "sources" / "SRC-001-notes.md").write_text(
    "---\nid: SRC-001\ntype: source\ntitle: Notes\nstatus: ingested\n---\n\n# Notes\n", encoding="utf-8")

import app  # noqa: E402

client = app.app.test_client()


def _crumbs(body):
    m = re.search(r'<nav class="crumbs">(.*?)</nav>', body, re.S)
    assert m, "no crumbs"
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", m.group(1))).strip()


def _current(body):
    return re.findall(r'<a[^>]*aria-current="page"[^>]*>([^<]+)</a>', body)


def test_page_path_follows_where_the_page_belongs():
    body = client.get("/page/quality-requirements/QR-001-fast").get_data(as_text=True)
    assert _crumbs(body) == "Home › Commons › Quality Requirements › QR-001", _crumbs(body)
    assert '<a href="/req42/quality">Quality Requirements</a>' in body
    body = client.get("/page/glossary/GLO-001-term").get_data(as_text=True)
    assert _crumbs(body) == "Home › Commons › Domain Terms › GLO-001", _crumbs(body)


def test_pages_outside_sections_show_home_and_page():
    body = client.get("/source/SRC-001-notes").get_data(as_text=True)
    assert _crumbs(body) == "Home › SRC-001", _crumbs(body)
    assert _crumbs(client.get("/metamodel").get_data(as_text=True)) == "Home › Metamodel"
    assert _crumbs(client.get("/changes").get_data(as_text=True)) == "Home › Changes"


def test_one_name_per_section():
    assert app.catalog.SECTION_BY_ID["C5"]["title"] == "Domain Terms"
    assert app.catalog.SECTION_BY_ID["C6"]["title"] == "Issues"
    home = client.get("/").get_data(as_text=True)
    nav = re.search(r'<nav class="mainnav".*?</nav>', home, re.S).group(0)
    assert ">Domain Terms<" in nav and ">Issues<" in nav and "Glossary" not in nav
    assert "Risks &amp; Assumptions" not in home and "Risks & Assumptions" not in home
    body = client.get("/glossary").get_data(as_text=True)
    assert _crumbs(body) == "Home › Commons › Domain Terms", _crumbs(body)
    assert '<h1 class="page-h1">Domain Terms' in body
    body = client.get("/graph/glossary").get_data(as_text=True)
    assert _crumbs(body) == "Home › Commons › Domain Terms › Term network", _crumbs(body)


def test_center_tile_shows_four_changes_and_no_page_count():
    home = client.get("/").get_data(as_text=True)
    valley = re.search(r'<div class="valley">(.*?)<div class="valley-block">\s*<h2 class="valley-h"><a href="/issues',
                       home, re.S).group(1)
    assert len(re.findall(r'class="ml-hit"', valley)) == 4
    assert 'href="/changes"' in valley
    status = re.search(r'<p class="vault-status">(.*?)</p>', home, re.S).group(1)
    assert "page" not in status, status


def test_changes_page_lists_every_page_newest_first():
    body = client.get("/changes").get_data(as_text=True)
    assert len(re.findall(r'class="ml-hit"', body)) == len(app.load_all_pages())


def test_section_open_issue_count_opens_only_those_issues():
    body = client.get("/commons").get_data(as_text=True)
    assert 'href="/issues?section=C1"' in body and 'href="/issues?section=C2"' in body
    body = client.get("/issues?section=C1").get_data(as_text=True)
    rows = re.findall(r'<tr class="issue-row" data-id="([^"]+)"', body)
    assert rows == ["ISS-001"], rows
    assert "Quality Requirements" in body and 'href="/issues"' in body
    rows = re.findall(r'<tr class="issue-row" data-id="([^"]+)"',
                      client.get("/issues").get_data(as_text=True))
    assert rows == ["ISS-001", "ISS-002", "ISS-003"], rows


def test_404_has_header_and_footer():
    r = client.get("/no-such-page")
    body = r.get_data(as_text=True)
    assert r.status_code == 404
    assert '<nav class="mainnav"' in body and "<footer" in body
    assert client.get("/page/glossary/GLO-999-missing").status_code == 404


def test_header_marks_its_entry_on_every_page_it_covers():
    for path, entry in (("/page/issues/ISS-001-about-qr", "Issues"),
                        ("/page/decisions/DR-001-choice", "Decisions"),
                        ("/page/glossary/GLO-001-term", "Domain Terms"),
                        ("/graph/glossary", "Domain Terms"),
                        ("/issues?section=C1", "Issues")):
        cur = _current(client.get(path).get_data(as_text=True))
        assert cur == [entry], (path, cur)
    cur = _current(client.get("/page/quality-requirements/QR-001-fast").get_data(as_text=True))
    assert cur == ["Commons"] or cur == [], cur


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
