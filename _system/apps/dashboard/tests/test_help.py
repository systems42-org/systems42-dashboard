"""The /help page: rendered from help.md, embeds the sections diagram. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_help.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
(_tmp / "wiki").mkdir(); (_tmp / "sources").mkdir()
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def test_help_renders_both_parts_and_the_diagram():
    r = app.app.test_client().get("/help")
    assert r.status_code == 200
    body = r.get_data(as_text=True)
    assert "Reading this dashboard" in body and "The Systems42 model in brief" in body
    assert "systems42-sections.svg" in body
    for word in ("Configure", "facilitator", "Maturity", "valley", "Commons", "req42", "arc42"):
        assert word in body, word
    assert (ROOT / "static" / "systems42-sections.svg").stat().st_size > 1000
    assert "docs/GETTING-STARTED.md" in body


if __name__ == "__main__":
    test_help_renders_both_parts_and_the_diagram()
    print("OK: help")
