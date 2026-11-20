"""mermaid really draws the diagrams, in a real browser — no pytest.

Every other diagram test checks the mermaid *source* the dashboard emits. None
of them notices when the vendored static/vendor/mermaid.min.js stops turning
that source into a picture: a broken or incompatible bundle, an API change in a
new mermaid version, a loader bug in templates/_mermaid.html. This test starts
the dashboard on a throwaway vault, opens the pages in headless Chromium, and
asserts that

  * the projected context diagram on /req42/scope becomes an SVG that carries
    the neighbours' labels and an edge label;
  * a fenced ```mermaid block in a page body becomes an SVG too;
  * the theme switch's re-render (window.ETSU_RERENDER_MERMAID) still
    produces the diagram, now in the other palette;
  * none of these pages logs a JavaScript error;
  * the bundle's version is the one static/vendor/README.md names, so an update
    that forgets the README (or the other way round) fails here.

It needs Playwright for Python and a Chromium for it, which the dashboard
itself does not: they live in requirements-dev.txt, not requirements.txt.

    .venv/bin/pip install -r requirements-dev.txt
    .venv/bin/python -m playwright install chromium

Without them the test prints SKIP and exits 77, which tests/run-all.sh counts
and names as skipped, not passed.

Run from the dashboard dir:
    .venv/bin/python tests/test_mermaid_browser.py
"""
import os
import re
import sys
import tempfile
import threading
from pathlib import Path

try:
    from playwright.sync_api import TimeoutError as PlaywrightTimeout
    from playwright.sync_api import sync_playwright
except ImportError:
    print("SKIP test_mermaid_browser: playwright not installed "
          "(pip install -r requirements-dev.txt)")
    sys.exit(77)

