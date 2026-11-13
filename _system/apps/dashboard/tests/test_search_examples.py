"""Search examples on a fixed test wiki (FR-001): every success-metric query of
FR-002 to FR-008 runs through static/search-rank.js under node, against the
index app.py builds from tests/fixtures/search-wiki. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_search_examples.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_DASH = Path(__file__).resolve().parent.parent
_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "search-wiki"
_tmp = Path(tempfile.mkdtemp())
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(_DASH))

import app  # noqa: E402

HARNESS = Path(__file__).resolve().parent / "search_harness.js"
_INDEX = None


def _index_json() -> str:
    global _INDEX
    if _INDEX is None:
        with app.app.test_request_context():
            _INDEX = json.dumps(app.build_search_index())
    return _INDEX


def run_query(q: str) -> list[dict]:
    """Rank the fixture wiki against `q`; returns [{id, score, note}] best first."""
    out = subprocess.run(["node", str(HARNESS), q], input=_index_json(),
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def js(expr: str):
    """Evaluate `expr` with static/search-rank.js loaded; returns its JSON value."""
    src = (_DASH / "static" / "search-rank.js").read_text(encoding="utf-8")
    script = ("var window = {};\n" + src + "\nvar S = window.S42Search;\n"
              "console.log(JSON.stringify(" + expr + "));")
    out = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def kind(q: str, w: str):
    m = js(f"S.matchWord({json.dumps(q)}, {json.dumps(w)})")
    return m and m["kind"]


def ids(q: str) -> list[str]:
    return [h["id"] for h in run_query(q)]


def hit(q: str, page_id: str) -> dict:
    return next(h for h in run_query(q) if h["id"] == page_id)


# --- FR-002 typos and word forms --------------------------------------------

def test_keyholder_exact_first():
    assert ids("keyholder")[0] == "STK-023", ids("keyholder")


def test_fr002_typo_keyholdr():
    assert "STK-023" in ids("keyholdr")[:3], ids("keyholdr")


def test_fr002_typo_stakholdrs():
    top = ids("stakholdrs")[:3]
    assert any(i.startswith("STK-") for i in top), top


def test_fr002_word_form_requirement_engineer():
    assert "STK-003" in ids("requirement engineer")[:3], ids("requirement engineer")


def test_fr002_id_prefix():
    assert sorted(ids("STK-02")[:4]) == ["STK-020", "STK-021", "STK-022", "STK-023"], ids("STK-02")


def test_fr002_exact_above_typo():
    found = ids("test")
    assert "FR-003" in found and "FR-002" in found, found          # test page, text page
    assert found.index("FR-003") < found.index("FR-002"), found


def test_fr002_match_word_rules():
    assert kind("keyholder", "keyholder") == "exact"
    assert kind("requirement", "requirements") == "form"
    assert kind("starts", "started") == "form"
    assert kind("keyhol", "keyholder") == "prefix"
    assert kind("keyholdr", "keyholder") == "typo"            # 8 letters: up to 2
    assert kind("stakholdrs", "stakeholders") == "typo"
    assert kind("tset", "test") == "typo"                     # swapped letters count once
    assert kind("tst", "test") is None                        # 3 letters: exact or prefix only
    assert kind("app", "apple") == "prefix"
    assert kind("stk-02", "stk-023") == "prefix"
    assert kind("stk-024", "stk-023") is None                 # IDs: no tolerance
    assert kind("trainer", "trainers") == "form"
    assert kind("trainer", "brainer") == "typo"               # 7 letters: 1
    assert kind("trainer", "bxainer") is None
    assert kind("ärztn", "ärztin") == "typo"


def test_fr002_stem():
    assert js('["started", "starts", "requirements", "boxes", "uses", "using", "is"].map(S.stem)') == \
        ["start", "start", "requirement", "box", "use", "using", "is"]


def test_fr002_exact_beats_typo_in_any_place():
    found = ids("test")
    assert found.index("FR-003") < found.index("FR-006"), found     # body "test" above title "Text tools"
    recs = [{"id": "A-1", "type": "Issue", "title": "Mist", "aliases": [], "plain": "", "fields": {}},
            {"id": "B-1", "type": "Issue", "title": "Other", "aliases": [], "plain": "",
             "fields": {"priority": ["must"]}},
            {"id": "C-1", "type": "Issue", "title": "Other", "aliases": [], "plain": "Musts and more", "fields": {}}]
    ranked = js(f'S.rank({json.dumps(recs)}, "must", []).map(function (h) {{ return [h.rec.id, h.score]; }})')
    assert [i for i, _ in ranked] == ["B-1", "C-1", "A-1"], ranked   # exact field, word form, typo title
    assert ranked[0][1] > ranked[1][1] > ranked[2][1], ranked


def test_fr002_typo_tie_prefers_same_first_letter():
    found = ids("seach")
    assert found.index("FR-007") < found.index("FR-009"), found     # Search the wiki above Reach


def test_fr002_stem_typo_uses_the_stem_length():
    assert "FR-009" not in ids("searches"), ids("searches")         # search → reach is 2 edits, 6 letters allow 1


def test_fr002_non_ascii_typo():
    assert "STK-022" in ids("ärztn"), ids("ärztn")                 # Ärztin, one letter missing


# --- FR-003 aliases and glossary synonyms ------------------------------------

def test_fr003_alias():
    assert "STK-023" in ids("Jedi Master")[:3], ids("Jedi Master")


def test_fr003_alias_below_exact_title():
    recs = [{"id": "STK-001", "type": "Stakeholder", "title": "Keyholder", "aliases": ["Jedi Master"], "plain": ""},
            {"id": "STK-002", "type": "Stakeholder", "title": "Jedi Master", "aliases": [], "plain": ""}]
    ranked = js(f'S.rank({json.dumps(recs)}, "jedi master", []).map(function (h) {{ return [h.rec.id, h.score]; }})')
    assert [i for i, _ in ranked] == ["STK-002", "STK-001"], ranked
    assert ranked[0][1] > ranked[1][1], ranked
    assert hit("Jedi Master", "STK-023")["score"] < 100


def test_fr003_synonym_group_works_both_ways():
    assert "GLO-001" in ids("moderator")                           # the term's own alias
    assert "STK-023" in ids("moderator")                           # says "facilitator" in its body
    assert "GLO-001" in ids("facilitator")


def test_fr003_glossary_alias():
    assert "FR-001" in ids("moderator")[:3], ids("moderator")      # FR-001 says only "facilitator"


# --- FR-004 question-style queries ---------------------------------------------

def test_fr004_question():
    assert "STK-023" in ids("who starts the app")[:3], ids("who starts the app")


def test_fr004_partial_below_full():
    hits = run_query("keyholder workshop")
    found = [h["id"] for h in hits]
    assert found[0] == "STK-023", found                            # the only page with both words
    for one in ("ISS-001", "STK-021", "FR-001"):
        assert one in found, (one, found)
        assert hit("keyholder workshop", one)["note"] == "matches 1 of 2 words", hits


def test_fr004_partial_after_every_full_hit():
    recs = [{"id": "A-1", "type": "Issue", "title": "Keyholder", "aliases": [], "plain": ""},
            {"id": "B-1", "type": "Issue", "title": "Other", "aliases": [], "plain": "keyholder and workshop"},
            {"id": "C-1", "type": "Issue", "title": "Workshop keys", "aliases": [], "plain": ""}]
    ranked = js(f'S.rank({json.dumps(recs)}, "keyholder workshop", [])'
                '.map(function (h) { return [h.rec.id, h.score, h.note]; })')
    assert [r[0] for r in ranked][0] == "B-1", ranked              # both words, in the body only
    assert all(r[2] == "matches 1 of 2 words" for r in ranked[1:]), ranked
    assert ranked[0][1] > max(r[1] for r in ranked[1:]), ranked     # the score agrees with the order


def test_fr004_filler_words_dropped():
    assert ids("who starts the app")[:1] == ["STK-023"], ids("who starts the app")
    assert hit("what is the keyholder", "STK-023")["note"] is None   # filler words don't count as missing


def test_fr004_only_filler_words():
    assert run_query("the a"), "a query of filler words alone still finds pages"


# --- FR-005 reason for every non-exact hit -----------------------------------

def test_fr005_notes():
    assert hit("keyholdr", "STK-023")["note"] == "typo: keyholdr → Keyholder"
    assert hit("who starts the app", "STK-023")["note"] == "word form: starts → started"
    assert hit("Jedi Master", "STK-023")["note"] == "via alias of Keyholder"
    assert hit("moderator", "FR-001")["note"] == "via alias of Facilitator"
    assert hit("requirement engineer", "STK-003")["note"].startswith("word form: requirement → ")


def test_fr005_no_note_on_exact_hits():
    assert hit("keyholder", "STK-023")["note"] is None
    assert hit("STK-02", "STK-020")["note"] is None
    assert hit("test", "FR-003")["note"] is None


# --- FR-006 tags and fields ----------------------------------------------------

def test_fr006_priority_must():
    found = ids("Must")
    assert "FR-001" in found and "FR-002" in found, found


def test_fr006_tag_between_title_and_body():
    found = ids("navigation")
    title, tag, body = found.index("GLO-002"), found.index("FR-004"), found.index("FR-005")
    assert title < tag < body, found


# --- FR-007 highlighted passage on /search -----------------------------------

def passages(q: str) -> dict[str, str]:
    """/search's passage per hit: {id: html}."""
    expr = (f"(function () {{ var ix = {_index_json()}; var o = {{}};"
            f" S.rank(ix.records, {json.dumps(q)}, ix.synonyms).forEach(function (h) {{"
            " o[h.rec.id] = S.passage(h); }); return o; })()")
    return js(expr)


