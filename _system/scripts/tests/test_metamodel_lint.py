"""The metamodel (DR-035) and its consumers — templates, wiki folders,
anchors — must agree. `_system/scripts/metamodel-lint.py`
diffs them; this test just runs it so the drift shows up with the other
contract tests. No pytest dependency.

Run from the repository root:
    python3 _system/scripts/tests/test_metamodel_lint.py
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
LINT = Path("_system") / "scripts" / "metamodel-lint.py"


def test_metamodel_lint_passes():
    r = subprocess.run([sys.executable, str(REPO / LINT)],
                       capture_output=True, text=True, cwd=REPO)
    assert r.returncode == 0, r.stdout + r.stderr
    print(r.stdout.strip())


def test_broken_input_is_a_finding_not_a_crash():
    # a copy of the files the lint reads, then broken on purpose: a template
    # without frontmatter, no wiki/, no Agile notation, a block declared twice
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("_system/metamodel", "_system/anchors", "_templates"):
            shutil.copytree(REPO / rel, root / rel)
        for rel in (LINT, LINT.with_name("fr_hierarchy.py")):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, root / rel)
        (root / "_templates" / "goal.md").write_text("# no frontmatter\n", encoding="utf-8")
        (root / "_system" / "metamodel" / "notations" / "notation-agile.md").unlink()
        fw = root / "_system" / "metamodel" / "frameworks" / "fw-commons.md"
        fw.write_text(fw.read_text(encoding="utf-8").replace(
            "blocks:\n", "blocks:\n  - {id: R3, title: Functional Requirements, types: [], scope: in}\n", 1),
            encoding="utf-8")
        r = subprocess.run([sys.executable, str(root / LINT)], capture_output=True, text=True, cwd=root)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "Traceback" not in r.stderr, r.stderr
    assert "_templates/goal.md has no frontmatter" in r.stdout, r.stdout
    assert "block R3 is declared by both" in r.stdout, r.stdout


def _lint_copy(setup) -> subprocess.CompletedProcess:
    """Run the lint on a copy of the schema plus whatever `setup(root)` adds."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("_system/metamodel", "_system/anchors", "_templates"):
            shutil.copytree(REPO / rel, root / rel)
        for rel in (LINT, LINT.with_name("fr_hierarchy.py")):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, root / rel)
        (root / "wiki" / "functional-requirements").mkdir(parents=True)
        (root / "_system" / "notations").mkdir()
        setup(root)
        return subprocess.run([sys.executable, str(root / LINT)], capture_output=True, text=True, cwd=root)


def _fr(root: Path, name: str, extra: str) -> None:
    (root / "wiki" / "functional-requirements" / f"{name}.md").write_text(
        f"---\nid: {name[:6]}\ntype: functional-requirement\ntitle: x\n{extra}---\n", encoding="utf-8")


def test_fr_pages_need_notation_level_and_filled_required_fields():
    def setup(root):
        _fr(root, "FR-001-no-notation", "level: story\n")
        _fr(root, "FR-002-empty-actor",
            "notation: use-case\nlevel: sea\nprimary-actor:\nscope-building-block: \"[[BB-001-x]]\"\n")
        _fr(root, "FR-003-actor-on-agile", "notation: agile\nlevel: story\nprimary-actor: \"[[STK-001-x]]\"\n")
        _fr(root, "FR-004-ok", "notation: use-case\nlevel: sea\nprimary-actor: \"[[STK-001-x]]\"\n"
                               "scope-building-block: \"[[BB-001-x]]\"\nbuilding-blocks: [\"[[BB-002-y]]\"]\n")
        # `aliases` is an optional universal field: allowed on any page.
        _fr(root, "FR-005-aliases-ok", "notation: agile\nlevel: story\naliases: [Old title]\n")
    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    out = r.stdout
    assert "FR-001-no-notation.md: notation (missing) is not a notation" in out, out
    assert "FR-002-empty-actor.md: required field primary-actor is missing or empty" in out, out
    assert "FR-003-actor-on-agile.md: field primary-actor is not declared" in out, out
    assert "FR-004-ok" not in out, out
    assert "FR-005-aliases-ok" not in out, out


