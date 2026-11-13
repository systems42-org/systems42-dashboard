"""The search index (FR-001): each record carries plain text, aliases, fields
and links, the index root carries the glossary's synonym groups, and
/search.json serves that root. Built from tests/fixtures/search-wiki. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_search_index.py
"""
import os
import sys
import tempfile
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "search-wiki"
_tmp = Path(tempfile.mkdtemp())
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402


def _index() -> dict:
    with app.app.test_request_context():
        return app.build_search_index()


def _rec(page_id: str) -> dict:
    return next(r for r in _index()["records"] if r["id"] == page_id)


def test_plain_drops_link_targets_and_markup():
    plain = _rec("ISS-001")["plain"].lower()           # body: Ask [[STK-023-keyholder|Keyholder]] about the key.
    assert "keyholder" in plain, plain
    assert "stk-023-keyholder" not in plain and "[[" not in plain, plain
    plain = _rec("STK-023")["plain"]
    assert "#" not in plain and "|" not in plain, plain
    assert not plain.startswith("Keyholder"), plain    # the H1 repeats the title
    assert plain.startswith("The person that started the dashboard app."), plain


def test_fields():
    fields = _rec("FR-001")["fields"]
    assert fields["priority"] == ["must"], fields
    assert fields["stereotype"] == ["feature"] and fields["status"] == ["accepted"], fields
    assert _rec("FR-004")["fields"]["tags"] == ["functional-requirement", "navigation"]
    assert "priority" not in _rec("STK-003")["fields"]  # missing keys left out


def test_aliases():
    assert _rec("STK-023")["aliases"] == ["Jedi Master"]
    assert _rec("STK-003")["aliases"] == []


def test_links_both_directions():
    links = _rec("STK-023")["links"]
    assert "ISS-001" in links, links                    # ISS-001 links STK-023
    assert {"GLO-001", "FR-001", "STK-020"} <= set(links), links   # STK-023 links these
    assert "STK-023" not in links


def test_synonyms_from_glossary():
    assert ["facilitator", "moderator"] in _index()["synonyms"], _index()["synonyms"]


def test_search_json_serves_the_index_root():
    data = app.app.test_client().get("/search.json").get_json()
    assert set(data) == {"records", "synonyms"}, set(data)
    rec = next(r for r in data["records"] if r["id"] == "STK-023")
    assert set(rec) == {"id", "type", "title", "status", "url", "aliases", "plain", "fields", "links"}, rec


if __name__ == "__main__":
    test_plain_drops_link_targets_and_markup()
    test_fields()
    test_aliases()
    test_links_both_directions()
    test_synonyms_from_glossary()
    test_search_json_serves_the_index_root()
    print("OK: search index")
