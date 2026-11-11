"""Obsidian callouts render as a labelled quote. No pytest.

The regression this guards: a callout with no title on its own line,

    > [!note]
    > The target is a proposal.

rendered its first text line as the bold label, with a stray "> " in front,
because the pattern's `\\s*` ran across the line break.

Run from the dashboard dir:
    .venv/bin/python tests/test_callouts.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
(_tmp / "wiki").mkdir()

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _render(body: str) -> str:
    with app.app.app_context():
        return app.render_markdown(body, {})


def test_a_callout_without_title_gets_its_type_as_label():
    html = _render("> [!note]\n> The target is a proposal.\n")
    assert "<strong>Note</strong>" in html, html
    assert "&gt; The target" not in html, f"stray quote marker: {html}"
    assert "<strong>&gt;" not in html and "<strong>The target" not in html, html
    assert "The target is a proposal." in html, html


def test_a_callout_with_title_keeps_its_title():
    html = _render("> [!note] Open points\n> None.\n")
    assert "<strong>Open points</strong>" in html, html
    assert "None." in html, html


if __name__ == "__main__":
    test_a_callout_without_title_gets_its_type_as_label()
    test_a_callout_with_title_keeps_its_title()
    print("test_callouts: OK")
