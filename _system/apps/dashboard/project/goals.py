"""The goals (req42 section 01): the vision, the objectives and their coverage.

Owns the vision page with its paragraphs and its first sentence, the enabler
lanes, the goals with the requirements that serve them (load_goals), the goal
coverage matrix and the goal tree (_mermaid_goal_tree).

May import `wiki`, `links`, `render`, `project.common` and
`project.requirements`. No Flask import and no import of `app` here
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re

import links as links_module  # link resolver and indexes
import project.common  # labels shared by the projections
import project.requirements  # a requirement's notation, level and parent
import render  # sanitizer, wikilinks and Markdown
import wiki  # paths, pages, parse cache and loaders


# --- goals (req42 block 01: vision + objectives) ---------------------------
#
# One content type `goal` with stereotype `vision | objective` (DR-016).
# The vision is the goal page carrying `stereotype: vision` (bootstrap.md step 3
# writes it as GOAL-001); every other goal page is an objective. Nothing is
# keyed off an ID list — a vault may hold any number of objectives at any IDs,
# and all of them must reach the screen.
# The Goal↔Epic edge is pinned at the Epic (`goal:` field on each FR, DR-018),
# and a use case carries the same field (DR-038); coverage is a pure projection
# from those edges.


def _goal_id_from_ref(ref: object) -> str:
    """From '[[GOAL-002-foo]]' / 'GOAL-002-foo' / 'GOAL-002', return 'GOAL-002'."""
    s = str(ref or "").strip()
    m = re.match(r"\[\[([^\]\|#]+)", s)
    stem = (m.group(1) if m else s).split("/")[-1].strip()
    parts = stem.split("-", 2)
    if len(parts) >= 2 and parts[0].upper() == "GOAL":
        return f"GOAL-{parts[1]}"
    return stem


def _goal_maturity(p: wiki.Page) -> str:
    """PAM until `horizon:` is set, then promotion to SMART (DR-016 / anchor)."""
    return "SMART" if str(p.meta.get("horizon") or "").strip() else "PAM"


_VISION_SECTION_RE = re.compile(r"##\s+Vision\b[^\n]*\n+(.+?)(?=\n##\s|\Z)", re.DOTALL)
# notes, comments and the template's hints under `## Vision` are not prose
_VISION_SKIP = (">", "<!--", "**Objectives.**", "*Optional:*")
# a sentence ends at . ! or ? followed by the end or by a word that does not
# start in lower case, so "e.g. the" does not end it
_SENTENCE_RE = re.compile(r"^(.+?[.!?])(?=\s+[^a-z\s]|\s*$)", re.DOTALL)


def _vision_paragraphs(page: wiki.Page, titles: dict[str, str],
                       links: dict[str, tuple[str, str]] | None = None) -> list[str]:
    """Every prose paragraph under `## Vision` in the Vision page, inline
    markdown (`**bold**`, wikilinks) rendered, no <p> wrapper. Pass `links` to
    emit real hyperlinks for resolvable targets.

    Skipped: notes and callouts (`> …`), HTML comments, and the template's
    `*Optional:*` hint and `**Objectives.**` pointer. Only the first paragraph used to be shown, so a
    vision that opened with "> follows the Geoffrey Moore format" showed that
    note and nothing else."""
    if not page:
        return []
    m = _VISION_SECTION_RE.search(page.body)
    if not m:
        return []
    out = []
    for para in m.group(1).split("\n\n"):
        para = para.strip()
        if not para or para.startswith(_VISION_SKIP):
            continue
        para = re.sub(r"\s+", " ", para)
        para = render.render_wikilinks(para, titles, links)
        out.append(render.sanitize_html(re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", para)))
    return out


def vision_sentence(page: wiki.Page | None, titles: dict[str, str]) -> str:
    """The first sentence of the vision as plain text, for the home hero
    (FR-018). A wikilink reads as its alias or its target's title. Empty when
    there is no vision or no prose under `## Vision`."""
    m = _VISION_SECTION_RE.search(page.body) if page else None
    if not m:
        return ""
    for para in m.group(1).split("\n\n"):
        para = para.strip()
        if not para or para.startswith(_VISION_SKIP):
            continue
        text = wiki.WIKILINK_RE.sub(
            lambda w: (w.group(2) or titles.get(w.group(1).strip().split("/")[-1], w.group(1))).strip(),
            re.sub(r"\s+", " ", para))
        text = render._strip_inline_markdown(text)
        first = _SENTENCE_RE.match(text)
        return (first.group(1) if first else text).strip()
    return ""


ENABLER_LANES = ("platform", "display")


def _in_enabler_lane(fr: wiki.Page) -> bool:
    return str(fr.meta.get("lane") or "").strip().lower() in ENABLER_LANES


def is_enabler(fr: wiki.Page, goals: list) -> bool:
    """rel-goal: an FR that serves no goal (`goals`, its own or its use-case
    parent's) and sits in lane platform or display is an explicit enabler."""
    return not goals and _in_enabler_lane(fr)


def breaks_fr_traces_to_goal(fr: wiki.Page, goals: list) -> bool:
    """rule-fr-traces-to-goal: an Agile epic or feature serves a goal (`goals`,
    its own or its use-case parent's) or is an enabler. Advisory only."""
    if project.requirements._fr_notation(fr) != "agile" or project.requirements._fr_level(fr) not in ("epic", "feature"):
        return False
    return not goals and not _in_enabler_lane(fr)


def vision_page() -> wiki.Page | None:
    """The goal page with `stereotype: vision`, picked by stereotype and never
    by ID. If two pages claim it, the lowest ID wins."""
    goals = sorted(wiki.load_type("goal"), key=lambda p: p.id)
    return next((p for p in goals
                 if str(p.meta.get("stereotype") or "").strip().lower() == "vision"), None)


def load_goals() -> dict:
    """Return everything /goals and the functional-requirements goal map need.

    Shape:
      vision     — the goal Page with `stereotype: vision`, or None
      objectives — every other goal Page, ordered by id (GOAL-002, -003, …)
      coverage   — { 'GOAL-NNN': [FR-Page, ...] } from goal: backlinks
      enablers   — FR-Pages that serve no goal, in lane platform or display
      untraced   — FR-Pages that break rule-fr-traces-to-goal
      frs        — every FR-Page that is not a use case, sorted by id
      ucs        — the FR-Pages in the use-case notation, sorted by id
                   (DR-038; a use case with goal: [] is simply untraced, not
                   an enabler)

    Derived entirely from the vault, never from a fixed ID list: a group may
    capture any number of objectives at any IDs and every one of them shows up.
    Anything that is not *the* vision counts as an objective, so a goal page
    with a missing or misspelt `stereotype:` is still rendered rather than
    silently dropped. If two pages claim `stereotype: vision`, the
    lowest-id one is the vision and the rest fall through to objectives.
    """
    goals = sorted(wiki.load_type("goal"), key=lambda p: p.id)
    vision = vision_page()
    objectives = [p for p in goals if p is not vision]

    all_frs = sorted(wiki.load_type("functional-requirement"), key=lambda p: p.id)
    ucs = [p for p in all_frs if project.requirements._fr_notation(p) == "use-case"]
    frs = [p for p in all_frs if project.requirements._fr_notation(p) != "use-case"]
    # the use cases Agile features and stories may refine (DR-038 amendment),
    # the same set the story map roots them under
    uc_by_stem = {u.stem: u for u in ucs if project.requirements._fr_level(u) in project.requirements.UC_REFINABLE_LEVELS}
    coverage: dict[str, list[wiki.Page]] = {o.id: [] for o in objectives}
    objective_by_stem = {o.stem: o for o in objectives}

    def served(p: wiki.Page) -> list[str]:
        # only links that resolve to an objective count: the vision, a missing
        # page or a mangled value serves no goal (rule-fr-traces-to-goal)
        return [objective_by_stem[s].id for s in links_module.links_of(p, "goal") if s in objective_by_stem]

    enablers: list[wiki.Page] = []
    untraced: list[wiki.Page] = []
    for fr in frs:
        gids = served(fr)
        if not gids and project.requirements._fr_notation(fr) == "agile" and project.requirements._fr_level(fr) in ("feature", "story"):
            # an Agile feature/story whose first parent is a sea- or fish-level
            # use case serves that use case's goals (rule-fr-traces-to-goal)
            first = project.requirements._fr_first_parent(fr)
            gids = served(uc_by_stem[first]) if first in uc_by_stem else []
        if is_enabler(fr, gids):
            enablers.append(fr)
        elif breaks_fr_traces_to_goal(fr, gids):
            untraced.append(fr)
        for gid in gids:
            coverage[gid].append(fr)
    for uc in ucs:
        for gid in served(uc):
            if uc not in coverage[gid]:
                coverage[gid].append(uc)
    return {"vision": vision, "objectives": objectives,
            "coverage": coverage, "enablers": enablers, "untraced": untraced,
            "frs": frs, "ucs": ucs}


def _goal_matrix(data: dict) -> tuple[list[dict], list[dict]]:
    """proj-goal-coverage as (columns, rows) for /goals (FR-036).

    Columns are the epics and use cases: epics that serve a goal or break
    rule-fr-traces-to-goal (`nogoal`), then use cases, then the enabler epics
    as their own group. Rows are the objectives. Per filter view (`views`, all
    pages or accepted only) a row is a `gap` when no requirement at all serves
    it, and a row without a mark lists the features and stories that serve it
    (`served`). Columns and rows carry their status for the filter."""
    enabler_ids = {fr.id for fr in data["enablers"]}
    untraced_ids = {fr.id for fr in data["untraced"]}
    epics = [fr for fr in data["frs"]
             if project.requirements._fr_notation(fr) == "agile" and project.requirements._fr_level(fr) == "epic"]

    def col(p: wiki.Page) -> dict:
        return {"id": p.id, "title": p.title, "url": links_module._page_url(p.folder, p.stem),
                "status": p.status, "enabler": p.id in enabler_ids,
                "nogoal": p.id in untraced_ids}

    cols = ([col(e) for e in epics if e.id not in enabler_ids]
            + [col(uc) for uc in data["ucs"]]
            + [col(e) for e in epics if e.id in enabler_ids])
    col_ids = {c["id"] for c in cols}

    def view(serving: list[wiki.Page]) -> dict:
        # gap: nothing serves the goal. served: a row without a mark names the
        # features and stories that serve it, grouped by kind
        groups = []
        if not any(p.id in col_ids for p in serving):
            for kind, label in (("feature", "features"), ("story", "stories")):
                links = [{"id": p.id, "url": links_module._page_url(p.folder, p.stem)} for p in serving
                         if project.requirements._fr_notation(p) == "agile" and project.requirements._fr_level(p) == kind]
                if links:
                    groups.append({"label": label, "links": links})
            # requirements in another notation (EARS, prose …) are no column either
            others = [{"id": p.id, "url": links_module._page_url(p.folder, p.stem)} for p in serving
                      if project.requirements._fr_notation(p) not in ("agile", "use-case")]
            if others:
                groups.append({"label": "other requirements", "links": others})
        return {"gap": not serving, "served": groups}

    rows = []
    for o in data["objectives"]:
        serving = data["coverage"].get(o.id, [])
        covered = {p.id for p in serving}
        cells = [c["id"] in covered for c in cols]
        rows.append({"id": o.id, "title": o.title, "url": links_module._page_url(o.folder, o.stem),
                     "status": o.status, "cells": cells,
                     "views": {"all": view(serving),
                               # for "Agreed only": counts accepted pages only
                               "accepted": view([p for p in serving if p.status == "accepted"])}})
    return cols, rows


def _mermaid_goal_tree(system_name: str, vision: wiki.Page, objectives: list[wiki.Page]) -> str | None:
    """Project the Vision→Objectives tree from `parent:` edges (DR-018 style).
    Top-down, short-name nodes; clicking a goal jumps to its anchor below.
    Default `useMaxWidth: true` so the SVG fits the container at typical
    desktop widths (≥1000 px) without horizontal scrolling."""
    if not vision or not objectives:
        return None
    root = project.common._clean_label(system_name, drop_parenthetical=False)
    lines = ["graph TD", f'  V["Vision {root}"]:::vision',
             f'  click V "/goals#{vision.id}"']
    for o in objectives:
        nid = project.common._diagram_node_id(o.id)
        label = project.common._clean_label(project.common._short_title(o))
        lines.append(f'  V --> {nid}["{o.id}<br/>{label}"]:::goal')
        # absolute target so the same diagram works on /goals (in-page anchor)
        # and on /req42 (cross-page navigation to the matching goal card)
        lines.append(f'  click {nid} "/goals#{o.id}"')
    lines += [
        "  classDef vision fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef goal fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)
