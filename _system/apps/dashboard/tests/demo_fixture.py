"""A small wiki exported as a static demo, for the demo tests. Not a test.

`build()` writes a throwaway repository with seven issues, exports it with
`export_demo` of site/build.py and returns the output folder and the Flask
test client of the same dashboard. The tests compare what the static pages
show with what that client answers for the same address.

It imports `app` through `export_demo`, so a script calls it once.
"""
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
REPO = HERE.parents[2]

STATUSES = ["", "all", "open", "closed", "in-progress", "resolved", "wontfix"]
CATEGORIES = ["", "requirements", "method", "content"]
SEVERITIES = ["", "major", "minor"]
SECTIONS = ["", "C1", "C2", "C4"]
OWNERS = ["", "none", "Gernot Starke", "STK-001-produktverantwortliche"]


def _page(wiki, folder, stem, typ, title, status, extra="", related=""):
    pid = "-".join(stem.split("-")[:2])
    (wiki / folder).mkdir(parents=True, exist_ok=True)
    (wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: {typ}\ntitle: {title}\nstatus: {status}\n"
        f"created: 2026-11-12\nupdated: 2026-11-12\nsources: []\nrelated: [{related}]\ntags: []\n"
        f"{extra}---\n\n# {title}\n", encoding="utf-8")


def build():
    """-> (site output folder, Flask test client)."""
    tmp = Path(tempfile.mkdtemp())
    wiki = tmp / "wiki"
    (tmp / "_system").mkdir()
    (tmp / "_system" / "wiki.yaml").write_text("system_name: Filter fixture\n", encoding="utf-8")
    # the method comes from this repository, the pages are the fixture's own
    os.environ["METAMODEL_DIR"] = str(REPO / "_system" / "metamodel")
    os.environ["DASH_STARTUP_GRACE"] = "3600"
    os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

    _page(wiki, "stakeholders", "STK-001-produktverantwortliche", "stakeholder", "Produktverantwortliche", "draft")
    _page(wiki, "quality-requirements", "QR-001-schnell", "quality-requirement", "Schnell", "draft")
    _page(wiki, "constraints", "CON-001-klein", "constraint", "Klein", "draft")
    _page(wiki, "issues", "ISS-001-tempo", "issue", "Wie schnell genau", "open",
          'severity: major\nkind: question\ncategory: requirements\nowner: "[[STK-001-produktverantwortliche]]"\n',
          '"[[QR-001-schnell]]"')
    _page(wiki, "issues", "ISS-002-schleife", "issue", "Die Klärungsschleife", "in-progress",
          "severity: minor\nkind: gap\ncategory: method\nowner:\n", '"[[CON-001-klein]]"')
    _page(wiki, "issues", "ISS-003-erledigt", "issue", "Erledigte Frage", "resolved",
          "severity: minor\nkind: risk\ncategory: content\nowner: Gernot Starke\n", '"[[QR-001-schnell]]"')
    _page(wiki, "issues", "ISS-004-unklar", "issue", "Unklare Kategorie", "open",
          "severity: minor\nkind: ambiguity\ncategory: bogus\n")
    _page(wiki, "issues", "ISS-005-kaputt", "issue", "Kaputte Felder", "bogus",
          "severity: huge\nkind: question\n")
    # closed for the dashboard, but written in a way the status list does not know
    _page(wiki, "issues", "ISS-006-gross", "issue", "Anders geschrieben", "Resolved",
          "severity: major\nkind: gap\ncategory: method\nowner: Gernot Starke\n", '"[[CON-001-klein]]"')
    _page(wiki, "issues", "ISS-007-abgelehnt", "issue", "Abgelehnt", "wontfix",
          'severity: major\nkind: risk\ncategory: requirements\nowner: "[[STK-001-produktverantwortliche]]"\n',
          '"[[QR-001-schnell]]", "[[CON-001-klein]]"')

    sys.path.insert(0, str(REPO / "site"))
    import build as site_build

    out = tmp / "_site"
    site_build.export_demo(REPO, tmp, out)
    import app

    return out, app.app.test_client()
