"""The exported demo's requirement list filters by delivery status without a
server (issue #91, FR-048). No pytest.

The demo is one saved page per path under /demo/ (site/build.py), so the filter
has to run in the browser, like the kind filter of the term list
(test_term_list_demo.py). Skips where the repository's site/ folder is not present.

Run from the dashboard dir:
    .venv/bin/python tests/test_delivery_filter_demo.py
"""
import importlib.util
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

_DASH = Path(__file__).resolve().parents[1]
_REPO = _DASH.parents[2]
BUILD = _REPO / "site" / "build.py"
if not BUILD.is_file():
    print("skip: no site/build.py beside this dashboard")
    sys.exit(77)

os.environ.update(DASH_STARTUP_GRACE="3600", DASH_HEARTBEAT_GRACE="3600")
spec = importlib.util.spec_from_file_location("site_build", BUILD)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

with tempfile.TemporaryDirectory() as temp:
    wiki_root = Path(temp) / "repo"
    fr = wiki_root / "wiki" / "functional-requirements"
    fr.mkdir(parents=True)
    shutil.copytree(_REPO / "_system" / "metamodel", wiki_root / "_system" / "metamodel")
    shutil.copytree(_REPO / "_system" / "anchors", wiki_root / "_system" / "anchors")
    (wiki_root / "_system" / "wiki.yaml").write_text("system_name: Tracking\n", encoding="utf-8")
    story = "status: draft\nnotation: agile\nlevel: story\n"
    for stem, frontmatter in {
        "FR-001-built": "id: FR-001\ntitle: Built\n" + story + "delivery: implemented\ndelivery-checked: 2026-11-20",
        "FR-002-drifted": "id: FR-002\ntitle: Drifted\n" + story + "delivery: outdated",
        "FR-003-open": "id: FR-003\ntitle: Open\n" + story,
    }.items():
        (fr / f"{stem}.md").write_text(f"---\n{frontmatter}\n---\n# T\n\nText.\n", encoding="utf-8")

    out = Path(temp) / "out"
    build.export_demo(_REPO, wiki_root, out)
    page = (out / "demo" / "req42" / "functional-requirements" / "index.html").read_text(encoding="utf-8")

    # the list and its delivery filter are on the page, with every requirement
    assert "<select data-list-delivery>" in page
    for value in ("partial", "implemented", "outdated", "removed", "none"):
        assert f'<option value="{value}">' in page, value
    values = re.findall(r'<tr data-status="[^"]*" data-delivery="([^"]*)">', page)
    assert values == ["implemented", "outdated", ""], values

    # nothing on the page leaves /demo/: no script navigates to a root path, and
    # every root address in an href, src or action is under /demo/
    assert not re.search(r"""location\.(?:assign|replace)\(\s*['"]/|location(?:\.href)?\s*=\s*['"]/""", page)
    outside = [m.group(0) for m in re.finditer(r"""\b(?:href|src|action)=["'](/[^"']*)["']""", page)
               if not (m.group(1) == "/" or m.group(1).startswith(("/demo/", "/docs/", "/downloads/")))]
    assert not outside, outside
    # the filter itself: the list script the demo ships is the one that filters by delivery
    script = (out / "demo" / "static" / "list-view.js").read_text(encoding="utf-8")
    assert "select[data-list-delivery]" in script and "location.assign" not in script
    assert re.search(r'<script src="/demo/static/list-view\.js', page)

    # the badge is on the exported requirement page
    detail = (out / "demo" / "functional-requirements" / "FR-001-built" / "index.html").read_text(encoding="utf-8")
    assert '<span class="delivery delivery-implemented">implemented</span>' in detail
    assert '<span class="delivery-checked">checked 2026-11-20</span>' in detail

print("OK: the demo's requirement list filters by delivery status in the browser")
