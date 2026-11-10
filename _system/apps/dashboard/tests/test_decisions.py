"""Decision records (wiki/decisions/, MADR) parse, render and redirect — no pytest.

Two parts. The page, filter and redirect checks run over the fixture vault, so
they hold in every project, including one freshly spawned with `make new`
(which starts with an empty `wiki/decisions/`). The record checks read this
project's own `wiki/decisions/` — whatever is there, possibly nothing — because
a defect in shipped content (a kind outside the enum, a title with raw
markdown, a former-ADR alias that no longer matches the number) shows on
/decisions, not in the parser.

Run from the dashboard dir:
    .venv/bin/python tests/test_decisions.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

PROJECT_WIKI = Path(__file__).resolve().parents[4] / "wiki"
_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"

_tmp = Path(tempfile.mkdtemp())
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402

KNOWN_STATUSES = {"draft", "review", "accepted", "deprecated"}
FIXTURE_STEM = "DR-001-carts-expire-after-a-day"


def _project_decisions():
    """This project's records; the fixture vault is swapped out for the call."""
    saved, app.WIKI_DIR = app.WIKI_DIR, PROJECT_WIKI
    try:
        with app.app.test_request_context():
            return app.load_decisions()
    finally:
        app.WIKI_DIR = saved


# --- this project's records (vacuous in a fresh project) -------------------

def test_every_decision_has_a_known_status_and_kind():
    bad = [(d["id"], d["status"], d["kind"]) for d in _project_decisions()
           if d["status"] not in KNOWN_STATUSES or d["kind"] not in app.DECISION_KINDS]
    assert not bad, f"decisions with an unknown status or kind: {bad}"


def test_every_decision_has_a_decided_date():
    bad = [d["id"] for d in _project_decisions() if d["decided"] in ("", "—")]
    assert not bad, f"decisions without a decided date: {bad}"


def test_no_decision_title_shows_raw_markdown():
    bad = [(d["id"], d["title"]) for d in _project_decisions()
           if "*" in d["title"] or "`" in d["title"]]
    assert not bad, f"decision titles rendering markdown literally: {bad}"


def test_a_former_adr_alias_matches_the_decision_number():
    """A record migrated from an ADR kept its number: ADR-NNNN is DR-NNN."""
    bad = []
    for d in _project_decisions():
        n = int(d["id"].split("-")[1])
        for a in d["aliases"]:
            m = re.fullmatch(r"ADR-(\d{4})", str(a))
            if m and int(m.group(1)) != n:
                bad.append((d["id"], a))
    assert not bad, f"former-ADR aliases that do not match the number: {bad}"


# --- pages over the fixture vault -----------------------------------------

def test_fixture_title_is_plain_text():
    with app.app.test_request_context():
        (d,) = app.load_decisions()
    assert d["title"] == "Carts expire after one day" and d["kind"] == "business", d


def test_decisions_page_lists_records_with_kind_filter():
    body = app.app.test_client().get("/decisions").get_data(as_text=True)
    assert "DR-001" in body and 'data-kind="business"' in body
    for k in ("architecture", "business", "undefined"):
        assert f'data-filter="{k}"' in body, k
    assert 'data-aliases="ADR-0001"' in body


def test_old_adr_urls_redirect():
    c = app.app.test_client()
    r = c.get("/adrs")
    assert r.status_code == 301 and r.headers["Location"].endswith("/decisions")
    r = c.get("/page/adr/0001-carts-expire-after-a-day")
    assert r.status_code == 301
    assert r.headers["Location"].endswith(f"/page/decisions/{FIXTURE_STEM}")
    r = c.get("/page/adr/0010-stakeholder-aliases-field")   # re-filed, no DR
    assert r.status_code == 301 and r.headers["Location"].endswith("/decisions")


def test_decision_detail_page_renders():
    body = app.app.test_client().get(f"/page/decisions/{FIXTURE_STEM}").get_data(as_text=True)
    assert "Considered Options" in body and "Decision Outcome" in body


if __name__ == "__main__":
    test_every_decision_has_a_known_status_and_kind()
    test_every_decision_has_a_decided_date()
    test_no_decision_title_shows_raw_markdown()
    test_a_former_adr_alias_matches_the_decision_number()
    test_fixture_title_is_plain_text()
    test_decisions_page_lists_records_with_kind_filter()
    test_old_adr_urls_redirect()
    test_decision_detail_page_renders()
    print(f"OK: {len(_project_decisions())} project decision records check out; "
          "fixture pages render and redirect")
