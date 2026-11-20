"""Every page fits a 320 px phone screen (QR-001), in a real browser. No pytest.

QR-001 asks that no page scrolls sideways at 320 CSS pixels, that text is
readable without zooming and that links and buttons are big enough to hit by
touch. This test starts the dashboard on two fixture vaults, opens every page
in headless Chromium emulating a 320 x 640 phone, and asserts that

  * the page is no wider than the screen (`scrollWidth <= 320`). A wide table
    scrolls inside its own box, a diagram first shows whole.
  * the main nav does not scroll sideways, and after one tap on the menu
    button every nav entry is visible.
  * breadcrumbs, footer links, sort headers, tile links, nav and menu entries
    are at least 24 x 24 px (WCAG 2.2, 2.5.8).
  * no visible text outside a diagram is smaller than 12 px.

The vaults are tests/fixtures/arc42-views/wiki and tests/fixtures/wiki. The
second gets a decision with a wide table and a diagram, and a context with
neighbours.
Each runs in its own server process, because app.py reads WIKI_DIR once, at
import.

It needs Playwright for Python and a Chromium for it, which the dashboard
itself does not: they live in requirements-dev.txt, not requirements.txt.

    .venv/bin/pip install -r requirements-dev.txt
    .venv/bin/python -m playwright install chromium

Without them the test prints SKIP and exits 0, so the plain test loop in the
README keeps working. Read its output: a SKIP is not a pass.

Run from the dashboard dir:
    .venv/bin/python tests/test_mobile_layout.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from playwright.sync_api import TimeoutError as PlaywrightTimeout
    from playwright.sync_api import sync_playwright
except ImportError:
    print("SKIP test_mobile_layout: playwright not installed "
          "(pip install -r requirements-dev.txt)")
    sys.exit(77)

HERE = Path(__file__).resolve().parent.parent
FIXTURES = HERE / "tests" / "fixtures"
WIDTH, HEIGHT = 320, 640

# Targets outside running text that QR-001 names, plus the header controls.
TARGETS = (".crumbs a, .foot a, .th-sort, .tile-link, .tile-stretch, .tile-cta, .tile-flag-link, "
           "a.area-section-link, .ml-hit, .mainnav a, .menu-btn, .menu-item, .diagram-links summary, "
           ".diagram-links a")

_tmp = Path(tempfile.mkdtemp())


def _page(wiki, folder, name, front, body):
    (wiki / folder).mkdir(parents=True, exist_ok=True)
    lines = ["---", *front, "sources: []", "related: []",
             "created: 2026-11-19", "updated: 2026-11-19", "---", "", body]
    (wiki / folder / f"{name}.md").write_text("\n".join(lines), encoding="utf-8")


def _library_vault() -> Path:
    """tests/fixtures/wiki plus the content that is wide on a phone."""
    wiki = _tmp / "library" / "wiki"
    shutil.copytree(FIXTURES / "wiki", wiki)
    cols = " | ".join(f"Column {i} with a long heading" for i in range(1, 7))
    row = " | ".join("a cell that does not fit" for _ in range(6))
    _page(wiki, "decisions", "DR-002-wide-table", [
        "id: DR-002", "type: decision-record", "title: Wide table", "status: draft",
        "tags: [decision-record]", "kind: architecture",
    ], f"# Wide table\n\n| {cols} |\n|{'---|' * 6}\n| {row} |\n\n"
       "```mermaid\nflowchart LR\n  Alpha --> Bravo --> Charlie --> Delta --> Echo --> Foxtrot\n```\n")
    _page(wiki, "external-interfaces", "EIF-001-union-catalogue", [
        "id: EIF-001", "type: external-interface", "title: Union catalogue", "status: draft",
        "tags: [external-interface]", "partner: Regional union catalogue", "tier: supply",
        "flows:", "  - { data: book records, direction: inbound, label: records }",
    ], "# Union catalogue\n")
    stk = (wiki / "stakeholders" / "STK-002-reader.md").read_text(encoding="utf-8")
    stk = stk.replace("provides: []", "provides: [loan requests]")
    (wiki / "stakeholders" / "STK-002-reader.md").write_text(stk, encoding="utf-8")
    (_tmp / "library" / "wiki.yaml").write_text("system_name: Library\n", encoding="utf-8")
    return wiki


# The server process: imports app on its vault, prints one JSON line with its
# port and the pages to open, then serves until it is killed.
_SERVER = """
import json, sys
sys.path.insert(0, sys.argv[1])
import app
# a shutdown (FR-050) must end this server only, never signal the test that started it
app.app.config["DEV_SERVER"] = True
from werkzeug.serving import WSGIRequestHandler, make_server

