"""Incremental search: /search.json serves the index, every page loads the
shared ranker and the popup, and static/search-rank.js ranks title hits above
body hits (checked under node when it is installed). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_search_popup.py
"""
import json
import os
import re
import shutil
import subprocess
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
(_tmp / "sources").mkdir()
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
_DASH = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_DASH))

import app  # noqa: E402

PAGE = """---
id: {id}
type: {type}
title: "{title}"
status: draft
---

{body}
"""


def _write(folder, stem, **kw):
    f = _wiki / folder / f"{stem}.md"
    f.write_text(PAGE.format(**kw), encoding="utf-8")
    return f


def test_index_endpoint():
    _write("glossary", "GLO-001-training", id="GLO-001", type="glossary-term",
           title="Training", body="Ein Training führt zur Prüfung.")
    app._PARSE_CACHE.clear()
    r = app.app.test_client().get("/search.json")
    assert r.status_code == 200 and r.is_json
    data = r.get_json()
    assert set(data) == {"records", "synonyms"}, set(data)
    rec = next(x for x in data["records"] if x["id"] == "GLO-001")
    assert {"id", "type", "title", "status", "url", "aliases", "plain", "fields", "links"} <= set(rec), rec
    assert rec["url"] == "/page/glossary/GLO-001-training"
    assert "Prüfung" in rec["plain"]
    assert ["training"] in data["synonyms"]


def test_every_page_loads_ranker_and_popup():
    body = app.app.test_client().get("/").get_data(as_text=True)
    assert "search-rank.js" in body and "search-popup.js" in body
    assert body.index("search-rank.js") < body.index("search-popup.js")   # popup needs the ranker
    page = app.app.test_client().get("/search").get_data(as_text=True)
    assert len(re.findall(r'<script src="[^"]*search-rank\.js', page)) == 1  # base only, not twice


def test_ranker_title_before_body():
    if not shutil.which("node"):
        print("skip: node not installed")
        return
    recs = [
        {"id": "ISS-001", "type": "Issue", "title": "Unklar", "plain": "Es geht um Training."},
        {"id": "GLO-001", "type": "Glossary term", "title": "Training", "plain": ""},
        {"id": "UC-001", "type": "Use case", "title": "Trainingstermin einreichen", "plain": ""},
        {"id": "STK-001", "type": "Stakeholder", "title": "Anbieter", "plain": "Bietet an."},
    ]
    js = (_DASH / "static" / "search-rank.js").read_text(encoding="utf-8")
    script = ("var window = {};\n" + js +
              "\nconsole.log(JSON.stringify(window.S42Search.rank(" + json.dumps(recs) +
              ", 'Training').map(function (h) { return [h.rec.id, h.score]; })));")
    out = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout
    ranked = json.loads(out)
    assert [i for i, _ in ranked] == ["GLO-001", "UC-001", "ISS-001"], ranked   # exact, prefix, body; no STK
    assert ranked[0][1] == 100 and ranked[1][1] == 92 and ranked[2][1] < 55, ranked


def test_reason_note_rendered_in_popup_and_page():
    """FR-005: both result lists have a place for the reason of a non-exact hit."""
    popup = (_DASH / "static" / "search-popup.js").read_text(encoding="utf-8")
    page = (_DASH / "templates" / "search.html").read_text(encoding="utf-8")
    assert 'class="hit-note"' in popup, "popup renders no reason note"
    assert 'class="hit-note"' in page, "/search renders no reason note"
    css = (_DASH / "static" / "style.css").read_text(encoding="utf-8")
    assert ".hit-note" in css


if __name__ == "__main__":
    test_index_endpoint()
    test_reason_note_rendered_in_popup_and_page()
    test_every_page_loads_ranker_and_popup()
    test_ranker_title_before_body()
    print("OK: search popup")
