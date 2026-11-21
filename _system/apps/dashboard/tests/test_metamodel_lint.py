"""The metamodel (DR-035) and its consumers — templates, wiki folders,
anchors — must agree. `_system/scripts/metamodel-lint.py` diffs them; this
test runs it so the drift shows up with the other contract tests. The lint
is part of the method and needs no dashboard code (CON-006, ISS-005). No
pytest dependency.

Run from the dashboard dir:
    .venv/bin/python tests/test_metamodel_lint.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
LINT = Path("_system") / "scripts" / "metamodel-lint.py"


def test_metamodel_lint_passes():
    r = subprocess.run([sys.executable, str(REPO / LINT)],
                       capture_output=True, text=True, cwd=REPO)
    assert "Traceback" not in r.stderr, r.stdout + r.stderr
    assert r.returncode == 0, r.stdout + r.stderr
    print(r.stdout.strip())


def test_the_lint_needs_no_dashboard_code():
    # it imports no dashboard module, and passes on a copy without _system/apps/
    assert "catalog" not in (REPO / LINT).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("_system/metamodel", "_system/anchors", "_templates", "wiki"):
            shutil.copytree(REPO / rel, root / rel)
        (root / "raw" / "sources").mkdir(parents=True)
        (root / LINT).parent.mkdir(parents=True)
        shutil.copy(REPO / LINT, root / LINT)
        r = subprocess.run([sys.executable, str(root / LINT)], capture_output=True, text=True, cwd=root)
    assert r.returncode == 0 and "Traceback" not in r.stderr, r.stdout + r.stderr


def test_broken_input_is_a_finding_not_a_crash():
    # a copy of the files the lint reads, then broken on purpose: a template
    # without frontmatter, no wiki/, no altitude.md, a block declared twice
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("_system/metamodel", "_system/anchors", "_templates"):
            shutil.copytree(REPO / rel, root / rel)
        (root / LINT).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO / LINT, root / LINT)
        (root / "_templates" / "goal.md").write_text("# no frontmatter\n", encoding="utf-8")
        (root / "_system" / "metamodel" / "altitude.md").unlink()
        fw = root / "_system" / "metamodel" / "frameworks" / "fw-commons.md"
        fw.write_text(fw.read_text(encoding="utf-8").replace(
            "blocks:\n", "blocks:\n  - {id: R3, title: Functional Requirements, types: [], scope: in}\n", 1),
            encoding="utf-8")
        r = subprocess.run([sys.executable, str(root / LINT)], capture_output=True, text=True, cwd=root)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "Traceback" not in r.stderr, r.stderr
    assert "_templates/goal.md has no frontmatter" in r.stdout, r.stdout
    assert "block R3 is declared by both" in r.stdout, r.stdout


if __name__ == "__main__":
    test_metamodel_lint_passes()
    test_the_lint_needs_no_dashboard_code()
    test_broken_input_is_a_finding_not_a_crash()
    print("ALL PASSED")
