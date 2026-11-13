"""The issue page shows its fields (FR-026, FR-028). No pytest.

Its own temporary vault. The header of an issue page names category, severity,
kind and owner, and "nobody yet" when no one owns it.

Run from the dashboard dir:
    .venv/bin/python tests/test_issue_page.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "stakeholders"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

HEAD = ("---\nid: {id}\ntype: {type}\ntitle: {title}\nstatus: {status}\ncreated: 2026-11-12\n"
        "updated: 2026-11-12\nsources: []\nrelated: []\ntags: []\n{extra}---\n\n# {title}\n")
(_wiki / "stakeholders" / "STK-001-team.md").write_text(
    HEAD.format(id="STK-001", type="stakeholder", title="Das Team", status="draft", extra=""), encoding="utf-8")
(_wiki / "issues" / "ISS-001-mit-owner.md").write_text(
    HEAD.format(id="ISS-001", type="issue", title="Mit Owner", status="open",
                extra='severity: major\nkind: question\ncategory: requirements\nowner: "[[STK-001-team]]"\n'),
    encoding="utf-8")
(_wiki / "issues" / "ISS-002-schleife.md").write_text(
    HEAD.format(id="ISS-002", type="issue", title="Die Klärungsschleife", status="in-progress",
                extra="severity: minor\nkind: gap\ncategory: systems42\nowner:\n"), encoding="utf-8")
(_wiki / "issues" / "ISS-003-kaputt.md").write_text(
    HEAD.format(id="ISS-003", type="issue", title="Kaputt", status="open",
                extra="severity: huge\nkind: question\ncategory: bogus\n"), encoding="utf-8")

# the template's unquoted form: YAML reads it as a nested list
(_wiki / "issues" / "ISS-004-alias.md").write_text(
    HEAD.format(id="ISS-004", type="issue", title="Mit Alias", status="open",
                extra="severity: minor\nkind: question\ncategory: content\nowner: [[STK-001-team|Die Ärzte]]\n"),
    encoding="utf-8")

import app  # noqa: E402

client = app.app.test_client()


def _fields(stem):
    resp = client.get(f"/page/issues/{stem}")
    assert resp.status_code == 200, stem
    body = resp.get_data(as_text=True)
    m = re.search(r'<dl class="issue-fields">(.*?)</dl>', body, re.S)
    assert m, "no issue fields in the header"
    # the fields sit in the header, above the body
    assert body.index('<dl class="issue-fields">') < body.index('<h1 class="page-h1">'), "fields below the title"
    pairs = re.findall(r"<dt>(.*?)</dt>\s*<dd>(.*?)</dd>", m.group(1), re.S)
    return {k: re.sub(r"<[^>]+>", "", v).strip() for k, v in pairs}, m.group(1)


def test_issue_page_shows_its_fields():
    fields, _ = _fields("ISS-002-schleife")
    assert fields == {"Category": "systems42", "Severity": "minor", "Kind": "gap", "Owner": "nobody yet"}, fields


def test_owner_links_its_stakeholder():
    fields, html = _fields("ISS-001-mit-owner")
    assert fields["Owner"] == "Das Team", fields
    assert 'href="/page/stakeholders/STK-001-team"' in html


def test_owner_in_the_unquoted_alias_form_links_its_stakeholder():
    fields, html = _fields("ISS-004-alias")
    assert fields["Owner"] == "Die Ärzte", fields
    assert 'href="/page/stakeholders/STK-001-team"' in html
    body = client.get("/issues").get_data(as_text=True)
    row = re.search(r'<tr class="issue-row" data-id="ISS-004".*?</tr>', body, re.S).group(0)
    assert re.search(r'<a class="wl" href="/page/stakeholders/STK-001-team">Die Ärzte</a>', row), row
    # one option per owner, named by the page's title, whatever alias an issue uses
    assert body.count('<option value="STK-001-team">') == 1 and "STK-001-team|" not in body
    assert '<option value="STK-001-team">Das Team</option>' in body
    ids = re.findall(r'<tr class="issue-row" data-id="([^"]+)"',
                     client.get("/issues?owner=STK-001-team").get_data(as_text=True))
    assert ids == ["ISS-001", "ISS-004"], ids


def test_unknown_values_show_empty():
    fields, _ = _fields("ISS-003-kaputt")
    assert fields["Category"] == "" and fields["Severity"] == "", fields


def test_other_pages_have_no_issue_fields():
    body = client.get("/page/stakeholders/STK-001-team").get_data(as_text=True)
    assert "issue-fields" not in body


if __name__ == "__main__":
    test_issue_page_shows_its_fields()
    test_owner_links_its_stakeholder()
    test_owner_in_the_unquoted_alias_form_links_its_stakeholder()
    test_unknown_values_show_empty()
    test_other_pages_have_no_issue_fields()
    print("OK: issue page")
