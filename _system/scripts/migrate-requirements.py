#!/usr/bin/env python3
"""Migrate a project's functional requirements and use cases to the
notation + level model (DR-038 in the Systems42 meta repository).

    _system/scripts/migrate-requirements.py <project-dir>          # migrate
    _system/scripts/migrate-requirements.py --check <project-dir>  # list, exit 1 if any

Called by `new-project.sh migrate-requirements`. For a project spawned before
functional requirements carried `notation:` and `level:`:

- every page in wiki/functional-requirements/ with `stereotype: <x>` gets
  `notation: agile` and `level: <x>` in its place;
- every page in wiki/use-cases/ moves to wiki/functional-requirements/ under
  the same file name, so its ID and every [[UC-...]] link stay valid. It gets
  `type: functional-requirement`, `notation: use-case`, its level mapped
  (summary -> kite, user-goal -> sea, subfunction -> fish), its priority in
  MoSCoW spelling, and an empty `scope-building-block:` for the project to fill
  (the notation requires exactly one, FR-005); wiki/use-cases/ goes;
- links that name a moved page by path (`[[wiki/use-cases/UC-001-…]]`,
  `](../use-cases/UC-001-….md)`) in wiki/ pages and the index follow it; bare
  [[UC-001-…]] links need no change. raw/ and the log are history, left as is;
- the index's "## Use cases" entries move under "## Functional requirements".

Body text is never rewritten. Nothing is committed: review with `git status` /
`git diff` in the project. Standard library only.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

UC_LEVELS = {"summary": "kite", "user-goal": "sea", "subfunction": "fish"}
PRIORITY = {"must": "Must", "should": "Should", "could": "Could", "wont": "Won't", "won't": "Won't"}
FM_RE = re.compile(r"\A---\n(.*?\n)---\n", re.S)


def die(msg: str) -> None:
    sys.exit(f"migrate-requirements: {msg}")


def split(text: str) -> tuple[str, str] | None:
    m = FM_RE.match(text)
    return (m.group(1), text[m.end():]) if m else None


def value(fm: str, key: str) -> str:
    m = re.search(rf"^{re.escape(key)}:[ \t]*([^#\n]*)", fm, re.M)
    return m.group(1).strip().strip("\"'") if m else ""


def legacy_frs(root: Path) -> list[Path]:
    folder = root / "wiki" / "functional-requirements"
    out = []
    for p in sorted(folder.glob("*.md")) if folder.is_dir() else []:
        parts = split(p.read_text(encoding="utf-8"))
        if parts and re.search(r"^stereotype:", parts[0], re.M):
            out.append(p)
    return out


def legacy_ucs(root: Path) -> list[Path]:
    folder = root / "wiki" / "use-cases"
    return sorted(folder.glob("*.md")) if folder.is_dir() else []


def migrate_fr(p: Path) -> None:
    text = p.read_text(encoding="utf-8")
    fm, body = split(text)
    level = value(fm, "stereotype").lower()
    fm = re.sub(r"^stereotype:.*\n", f"notation: agile\nlevel: {level}\n", fm, count=1, flags=re.M)
    p.write_text(f"---\n{fm}---\n{body}", encoding="utf-8")


def migrate_uc(p: Path, dest: Path) -> list[str]:
    text = p.read_text(encoding="utf-8")
    parts = split(text)
    if not parts:
        die(f"{p}: no frontmatter")
    fm, body = parts
    notes = []
    fm = re.sub(r"^type:.*\n", "type: functional-requirement\n", fm, count=1, flags=re.M)
    fm = re.sub(r"^(tags:.*?)\buse-case\b", r"\1functional-requirement", fm, count=1, flags=re.M)
    old_level = value(fm, "level").lower()
    level = UC_LEVELS.get(old_level, old_level)
    if level not in UC_LEVELS.values():
        notes.append(f"level '{old_level}' has no Cockburn mapping; set kite, sea or fish")
    line = f"notation: use-case\nlevel: {level}\n"
    if re.search(r"^level:", fm, re.M):
        fm = re.sub(r"^level:.*\n", line, fm, count=1, flags=re.M)
    else:
        fm += line
    prio = value(fm, "priority")
    if prio:
        fm = re.sub(r"^priority:.*\n", f"priority: {PRIORITY.get(prio.lower(), prio)}\n",
                    fm, count=1, flags=re.M)
    if not re.search(r"^scope-building-block:", fm, re.M):
        fm += "scope-building-block:\n"
    notes.append("set scope-building-block to the one building block under discussion")
    dest.write_text(f"---\n{fm}---\n{body}", encoding="utf-8")
    p.unlink()
    return notes


def migrate_links(root: Path, stems: list[str]) -> list[Path]:
    """Point path-qualified links to moved use cases at their new folder."""
    if not stems:
        return []
    pattern = re.compile(r"\buse-cases/(" + "|".join(re.escape(s) for s in stems) + r")\b")
    files = sorted((root / "wiki").rglob("*.md")) + [root / "_system" / "index.md"]
    changed = []
    for f in files:
        if not f.is_file():
            continue
        text = f.read_text(encoding="utf-8")
        new = pattern.sub(r"functional-requirements/\1", text)
        if new != text:
            f.write_text(new, encoding="utf-8")
            changed.append(f)
    return changed


def migrate_index(root: Path) -> None:
    index = root / "_system" / "index.md"
    if not index.is_file():
        return
    lines = index.read_text(encoding="utf-8").splitlines(keepends=True)
    out, moved, in_uc = [], [], False
    for line in lines:
        if line.startswith("## "):
            in_uc = line.strip() == "## Use cases"
            if in_uc:
                continue
        if in_uc:
            if line.startswith("- "):
                moved.append(line.replace("wiki/use-cases/", "wiki/functional-requirements/"))
            continue
        out.append(line)
    if moved:
        at = next((i for i, l in enumerate(out) if l.strip() == "## Functional requirements"), None)
        if at is None:
            out += ["\n## Functional requirements\n\n"] + moved
        else:
            end = at + 1
            while end < len(out) and not out[end].startswith("## "):
                end += 1
            while end > at + 1 and not out[end - 1].strip():
                end -= 1
            if end == at + 1:
                moved = ["\n"] + moved
            out[end:end] = moved
    index.write_text("".join(out), encoding="utf-8")


def main() -> None:
    args = sys.argv[1:]
    check = bool(args) and args[0] == "--check"
    if check:
        args = args[1:]
    if len(args) != 1:
        die("usage: migrate-requirements.py [--check] <project-dir>")
    root = Path(args[0]).resolve()
    frs, ucs = legacy_frs(root), legacy_ucs(root)
    if check:
        for p in frs + ucs:
            print(p.relative_to(root))
        sys.exit(1 if frs or ucs else 0)
    if not frs and not ucs:
        print("Nothing to migrate: no `stereotype:` FR pages and no wiki/use-cases/ pages.")
        if (root / "wiki" / "use-cases").is_dir():
            for p in (root / "wiki" / "use-cases").iterdir():
                if p.name == ".gitkeep":
                    p.unlink()
            (root / "wiki" / "use-cases").rmdir()
        return
    fr_dir = root / "wiki" / "functional-requirements"
    fr_dir.mkdir(parents=True, exist_ok=True)
    for p in ucs:
        if (fr_dir / p.name).exists():
            die(f"{fr_dir / p.name} already exists; nothing was changed")
    for p in frs:
        migrate_fr(p)
        print(f"migrated {p.relative_to(root)}")
    todo = []
    for p in ucs:
        dest = fr_dir / p.name
        todo += [f"{dest.relative_to(root)}: {n}" for n in migrate_uc(p, dest)]
        print(f"moved {p.relative_to(root)} -> {dest.relative_to(root)}")
    uc_dir = root / "wiki" / "use-cases"
    if uc_dir.is_dir():
        for p in uc_dir.iterdir():
            if p.name == ".gitkeep":
                p.unlink()
        if not any(uc_dir.iterdir()):
            uc_dir.rmdir()
    migrate_index(root)
    for f in migrate_links(root, [p.stem for p in ucs]):
        print(f"relinked {f.relative_to(root)}")
    if todo:
        print("\nTo do in the project:")
        for t in todo:
            print(f"  - {t}")


if __name__ == "__main__":
    main()
