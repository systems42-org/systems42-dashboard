"""`_templates/` and `app.py` are two halves of one contract — no pytest.

Frontmatter keys, `TYPE-NNN` ID prefixes and body-structure markers are shared
between the template the agent writes from and the parser the dashboard reads
with. When they drift, nothing raises: Jinja renders Undefined as "", a regex
that matches nothing returns [], and the page comes up looking merely empty.
Three instances of exactly that were found in this repo:

  * `tile_claim:` was read by app.py and declared by no template, so the Vision
    tile's claim line was permanently blank;
  * `_templates/data-model.md` prescribed `- <name> : <type>` while the parser
    required the name in backticks, so /entity-diagram's Attributes column was `—`
    for every entity while the cards below it showed them;
  * `_templates/activity-model.md` emits `ACT-NNN` while app.py's type maps
    said `AM`, so the relations panel showed the raw code `ACT` as a group
    heading and the `AM` entries were dead code.

This suite diffs the two halves instead of trusting a reader to notice.

Run from the dashboard dir:
    .venv/bin/python tests/test_template_contract.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
TEMPLATES = REPO / "_templates"

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import links  # noqa: E402

_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_KEY_RE = re.compile(r"^([a-zA-Z][a-zA-Z0-9_-]*)\s*:", re.MULTILINE)

# `SRC-` records live in raw/sources/, not in the wiki layer, so they carry no
# entry in the wiki type maps (DR-006).
NON_WIKI_PREFIXES = {"SRC"}


def _templates() -> list[Path]:
    files = sorted(TEMPLATES.glob("*.md"))
    assert files, f"no templates found under {TEMPLATES}"
    return files


def _frontmatter(path: Path) -> str:
    m = _FRONTMATTER_RE.match(path.read_text(encoding="utf-8"))
    assert m, f"{path.name} has no frontmatter block"
    return m.group(1)


def test_every_key_app_reads_is_declared_by_some_template():
    """The `tile_claim` failure class: app.py reads a key no template mentions,
    AGENTS.md forbids the agent from inventing fields, so the read is dead."""
    declared: set[str] = set()
    for f in _templates():
        declared |= set(_KEY_RE.findall(_frontmatter(f)))
    source = (Path(__file__).resolve().parent.parent / "app.py").read_text(encoding="utf-8")
    read = set(re.findall(r'\.meta\.get\(\s*"([^"]+)"', source))
    assert read, "found no .meta.get() reads — did app.py move?"
    undeclared = sorted(read - declared)
    assert not undeclared, \
        f"app.py reads frontmatter keys no template declares: {undeclared}"


def test_every_template_id_prefix_is_known_to_the_type_maps():
    """The `ACT` vs `AM` failure class: the prefix the template emits must be
    the prefix the parser maps to a folder and a human label."""
    for f in _templates():
        m = re.search(r"^id:\s*([A-Z]+)-", _frontmatter(f), re.MULTILINE)
        assert m, f"{f.name} declares no `id: TYPE-NNN`"
        prefix = m.group(1)
        if prefix in NON_WIKI_PREFIXES:
            continue
        assert app.catalog.folder_for_prefix(prefix), \
            f"{f.name} emits {prefix}- but the catalog knows no folder for it"
        assert app.catalog.group_label(prefix) != prefix, \
            f"{f.name} emits {prefix}- but the catalog has no group label for it"
        assert prefix in app.catalog.prefix_order(), \
            f"{f.name} emits {prefix}- but the catalog's group order omits it"


def test_no_type_map_entry_is_dead():
    """The other half of the same check: a mapped prefix no template emits is a
    key that can never match a page."""
    emitted = set()
    for f in _templates():
        m = re.search(r"^id:\s*([A-Z]+)-", _frontmatter(f), re.MULTILINE)
        emitted.add(m.group(1))
    for name, keys in (("the catalog's prefix lookup", set(app.catalog._TYPE_BY_PREFIX)),
                       ("the catalog's group order", set(app.catalog.prefix_order()))):
        # UC: a use case migrated to a functional requirement keeps its ID
        # (notation-use-case, DR-038)
        dead = sorted(keys - emitted - {"UC"})
        assert not dead, f"{name} maps prefixes no template emits: {dead}"



def test_goal_template_body_markers_are_extractable():
    """`## Vision` (vision) and the `- **Purpose.**` / `- **Advantage.**`
    bullets (objective) are parsed out of the goal body for /goals and the
    home hero."""
    tpl = (TEMPLATES / "goal.md").read_text(encoding="utf-8")
    base = (tpl.replace("{{date}}", "2026-09-06")
               .replace("{{title}}", "System X Runs Itself")
               .replace("<Name>", "System X Runs Itself")
               .replace("<target group>", "Role B")
               .replace("<need / problem>", "need Entity A handled")
               .replace("<system>", "System X")
               .replace("<category>", "platform")
               .replace("<key benefit>", "does the bookkeeping")
               .replace("<the outcome sought, not an activity>", "The outcome.")
               .replace("<for whom (see `beneficiary:`), what concrete benefit — \"so what?\">",
                        "Role B saves time.")
               .replace("<the one indicator (see `metric:` / `baseline:` / `target:`)>",
                        "Indicator A."))
    vision = (base.replace("id: GOAL-NNN", "id: GOAL-001")
                  .replace("stereotype: objective", "stereotype: vision"))
    objective = (base.replace("id: GOAL-NNN", "id: GOAL-002")
                     .replace("title: System X Runs Itself", "title: Objective A"))
    vp = _wiki / "goals" / "GOAL-001-system-x.md"
    op = _wiki / "goals" / "GOAL-002-objective-a.md"
    vp.write_text(vision, encoding="utf-8")
    op.write_text(objective, encoding="utf-8")
    try:
        with app.app.app_context():
            data = app.load_goals()
            titles = links.title_index()
            assert data["vision"] is not None, "the template's vision is not recognised"
            para = " ".join(app._vision_paragraphs(data["vision"], titles))
            assert "System X" in para, f"`## Vision` did not parse: {para!r}"
            sentence = app.vision_sentence(data["vision"], titles)
            assert sentence == ("For Role B who need Entity A handled, System X is a "
                                "platform that does the bookkeeping."), sentence
            obj = data["objectives"][0]
            for label in ("Purpose", "Advantage", "Metric"):
                got = app.extract_pam_bullet(obj, label, titles)
                assert got.strip(), f"`- **{label}.**` did not parse from the template"
    finally:
        vp.unlink()
        op.unlink()


if __name__ == "__main__":
    test_every_key_app_reads_is_declared_by_some_template()
    test_every_template_id_prefix_is_known_to_the_type_maps()
    test_no_type_map_entry_is_dead()
    test_goal_template_body_markers_are_extractable()
    print(f"OK: {len(_templates())} templates match the parser contract")
