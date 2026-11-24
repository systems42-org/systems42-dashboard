"""The issue filters of the static demo, in a real browser (FR-058, issue 181). No pytest.

The demo is static files: no server filters its issue list. This test exports
a small wiki with site/build.py, serves the output folder with Python's plain
file server, opens it in headless Chromium and asserts that

  * changing a filter stays on the demo's issue list and shows the issues the
    dashboard's server gives for the same address, alone and combined;
  * a reload shows the same issues and filter values;
  * a chosen sort order survives a filter change and a reload;
  * a section's issue count on an area page opens that section's open issues;
  * filters that match nothing say so, and "Show all issues" lists all again;
  * the browser requests nothing outside /demo/, nothing is missing, and no
    page logs a JavaScript error.

The expected issues come from the Flask test client of the same wiki, so the
browser and the server are compared, not the browser and a list in this file.
tests/test_demo_issue_filters.py checks the export and the filter logic
without a browser.

It needs Playwright for Python and a Chromium for it, which the dashboard
itself does not: they live in requirements-dev.txt, not requirements.txt.

    .venv/bin/pip install -r requirements-dev.txt
    .venv/bin/python -m playwright install chromium

Without them the test prints SKIP and exits 77, which tests/run-all.sh counts
and names as skipped, not passed.

Run from the dashboard dir:
    .venv/bin/python tests/test_demo_issue_filters_browser.py
"""
import functools
import re
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("SKIP test_demo_issue_filters_browser: playwright not installed "
          "(pip install -r requirements-dev.txt)")
    sys.exit(77)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import demo_fixture  # noqa: E402

OUT, client = demo_fixture.build()
REQUESTS = []          # (path with query, status) of everything the browser asked for


