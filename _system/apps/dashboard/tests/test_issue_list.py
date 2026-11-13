"""The issue list: category, owner and filters (FR-025, FR-026, FR-028). No pytest.

Its own temporary vault. The filters run on the server, so the address carries
them and a copied link shows the same issues. Unknown filter values are ignored,
and an issue with unknown field values still lists, with an empty cell.

Run from the dashboard dir:
    .venv/bin/python tests/test_issue_list.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "stakeholders", "quality-requirements", "constraints"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _page(folder, stem, typ, title, status, extra="", related=""):
    pid = "-".join(stem.split("-")[:2])
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: {typ}\ntitle: {title}\nstatus: {status}\n"
        f"created: 2026-11-12\nupdated: 2026-11-12\nsources: []\nrelated: [{related}]\ntags: []\n"
        f"{extra}---\n\n# {title}\n", encoding="utf-8")


_page("stakeholders", "STK-001-produktverantwortliche", "stakeholder", "Produktverantwortliche", "draft")
_page("quality-requirements", "QR-001-schnell", "quality-requirement", "Schnell", "draft")
_page("constraints", "CON-001-klein", "constraint", "Klein", "draft")
_page("issues", "ISS-001-tempo", "issue", "Wie schnell genau", "open",
      'severity: major\nkind: question\ncategory: requirements\nowner: "[[STK-001-produktverantwortliche]]"\n',
      '"[[QR-001-schnell]]"')
_page("issues", "ISS-002-schleife", "issue", "Die Klärungsschleife", "in-progress",
      "severity: minor\nkind: gap\ncategory: systems42\nowner:\n", '"[[CON-001-klein]]"')
_page("issues", "ISS-003-erledigt", "issue", "Erledigte Frage", "resolved",
      "severity: minor\nkind: risk\ncategory: content\nowner: Gernot Starke\n", '"[[QR-001-schnell]]"')
_page("issues", "ISS-004-unklar", "issue", "Unklare Kategorie", "open",
      "severity: minor\nkind: ambiguity\ncategory: bogus\n")
_page("issues", "ISS-005-kaputt", "issue", "Kaputte Felder", "bogus",
      "severity: huge\nkind: question\n")
ALL = ["ISS-001", "ISS-002", "ISS-003", "ISS-004", "ISS-005"]

import app  # noqa: E402

client = app.app.test_client()


def _body(q=""):
    resp = client.get("/issues" + q)
    assert resp.status_code == 200, (q, resp.status_code)
    return resp.get_data(as_text=True)


def _ids(q=""):
    return re.findall(r'<tr class="issue-row" data-id="([^"]+)"', _body(q))


def _row(body, issue_id):
    return re.search(r'<tr class="issue-row" data-id="' + issue_id + r'".*?</tr>', body, re.S).group(0)


def _cell(row, cls):
    m = re.search(r'<td class="[^"]*\b' + cls + r'\b[^"]*"[^>]*>(.*?)</td>', row, re.S)
    assert m, (cls, row)
    return re.sub(r"<[^>]+>", "", m.group(1)).strip()


def test_category_and_owner_columns():
    body = _body()
    head = body[body.index("<thead"):body.index("</thead>")]
    for label in ("Category", "Owner", "Kind", "Severity", "Status"):
        assert re.search(r"<th\b[^>]*>" + label + "</th>", head), label
    assert _cell(_row(body, "ISS-001"), "c-category") == "requirements"
    assert _cell(_row(body, "ISS-002"), "c-owner") == "nobody yet"
    assert _cell(_row(body, "ISS-004"), "c-owner") == "nobody yet"     # no owner: key at all
    assert _cell(_row(body, "ISS-003"), "c-owner") == "Gernot Starke"
    # a stakeholder owner shows its title and links its page
    row = _row(body, "ISS-001")
    assert _cell(row, "c-owner") == "Produktverantwortliche"
    assert 'href="/page/stakeholders/STK-001-produktverantwortliche"' in row


def test_each_filter_alone():
    assert _ids("?category=systems42") == ["ISS-002"]
    assert _ids("?severity=major") == ["ISS-001"]
    assert _ids("?owner=none") == ["ISS-002", "ISS-004", "ISS-005"]
    assert _ids("?owner=Gernot+Starke") == ["ISS-003"]
    assert _ids("?owner=STK-001-produktverantwortliche") == ["ISS-001"]
    assert _ids("?status=open") == ["ISS-001", "ISS-002", "ISS-004"]     # open or in progress
    assert _ids("?status=in-progress") == ["ISS-002"]
    assert _ids("?status=closed") == ["ISS-003"]
    assert _ids("?status=all") == ALL


def test_filters_combine():
    assert _ids("?owner=none&severity=minor") == ["ISS-002", "ISS-004"]
    assert _ids("?category=content&status=open") == []


def test_section_filter_from_pr_13_keeps_working():
    # a section's open issue count opens the list with the open issues of that section
    assert _ids("?section=C1") == ["ISS-001"]
    assert _ids("?section=C1&status=all") == ["ISS-001", "ISS-003"]
    assert _ids("?section=C1&severity=minor&status=all") == ["ISS-003"]
    assert re.search(r'data-sections="[^"]*\bC1\b', _row(_body(), "ISS-001"))


def test_former_filter_parameter_still_opens_the_open_issues():
    assert _ids("?filter=open") == ["ISS-001", "ISS-002", "ISS-004"]


def test_open_count_counts_open_and_in_progress_only():
    body = _body()
    assert re.search(r'<strong class="issue-open-count">3</strong> open', body), body[:2000]
    assert re.search(r"of 5 in total", body)


def test_unknown_values_list_with_empty_cells():
    body = _body()
    assert _cell(_row(body, "ISS-004"), "c-category") == ""
    row = _row(body, "ISS-005")
    assert _cell(row, "c-severity") == "" and _cell(row, "c-istatus") == "" and _cell(row, "c-category") == ""


def test_bad_query_strings_show_the_unfiltered_list():
    for q in ("?section=XYZ", "?status=bogus", "?category=nope", "?severity=huge",
              "?owner=whoever", "?sort=nosuchcol", "?status=<b>"):
        assert _ids(q) == ALL, q


def test_rows_link_their_page_and_the_pane_is_gone():
    body = _body()
    for issue_id in ALL:
        row = _row(body, issue_id)
        links = re.findall(r'<a [^>]*href="(/page/issues/' + issue_id + r'-[^"]+)"', row)
        assert len(links) == 2, (issue_id, links)          # the ID and the title
    assert "issue-detail" not in body and "issue-store" not in body


def test_filter_controls_show_the_address():
    body = _body("?category=systems42&owner=none")
    assert re.search(r'<option value="systems42" selected>', body)
    assert re.search(r'<option value="none" selected>nobody yet</option>', body)
    form = re.search(r'<form class="issue-filters" method="get" action="/issues">(.*?)</form>', body, re.S)
    assert form, "no filter form"
    for name in ("status", "category", "severity", "section", "owner"):
        assert f'name="{name}"' in form.group(1), name
    # section names come from the catalog
    assert f'>{app.catalog.SECTION_BY_ID["C1"]["title"]}</option>' in form.group(1)


if __name__ == "__main__":
    test_category_and_owner_columns()
    test_each_filter_alone()
    test_filters_combine()
    test_section_filter_from_pr_13_keeps_working()
    test_former_filter_parameter_still_opens_the_open_issues()
    test_open_count_counts_open_and_in_progress_only()
    test_unknown_values_list_with_empty_cells()
    test_bad_query_strings_show_the_unfiltered_list()
    test_rows_link_their_page_and_the_pane_is_gone()
    test_filter_controls_show_the_address()
    print("OK: issue list")
