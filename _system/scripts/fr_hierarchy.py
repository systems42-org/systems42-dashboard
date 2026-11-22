"""Functional-requirement hierarchy shared by metamodel-lint.py and delivery.py.

One place resolves `parent:` links and decides which Agile children count, so
the two checks cannot disagree with each other (or with systems42-dashboard,
which matches parents by stem and drops deprecated pages).

`pages` maps a page stem to its frontmatter dict.
"""
from __future__ import annotations

import re

_LINK = re.compile(r"\[\[([^\]|#]+)")


def stem_of(ref: object) -> str:
    """Page stem of a `parent:` entry: `[[FR-1-x]]`, `[[wiki/…/FR-1-x|alias]]` or a bare stem."""
    s = str(ref or "").strip()
    m = _LINK.match(s)
    return (m.group(1) if m else s).split("/")[-1].strip()


def parent_stems(meta: dict) -> list[str]:
    refs = meta.get("parent") or []
    return [s for s in (stem_of(r) for r in (refs if isinstance(refs, list) else [refs])) if s]


def is_active(meta: dict) -> bool:
    """A deprecated page no longer counts towards a parent's delivery. Maturity
    and delivery are independent: a valid requirement whose implementation was
    removed (`delivery: removed`) still counts, and keeps its parent from `implemented`."""
    return meta.get("status") != "deprecated"


def agile_children(pages: dict[str, dict]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for stem, meta in pages.items():
        if str(meta.get("notation") or "") == "agile" and is_active(meta):
            for parent in parent_stems(meta):
                out.setdefault(parent, []).append(stem)
    return out


def refining_stories(stem: str, pages: dict[str, dict],
                     children: dict[str, list[str]]) -> tuple[list[str], list[str]]:
    """Stories refining `stem`, directly or via a feature, and the features without stories."""
    stories: list[str] = []
    empty: list[str] = []
    for kid in children.get(stem, []):
        if str(pages[kid].get("level") or "") == "story":
            stories.append(kid)
            continue
        grand = [g for g in children.get(kid, []) if str(pages[g].get("level") or "") == "story"]
        stories += grand
        if not grand:
            empty.append(kid)
    return stories, empty
