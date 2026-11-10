"""The metamodel (DR-035) and its consumers — templates, wiki folders,
anchors, this dashboard's catalog — must agree. `_system/scripts/metamodel-lint.py`
diffs them; this test just runs it so the drift shows up with the other
contract tests. No pytest dependency.

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
    assert r.returncode == 0, r.stdout + r.stderr
    print(r.stdout.strip())


def test_broken_input_is_a_finding_not_a_crash():
    # a copy of the files the lint reads, then broken on purpose: a template
    # without frontmatter, no wiki/, no altitude.md, a block declared twice
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("_system/metamodel", "_system/anchors", "_templates"):
            shutil.copytree(REPO / rel, root / rel)
        for rel in (LINT, Path("_system/apps/dashboard/catalog.py")):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, root / rel)
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
    test_broken_input_is_a_finding_not_a_crash()
    print("ALL PASSED")
