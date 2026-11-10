"""The brand slot: marks, favicon and the optional intro. No pytest.

Every product-specific look lives in static/brand/ plus an optional
templates/_brand_intro.html (contract: static/brand/README.md), so a rebrand
replaces files and changes no template.

Run from the dashboard dir:
    .venv/bin/python tests/test_brand.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
(_tmp / "wiki").mkdir()
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

_HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_HERE))

import jinja2  # noqa: E402

import app  # noqa: E402

client = app.app.test_client()
BRAND = _HERE / "static" / "brand"


def test_marks_and_favicon_come_from_the_brand_slot():
    home = client.get("/").get_data(as_text=True)
    sub = client.get("/glossary").get_data(as_text=True)
    for page in (home, sub):
        assert re.search(r'rel="icon" type="image/svg\+xml" href="/static/brand/favicon\.svg', page)
    for name in ("mark-dark.svg", "mark-light.svg"):
        assert f'src="/static/brand/{name}' in home, name      # hero
        assert f'src="/static/brand/{name}' in sub, name       # top bar
    for name in ("mark-dark.svg", "mark-light.svg", "favicon.svg"):
        assert (BRAND / name).is_file(), name
        assert client.get(f"/static/brand/{name}").status_code == 200, name


def test_marks_are_square_and_text_free():
    for name in ("mark-dark.svg", "mark-light.svg", "favicon.svg"):
        svg = (BRAND / name).read_text(encoding="utf-8")
        w, h = re.search(r'viewBox="[\d.\s-]*?\s([\d.]+)\s+([\d.]+)"', svg).groups()
        assert w == h, (name, w, h)
        assert "<text" not in svg and "gradient" not in svg.lower(), name


def test_no_intro_file_means_no_intro():
    assert not (_HERE / "templates" / "_brand_intro.html").exists(), \
        "a brand intro ships now: replace this test with one for its contract"
    home = client.get("/").get_data(as_text=True)
    assert "splash" not in home and "intro.js" not in home


def test_an_intro_file_is_included_before_the_hero():
    original = app.app.jinja_loader
    app.app.jinja_env.loader = jinja2.ChoiceLoader([
        jinja2.DictLoader({"_brand_intro.html": '<div id="brand-splash" hidden></div>'}),
        original,
    ])
    app.app.jinja_env.cache.clear()
    try:
        home = client.get("/").get_data(as_text=True)
        assert 'id="brand-splash"' in home
        assert home.index('id="brand-splash"') < home.index('class="hero"')
    finally:
        app.app.jinja_env.loader = original
        app.app.jinja_env.cache.clear()


def test_no_atrium_branding_left():
    for path in list((_HERE / "templates").glob("*.html")) + list((_HERE / "static").glob("*.*")):
        if path.suffix in (".html", ".css", ".js", ".svg"):
            assert "atrium" not in path.read_text(encoding="utf-8").lower(), path.name


if __name__ == "__main__":
    test_marks_and_favicon_come_from_the_brand_slot()
    test_marks_are_square_and_text_free()
    test_no_intro_file_means_no_intro()
    test_an_intro_file_is_included_before_the_hero()
    test_no_atrium_branding_left()
    print("OK: brand slot")