def test_custom_notation_with_level_scoped_anchors():
    custom = """---
type: metamodel
construct: notation
name: custom-theme-story
title: Theme and story
extends: functional-requirement
levels: [theme, story]
fields: []
anchors:
  - user-story-format
  - {name: INVEST, levels: [story]}
  - {name: acceptance-criteria, levels: [epic]}
---

# {{title}}

<!-- levels: theme, story -->
## Story

<!-- levels: feature -->
**Scope.**
"""

    def setup(root):
        (root / "_system" / "notations" / "custom-theme-story.md").write_text(custom, encoding="utf-8")
        _fr(root, "FR-001-story-under-theme", "notation: custom-theme-story\nlevel: story\n")
    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    assert "anchor acceptance-criteria names unknown level epic" in r.stdout, r.stdout
    assert "body marker names unknown level feature" in r.stdout, r.stdout
    assert "FR-001-story-under-theme" not in r.stdout, r.stdout


def test_domain_terms_enforce_the_structure_contract():
    def setup(root):
        folder = root / "wiki/domain-terms"
        folder.mkdir()
        for name, fields in {
            "DT-003-self": 'stereotype: entity\nrelationships: [{to: "[[DT-003-self]]", kind: generalization}]\n',
            "DT-001-plain": "attributes: [{name: key}]\n",
            "DT-002-model": 'stereotype: value-object\nparent: ["[[DT-001-plain]]"]\n'
                            'attributes: [{name: key, identifier: true}]\n'
                            'relationships: [{to: "[[DT-001-plain]]", kind: generalization, multiplicity: "1"}]\n',
        }.items():
            (folder / f"{name}.md").write_text(
                f"---\nid: {name[:6]}\ntype: domain-term\ntitle: {name}\n{fields}---\n", encoding="utf-8")

    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    for message in ("structured fields require a stereotype",
                    "only entities can have identifier attributes",
                    "relationship target must resolve to a structured domain term",
                    "parent must resolve to another domain term with stereotype sum-type",
                    "a term cannot generalize itself",
                    "generalization does not carry multiplicity"):
        assert message in r.stdout, r.stdout


def test_delivery_states_per_notation_and_strict_timestamps():
    ok = "delivery-checked: 2026-10-28T10:00:00+01:00\n"
    def setup(root):
        _fr(root, "FR-001-partial-story", "notation: agile\nlevel: story\ndelivery: partial\n" + ok)
        _fr(root, "FR-002-partial-use-case", "notation: use-case\nlevel: sea\nprimary-actor: \"[[STK-001-x]]\"\n"
                                            "scope-building-block: \"[[BB-001-x]]\"\ndelivery: partial\n" + ok)
        _fr(root, "FR-003-date-only", "notation: agile\nlevel: story\ndelivery: implemented\n"
                                     "delivery-checked: 2026-10-28\n")
        _fr(root, "FR-004-no-zone", "notation: agile\nlevel: story\ndelivery: implemented\n"
                                   "delivery-checked: 2026-10-28T12:00:00\n")
        _fr(root, "FR-005-epic", "notation: agile\nlevel: epic\ndelivery: implemented\n" + ok)
    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    out = r.stdout
    assert "FR-001-partial-story.md: delivery partial is not allowed in notation agile" in out, out
    assert "FR-002-partial-use-case" not in out, out
    assert "FR-003-date-only.md: delivery-checked must be an ISO 8601 timestamp with time and timezone" in out, out
    assert "FR-004-no-zone.md: delivery-checked must be an ISO 8601 timestamp with time and timezone" in out, out
    assert "FR-005-epic.md: delivery is not allowed at agile level epic" in out, out


