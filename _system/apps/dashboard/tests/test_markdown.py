"""render_markdown / _unwrap_prose contract: hard-wrapped prose (agents write
wiki pages wrapped at ~80 columns) renders as one paragraph, not one <br> per
source line — while lists, fenced code, and explicit two-space breaks are
left untouched. Also the sanitizer's own rules (sanitize_html): which ids,
classes, image sources and styles of wiki content reach the page. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_markdown.py
"""
import os
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "glossary", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "use-cases", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import app  # noqa: E402


def test_hard_wrapped_prose_is_one_paragraph():
    html = app.render_markdown("First line of a\nwrapped paragraph.\n\nSecond.", {})
    assert "<br" not in html, html
    assert "<p>First line of a wrapped paragraph.</p>" in html, html


def test_list_directly_after_prose_line_is_a_list():
    html = app.render_markdown("**Goals.** PAM (light)\n- one thing\n- two things", {})
    assert "<ul>" in html and "<li>one thing</li>" in html, html


def test_wrapped_list_item_stays_one_item():
    html = app.render_markdown("- Replace the ad-hoc\n  coordination.\n- Second item", {})
    assert html.count("<li>") == 2, html
    assert "ad-hoc coordination" in html.replace("\n", " "), html


def test_fenced_code_is_untouched():
    html = app.render_markdown("```\nline a\nline b\n```", {})
    assert "line a\nline b" in html, html


def test_explicit_two_space_break_is_kept():
    html = app.render_markdown("roses are red  \nviolets are blue", {})
    assert "<br" in html, html


def test_wrapped_list_stays_tight():
    html = app.render_markdown("- Replace the ad-hoc\n  coordination.\n- Second item", {})
    assert "<li><p>" not in html, html
    assert html.count("<li>") == 2, html


def test_headerless_gfm_table_survives():
    html = app.render_markdown("Header1 | Header2\n--- | ---\na | b", {})
    assert "<table>" in html, html


def test_prose_starting_with_a_wikilink_is_joined():
    html = app.render_markdown("[[STK-001]] wants faster\nonboarding.", {})
    assert "wants faster onboarding." in html, html


def test_spaced_pipe_in_prose_is_still_joined():
    html = app.render_markdown("See the linked feature for\ndetails: a | b here.", {})
    assert "feature for details: a | b here." in html, html


def test_leading_pipe_table_survives():
    html = app.render_markdown("| H1 | H2 |\n|----|----|\n| a | b |", {})
    assert "<table>" in html, html


# --- sanitize_html ---------------------------------------------------------
# tests/test_hostile_vault.py checks whole pages. These name each rule on its
# own, so a rule that is switched off fails here by name.

def test_ids_of_the_pages_own_controls_are_dropped():
    for taken in ("settings-dialog", "search-index", "brand-intro", "fn1", "x"):
        html = app.sanitize_html(f'<p id="{taken}">a</p>')
        assert "id=" not in html, (taken, html)
    assert app.render_markdown('<div id="settings-dialog">a</div>', {}).count("id=") == 0


def test_footnote_ids_are_kept():
    for own in ("fn:1", "fnref:1", "fnref2:1", "fn:note-a"):
        assert f'id="{own}"' in app.sanitize_html(f'<p id="{own}">a</p>'), own
    html = app.render_markdown("Text[^1].\n\n[^1]: The note.", {})
    assert 'id="fn:1"' in html and 'id="fnref:1"' in html, html


def test_classes_of_the_pages_own_controls_are_dropped():
    html = app.sanitize_html('<a class="fbtn wl sresult layer-btn language-python">a</a>')
    assert 'class="wl language-python"' in html, html
    assert "class=" not in app.sanitize_html('<p class="fbtn">a</p>')


def test_images_from_outside_lose_their_source():
    for remote in ("https://evil.example/p.gif", "http://evil.example/p.gif",
                   "//evil.example/p.gif", "/\\evil.example/p.gif", "\\\\evil.example/p.gif",
                   " https://evil.example/p.gif", "ht\ttps://evil.example/p.gif",
                   "HTTPS://evil.example/p.gif", "data:image/gif;base64,AAAA"):
        html = app.sanitize_html(f'<img src="{remote}" alt="pixel">')
        assert "src=" not in html and 'alt="pixel"' in html, (remote, html)
    assert "evil.example" not in app.render_markdown("![pixel](https://evil.example/p.gif)", {})


def test_images_of_the_dashboard_keep_their_source():
    for local in ("/about/files/a.png", "a.png", "img/a.png", "../a.png", "/static/x.svg?v=1"):
        assert f'src="{local}"' in app.sanitize_html(f'<img src="{local}" alt="a">'), local


def test_links_to_outside_are_kept():
    html = app.sanitize_html('<a href="https://example.org/x">x</a>')
    assert 'href="https://example.org/x"' in html, html


def test_about_styles_cannot_fetch():
    for bad in ("background:url(https://evil.example/p.gif)",
                "background: URL( 'https://evil.example/p.gif' )",
                "background:u\\72l(https://evil.example/p.gif)",
                "background:image-set('https://evil.example/p.gif' 1x)",
                "background:-webkit-image-set(url(https://evil.example/p.gif) 1x)",
                "background:image('https://evil.example/p.gif')"):
        html = app.sanitize_html(f'<div style="color:red;{bad};padding:4px">a</div>', about=True)
        assert "evil.example" not in html, (bad, html)
        assert "color:red" in html and "padding:4px" in html, (bad, html)
    kept = app.sanitize_html('<div style="background:#123456;display:flex">a</div>', about=True)
    assert "background:#123456" in kept and "display:flex" in kept, kept
    # a wiki page keeps no layout style at all, About or not
    assert "style=" not in app.sanitize_html('<div style="background:#123456">a</div>')


if __name__ == "__main__":
    test_hard_wrapped_prose_is_one_paragraph()
    test_list_directly_after_prose_line_is_a_list()
    test_wrapped_list_item_stays_one_item()
    test_fenced_code_is_untouched()
    test_explicit_two_space_break_is_kept()
    test_wrapped_list_stays_tight()
    test_headerless_gfm_table_survives()
    test_prose_starting_with_a_wikilink_is_joined()
    test_spaced_pipe_in_prose_is_still_joined()
    test_leading_pipe_table_survives()
    test_ids_of_the_pages_own_controls_are_dropped()
    test_footnote_ids_are_kept()
    test_classes_of_the_pages_own_controls_are_dropped()
    test_images_from_outside_lose_their_source()
    test_images_of_the_dashboard_keep_their_source()
    test_links_to_outside_are_kept()
    test_about_styles_cannot_fetch()
    print("OK: markdown unwrap contract, sanitizer rules")
