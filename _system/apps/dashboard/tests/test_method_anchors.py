"""Method terms lead to their definition (FR-035). No pytest.

Its own temporary vault and its own anchors folder (ANCHORS_DIR), so the
anchors here are fixed: MADR, PAM (opens with a note, not the definition),
arc42 and the user-story format, plus a README without frontmatter. The
metamodel is the real one, since the anchor entries link to its type rows.

  * /metamodel has one entry per anchor: name, short definition, the types it
    applies to and its outside reference.
  * Every wikilink to an anchor name or alias, in any case, leads to that
    entry, with the definition as its title.
  * A "> follows [[X]]" note is a small "Format: X" label in the page head,
    never a box in the body.

Run from the dashboard dir:
    .venv/bin/python tests/test_method_anchors.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
_anchors = _tmp / "anchors"
for _f in ("decisions", "goals", "building-blocks", "functional-requirements", "stakeholders", "issues"):
    (_wiki / _f).mkdir(parents=True)
_anchors.mkdir()
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["ANCHORS_DIR"] = str(_anchors)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def _anchor(stem, title, aliases, applies, body):
    (_anchors / f"{stem}.md").write_text(
        f"---\ntype: anchor\ntitle: {title}\naliases: [{aliases}]\ntags: [anchor]\n"
        f"applies-to: [{applies}]\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


_anchor("madr", "MADR", "MADR", "decision-record",
        "Markdown Any Decision Records, the record format for a\ndecision record.\n"
        "Reference: <https://adr.github.io/madr/> (MADR 4.x).\n\n**Shape.** Sections in order.")
_anchor("pam", "PAM", "PAM, pam-goals", "goals in stakeholder",
        "> A note about the letter M.\n\nA lightweight goal frame, the alternative to [[SMART]].\n\n- **Purpose**")
_anchor("arc42", "arc42", "arc42, arc42-template", "building blocks",
        "The template for software architecture (<https://arc42.org>).")
_anchor("user-story-format", "User-Story Format", "user-story-format, story-format", "user-story",
        "The canonical shape of a user story.")
(_anchors / "README.md").write_text("# Anchors\n\nNo frontmatter here.\n", encoding="utf-8")


def _page(folder, stem, typ, title, status="draft", extra="", body=""):
    pid = "-".join(stem.split("-")[:2])
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntype: {typ}\ntitle: {title}\nstatus: {status}\n"
        f"created: 2026-11-13\nupdated: 2026-11-13\nsources: []\nrelated: []\ntags: []\n"
        f"{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


_page("decisions", "DR-001-eine-wahl", "decision-record", "Eine Wahl", extra="kind: business\n",
      body="## Kontext\n\n> follows [[MADR]]\n\nDas Format ist [[madr|das Format]], "
           "die Ziele folgen [[pam-goals]], und [[NOPE]] gibt es nicht.\n")
_page("goals", "GOAL-001-vision", "goal", "Vision", extra="stereotype: vision\n",
      body="## Vision\n\n> follows the Geoffrey Moore format\n\nFür Leser.\n")
_page("goals", "GOAL-002-ziel", "goal", "Ziel", extra="stereotype: objective\n",
      body="## Objective\n\n> follows [[PAM]]\n\n- **Purpose.** Etwas.\n\n## Noch einmal\n\n"
           "> follows [[pam]] (again)\n\nText.\n")
_page("building-blocks", "BB-001-kern", "building-block", "Kern", extra="state: target\n",
      body="> follows [[arc42]] (section 5, black box)\n\n## Purpose / Responsibility\n\nDer Kern.\n")
_page("functional-requirements", "FR-001-suche", "functional-requirement", "Suche",
      extra="stereotype: story\n",
      body="## Story\n\n> follows [[user-story-format]]\n\nAs a reader I want to search.\n")

import app  # noqa: E402
import metamodel  # noqa: E402

client = app.app.test_client()


def _get(path):
    resp = client.get(path)
    assert resp.status_code == 200, (path, resp.status_code)
    return resp.get_data(as_text=True)


def _entry(html, slug):
    m = re.search(rf'<(\w+)[^>]*id="anchor-{slug}"[^>]*>(.*?)</\1>', html, re.S)
    assert m, (slug, "no anchor entry")
    return m.group(2)


def _head(html):
    m = re.search(r'<div class="detail-head">(.*?)</div>', html, re.S)
    assert m, "no detail head"
    return m.group(1)


def _labels(html):
    return re.findall(r'class="format-label"[^>]*>Format: ([^<]+)<', _head(html))


# -- the anchors as data ----------------------------------------------------

def test_loader_reads_each_anchor_file():
    got = {a["slug"]: a for a in metamodel.method_anchors()}
    assert set(got) == {"madr", "pam", "arc42", "user-story-format"}, got.keys()
    madr = got["madr"]
    assert madr["id"] == "anchor-madr" and madr["name"] == "MADR"
    assert madr["definition"].startswith("Markdown Any Decision Records, the record format"), madr
    assert "Shape" not in madr["definition"]
    assert madr["reference"] == "https://adr.github.io/madr/"
    assert madr["applies_to"] == ["decision-record"]
    # a note before the definition is not the definition
    assert got["pam"]["definition"].startswith("A lightweight goal frame"), got["pam"]
    assert got["pam"]["reference"] == ""
    assert got["arc42"]["reference"] == "https://arc42.org"


def test_lookup_is_case_insensitive_on_title_and_aliases():
    idx = metamodel.anchor_index(metamodel.method_anchors())
    for key in ("MADR", "madr", "PAM", "pam-goals", "PAM-GOALS", "story-format", "User-Story Format"):
        assert key.lower() in idx, key
    assert idx["pam-goals"]["slug"] == "pam"
    assert "nope" not in idx


# -- the entries on /metamodel ----------------------------------------------

def test_metamodel_page_has_an_entry_per_anchor():
    html = _get("/metamodel")
    assert 'href="#anchors"' in html, "no Anchors link in the page's table of contents"
    madr = _entry(html, "madr")
    assert "MADR" in madr
    assert "Markdown Any Decision Records" in madr
    assert 'href="https://adr.github.io/madr/"' in madr
    # the type it applies to links to that type's row
    assert 'href="#type-decision-record"' in madr, madr
    pam = _entry(html, "pam")
    assert "A lightweight goal frame" in pam
    # a wikilink inside a definition leads to the other anchor's entry, or stays a chip
    assert 'href="#type-goal"' in pam, pam


def test_metamodel_standards_link_to_their_entry():
    html = _get("/metamodel")
    row = re.search(r'<tr id="type-decision-record".*?</tr>', html, re.S).group(0)
    assert 'href="#anchor-madr"' in row, row


# -- links on wiki pages ----------------------------------------------------

def test_anchor_wikilinks_lead_to_their_entry_with_the_definition():
    html = _get("/page/decisions/DR-001-eine-wahl")
    links = re.findall(r'<a class="wl wl-anchor" href="([^"]+)" title="([^"]*)">([^<]+)</a>', html)
    by_label = {label: (href, title) for href, title, label in links}
    assert by_label["das Format"][0] == "/metamodel#anchor-madr", links
    assert by_label["das Format"][1].startswith("Markdown Any Decision Records"), links
    assert by_label["PAM"][0] == "/metamodel#anchor-pam", links
    assert '<span class="wl">NOPE</span>' in html


# -- the "follows" note -----------------------------------------------------

def test_follows_note_is_a_label_in_the_head_not_a_box():
    html = _get("/page/decisions/DR-001-eine-wahl")
    assert _labels(html) == ["MADR"], _head(html)
    assert 'href="/metamodel#anchor-madr"' in _head(html)
    assert "follows" not in re.sub(r"<[^>]+>", "", html.split('class="detail-pane"', 1)[1]).lower()
    assert "<blockquote>" not in html


def test_several_follows_notes_give_one_label_each_deduplicated():
    html = _get("/page/goals/GOAL-002-ziel")
    assert _labels(html) == ["PAM"], _head(html)
    assert "<blockquote>" not in html


def test_follows_note_keeps_its_trailing_note_quietly():
    html = _get("/page/building-blocks/BB-001-kern")
    assert _labels(html) == ["arc42"], _head(html)
    assert "section 5, black box" in _head(html)
    assert "<blockquote>" not in html


def test_follows_note_without_a_link_is_a_plain_label():
    html = _get("/page/goals/GOAL-001-vision")
    assert _labels(html) == ["Geoffrey Moore format"], _head(html)
    assert "<blockquote>" not in html


def test_functional_requirement_page_shows_the_label_too():
    html = _get("/functional-requirements/FR-001-suche")
    assert _labels(html) == ["User-Story Format"], _head(html)
    assert "<blockquote>" not in html


def test_decision_list_shows_no_follows_box():
    html = _get("/decisions")
    assert "<blockquote>" not in html


# -- against the real anchors ------------------------------------------------

def test_every_real_anchor_has_a_definition():
    real = Path(__file__).resolve().parents[3] / "anchors"
    saved = metamodel.ANCHORS_DIR
    metamodel.ANCHORS_DIR = real
    try:
        got = metamodel.method_anchors()
    finally:
        metamodel.ANCHORS_DIR = saved
    assert len(got) >= 10, [a["slug"] for a in got]
    for a in got:
        assert a["definition"], a["slug"]


if __name__ == "__main__":
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"ok   {name}")
        except Exception as e:  # noqa: BLE001  a KeyError is a failure too
            failed += 1
            print(f"FAIL {name}: {type(e).__name__} {str(e)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