class _Files(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_response(self, code, message=None):
        REQUESTS.append((self.path, code))
        super().send_response(code, message)


_server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(_Files, directory=str(OUT)))
threading.Thread(target=_server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{_server.server_port}"
LIST = "/demo/issues/"

_pw = sync_playwright().start()
try:
    _browser = _pw.chromium.launch()
except Exception as exc:  # playwright present, but its Chromium was never installed
    _pw.stop()
    print(f"SKIP test_demo_issue_filters_browser: no Chromium for Playwright "
          f"(python -m playwright install chromium): {str(exc).splitlines()[0]}")
    sys.exit(77)

ERRORS = []


def _open(path):
    page = _browser.new_page()
    page.on("console", lambda m: m.type == "error" and ERRORS.append(m.text))
    page.on("pageerror", lambda e: ERRORS.append(str(e)))
    resp = page.goto(BASE + path, wait_until="load")
    assert resp and resp.status == 200, f"{path} answered {resp and resp.status}"
    return page


def _server_ids(q=""):
    body = client.get("/issues" + ("?" + q if q else "")).get_data(as_text=True)
    return re.findall(r'<tr class="issue-row" data-id="([^"]+)"', body)


def _visible(page):
    """The IDs of the issue rows the reader sees, top to bottom."""
    return page.eval_on_selector_all(
        "#issues-table tbody tr", "rows => rows.filter(r => r.getClientRects().length).map(r => r.dataset.id)")


def _chosen(page):
    return page.eval_on_selector(
        ".issue-filters", "f => Object.fromEntries(['status','category','severity','section','owner']"
                          ".map(n => [n, f.elements[n].value]))")


def _choose(page, name, value):
    """Change one filter and wait for the list it opens."""
    with page.expect_navigation(wait_until="load"):
        page.select_option(f'.issue-filters select[name="{name}"]', value)
    url = urlsplit(page.url)
    assert url.path == LIST, f"the {name} filter left the demo's issue list: {page.url}"
    return url.query


def test_the_plain_list_shows_every_issue():
    page = _open(LIST)
    assert _visible(page) == _server_ids() and len(_server_ids()) == 7
    assert "These filters show" not in page.inner_text(".issue-counts")
    assert page.locator(".filter-note").count() == 0
    page.close()


def test_filters_work_alone_combined_and_after_a_reload():
    page = _open(LIST)
    steps = [("status", "open", "status=open"),
             ("severity", "minor", "status=open&severity=minor"),
             ("owner", "none", "status=open&severity=minor&owner=none"),
             ("status", "all", "severity=minor&owner=none"),
             ("owner", "Gernot Starke", "severity=minor&owner=Gernot+Starke"),
             ("severity", "", "owner=Gernot+Starke"),
             ("category", "method", "category=method&owner=Gernot+Starke"),
             ("owner", "", "category=method"),
             ("section", "C2", "status=all&category=method&section=C2"),
             ("status", "closed", "status=closed&category=method&section=C2"),
             ("category", "", "status=closed&section=C2"),
             ("status", "in-progress", "status=in-progress&section=C2")]
    for name, value, query in steps:
        assert _choose(page, name, value) == query, (name, value, urlsplit(page.url).query)
        want = _server_ids(query)
        assert 0 < len(want) < 7, (query, want)
        assert _visible(page) == want, (query, _visible(page), want)
        assert _chosen(page)[name] == value, (query, _chosen(page))
        assert f"These filters show {len(want)}." in page.inner_text(".issue-counts"), query
        page.reload(wait_until="load")
        assert urlsplit(page.url).query == query
        assert _visible(page) == want, ("after reload", query, _visible(page), want)
        assert _chosen(page)[name] == value, ("after reload", query, _chosen(page))
    page.close()


def test_the_sort_order_survives_a_filter_change_and_a_reload():
    page = _open(LIST + "?sort=id:desc")
    assert _visible(page) == _server_ids()[::-1]
    query = _choose(page, "status", "open")
    assert query == "status=open&sort=id:desc", query
    want = _server_ids("status=open")[::-1]
    assert len(want) > 1 and _visible(page) == want, (_visible(page), want)
    query = _choose(page, "severity", "minor")
    assert query == "status=open&severity=minor&sort=id:desc", query
    want = _server_ids("status=open&severity=minor")[::-1]
    assert len(want) > 1 and _visible(page) == want, (_visible(page), want)
    page.reload(wait_until="load")
    assert urlsplit(page.url).query == query and _visible(page) == want
    # a sort chosen on the page goes into the address and stays there as well
    page.click('#issues-table th[data-key="title"] .th-sort')
    assert urlsplit(page.url).query == "status=open&severity=minor&sort=title:asc", page.url
    by_title = _visible(page)
    assert sorted(by_title) == sorted(want) and by_title != want
    assert _choose(page, "severity", "") == "status=open&sort=title:asc"
    assert sorted(_visible(page)) == _server_ids("status=open")
    page.close()


def test_a_section_issue_count_opens_that_sections_open_issues():
    page = _open("/demo/commons/")
    link = page.locator('a.tile-flag-link[href$="issues/?section=C1"]')
    assert link.count() == 1, "no issue count for section C1 on the commons page"
    with page.expect_navigation(wait_until="load"):
        link.click()
    url = urlsplit(page.url)
    assert (url.path, url.query) == (LIST, "section=C1"), page.url
    want = _server_ids("section=C1")
    assert 0 < len(want) < len(_server_ids("section=C1&status=all"))
    assert _visible(page) == want, (_visible(page), want)
    assert _chosen(page) == {"status": "open", "category": "", "severity": "", "section": "C1", "owner": ""}
    assert "Showing the issues that point at pages of Quality Requirements." in page.inner_text(".filter-note")
    # every issue of the section, then every issue
    assert _choose(page, "status", "all") == "status=all&section=C1"
    assert _visible(page) == _server_ids("section=C1&status=all")
    with page.expect_navigation(wait_until="load"):
        page.click(".filter-note a")
    assert urlsplit(page.url).path == LIST and not urlsplit(page.url).query
    assert _visible(page) == _server_ids()
    page.close()


def test_the_home_page_opens_the_open_issues():
    page = _open("/demo/")
    with page.expect_navigation(wait_until="load"):
        page.locator('a[href$="issues/?status=open"]').first.click()
    assert _visible(page) == _server_ids("status=open")
    assert _chosen(page)["status"] == "open"
    page.close()


def test_filters_that_match_nothing_say_so():
    query = "status=open&category=content"
    assert _server_ids(query) == []
    page = _open(LIST + "?" + query)
    assert _visible(page) == []
    assert page.inner_text(".table-card .empty-hint") == "No issues match these filters."
    assert "These filters show 0." in page.inner_text(".issue-counts")
    page.close()


def test_unknown_values_show_every_issue():
    for query in ("status=bogus", "section=XYZ", "owner=whoever", "category=nope"):
        page = _open(LIST + "?" + query)
        assert _visible(page) == _server_ids(query) == _server_ids(), query
        page.close()


def test_z_nothing_was_asked_outside_the_demo_and_nothing_failed():
    assert len(REQUESTS) > 20
    outside = [r for r in REQUESTS if not r[0].startswith("/demo/")]
    assert not outside, outside
    missing = [r for r in REQUESTS if r[1] >= 400]
    assert not missing, missing
    assert not ERRORS, ERRORS


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    try:
        for fn in fns:
            try:
                fn()
            except AssertionError as exc:
                failed += 1
                print(f"FAIL {fn.__name__}: {exc}")
    finally:
        _browser.close()
        _pw.stop()
        _server.shutdown()
    if failed:
        sys.exit(1)
    print(f"ok — {len(fns)} checks in headless Chromium")
