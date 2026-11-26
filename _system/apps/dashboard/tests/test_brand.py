"""The brand shipped in brands/ keeps the brand contract
(brands/README.md): three square marks and an optional intro that shows once
per tab, never under reduced motion, ends on click or key, starts hidden and
stays offline. How wiki.yaml selects a brand: tests/test_brand_config.py.
No pytest.

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
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

_HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_HERE))

import app  # noqa: E402

client = app.app.test_client()
BRANDS = _HERE / "brands"
SHIPPED = ("systems42",)
MARKS = ("mark-dark.svg", "mark-light.svg", "favicon.svg")
ARCHIVE = _HERE.parents[2] / "docs" / "brand" / "archive" / "chart"


def intro(brand: str) -> str:
    return (BRANDS / brand / "intro.html").read_text(encoding="utf-8")


def test_the_example_brands_are_the_ones_shipped():
    assert tuple(app.EXAMPLE_BRANDS) == SHIPPED
    assert app.DEFAULT_BRAND == "systems42"
    assert sorted(p.name for p in BRANDS.iterdir() if p.is_dir()) == sorted(SHIPPED)
    assert (BRANDS / "README.md").is_file(), "the brand contract lives beside the brands"


def test_marks_are_square_and_text_free():
    for brand in SHIPPED:
        for name in MARKS:
            svg = (BRANDS / brand / name).read_text(encoding="utf-8")
            w, h = re.search(r'viewBox="[\d.\s-]*?\s([\d.]+)\s+([\d.]+)"', svg).groups()
            assert float(w) == float(h), (brand, name, w, h)
            assert "<text" not in svg and "gradient" not in svg.lower(), (brand, name)


def test_marks_and_favicon_are_served_on_every_page():
    (_tmp / "wiki.yaml").write_text("", encoding="utf-8")
    home = client.get("/").get_data(as_text=True)
    sub = client.get("/domain-terms").get_data(as_text=True)
    for page in (home, sub):
        assert re.search(r'rel="icon" type="image/svg\+xml" href="/brand/favicon\.svg\?v=', page)
        for name in ("mark-dark.svg", "mark-light.svg"):
            assert f'src="/brand/{name}?v=' in page, name
    for name in MARKS:
        assert client.get(f"/brand/{name}").status_code == 200, name


def test_intro_is_hidden_until_the_script_shows_it():
    for brand in SHIPPED:
        text = intro(brand)
        assert re.search(r'<div [^>]*\bhidden\b', text), brand
        assert "el.hidden = false" in text, brand


def test_intro_shows_once_per_tab_and_not_under_reduced_motion():
    for brand in SHIPPED:
        text = intro(brand)
        assert "sessionStorage" in text and "catch" in text, brand   # blocked storage shows it every time
        assert "prefers-reduced-motion: reduce" in text, brand
        check = re.search(r"""prefers-reduced-motion: reduce\)["']\)\.matches""", text)
        assert check and check.start() < text.index("el.hidden = false"), brand


def test_intro_ends_on_click_or_key_and_removes_itself():
    for brand in SHIPPED:
        text = intro(brand)
        for event in ("click", "keydown"):
            assert re.search(rf"""addEventListener\(["']{event}["']""", text), (brand, event)
        assert "el.remove()" in text, brand


def test_systems42_intro_ends_within_two_and_a_half_seconds():
    text = intro("systems42")
    assert "setTimeout(done, 2400)" in text
    assert "classList.add('bi-out'); }, 2150)" in text


def test_the_shipped_intro_is_the_helix_with_a_dashboard_line():
    """FR-032: the dashboard ships the helix of the systems42 logo. The helix
    winds up, "systems42" rises in, then "dashboard". It is the default of
    every wiki without a brand of its own, so the look of one wiki never goes
    in here. Such a wiki names its own folder in `brand:` (FR-031)."""
    text = intro("systems42")
    assert text.count('class="bi-strand') == 2, "green and blue strand"
    assert text.count('class="bi-word"') == 1
    sub = re.search(r'<svg class="bi-sub"[^>]*>(.*?)</svg>', text, re.S)
    assert sub and sub.group(1).count("<path") == 9, "d a s h b o a r d"
    assert "bi-block" not in text and "bi-axis" not in text
    assert sorted(p.name for p in (BRANDS / "systems42").iterdir()) == \
        ["favicon.svg", "intro.html", "mark-dark.svg", "mark-light.svg"]


