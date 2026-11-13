"""Read a page with its links (FR-034). No pytest.

Its own temporary vault. "Links to" and "Linked from" list the related pages
by type, on every page, a functional requirement included. A linked issue
shows its status, and a resolved or wontfix one is marked closed the way the
issues panel (FR-027) marks it, by the one meaning of "open"
(`is_open_issue`).

Run from the dashboard dir:
    .venv/bin/python tests/test_read_a_page.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "stakeholders", "functional-requirements"):
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
        f"created: 2026-11-13\nupdated: 2026-11-13\nsources: []\nrelated: [{related}]\ntags: []\n"
        f"{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


_page("stakeholders", "STK-001-leserin", "stakeholder", "Leserin", "draft",
      body="Siehe [[ISS-003-verworfen]] und [[FR-001-suche]].")
_page("functional-requirements", "FR-001-suche", "functional-requirement", "Suche", "draft",
      "stereotype: feature\n")
_page("issues", "ISS-001-offen", "issue", "Offen", "open", "severity: major\n",
      body="Betrifft [[STK-001-leserin]] und [[FR-001-suche]].")
_page("issues", "ISS-002-erledigt", "issue", "Erledigt", "resolved", "severity: minor\n",
      '"[[STK-001-leserin]]"')
_page("issues", "ISS-003-verworfen", "issue", "Verworfen", "wontfix", "severity: minor\n")
_page("issues", "ISS-004-ohne-status", "issue", "Ohne Status", "", "severity: minor\n",
      '"[[STK-001-leserin]]"')

import app  # noqa: E402

client = app.app.test_client()


def _relations(path):
    resp = client.get(path)
    assert resp.status_code == 200, (path, resp.status_code)
    html = resp.get_data(as_text=True)
    m = re.search(r'<nav class="detail-relations"[^>]*>(.*?)</nav>', html, re.S)
    assert m, (path, "no relations")
    return m.group(1)


def _block(rel, heading):
    m = re.search(rf'<h2 class="rel-h">{heading}</h2>(.*?)</section>', rel, re.S)
    assert m, (heading, rel)
    return m.group(1)


def _item(block, pid):
    m = re.search(rf'<li[^>]*>(?:(?!</li>).)*<code>{pid}</code>.*?</li>', block, re.S)
    assert m, (pid, block)
    return m.group(0)


def test_a_linked_open_issue_shows_its_status():
    inbound = _block(_relations("/page/stakeholders/STK-001-leserin"), "Linked from")
    li = _item(inbound, "ISS-001")
    assert 'class="status status-open"' in li and ">open<" in li, li
    assert "rel-closed" not in li, li


def test_a_resolved_issue_is_marked_closed():
    inbound = _block(_relations("/page/stakeholders/STK-001-leserin"), "Linked from")
    li = _item(inbound, "ISS-002")
    assert "rel-closed" in li and ">resolved<" in li, li


def test_a_wontfix_issue_it_links_to_is_marked_closed():
    outbound = _block(_relations("/page/stakeholders/STK-001-leserin"), "Links to")
    li = _item(outbound, "ISS-003")
    assert "rel-closed" in li and ">wontfix<" in li, li


def test_an_issue_without_status_stays_open():
    li = _item(_block(_relations("/page/stakeholders/STK-001-leserin"), "Linked from"), "ISS-004")
    assert "rel-closed" not in li, li


def test_other_pages_carry_no_status_badge():
    li = _item(_block(_relations("/page/stakeholders/STK-001-leserin"), "Links to"), "FR-001")
    assert "status" not in li, li


def test_relations_mark_closed_exactly_where_the_issues_panel_does():
    with app.app.test_request_context("/"):
        rel = app.build_relations_panel("STK-001-leserin")
        panel = {i["id"]: i["is_open"] for i in app.open_issues_for("STK-001-leserin")}
    items = {it["id"]: it for g in rel["inbound"] + rel["outbound"] for it in g["links"]}
    for pid, is_open in panel.items():
        assert items[pid]["closed"] is (not is_open), (pid, items[pid])
    assert items["ISS-003"]["closed"] is True


def test_a_functional_requirement_page_has_links_to_and_linked_from():
    inbound = _block(_relations("/functional-requirements/FR-001-suche"), "Linked from")
    assert "<code>STK-001</code>" in inbound, inbound
    assert ">open<" in _item(inbound, "ISS-001")


if __name__ == "__main__":
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"ok   {name}")
        except Exception as e:  # noqa: BLE001  a KeyError is a failure too
            failed += 1
            print(f"FAIL {name}: {type(e).__name__} {str(e)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
