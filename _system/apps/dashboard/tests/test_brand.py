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


INTRO = (_HERE / "templates" / "_brand_intro.html").read_text(encoding="utf-8")


def test_intro_is_hidden_until_the_script_shows_it():
    assert re.search(r'<div id="brand-intro" hidden', INTRO)
    assert "el.hidden = false" in INTRO


def test_intro_is_placed_before_the_hero_on_the_home_page():
    home = client.get("/").get_data(as_text=True)
    assert 'id="brand-intro"' in home
    assert home.index('id="brand-intro"') < home.index('class="hero"')
    assert 'id="brand-intro"' not in client.get("/glossary").get_data(as_text=True)


def test_intro_shows_once_per_tab_and_not_under_reduced_motion():
    assert "sessionStorage" in INTRO and "catch" in INTRO          # blocked storage shows it every time
    assert "prefers-reduced-motion: reduce" in INTRO
    assert INTRO.index("prefers-reduced-motion: reduce)').matches") < INTRO.index("el.hidden = false")


def test_intro_ends_on_click_or_key_and_within_two_seconds():
    assert "'click'" in INTRO and "'keydown'" in INTRO
    assert "setTimeout(done, 2000)" in INTRO


def test_intro_covers_the_page_with_bg_uses_tokens_and_stays_offline():
    assert "background: var(--bg)" in INTRO
    assert not re.search(r"#[0-9a-fA-F]{3,8}\b", INTRO), "colours must be theme tokens"
    for bad in ("http://", "https://", "fetch(", "XMLHttpRequest", "gradient", "defer"):
        assert bad not in INTRO, bad


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
    test_intro_is_hidden_until_the_script_shows_it()
    test_intro_is_placed_before_the_hero_on_the_home_page()
    test_intro_shows_once_per_tab_and_not_under_reduced_motion()
    test_intro_ends_on_click_or_key_and_within_two_seconds()
    test_intro_covers_the_page_with_bg_uses_tokens_and_stays_offline()
    test_an_intro_file_is_included_before_the_hero()
    test_no_atrium_branding_left()
    print("OK: brand slot")