class Quiet(WSGIRequestHandler):
    def log_request(self, *a, **k):
        pass

# /brand/intro.html is a fragment for a frame on the home page, not a page
paths = sorted(r.rule for r in app.app.url_map.iter_rules()
               if not r.arguments and "GET" in r.methods and not r.rule.startswith("/static")
               and r.rule != "/brand/intro.html")
paths += sorted(s["href"] for s in app.catalog.SECTION_BY_SLUG.values()
               if s["href"] and s["href"].startswith("/req42/"))
for d in sorted(app.WIKI_DIR.iterdir()):
    pages = sorted(app.load_folder(d.name), key=lambda p: p.stem) if d.is_dir() else []
    paths += [app._page_url(d.name, p.stem) for p in pages[:2]]
srv = make_server("127.0.0.1", 0, app.app, threaded=True, request_handler=Quiet)
print(json.dumps({"port": srv.server_port, "paths": paths}), flush=True)
srv.serve_forever()
"""


def _serve(wiki: Path, config: Path | None):
    # closing a page sends /leaving: without a long leave grace the dashboard
    # stops itself between two pages on a slow machine (FR-050)
    env = dict(os.environ, WIKI_DIR=str(wiki), DASH_STARTUP_GRACE="3600",
               DASH_HEARTBEAT_GRACE="3600", DASH_LEAVE_GRACE="3600")
    if config:
        env["WIKI_CONFIG"] = str(config)
    proc = subprocess.Popen([sys.executable, "-c", _SERVER, str(HERE)], env=env,
                            stdout=subprocess.PIPE, text=True, cwd=str(_tmp))
    line = proc.stdout.readline()
    if not line:
        proc.kill()
        raise RuntimeError(f"the dashboard did not start on {wiki}")
    info = json.loads(line)
    return proc, f"http://127.0.0.1:{info['port']}", info["paths"]


_procs = []
VAULTS = []
for _wiki, _cfg in ((_library_vault(), _tmp / "library" / "wiki.yaml"),
                    (FIXTURES / "arc42-views" / "wiki", None)):
    _proc, _base, _paths = _serve(_wiki, _cfg)
    _procs.append(_proc)
    VAULTS.append((_wiki.parent.name if _cfg else "arc42-views", _base, _paths))

_pw = sync_playwright().start()
try:
    _browser = _pw.chromium.launch()
except Exception as exc:  # playwright present, but its Chromium was never installed
    _pw.stop()
    for _p in _procs:
        _p.kill()
    print(f"SKIP test_mobile_layout: no Chromium for Playwright "
          f"(python -m playwright install chromium): {str(exc).splitlines()[0]}")
    sys.exit(77)
_phone = _browser.new_context(viewport={"width": WIDTH, "height": HEIGHT},
                              device_scale_factor=2, is_mobile=True, has_touch=True)

_SMALL_TEXT_JS = """() => {
  const out = [];
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walk.nextNode(); n; n = walk.nextNode()) {
    const el = n.parentElement;
    if (!n.textContent.trim() || !el || el.closest("svg, canvas, script, style, pre.mermaid")) continue;
    const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
    if (r.width <= 1 || r.height <= 1 || cs.visibility === "hidden") continue;
    const px = parseFloat(cs.fontSize);
    if (px < 11.95) out.push(`${px.toFixed(1)}px <${el.tagName.toLowerCase()} class="${el.className}">${n.textContent.trim().slice(0, 30)}`);
  }
  return [...new Set(out)];
}"""

_SMALL_TARGETS_JS = """(sel) => [...document.querySelectorAll(sel)].flatMap(el => {
  const r = el.getBoundingClientRect();
  if (!r.width || !r.height) return [];   // not shown at this width
  return (r.width < 23.5 || r.height < 23.5)
    ? [`${Math.round(r.width)}x${Math.round(r.height)} <${el.tagName.toLowerCase()} class="${el.className}">${el.textContent.trim().slice(0, 30)}`]
    : [];
})"""


def _open(url):
    page = _phone.new_page()
    resp = page.goto(url, wait_until="load")
    if not resp or resp.status != 200 or "text/html" not in resp.headers.get("content-type", ""):
        page.close()
        return None
    if page.locator("pre.mermaid").count():
        try:
            page.wait_for_function("() => [...document.querySelectorAll('pre.mermaid')]"
                                   ".every(n => n.querySelector('svg'))", timeout=15000)
        except PlaywrightTimeout:
            pass   # test_mermaid_browser.py owns drawing. The layout is checked as it stands.
    return page


def test_every_page_fits_320px():
    problems, seen = [], 0
    for name, base, paths in VAULTS:
        for path in paths:
            page = _open(base + path)
            if page is None:
                continue
            seen += 1
            width = page.evaluate("document.documentElement.scrollWidth")
            if width > WIDTH:
                wide = page.evaluate("""(w) => [...document.querySelectorAll('body *')]
                  .filter(e => e.getBoundingClientRect().right > w + 1)
                  .filter(e => !e.parentElement || e.parentElement.getBoundingClientRect().right <= w + 1)
                  .slice(0, 3).map(e => e.tagName.toLowerCase() + '.' + e.className)""", WIDTH)
                problems.append(f"{name} {path}: page is {width}px wide ({', '.join(wide)})")
            nav = page.evaluate("""() => { const n = document.querySelector('.mainnav');
              return n && n.getClientRects().length ? n.scrollWidth - n.clientWidth : 0; }""")
            if nav > 0:
                problems.append(f"{name} {path}: the nav scrolls sideways by {nav}px")
            for t in page.evaluate(_SMALL_TARGETS_JS, TARGETS):
                problems.append(f"{name} {path}: target smaller than 24x24: {t}")
            for t in page.evaluate(_SMALL_TEXT_JS):
                problems.append(f"{name} {path}: text below 12px: {t}")
            page.close()
    assert seen > 30, f"only {seen} pages answered 200. Did the fixtures or the routes change?"
    assert not problems, f"{len(problems)} problems at {WIDTH}px:\n  " + "\n  ".join(problems)


def test_nav_entries_are_one_tap_away():
    _, base, _ = VAULTS[0]
    page = _open(base + "/")
    entries = page.evaluate("[...document.querySelectorAll('.mainnav a')].map(a => a.getAttribute('href'))")
    assert len(entries) >= 3, f"the nav has too few entries to test: {entries}"
    page.close()
    page = _open(base + entries[0])
    page.locator(".menu-btn").tap()
    box = page.locator(".menu-list").bounding_box()
    assert box["x"] >= 0 and box["x"] + box["width"] <= WIDTH, f"the open menu sticks out of the screen: {box}"
    for href in entries:
        link = page.locator(f'#menu a[href="{href}"]')
        assert link.count() == 1 and link.is_visible(), f"nav entry {href} is not in the open menu"
    current = page.locator('#menu a[aria-current="page"]')
    assert current.count() == 1 and current.get_attribute("href") == entries[0], \
        "the open menu does not mark the current page"
    page.close()


def test_wide_table_scrolls_and_diagram_shows_whole():
    _, base, _ = VAULTS[0]
    page = _open(base + "/page/decisions/DR-002-wide-table")
    box = page.evaluate("""() => { const t = document.querySelector('.table-scroll');
      return t && {scroll: t.scrollWidth, client: t.clientWidth, overflow: getComputedStyle(t).overflowX}; }""")
    assert box, "the markdown table has no .table-scroll wrapper"
    assert box["scroll"] > box["client"] and box["overflow"] == "auto", box
    diagram = page.evaluate("""() => { const d = document.querySelector('.diagram-scroll');
      return d && {touch: getComputedStyle(d).touchAction, overflow: getComputedStyle(d).overflowX,
                   scroll: d.scrollWidth, client: d.clientWidth}; }""")
    assert diagram, "the mermaid diagram has no .diagram-scroll wrapper"
    # Chromium reports `pan-x pan-y pinch-zoom` by its short name
    assert diagram["touch"] in ("pan-x pan-y pinch-zoom", "manipulation") \
        and diagram["overflow"] == "auto", diagram
    assert diagram["scroll"] <= diagram["client"] + 1, f"the diagram does not show whole: {diagram}"
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
        for _p in _procs:
            _p.kill()
    if failed:
        sys.exit(1)
    print(f"ok: {len(fns)} checks in headless Chromium at {WIDTH}x{HEIGHT}")