def test_intro_covers_the_page_with_bg_uses_tokens_and_stays_offline():
    for brand in SHIPPED:
        text = intro(brand)
        assert "background: var(--bg)" in text, brand
        # colours are theme tokens, or the brand's own --brand-* tokens declared once
        for line in text.splitlines():
            if re.search(r"#[0-9a-fA-F]{3,8}\b", line):
                assert re.fullmatch(r"\s*(:root\[data-theme=\"light\"\] )?#[\w-]+ \{( --brand-[\w-]+: #[0-9a-fA-F]{3,8};)+ \}", line), (brand, line)
        for bad in ("http://", "https://", "fetch(", "XMLHttpRequest", "gradient", "defer", "{{", "{%"):
            assert bad not in text.replace('xmlns="http://www.w3.org/2000/svg"', ""), (brand, bad)


def test_intro_is_placed_before_the_hero_on_the_home_page_only():
    for brand, marker in (("systems42", 'id="brand-intro"'),):
        (_tmp / "wiki.yaml").write_text(f"brand: {brand}\n", encoding="utf-8")
        home = client.get("/").get_data(as_text=True)
        assert marker in client.get("/brand/intro.html").get_data(as_text=True), brand
        assert marker not in home, "the intro runs in a frame, never in the page"
        assert home.index("brand-intro-frame") < home.index('class="hero"'), brand
        assert "brand-intro-frame" not in client.get("/domain-terms").get_data(as_text=True), brand


def test_the_dashboard_holds_no_atrium_branding():
    """The atrium brand lives in the isaqb-atrium repository (FR-032)."""
    for path in list((_HERE / "templates").glob("*.html")) + list((_HERE / "static").glob("*.*")) \
            + list(BRANDS.rglob("*")):
        if path.suffix in (".html", ".css", ".js", ".svg", ".md"):
            assert "atrium" not in path.read_text(encoding="utf-8").lower(), path.name


def test_the_shipped_marks_are_the_helix():
    """FR-032: the shipped brand is the helix of the systems42 logo."""
    light = (BRANDS / "systems42" / "mark-light.svg").read_text(encoding="utf-8")
    dark = (BRANDS / "systems42" / "mark-dark.svg").read_text(encoding="utf-8")
    assert 'viewBox="5.36 13.97 32.03 32.03"' in light and 'viewBox="5.36 13.97 32.03 32.03"' in dark
    assert "#0f7f66" in light and "#1667c4" in light
    assert "#199c7e" in dark and "#3a86e6" in dark
    for name in MARKS:
        assert "Chart" not in (BRANDS / "systems42" / name).read_text(encoding="utf-8"), name


def test_the_chart_mark_is_archived_as_a_brand_folder():
    """The Chart mark stays usable: a wiki copies the folder into its brand/."""
    names = {p.name for p in ARCHIVE.iterdir()}
    assert {"mark-dark.svg", "mark-light.svg", "favicon.svg", "intro.html", "README.md"} <= names
    assert 'class="bi-block' in (ARCHIVE / "intro.html").read_text(encoding="utf-8")


if __name__ == "__main__":
    test_the_example_brands_are_the_ones_shipped()
    test_marks_are_square_and_text_free()
    test_marks_and_favicon_are_served_on_every_page()
    test_intro_is_hidden_until_the_script_shows_it()
    test_intro_shows_once_per_tab_and_not_under_reduced_motion()
    test_intro_ends_on_click_or_key_and_removes_itself()
    test_systems42_intro_ends_within_two_and_a_half_seconds()
    test_the_shipped_intro_is_the_helix_with_a_dashboard_line()
    test_intro_covers_the_page_with_bg_uses_tokens_and_stays_offline()
    test_intro_is_placed_before_the_hero_on_the_home_page_only()
    test_the_dashboard_holds_no_atrium_branding()
    test_the_shipped_marks_are_the_helix()
    test_the_chart_mark_is_archived_as_a_brand_folder()
    print("OK: shipped brand")
