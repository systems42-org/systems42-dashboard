"""Regression test for the Task 6 failure mode — no pytest dependency.

Task 6 removed the `en:` key from every REQ42_BLOCKS entry and promoted its
value into `title`, but two templates (req42.html, req42_block.html) still
referenced `.en`. Nothing raised: Jinja's default Undefined renders as an
empty string, so `<span class="req42-title">{{ b.title }}</span>` next to
`<span class="req42-en">{{ b.en }}</span>` rendered the title once and an
*empty* span next to it, and req42_block.html's lead paragraph
(`{{ block.en }} — req42-Baustein {{ block.num }}.`) rendered as a leading
blank plus a dangling em-dash: " — req42-Baustein 03.". The bug was only
caught by rendering the pages against a *populated* vault and looking — the
empty-vault suite can't see it, because on an empty vault every block's
sample list is empty too, so the missing text is invisible either way.

This test renders every GET route against the populated fixture vault
(tests/fixtures/wiki/ — GOAL/STK/FR/GLO content) and asserts that labels
which should carry text actually do.

Run from the dashboard dir:
    .venv/bin/python tests/test_populated_render.py
"""
import os
import re
import sys
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402

# Same non-parametrized routes as test_empty_vault.py's GET_ROUTES.
# /leaving is deliberately NOT exercised: it arms the self-shutdown watchdog,
# which would SIGTERM this test process. Its behaviour is covered by DR-022.
GET_ROUTES = [
    "/", "/domain-terms", "/graph/domain-terms", "/issues", "/stakeholders", "/decisions",
    "/search", "/goals", "/entity-diagram", "/req42", "/req42/functional-requirements", "/arc42/building-blocks",
    "/arc42/deployment", "/arc42/runtime", "/arc42/concepts",
    "/req42/scope", "/req42/models", "/req42/quality", "/req42/constraints",
    "/arc42", "/commons", "/help", "/metamodel", "/method",
]

# Section titles per area page, HTML-escaped once the way Jinja's autoescape
# would render them.
AREA_TITLES = {
    path: [s["title"].replace("&", "&amp;") for s in app.catalog.SECTIONS if s["id"][0] == letter]
    for path, letter in (("/req42", "R"), ("/arc42", "A"), ("/commons", "C"))
}

# An empty label span/element that should never carry a display class but no
# text — the exact shape of the Task 6 bug (req42-en) plus a few sibling
# label classes used the same way elsewhere in the templates.
EMPTY_LABEL_RE = re.compile(
    r'<span class="(req42-title|req42-en|req42-type|term|ml-title)"[^>]*>\s*</span>'
)

# A lead paragraph that starts with a dangling separator — i.e. its first
# real content is missing and only the punctuation that was meant to follow
# it survived (the exact req42_block.html "{{ block.en }} — ..." shape).
DANGLING_LEAD_RE = re.compile(r'<p class="lead">\s*(&mdash;|—|-)\s')


def _bodies():
    client = app.app.test_client()
    out = {}
    for route in GET_ROUTES:
        resp = client.get(route)
        assert resp.status_code == 200, (route, resp.status_code)
        out[route] = resp.get_data(as_text=True)
    return out


def test_all_get_routes_render_populated():
    bodies = _bodies()
    for route, body in bodies.items():
        assert "Traceback" not in body, route
        assert "jinja2.exceptions" not in body, route


def test_no_empty_label_spans():
    bodies = _bodies()
    for route, body in bodies.items():
        m = EMPTY_LABEL_RE.search(body)
        assert m is None, f"{route}: empty label element {m.group(0) if m else ''}"


def test_no_dangling_lead_paragraphs():
    bodies = _bodies()
    for route, body in bodies.items():
        m = DANGLING_LEAD_RE.search(body)
        assert m is None, f"{route}: lead paragraph starts with a dangling separator: {m.group(0) if m else ''}"


def test_area_pages_list_every_section_title_nonempty():
    for path, titles in AREA_TITLES.items():
        body = _bodies()[path]
        for title in titles:
            assert title in body, f"{path} missing section title: {title!r}"
        assert '<span class="req42-title"></span>' not in body


def test_req42_block_leads_are_populated():
    # /req42/functional-requirements is served by functional-requirements.html (its own lead), but scope,
    # models, quality and constraints all go through req42_block.html —
    # exactly the template whose lead paragraph broke in Task 6
    # ("{{ block.en }} — req42-Baustein {{ num }}." rendered with a leading
    # blank and a dangling em-dash). Each must show "<Title> — section
    # <id>." with no gap before the dash.
    for slug, num, title in (
        ("scope", "C3", "Scope &amp; Context"),
        ("models", "R4", "Supporting Models"),
        ("quality", "C1", "Quality Requirements"),
        ("constraints", "C2", "Constraints"),
    ):
        body = app.app.test_client().get(f"/req42/{slug}").get_data(as_text=True)
        assert f"{title} — section {num}." in body, (slug, body[:400])


def test_tile_unit_lines_agree_with_their_numbers():
    """A tile's unit is a lowercase noun pluralised against the tile's own
    count, so a count of 1 is never followed by a plural ("1 Features" was
    the bug). Since FR-019 the unit carries no breakdown."""
    for route in ("/req42", "/commons"):
        body = _bodies()[route]
        pairs = re.findall(r'<span class="num">(\d+)</span><span class="unit">(.*?)</span>', body, re.S)
        assert pairs, body[:400]
        for n, unit in pairs:
            assert unit == unit.lower() and "·" not in unit, (route, n, unit)
            assert unit.endswith("s") != (n == "1"), (route, n, unit)


if __name__ == "__main__":
    test_all_get_routes_render_populated()
    test_no_empty_label_spans()
    test_no_dangling_lead_paragraphs()
    test_area_pages_list_every_section_title_nonempty()
    test_req42_block_leads_are_populated()
    test_tile_unit_lines_agree_with_their_numbers()
    print(f"OK: {len(GET_ROUTES)} routes render on the populated fixture vault; "
          f"no empty labels, no dangling leads, all 18 section titles present on the area pages")
