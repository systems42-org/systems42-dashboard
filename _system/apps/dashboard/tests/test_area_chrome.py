"""The area colour bar under the topbar: present on area and section pages,
absent on home, ADRs and help; hidden areas lose it. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_area_chrome.py
"""
import os
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
_cfg = _tmp / "dashboard.yaml"
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_cfg)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402


def _get(path):
    app._PARSE_CACHE.clear()
    return app.app.test_client().get(path).get_data(as_text=True)


def test_bar_on_section_and_area_pages_only():
    if _cfg.exists():
        _cfg.unlink()
    assert 'class="area-bar area-bar-req"' in _get("/goals")           # R1 is org-coloured, but the BAR is the area's
    assert 'class="area-bar area-bar-req"' in _get("/req42/functional-requirements")
    assert 'class="area-bar area-bar-2 area-bar-req area-bar-arc"' in _get("/stakeholders")
    assert 'class="area-bar area-bar-2 area-bar-req area-bar-arc"' in _get("/commons")
    for path in ("/", "/adrs", "/search", "/join"):
        assert 'class="area-bar' not in _get(path), path


def test_hidden_area_has_no_bar_but_still_renders():
    _cfg.write_text("hidden: [commons]\n", encoding="utf-8")
    body = _get("/stakeholders")
    assert 'class="area-bar' not in body
    assert 'class="mainnav"' in body
    _cfg.unlink()


if __name__ == "__main__":
    test_bar_on_section_and_area_pages_only()
    test_hidden_area_has_no_bar_but_still_renders()
    print("OK: area chrome")