HERE = Path(__file__).resolve().parent.parent
WIKI_FOLDERS = [
    "domain-terms", "glossary", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "use-cases", "functional-requirements",
    "quality-requirements", "constraints", "decisions", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
(_tmp / "wiki.yaml").write_text("system_name: System X\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(HERE))  # import app.py

import app  # noqa: E402
from werkzeug.serving import WSGIRequestHandler, make_server  # noqa: E402


def _page(folder, name, front, body):
    lines = ["---", *front, "sources: []", "related: []",
             "created: 2026-11-02", "updated: 2026-11-02", "---", "", body]
    (_wiki / folder / f"{name}.md").write_text("\n".join(lines), encoding="utf-8")


# Two neighbours: one both ways (draws `<-->` with one label), one one-way.
_page("external-interfaces", "EIF-001-artists", [
    "id: EIF-001", "type: external-interface", "title: Artists", "status: draft",
    "tags: [external-interface]", "partner: Artists", "tier: supply", "flows:",
    "  - { data: artwork submissions, direction: inbound, label: artwork }",
    "  - { data: commission statements, direction: outbound, label: sales }",
], "# Artists\n")
_page("external-interfaces", "EIF-002-regulator", [
    "id: EIF-002", "type: external-interface", "title: Regulator", "status: draft",
    "tags: [external-interface]", "partner: Tax authorities", "tier: core-operations",
    "flows:",
    "  - { data: tax filings, direction: outbound, label: filings }",
], "# Regulator\n")
# A page body with a fenced mermaid block, the other way a diagram reaches the page.
_page("decisions", "DR-001-fenced-diagram", [
    "id: DR-001", "type: decision-record", "title: Fenced diagram", "status: draft",
    "tags: [decision-record]", "kind: architecture",
], "# Fenced diagram\n\n```mermaid\nflowchart LR\n  Alpha --> Bravo\n```\n")

_page("domain-terms", "DT-001-order", [
    "id: DT-001", "type: domain-term", "title: Order", "stereotype: entity",
    'attributes: [{name: "order date"}, {name: "cost {net}"}]',
], "# Order\n")


class _Quiet(WSGIRequestHandler):
    def log_request(self, *args, **kwargs):  # one line per asset buries the result
        pass


_server = make_server("127.0.0.1", 0, app.app, threaded=True, request_handler=_Quiet)
threading.Thread(target=_server.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{_server.server_port}"

_pw = sync_playwright().start()
try:
    _browser = _pw.chromium.launch()
except Exception as exc:  # playwright present, but its Chromium was never installed
    _pw.stop()
    print(f"SKIP test_mermaid_browser: no Chromium for Playwright "
          f"(python -m playwright install chromium): {str(exc).splitlines()[0]}")
    sys.exit(77)


def _open(path):
    """Load a page, wait for every mermaid node to hold an SVG, and return the
    page with the JavaScript errors it logged on the way."""
    page = _browser.new_page()
    errors = []
    page.on("console", lambda m: m.type == "error" and errors.append(m.text))
    page.on("pageerror", lambda e: errors.append(str(e)))
    resp = page.goto(BASE + path, wait_until="load")
    assert resp and resp.status == 200, f"{path} answered {resp and resp.status}"
    assert page.locator("pre.mermaid").count() > 0, \
        f"{path} has no mermaid node — did the loader or the projection go missing?"
    try:
        page.wait_for_function(
            "() => [...document.querySelectorAll('pre.mermaid')]"
            ".every(n => n.querySelector('svg'))", timeout=15000)
    except PlaywrightTimeout:
        page.close()
        raise AssertionError(f"{path}: mermaid drew no SVG within 15 s; "
                             f"JavaScript errors: {errors or 'none'}") from None
    return page, errors


def _svg_text(page):
    return " ".join(page.locator("pre.mermaid svg").all_text_contents())


def test_context_diagram_renders_with_its_labels():
    page, errors = _open("/req42/scope")
    text = _svg_text(page)
    for label in ("System X", "Artists", "Regulator", "artwork · sales", "filings"):
        assert label in text, f"{label!r} missing from the drawn context diagram: {text!r}"
    assert not errors, f"JavaScript errors on /req42/scope: {errors}"
    page.close()


def test_fenced_block_in_a_page_body_renders():
    page, errors = _open("/page/decisions/DR-001-fenced-diagram")
    text = _svg_text(page)
    assert "Alpha" in text and "Bravo" in text, f"fenced diagram not drawn: {text!r}"
    assert not errors, f"JavaScript errors on the decision page: {errors}"
    page.close()


def test_entity_diagram_preserves_attribute_labels():
    page, errors = _open("/entity-diagram")
    text = _svg_text(page)
    assert "order date" in text and "cost {net}" in text, text
    assert not errors, errors
    page.close()


def test_theme_switch_rerenders_the_diagram():
    page, errors = _open("/req42/scope")
    page.evaluate("document.documentElement.setAttribute('data-theme', 'light')")
    page.evaluate("window.ETSU_RERENDER_MERMAID('light')")
    light = page.locator("pre.mermaid svg").first.inner_html()
    page.evaluate("window.ETSU_RERENDER_MERMAID('dark')")
    page.wait_for_function(
        "() => [...document.querySelectorAll('pre.mermaid')]"
        ".every(n => n.querySelector('svg'))", timeout=15000)
    dark = page.locator("pre.mermaid svg").first.inner_html()
    assert "Artists" in dark, "re-render under the dark theme lost the diagram"
    assert light != dark, "the dark re-render produced the light palette's SVG"
    assert not errors, f"JavaScript errors while re-rendering: {errors}"
    page.close()


def test_bundle_version_matches_vendor_readme():
    readme = (HERE / "static" / "vendor" / "README.md").read_text(encoding="utf-8")
    m = re.search(r"## mermaid\.min\.js.*?\*\*Version:\*\*\s*([0-9.]+)", readme, re.S)
    assert m, "static/vendor/README.md names no mermaid version"
    page, _ = _open("/req42/scope")
    # mermaid's own `info` diagram draws "v<version>" of the loaded bundle
    svg = page.evaluate("async () => (await mermaid.render('ver', 'info')).svg")
    assert f"v{m.group(1)}" in svg, \
        f"vendored bundle is not mermaid {m.group(1)} as the README says"
    page.close()


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