def test_fr007_body_hit_shows_marked_sentence():
    ps = passages("facilitator")
    assert ps["STK-023"] == ('<p class="hit-passage">Works with the <mark>facilitator</mark>'
                             ' in every workshop.</p>'), ps["STK-023"]
    assert "<mark>facilitator</mark>" in ps["FR-001"], ps
    for q in ("person", "start", "session"):                         # body-only queries: every hit is marked
        for page_id, html in passages(q).items():
            assert html.startswith('<p class="hit-passage">') and "<mark>" in html, (q, page_id, html)


def test_fr007_title_hit_shows_first_sentence():
    assert passages("facilitator")["GLO-001"] == '<p class="hit-passage">Person who guides a session.</p>'


def test_fr007_passage_is_escaped():
    rec = {"id": "X-1", "type": "Issue", "title": "X", "aliases": [], "fields": {},
           "plain": "Use <script> & a facilitator."}
    html = js(f"S.passage(S.rank([{json.dumps(rec)}], 'facilitator', [])[0])")
    assert "&lt;script&gt; &amp; a <mark>facilitator</mark>." in html, html


def test_fr007_only_on_the_results_page():
    popup = (_DASH / "static" / "search-popup.js").read_text(encoding="utf-8")
    page = (_DASH / "templates" / "search.html").read_text(encoding="utf-8")
    assert "passage" not in popup
    assert "S42Search.passage(" in page


