"""The issue filters of the exported static demo (FR-058, issue 181). No pytest.

The live dashboard filters issues on the server. The static demo has no
server: its one issue page holds every issue, and site/demo/issue-filters.js
filters in the browser from the address. This test exports a small wiki with
site/build.py and checks, without a browser, that

  * no script of an exported page navigates to a path outside the demo folder,
    and the site build's own check fails on one that does,
  * every issue row carries the values the filters need,
  * the links that open a filtered list stay under the demo folder and keep
    their filters,
  * the filter script picks the same issues as the server for the same address
    (run under node, skipped without it).

tests/test_demo_issue_filters_browser.py checks the same pages in a browser.

Run from the dashboard dir:
    .venv/bin/python tests/test_demo_issue_filters.py
"""
import html
import itertools
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlencode

sys.path.insert(0, str(Path(__file__).resolve().parent))
import demo_fixture  # noqa: E402

OUT, client = demo_fixture.build()
import build as site_build  # noqa: E402  (demo_fixture put site/ on the path)

HARNESS = Path(__file__).resolve().parent / "demo_issue_filters_harness.js"
ISSUES = (OUT / "demo" / "issues" / "index.html").read_text(encoding="utf-8")
ALL = ["ISS-001", "ISS-002", "ISS-003", "ISS-004", "ISS-005", "ISS-006", "ISS-007"]


def _server(q):
    """-> (ids, chosen filter values, the count line) as the server answers."""
    body = client.get("/issues" + ("?" + q if q else "")).get_data(as_text=True)
    ids = re.findall(r'<tr class="issue-row" data-id="([^"]+)"', body)
    chosen = {name: html.unescape(re.search(r'<option value="([^"]*)" selected', sel).group(1))
              for name, sel in re.findall(r'<select name="(\w+)">(.*?)</select>', body, re.S)}
    return ids, chosen, "These filters show" in body


def _rows():
    rows = []
    for tag in re.findall(r'<tr class="issue-row"[^>]*>', ISSUES):
        a = {k: html.unescape(v) for k, v in re.findall(r'data-([a-z]+)="([^"]*)"', tag)}
        rows.append(a)
    return rows


def _options():
    return {name: [html.unescape(v) for v in re.findall(r'<option value="([^"]*)"', sel)]
            for name, sel in re.findall(r'<select name="(\w+)">(.*?)</select>', ISSUES, re.S)}


def test_the_export_holds_every_issue():
    assert [r["id"] for r in _rows()] == ALL


def test_no_exported_page_navigates_outside_the_demo():
    for page in sorted((OUT / "demo").rglob("*.html")):
        text = page.read_text(encoding="utf-8")
        assert not site_build.root_navigation(text), (page, site_build.root_navigation(text))
    assert "location.assign('/" not in ISSUES
    site_build.verify_demo_filters(OUT)


def test_the_site_check_fails_on_a_filter_that_leaves_the_demo():
    for broken in (
        ISSUES.replace("location.assign(location.pathname", "location.assign('/issues'"),
        ISSUES.replace("demo-issue-filters.js", "gone.js"),
        ISSUES.replace(" data-owner=", " data-o="),
    ):
        assert broken != ISSUES
        tmp = Path(tempfile.mkdtemp())
        shutil.copytree(OUT / "demo", tmp / "demo")
        (tmp / "demo" / "issues" / "index.html").write_text(broken, encoding="utf-8")
        try:
            site_build.verify_demo_filters(tmp)
        except RuntimeError:
            continue
        raise AssertionError("verify_demo_filters accepted a broken issue page")


def test_every_row_carries_its_filter_values():
    rows = {r["id"]: r for r in _rows()}
    for r in rows.values():
        assert {"status", "open", "category", "severity", "sections", "owner"} <= set(r), r
    assert rows["ISS-001"] == {"id": "ISS-001", "status": "open", "open": "yes", "category": "requirements",
                               "severity": "major", "sections": "C1 C4",
                               "owner": "STK-001-produktverantwortliche"}
    assert rows["ISS-002"]["owner"] == "" and rows["ISS-002"]["status"] == "in-progress"
    assert rows["ISS-003"]["open"] == "no" and rows["ISS-003"]["owner"] == "Gernot Starke"
    # unknown values: the row lists with empty values, and counts as open
    assert rows["ISS-005"]["status"] == "" and rows["ISS-005"]["open"] == "yes"
    assert rows["ISS-005"]["severity"] == "" and rows["ISS-004"]["category"] == ""
    # "Resolved" is closed although the status list does not know the spelling
    assert rows["ISS-006"]["status"] == "" and rows["ISS-006"]["open"] == "no"


def test_the_export_loads_the_filter_script_from_the_demo_folder():
    assert '<script src="/demo/static/demo-issue-filters.js"></script>' in ISSUES
    assert (OUT / "demo" / "static" / "demo-issue-filters.js").is_file()
    assert '<form class="issue-filters" method="get" action="/demo/issues/">' in ISSUES


def test_links_to_a_filtered_list_stay_under_the_demo():
    found = set()
    for page in sorted((OUT / "demo").rglob("*.html")):
        for href in re.findall(r'href="([^"]*issues[^"]*\?[^"]*)"', page.read_text(encoding="utf-8")):
            assert href.startswith("/demo/issues/?"), (page, href)
            found.add(html.unescape(href))
    # the section counts of the area pages and the open count of the home page
    assert "/demo/issues/?status=open" in found, found
    for sid in ("C1", "C2", "C4"):
        assert f"/demo/issues/?section={sid}" in found, found


def test_the_script_filters_as_the_server_does():
    if not shutil.which("node"):
        print("skip: node not installed")
        return
    f = demo_fixture
    queries = [urlencode({k: v for k, v in zip(("status", "category", "severity", "section", "owner"), combo) if v})
               for combo in itertools.product(f.STATUSES, f.CATEGORIES, f.SEVERITIES, f.SECTIONS, f.OWNERS)]
    queries += ["filter=open", "status=bogus&filter=open", "status=closed&filter=open", "section=c1",
                "section=XYZ", "status=bogus", "category=nope", "severity=huge", "owner=whoever",
                "sort=severity:desc&status=open", "status=%20open%20", "section=c2&status=all&sort=id:desc",
                "owner=none&section=C3", "status=%3Cb%3E", "section=C6", "section=C1&status=bogus"]
    out = subprocess.run(["node", str(HARNESS)], capture_output=True, text=True, check=True,
                         input=json.dumps({"rows": [{**r, "sections": r["sections"].split()} for r in _rows()],
                                           "options": _options(), "queries": queries})).stdout
    answers = json.loads(out)
    assert len(answers) == len(queries) > 1000
    some_empty = some_partial = False
    for q, a in zip(queries, answers):
        ids, chosen, filtered = _server(q)
        assert a["ids"] == ids, (q, a["ids"], ids)
        assert a["chosen"] == chosen, (q, a["chosen"], chosen)
        assert a["filtered"] == filtered, (q, a["filtered"], filtered)
        some_empty = some_empty or not ids
        some_partial = some_partial or 0 < len(ids) < len(ALL)
    assert some_empty and some_partial


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
    print("all demo issue filter tests passed")
