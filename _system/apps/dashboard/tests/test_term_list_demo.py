"""The exported demo's term list filters by kind without a server (FR-038). No pytest.

The demo is one saved page per path under /demo/ (site/build.py). A filter that
asks the server, or a script that navigates to a root path, leaves the demo.
Skips where the repository's site/ folder is not present.

Run from the dashboard dir:
    .venv/bin/python tests/test_term_list_demo.py
"""
import importlib.util
import os
import re
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
    out = Path(temp)
    build.export_demo(_REPO, _DASH / "tests" / "fixtures" / "domain-model", out)
    page = (out / "demo" / "domain-terms" / "index.html").read_text(encoding="utf-8")

    # the list and its kind filter are on the page, with every term
    assert "<select data-list-kind>" in page
    for value in ("entity", "value-object", "sum-type", "none"):
        assert f'<option value="{value}">' in page, value
    kinds = re.findall(r'<tr data-status="[^"]*" data-kind="([^"]*)">', page)
    assert sorted(kinds) == ["", "entity", "entity", "entity"], kinds

    # nothing on the page leaves /demo/: no script navigates to a root path, and
    # every root address in an href, src or action is under /demo/
    assert not re.search(r"""location\.(?:assign|replace)\(\s*['"]/|location(?:\.href)?\s*=\s*['"]/""", page)
    outside = [m.group(0) for m in re.finditer(r"""\b(?:href|src|action)=["'](/[^"']*)["']""", page)
               if not (m.group(1) == "/" or m.group(1).startswith(("/demo/", "/docs/", "/downloads/")))]
    assert not outside, outside
    # the filter itself: the list script the demo ships is the one that filters by kind
    script = (out / "demo" / "static" / "list-view.js").read_text(encoding="utf-8")
    assert "select[data-list-kind]" in script and "location.assign" not in script
    assert re.search(r'<script src="/demo/static/list-view\.js', page)

print("OK: the demo's term list filters by kind in the browser")
