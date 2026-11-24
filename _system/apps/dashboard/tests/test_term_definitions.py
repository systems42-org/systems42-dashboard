"""A link to a domain term carries the term's definition (FR-041). No pytest.

Its own temporary vault. A term page is a page of type `domain-term`, in the
folder the metamodel names for that type.

  * Every wikilink to a term, on a page body, a requirement page, the term
    list and a source record, is `<a class="wl wl-term" title="...">`: the
    definition as plain text, at most 300 characters.
  * A term without a definition, a page of another type and a wikilink in
    code get no definition.
  * Markup in a definition stays text, in the title and on the page.
  * A page with many term links reads each definition once per request.
  * Every page loads the script that shows the definition in place. The
    script runs under node on a stand-in page (term_definition_harness.js):
    hover, focus, tap, Escape and the place of the box. No browser renders it
    here.

Run from the dashboard dir:
    .venv/bin/python tests/test_term_definitions.py
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
_sources = _tmp / "sources"
_sources.mkdir()
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(HERE))

import catalog  # noqa: E402

TERMS = catalog.folder("domain-term")
FRS = catalog.folder("functional-requirement")
for _f in (TERMS, FRS, "stakeholders"):
    (_wiki / _f).mkdir(parents=True)


def _page(folder, stem, typ, title, body, extra=""):
    pid = "-".join(stem.split("-")[:2])
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: {typ}\ntitle: {title}\nstatus: draft\nsources: []\n"
        f"related: []\ntags: []\n{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


LONG = "A thing to sell, " + "with a very long list of properties, " * 12 + "and an end."
HOSTILE = ('"><script>alert(1)</script> <img src=x onerror=alert(2)> it\'s '
           "[click](javascript:alert(3)) javascript:alert(4) a ` tick, a \\* star & an [open bracket")
# the same text with the Markdown link reduced to its label
HOSTILE_TEXT = ('"><script>alert(1)</script> <img src=x onerror=alert(2)> it\'s '
                "click) javascript:alert(4) a ` tick, a \\* star & an [open bracket")

_page(TERMS, "DT-001-order", "domain-term", "Order",
      "**Definition.** A customer's **binding** request for\n[[DT-002-item|items]], "
      "see [[DT-003-empty]], `code` and [the shop](https://example.org).\n\n"
      "**In context.** Sales only. An [[DT-001-order]] links itself.")
_page(TERMS, "DT-002-item", "domain-term", "Item", f"**Definition.** {LONG}")
_page(TERMS, "DT-003-empty", "domain-term", "Empty", "No labelled paragraph here.")
_page(TERMS, "DT-004-hostile", "domain-term", "Hostile", f"**Definition.** {HOSTILE}")
_page("stakeholders", "STK-001-reader", "stakeholder", "Reader",
      "**Definition.** A stakeholder is no term.\n\n"
      "Reads an [[DT-001-order]], by ID an [[DT-001|order by id]], an [[DT-003-empty]] "
      "and [[STK-002-other]].\n\n"
      "Quoted: `[[DT-001-order]]`.\n\n```\n[[DT-001-order]]\n```\n\n"
      "A stray ` tick before [[DT-004-hostile]].")
_page("stakeholders", "STK-002-other", "stakeholder", "Other",
      "**Definition.** A stakeholder is no term.\n\n"
      + " ".join("[[DT-001-order]] and [[DT-002-item]]." for _ in range(40)))
_page(FRS, "FR-001-buy", "functional-requirement", "Buy",
      "## Story\n\nAs a reader I want an [[DT-001-order]].", extra="notation: agile\nlevel: story\n")
(_sources / "SRC-001-notes.md").write_text(
    '---\nid: SRC-001\ntitle: Notes\ntype: source\ningested-pages: "[[DT-004-hostile]] <b>x</b>"\n---\n\nNotes.\n',
    encoding="utf-8")

import app  # noqa: E402
import render  # noqa: E402

client = app.app.test_client()

ORDER = "A customer's binding request for items, see Empty, code and the shop."
LINK_RE = re.compile(r'<a class="wl wl-term" href="([^"]*)" title="([^"]*)">(.*?)</a>')


def _get(url):
    r = client.get(url)
    assert r.status_code == 200, (url, r.status_code)
    return r.get_data(as_text=True)


def _term_links(body):
    """(href, definition, label) of every term link, the title decoded."""
    return [(h, html.unescape(t), label) for h, t, label in LINK_RE.findall(body)]


def test_the_definition_is_plain_text_and_bounded():
    with app.app.test_request_context("/"):
        assert render.term_definition("DT-001-order") == ORDER, render.term_definition("DT-001-order")
        long = render.term_definition("DT-002-item")
        assert len(long) <= render.TERM_DEFINITION_MAX, len(long)
        assert long.endswith("…") and LONG.startswith(long[:-1]), long
        assert not long[:-1].endswith(" "), "the cut leaves a blank before the ellipsis"
        assert render.term_definition("DT-003-empty") == ""
        assert render.term_definition("STK-001-reader") == "", "only a domain term has a definition here"
        assert render.term_definition("no-such-page") == ""


def test_links_in_a_page_body_carry_the_definition():
    body = _get("/page/stakeholders/STK-001-reader")
    links = _term_links(body)
    href = f"/page/{TERMS}/DT-001-order"
    assert (href, ORDER, "Order") in links, links
    assert (href, ORDER, "order by id") in links, "a link by ID carries it too"
    # no definition: the plain link, no empty title
    assert f'<a class="wl" href="/page/{TERMS}/DT-003-empty">Empty</a>' in body
    assert 'title=""' not in body
    # another type: the plain link
    assert '<a class="wl" href="/page/stakeholders/STK-002-other">Other</a>' in body
    # in code the link stays as written
    assert "<code>[[DT-001-order]]</code>" in body
    assert len([link for link in links if link[0] == href]) == 2, links


def test_requirement_page_term_list_and_own_page():
    href = f"/page/{TERMS}/DT-001-order"
    assert (href, ORDER, "Order") in _term_links(_get(f"/functional-requirements/FR-001-buy"))
    # the term list renders each definition with its links
    listed = _term_links(_get("/domain-terms"))
    assert any(h == f"/page/{TERMS}/DT-002-item" and label == "items" for h, _, label in listed), listed
    # a term's own page: a link to itself carries the definition like any other
    assert (href, ORDER, "Order") in _term_links(_get(href))


def test_a_hostile_definition_stays_text():
    want = render.term_definition.__wrapped__("DT-004-hostile")
    assert want == HOSTILE_TEXT, want
    for url in ("/page/stakeholders/STK-001-reader", "/source/SRC-001-notes"):
        body = _get(url)
        assert "<script>alert" not in body, url
        assert not re.search(r"<img[^>]*onerror", body), url
        assert not re.search(r'href="\s*javascript:', body), url
        links = [link for link in _term_links(body) if link[0].endswith("DT-004-hostile")]
        assert links == [(f"/page/{TERMS}/DT-004-hostile", want, "Hostile")], (url, links)
    # the frontmatter value around the link is still escaped
    assert "&lt;b&gt;x&lt;/b&gt;" in _get("/source/SRC-001-notes")


def test_the_title_and_the_class_pass_markdown_and_the_sanitizer():
    # the same literal as internal/render/render_test.go
    assert render._title_attribute(HOSTILE_TEXT) == (
        "&#34;&gt;&lt;script&gt;alert(1)&lt;/script&gt; &lt;img src=x onerror=alert(2)&gt; it&#39;s "
        "click) javascript:alert(4) a &#96; tick, a &#92;&#42; star &amp; an &#91;open bracket")
    assert render.sanitize_html('<a class="wl wl-term fbtn" href="/x" title="d">x</a>') == \
        '<a class="wl wl-term" href="/x" title="d">x</a>'


def test_many_links_read_each_definition_once():
    calls = []
    real = render.labeled_text
    render.labeled_text = lambda page, label: (calls.append(page.stem), real(page, label))[1]
    try:
        body = _get("/page/stakeholders/STK-002-other")
    finally:
        render.labeled_text = real
    assert len(_term_links(body)) == 80, len(_term_links(body))
    assert sorted(calls) == ["DT-001-order", "DT-002-item"], calls


def test_pages_load_the_script_and_it_covers_keyboard_and_touch():
    body = _get("/page/stakeholders/STK-001-reader")
    assert re.search(r'<script src="/static/term-definition\.js[^"]*" defer></script>', body)
    js = (HERE / "static" / "term-definition.js").read_text(encoding="utf-8")
    for needle in ("a.wl-term[title]", "a.wl-anchor[title]", "focusin", "focusout", "mouseover",
                   "Escape", "aria-describedby", 'role", "tooltip"', "pointerType", "preventDefault",
                   "textContent", "clientWidth"):
        assert needle in js, needle
    assert "innerHTML" not in js, "a definition is text, never markup"
    css = (HERE / "static" / "style.css").read_text(encoding="utf-8")
    block = css[css.index("/* --- term definition in place"):css.index("/* --- end of term definition in place")]
    assert ".term-def" in block and "max-width" in block and "100vw" in block
    assert "prefers-reduced-motion" in block
    assert not re.search(r"#[0-9a-fA-F]{3,8}\b|rgba?\(", block), "colours come from the design tokens"


# --- the script, under node on a stand-in page ---------------------------------

A = {"title": "A request.", "href": "/page/x/DT-001-order",
     "rect": {"left": 20, "top": 100, "right": 80, "bottom": 118}}
B = {"title": "A thing to sell.", "href": "/page/x/DT-002-item",
     "rect": {"left": 250, "top": 600, "right": 310, "bottom": 618}}
PLAIN = {"title": "", "href": "/page/x/DT-003-empty",
         "rect": {"left": 20, "top": 200, "right": 80, "bottom": 218}}


def _script(actions, viewport=(1000, 700), box=(300, 60)):
    """The state of the page after each action (tests/term_definition_harness.js)."""
    spec = {"viewport": {"w": viewport[0], "h": viewport[1]}, "box": {"w": box[0], "h": box[1]},
            "links": [A, B, PLAIN], "actions": actions}
    out = subprocess.run(["node", str(HERE / "tests" / "term_definition_harness.js")],
                         input=json.dumps(spec), capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def test_hover_shows_the_definition_and_the_box_can_be_reached():
    s = _script([{"hover": 0}, {"leave": 0, "to": "box"}, {"wait": 500}, {"leaveBox": True},
                 {"wait": 100}, {"wait": 100}, {"hover": 2}])
    assert s[0]["shown"] and s[0]["text"] == "A request." and s[0]["role"] == "tooltip" and s[0]["inBody"]
    # read once: the title moves to aria-describedby while the box shows
    assert s[0]["titles"] == [None, B["title"], None] and s[0]["described"] == ["term-def-text", None, None]
    assert not s[0]["open"], "a pointer needs no second link"
    # under the link, at its left edge
    assert (s[0]["left"], s[0]["top"]) == (20, 124), s[0]
    assert s[2]["shown"], "the box closed while the pointer was on it"
    assert s[4]["shown"] and not s[5]["shown"], "the box closes shortly after the pointer left it"
    assert s[5]["titles"] == [A["title"], B["title"], None] and s[5]["described"] == [None, None, None]
    assert not s[6]["shown"], "a link without a definition shows no box"


def test_focus_shows_it_and_escape_closes_it():
    s = _script([{"focus": 0}, {"click": 0}, {"key": "Escape"}, {"focus": 1}, {"blur": 1}])
    assert s[0]["shown"] and s[0]["described"][0] == "term-def-text" and not s[0]["open"]
    assert not s[1]["prevented"], "Enter or a click on a focused term must open its page"
    assert not s[2]["shown"] and s[2]["titles"][0] == A["title"]
    assert s[3]["shown"] and s[3]["text"] == B["title"]
    assert not s[4]["shown"], "the box stayed after focus left the term"


def test_first_tap_shows_it_second_tap_opens_the_page():
    s = _script([{"tap": 0}, {"tap": 0}, {"tap": 1}, {"tapElsewhere": True}, {"tap": 0}, {"tap": 2}])
    assert s[0]["prevented"] and s[0]["shown"] and s[0]["text"] == "A request."
    assert s[0]["open"] and s[0]["openHref"] == A["href"], "no way to open the page after the first tap"
    assert not s[1]["prevented"], "the second tap on the term must open its page"
    assert s[2]["prevented"] and s[2]["text"] == B["title"] and s[2]["openHref"] == B["href"]
    assert not s[3]["shown"] and not s[3]["prevented"], "a tap elsewhere closes the box"
    assert s[4]["prevented"], "after closing, the first tap shows the definition again"
    assert not s[5]["prevented"], "a term without a definition opens at the first tap"


def test_the_box_stays_inside_a_narrow_screen():
    s = _script([{"hover": 1}, {"hover": 0}], viewport=(320, 640), box=(304, 80))
    # the link sits at the right edge and at the bottom: the box moves left and above it
    assert s[0]["left"] == 8 and s[0]["left"] + 304 <= 320 - 8, s[0]
    assert s[0]["top"] == 600 - 6 - 80, s[0]
    assert s[1]["left"] == 8 and s[1]["top"] == 124, s[1]


if __name__ == "__main__":
    test_the_definition_is_plain_text_and_bounded()
    test_links_in_a_page_body_carry_the_definition()
    test_requirement_page_term_list_and_own_page()
    test_a_hostile_definition_stays_text()
    test_the_title_and_the_class_pass_markdown_and_the_sanitizer()
    test_many_links_read_each_definition_once()
    test_pages_load_the_script_and_it_covers_keyboard_and_touch()
    if shutil.which("node"):
        test_hover_shows_the_definition_and_the_box_can_be_reached()
        test_focus_shows_it_and_escape_closes_it()
        test_first_tap_shows_it_second_tap_opens_the_page()
        test_the_box_stays_inside_a_narrow_screen()
    else:
        print("skip: node not installed, the script's behaviour is not tested")
    print("OK: term links carry the definition")
