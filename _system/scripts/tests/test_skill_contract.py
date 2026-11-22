"""The workflows and the installed skills are two halves of one contract.

`_system/workflows/`, `AGENTS.md` and the skills themselves tell the agent to
activate skills by name.
Nothing checks that those skills are actually here, and the failure is silent in
the worst way: the agent reaches a gate of a capture, finds no skill by the name
it was told, and quietly does without — the vendored `grilling` skill did
exactly that for weeks, and every capture closed without it. Nobody sees a stack
trace. The wiki just gets a little worse.

Same shape as the dashboard's template contract test, one layer out: a name written in one
place, a directory that has to exist in another, and no runtime that complains
when they drift. Skills are vendored into the repo precisely so `git clone` is
the whole install — this test is what keeps that true.

Installed means discoverable, not merely present (DR-037): a skill lives once in
`.agents/skills/`, which OpenCode, Codex and Copilot read, and Claude Code —
which reads only `.claude/skills/` — reaches it through a symlink there. A skill
that exists in one folder but not the other passes an existence check and is
still invisible to half the harnesses.

Run from the repository root:
    python3 _system/scripts/tests/test_skill_contract.py
"""
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SKILLS = REPO / ".agents" / "skills"
CLAUDE_LINKS = REPO / ".claude" / "skills"
DOCS = (sorted((REPO / "_system" / "workflows").glob("*.md")) + [REPO / "AGENTS.md"]
        + sorted(SKILLS.glob("*/SKILL.md")))

# "the **capture** skill", "activate the `grill-requirements` skill" — a name
# in bold or backticks, immediately followed by the word "skill".
_REFERENCE_RE = re.compile(r"(?:\*\*|`)([a-z][a-z0-9-]*)(?:\*\*|`)\s+skill\b")
# a literal path to a skill file, e.g. `.claude/skills/grill-requirements/SKILL.md`
_PATH_RE = re.compile(r"`((?:\.claude|\.agents)/skills/[A-Za-z0-9._/-]*SKILL\.md)`")
_NAME_RE = re.compile(r"^name:\s*(\S+)\s*$", re.MULTILINE)
_DESCRIPTION_RE = re.compile(r"^description:\s*\S", re.MULTILINE)
# the Agent Skills name rule OpenCode enforces: lowercase, single hyphens
_VALID_NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def _skills() -> list:
    return sorted(SKILLS.glob("*/SKILL.md"))


def _installed() -> dict:
    """Every skill in `.agents/skills/`, by the `name:` in its frontmatter and
    by its directory name — the test below keeps the two equal, and a doc may
    reasonably cite either."""
    found = {}
    for skill in _skills():
        found[skill.parent.name] = skill
        m = _NAME_RE.search(skill.read_text(encoding="utf-8"))
        if m:
            found[m.group(1)] = skill
    return found


def _docs() -> list:
    present = [d for d in DOCS if d.is_file()]
    assert present, f"no workflow docs found under {REPO}"
    return present


def test_every_skill_the_docs_name_is_installed():
    """The failure this exists for: a workflow orders the agent to activate a
    skill that was never vendored, and the agent silently does without."""
    installed = _installed()
    assert installed, f"no skills found under {SKILLS}"
    missing = []
    for doc in _docs():
        for name in _REFERENCE_RE.findall(doc.read_text(encoding="utf-8")):
            if name not in installed:
                missing.append(f"{doc.relative_to(REPO)} -> {name}")
    assert not missing, \
        "docs name skills that are not installed in this repo: " + str(sorted(set(missing)))


def test_the_docs_reference_at_least_the_capture_gate():
    """A guard on the regex, not on the repo. If the wording drifts so far that
    nothing matches, the test above starts passing vacuously and stops being
    worth having."""
    referenced = set()
    for doc in _docs():
        referenced |= set(_REFERENCE_RE.findall(doc.read_text(encoding="utf-8")))
    assert "grill-requirements" in referenced, \
        f"no doc names the 'grill-requirements' skill any more — did the wording change? {sorted(referenced)}"


def test_every_skill_path_the_docs_quote_exists():
    """Paths rot differently from names: a skill can be renamed or moved and the
    prose still reads correctly while the path underneath it points nowhere."""
    broken = []
    for doc in _docs():
        for rel in _PATH_RE.findall(doc.read_text(encoding="utf-8")):
            if not (REPO / rel).is_file():
                broken.append(f"{doc.relative_to(REPO)} -> {rel}")
    assert not broken, "docs quote skill paths that do not exist: " + str(sorted(set(broken)))


def test_every_installed_skill_declares_a_valid_name_and_a_description():
    """Frontmatter `name:` is how a skill is addressed; one without it cannot be
    activated by the workflows no matter where it sits. OpenCode also refuses a
    name that breaks the Agent Skills rule or differs from its directory, and
    drops a skill without a description."""
    for skill in _skills():
        rel = skill.relative_to(REPO)
        text = skill.read_text(encoding="utf-8")
        m = _NAME_RE.search(text)
        assert m, f"{rel} has no `name:` in its frontmatter"
        name = m.group(1)
        assert _VALID_NAME_RE.match(name), f"{rel}: name {name!r} is not lowercase-hyphenated"
        assert name == skill.parent.name, \
            f"{rel}: name {name!r} differs from its directory {skill.parent.name!r}"
        assert _DESCRIPTION_RE.search(text), f"{rel} has no `description:`"


def test_claude_code_reaches_every_skill_through_a_link():
    """Claude Code reads only `.claude/skills/`. Each skill there is a relative
    symlink into `.agents/skills/`, never a second copy that can drift."""
    missing, wrong = [], []
    for skill in _skills():
        name = skill.parent.name
        link = CLAUDE_LINKS / name
        if not link.is_symlink():
            missing.append(name)
        elif os.readlink(link) != f"../../.agents/skills/{name}" or not (link / "SKILL.md").is_file():
            wrong.append(f"{name} -> {os.readlink(link)}")
    assert not missing, f"no .claude/skills link for: {missing}"
    assert not wrong, f".claude/skills links that do not resolve to .agents/skills: {wrong}"


def test_every_claude_link_points_at_an_installed_skill():
    """The reverse: a link left behind after a skill was renamed or removed."""
    if not CLAUDE_LINKS.is_dir():
        return
    dangling = [p.name for p in sorted(CLAUDE_LINKS.iterdir())
                if p.is_symlink() and not (p / "SKILL.md").is_file()]
    assert not dangling, f"dangling .claude/skills links: {dangling}"


def test_claude_md_imports_agents_md():
    """`AGENTS.md` is the schema; `CLAUDE.md` exists only so every Claude Code
    version loads it. If the import goes, Claude Code may read nothing."""
    claude = REPO / "CLAUDE.md"
    assert claude.is_file(), "CLAUDE.md is missing"
    assert re.search(r"^@AGENTS\.md\s*$", claude.read_text(encoding="utf-8"), re.MULTILINE), \
        "CLAUDE.md does not import @AGENTS.md"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn()
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
    if failed:
        sys.exit(1)
    print(f"ok — {len(fns)} checks, {len(_installed())} skill names installed")
