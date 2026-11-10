"""Every test script that imports app points DASHBOARD_CONFIG away from the
project's own settings file first. No pytest.

Without DASHBOARD_CONFIG, app.py falls back to the repository's
`_system/dashboard.yaml` — the hide list the Configure dialog last wrote. In a
project that hides sections (say `hidden: [R5, R6, C6]`) a test asserting on a
hidden tile fails for reasons that have nothing to do with the code, and only
in that project. Run in one process, a script that leaves the variable unset
also inherits whatever hide list the previous script set up.

The fix is one line per script, set before `import app` because the path is
resolved at import time. This test keeps it that way for the next script too.

Run from the dashboard dir:
    .venv/bin/python tests/test_config_isolation.py
"""
import re
import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parent
_IMPORT_RE = re.compile(r"^(?:import app\b|from app import)", re.MULTILINE)
_SET_RE = re.compile(r'^os\.environ\["DASHBOARD_CONFIG"\]\s*=', re.MULTILINE)


def _importers() -> list[Path]:
    return [p for p in sorted(TESTS.glob("test_*.py"))
            if _IMPORT_RE.search(p.read_text(encoding="utf-8"))]


def test_scripts_found():
    assert len(_importers()) >= 10, "expected the app-importing test scripts; glob broken?"


def test_dashboard_config_set_before_import_app():
    bad = []
    for p in _importers():
        src = p.read_text(encoding="utf-8")
        imp = _IMPORT_RE.search(src)
        cfg = _SET_RE.search(src)
        if not cfg or cfg.start() > imp.start():
            bad.append(p.name)
    assert not bad, ("set os.environ[\"DASHBOARD_CONFIG\"] to a temp or absent "
                     f"file before `import app` in: {', '.join(bad)}")


if __name__ == "__main__":
    test_scripts_found()
    test_dashboard_config_set_before_import_app()
    print(f"OK: config isolation ({len(_importers())} scripts)")
