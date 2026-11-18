"""Keep pytest from running several test scripts in one process.

The tests are plain scripts (README, "Tests"): each one points WIKI_DIR,
WIKI_CONFIG and friends at its own throwaway vault *before* `import app`,
and app.py reads those paths once, at import. In one shared process only the
first script's vault is ever loaded, so every later script tests the wrong
vault and fails in ways that look like real bugs. One script under pytest
(`pytest tests/test_reload.py`) is fine; a whole folder is refused.
"""
import pytest


def pytest_collection_modifyitems(session, config, items):
    modules = {item.module.__name__ for item in items if getattr(item, "module", None)}
    if len(modules) > 1:
        pytest.exit(
            "These tests are separate scripts and cannot share one process "
            "(each sets its own vault before importing app). Run them one "
            "by one, as the dashboard README shows:\n"
            '  for t in tests/test_*.py; do .venv/bin/python "$t" || echo "FAILED: $t"; done',
            returncode=2,
        )