def test_use_case_implemented_only_with_its_refining_stories():
    ok = "delivery-checked: 2026-10-28T10:00:00+01:00\n"
    uc = ("notation: use-case\nlevel: sea\nprimary-actor: \"[[STK-001-x]]\"\n"
          "scope-building-block: \"[[BB-001-x]]\"\n")
    def setup(root):
        _fr(root, "UC-001-done", uc + "delivery: implemented\n" + ok)
        _fr(root, "FR-001-story-done", "notation: agile\nlevel: story\nparent: [\"[[UC-001-done]]\"]\n"
                                      "delivery: implemented\n" + ok)
        _fr(root, "UC-002-claims-done", uc + "delivery: implemented\n" + ok)
        _fr(root, "FR-002-story-unchecked", "notation: agile\nlevel: story\nparent: [\"[[UC-002-claims-done]]\"]\n")
        _fr(root, "FR-003-feature-empty", "notation: agile\nlevel: feature\nparent: [\"[[UC-002-claims-done]]\"]\n")
        _fr(root, "UC-003-partial", uc + "delivery: partial\n" + ok)
        _fr(root, "FR-004-story-open", "notation: agile\nlevel: story\nparent: [\"[[UC-003-partial]]\"]\n")
    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    out = r.stdout
    assert "UC-001-done" not in out, out
    assert "UC-002-claims-done.md: delivery implemented, but refining story FR-002-story-unchecked is without delivery" in out, out
    assert "UC-002-claims-done.md: delivery implemented, but refining FR-003-feature-empty has no stories" in out, out
    assert "UC-003-partial" not in out, out


def test_use_case_delivery_ignores_withdrawn_stories_and_resolves_path_links():
    ok = "delivery-checked: 2026-10-28T10:00:00+01:00\n"
    uc = ("notation: use-case\nlevel: sea\nprimary-actor: \"[[STK-001-x]]\"\n"
          "scope-building-block: \"[[BB-001-x]]\"\n")
    def setup(root):
        _fr(root, "UC-001-done", uc + "delivery: implemented\n" + ok)
        _fr(root, "FR-001-story-done", "notation: agile\nlevel: story\nparent: [\"[[UC-001-done]]\"]\n"
                                      "delivery: implemented\n" + ok)
        _fr(root, "FR-002-story-withdrawn", "notation: agile\nlevel: story\nstatus: deprecated\n"
                                          "parent: [\"[[UC-001-done]]\"]\ndelivery: removed\n" + ok)
        _fr(root, "UC-003-live-removed", uc + "delivery: implemented\n" + ok)
        _fr(root, "FR-004-story-removed-but-valid", "notation: agile\nlevel: story\nstatus: accepted\n"
                                                    "parent: [\"[[UC-003-live-removed]]\"]\ndelivery: removed\n" + ok)
        _fr(root, "UC-002-pathy", uc + "delivery: implemented\n" + ok)
        _fr(root, "FR-003-story-unchecked", "notation: agile\nlevel: story\n"
                                           "parent: [\"[[wiki/functional-requirements/UC-002-pathy|x]]\"]\n")
    r = _lint_copy(setup)
    assert "Traceback" not in r.stderr, r.stderr
    assert "UC-001-done" not in r.stdout, r.stdout
    assert "UC-003-live-removed.md: delivery implemented, but refining story FR-004-story-removed-but-valid is removed" in r.stdout, r.stdout
    assert "UC-002-pathy.md: delivery implemented, but refining story FR-003-story-unchecked" in r.stdout, r.stdout


if __name__ == "__main__":
    test_domain_terms_enforce_the_structure_contract()
    test_metamodel_lint_passes()
    test_broken_input_is_a_finding_not_a_crash()
    test_fr_pages_need_notation_level_and_filled_required_fields()
    test_custom_notation_with_level_scoped_anchors()
    test_delivery_states_per_notation_and_strict_timestamps()
    test_use_case_implemented_only_with_its_refining_stories()
    test_use_case_delivery_ignores_withdrawn_stories_and_resolves_path_links()
    print("ALL PASSED")
