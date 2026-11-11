"""Hamburger menu and footer contract (DR-033). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_menu.py
"""
import os
import re
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
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MENU_ORDER = ["open-settings", "theme-toggle", 'href="/who"', 'href="/help"', "reload-data", "disconnect-all"]


def _get(path):
    return app.app.test_client().get(path).get_data(as_text=True)


def test_menu_on_every_page_in_order():
    for path in ("/", "/issues", "/req42", "/help", "/who"):
        body = _get(path)
        menu = re.search(r'<details class="menu"[^>]*>(.*?)</details>', body, re.S)
        assert menu, path
        pos = [menu.group(1).index(k) for k in MENU_ORDER]
        assert pos == sorted(pos), (path, pos)
        assert re.search(r'<button[^>]*id="disconnect-all"[^>]*\bhidden', menu.group(1)), path


def test_footer_lost_its_buttons_and_says_wiki_dashboard():
    body = _get("/issues")
    foot = re.search(r'<footer class="foot">(.*?)</footer>', body, re.S).group(1)
    assert "<button" not in foot, foot
    assert "Read-only dashboard for Systems42" in foot and "Karpathy" not in foot
    assert 'href="/help#llm-wiki"' in foot
    assert 'id="llm-wiki"' in _get("/help")
    for href in ('href="/metamodel"', 'href="/help"'):
        assert href in foot, href
    # Content links belong to the header and are not repeated in the footer.
    for href in ('href="/req42"', 'href="/arc42"', 'href="/commons"', 'href="/glossary"',
                 'href="/decisions"'):
        assert href not in foot, href
    assert "python-logo.svg" in foot and "Flask" in foot


def test_settings_dialog_and_script_are_wired():
    body = _get("/")
    assert '<dialog id="settings-dialog"' in body
    assert 'id="settings-form"' in body and 'id="settings-save"' in body
    assert "settings.js" in body
    js = (ROOT / "static" / "settings.js").read_text(encoding="utf-8")
    assert '"/settings"' in js and "etsu-client-id" in js and "dataset.facilitator" in js
    base = (ROOT / "templates" / "base.html").read_text(encoding="utf-8")
    assert "dataset.facilitator" in base


if __name__ == "__main__":
    test_menu_on_every_page_in_order()
    test_footer_lost_its_buttons_and_says_wiki_dashboard()
    test_settings_dialog_and_script_are_wired()
    print("OK: menu")