# --- FR-008 related pages on /search -----------------------------------------

def related(q: str) -> list[dict]:
    """/search's "Related pages" group: [{id, note}]."""
    expr = (f"(function () {{ var ix = {_index_json()};"
            f" var hits = S.rank(ix.records, {json.dumps(q)}, ix.synonyms);"
            " return S.related(hits, ix.records).map(function (r) { return {id: r.rec.id, note: r.note}; });"
            " })()")
    return js(expr)


def test_fr008_neighbours_of_a_title_hit():
    rel = related("keyholder")
    hits = ids("keyholder")
    assert 1 <= len(rel) <= 5, rel
    assert not {r["id"] for r in rel} & set(hits), (rel, hits)      # never repeats a hit
    assert all(r["note"] == "linked from STK-023" for r in rel), rel
    assert len(rel) == 5                                            # STK-023 has 6 neighbours that are no hit


def test_fr008_alias_hit_counts_body_hit_does_not():
    assert {r["id"] for r in related("jedi master")} >= {"FR-001", "GLO-001"}
    assert related("ask") == []                                     # ISS-001 says "ask" only in its body


def test_fr008_only_on_the_results_page():
    popup = (_DASH / "static" / "search-popup.js").read_text(encoding="utf-8")
    page = (_DASH / "templates" / "search.html").read_text(encoding="utf-8")
    assert "related" not in popup
    assert 'class="related-pages"' in page and "S42Search.related(" in page
    assert page.index('id="search-results"') < page.index('class="related-pages"')   # below the hits


# --- FR-009 filters on /search -------------------------------------------------

def filtered(q: str, **f) -> list[str]:
    expr = (f"(function () {{ var ix = {_index_json()};"
            f" return S.filter(S.rank(ix.records, {json.dumps(q)}, ix.synonyms), {json.dumps(f)})"
            ".map(function (h) { return [h.rec.id, h.rec.status]; }); })()")
    return js(expr)


def test_fr009_status_filter_leaves_only_that_status():
    everything = run_query("the")
    assert {h["id"] for h in everything} > {i for i, _ in filtered("the", status="accepted")}
    rows = filtered("the", status="accepted")
    assert rows and all(s == "accepted" for _, s in rows), rows


def test_fr009_priority_and_tag_filters():
    assert sorted(i for i, _ in filtered("the", priority="must")) == ["FR-001", "FR-002"]
    assert [i for i, _ in filtered("every", tag="navigation")] == ["FR-004"]
    assert [i for i, _ in filtered("every", tag="navigation", status="accepted")] == []   # filters combine
    assert len(filtered("the")) == len(run_query("the"))                                  # no filter, no change


def test_fr009_filters_sit_next_to_the_type_facets():
    page = app.app.test_client().get("/search").get_data(as_text=True)
    bar = page[page.index('class="toolbar"'):page.index('class="table-card"')]
    for name in ("status", "priority", "tag"):
        assert f'id="search-{name}"' in bar, name
    for value in ("accepted", "draft", "open", "must", "should", "could", "navigation"):
        assert f'<option value="{value}">' in bar, value
    assert "S42Search.filter(" in page


def test_fr009_no_filter_syntax_in_the_box():
    assert ids("status:draft") == ids("status draft")             # the colon is only a word break


TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_")]

if __name__ == "__main__":
    if not shutil.which("node"):
        print("skip: node not installed")
        sys.exit(0)
    failed = 0
    for t in TESTS:
        try:
            t()
        except Exception as e:  # noqa: BLE001 — report every failing example, not just the first
            failed += 1
            print(f"FAIL {t.__name__}: {type(e).__name__} {e}")
    if failed:
        sys.exit(1)
    print(f"OK: search examples ({len(TESTS)})")
