"""/method explains the three loops on one screen (FR-011). No pytest.

Capture, inspect and clarify each get a headed part, and one part says how
they feed each other. Clarify has no definition yet: the page says so and
links ISS-002 while that issue is open. Every page's footer links /method.

Run from the dashboard dir:
    .venv/bin/python tests/test_method.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "goals", "domain-terms"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import wiki  # noqa: E402

ISSUE = """---
id: ISS-002
type: issue
title: Define the clarify loop
status: {status}
created: 2026-11-11
updated: 2026-11-12
sources: []
related: []
tags: [issue]
---

# Define the clarify loop
"""
ISSUE_PATH = _wiki / "issues" / "ISS-002-define-the-clarify-loop.md"
LINK = '<a href="/page/issues/ISS-002-define-the-clarify-loop">ISS-002 Define the clarify loop</a>'


def _method():
    wiki._PARSE_CACHE.clear()
    r = app.app.test_client().get("/method")
    assert r.status_code == 200, r.status_code
    body = r.get_data(as_text=True)
    return body[body.index('<article class="help-prose">'):body.index("</article>")]


def test_three_loops_on_one_screen():
    text = _method()
    heads = re.findall(r"<h2>(.*?)</h2>", text)
    assert heads == ["Capture", "Inspect", "Clarify", "How they feed each other"], heads
    plain = " ".join(re.sub(r"<[^>]+>", " ", text).split())
    assert "Capture and inspect feed clarify" in plain and "Clarify feeds the pages" in plain, plain
    words = len(plain.split())
    assert words <= 250, f"{words} words do not fit one screen"


def test_clarify_links_iss_002_while_it_is_open():
    try:
        assert "Being defined by the Systems42 team." in _method()
        assert LINK not in _method(), "no issue page, no link"
        for status in ("open", "in-progress"):
            ISSUE_PATH.write_text(ISSUE.format(status=status), encoding="utf-8")
            assert LINK in _method(), status
        for status in ("resolved", "wontfix"):
            ISSUE_PATH.write_text(ISSUE.format(status=status), encoding="utf-8")
            text = _method()
            assert LINK not in text and "Being defined by the Systems42 team." in text, status
    finally:
        ISSUE_PATH.unlink(missing_ok=True)


def test_a_projects_own_iss_002_is_not_linked():
    """A project numbers its own issues: only the clarify issue's stem counts."""
    other = _wiki / "issues" / "ISS-002-who-pays.md"
    other.write_text(ISSUE.format(status="open").replace("Define the clarify loop", "Who pays"),
                     encoding="utf-8")
    try:
        assert "ISS-002" not in _method()
    finally:
        other.unlink()


def test_every_footer_links_method_next_to_metamodel_and_help():
    c = app.app.test_client()
    for route in ("/", "/req42", "/commons", "/issues", "/help", "/metamodel", "/method"):
        body = c.get(route).get_data(as_text=True)
        foot = body[body.index('<footer class="foot">'):body.index("</footer>")]
        assert '<a href="/method">Method</a> · <a href="/metamodel">Metamodel</a> · <a href="/help">Help</a>' \
            in foot, route


if __name__ == "__main__":
    test_three_loops_on_one_screen()
    test_clarify_links_iss_002_while_it_is_open()
    test_a_projects_own_iss_002_is_not_linked()
    test_every_footer_links_method_next_to_metamodel_and_help()
    print("OK: /method explains the three loops and every footer links it")
