"""The functional requirements (req42 section 04) and the quality scenarios.

Owns a requirement's notation, level and delivery status, the requirement hierarchy with the
story map (build_fr_hierarchy), a requirement's node and ancestors in it, the
Mermaid trees of goals with epics and of one requirement with its building
blocks, and the scenario rows of a quality requirement.

May import `wiki`, `links`, `render` and `project.common`. No Flask import and
no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import datetime
import re

import links as links_module  # link resolver and indexes
import project.common  # what several projections share
import render  # sanitizer, wikilinks and Markdown
import wiki  # paths, pages, parse cache and loaders


# --- functional requirements (req42 block 04) ----------------------------
#
# One content type `functional-requirement`; every page stores its `notation:`
# (agile, use-case, ears, prose or a project's own) and one of that notation's
# `level:` values (DR-038). The hierarchy edge is the `parent:` wikilink field,
# a graph independent of notation and level. build_fr_hierarchy is the story
# map: a pure projection over the Agile epic/feature/story pages (plus the use
# cases Agile features and stories refine) — the single source for the
# /req42/functional-requirements page. Everything it cannot
# place is listed under the other notations.


def _fr_level(p: "wiki.Page") -> str:
    return str(p.meta.get("level") or "").strip().lower()


def _fr_notation(p: "wiki.Page") -> str:
    # No fallback: a page without `notation:` is unplaced, not silently Agile.
    return str(p.meta.get("notation") or "").strip().lower()


AGILE_LEVELS = ("epic", "feature", "story")
# use-case levels an Agile feature or story may refine (DR-038 amendment): a
# kite-level use case summarises others and takes no Agile children
UC_REFINABLE_LEVELS = ("sea", "fish")


def _fr_first_parent(p: "wiki.Page") -> str | None:
    """The stem of an FR's first `parent:`. The story map is a tree: a page
    with several parents is placed under its first; multi-parent graphs are
    out of scope for this view. Goal inheritance from a use case reads the
    same edge, so the two always agree."""
    for ref in p.as_list("parent"):
        stem = links_module._link_stem(ref)
        if stem:
            return stem
    return None


def _fr_sort_key(p: "wiki.Page"):
    """Hierarchy order: numeric `order:` field, then id as a stable tiebreak."""
    try:
        order = int(p.meta.get("order"))
    except (TypeError, ValueError):
        order = 9999
    return (order, p.id)


def _fr_node(p: "wiki.Page") -> dict:
    """Slim per-page record shared by cards and the diagram."""
    return {
        "id": p.id, "title": p.title, "stem": p.stem,
        "priority": str(p.meta.get("priority") or "").strip(),
        "level": _fr_level(p), "notation": _fr_notation(p),
        "status": p.status,
    }


_DATE_PREFIX_RE = re.compile(r"([0-9]{4}-[0-9]{2}-[0-9]{2})(?:[Tt ].*)?\Z")


def _delivery_checked(value) -> str:
    """The day of a `delivery-checked:` timestamp, as written in its own time
    zone. Text that does not start with a date stays as written."""
    if isinstance(value, datetime.datetime):
        return value.date().isoformat()
    if isinstance(value, datetime.date):
        return value.isoformat()
    if value is None or isinstance(value, (list, dict)):
        return ""
    text = str(value).strip()
    m = _DATE_PREFIX_RE.match(text)
    return m.group(1) if m else text


def fr_delivery(p: "wiki.Page") -> dict:
    """A requirement's delivery status (meta FR-031, FR-048):

      value    `delivery:` as written, "" when the page has none. Absent means
               no delivery record, not "not implemented"
      known    whether the metamodel allows the value on this page: it is one
               of the type's states, and the page's notation allows the state
               and lists the page's level as implementable. A page without a
               known notation is held to the type's states only
      checked  the day of `delivery-checked:`, "" without one or without a value
    """
    raw = p.meta.get("delivery")
    value = "" if raw is None or isinstance(raw, (list, dict)) else str(raw).strip()
    if not value:
        return {"value": "", "known": False, "checked": ""}
    vocab = project.common.delivery_vocab()
    rules = vocab["notations"].get(_fr_notation(p)) or {}
    known = (value in vocab["states"]
             and (rules.get("states") is None or value in rules["states"])
             and (rules.get("levels") is None or _fr_level(p) in rules["levels"]))
    return {"value": value, "known": known, "checked": _delivery_checked(p.meta.get("delivery-checked"))}


def build_fr_hierarchy() -> dict:
    """Project the Epic→Feature→Story hierarchy from each FR's `parent:` field.

    Returns:
      epics          — list of epic dicts in `order` then id order; each carries
                       `features` (with nested `stories`), `direct_stories`
                       (stories hung straight off the epic), `n_features`
                       (direct feature children) and `n_stories` (its direct
                       stories plus the stories of its direct features — exactly
                       what the page renders), plus priority/release/status.
      total_epics / total_features / total_stories — aggregate counters:
                       every feature and story the roots and the orphans show.
      use_cases      — use cases (use-case notation, level sea or fish) that
                       Agile features or stories name as `parent:` (DR-038
                       amendment), shaped like an epic row (features,
                       direct_stories, counts); a use case without such
                       children stays under other_notations only.
      orphans        — Agile feature/story pages no root shows: a feature
                       whose parent is not an epic or a refinable use case,
                       a story whose parent is none of epic, feature and
                       refinable use case (no parent, a dangling or retired
                       one, a cycle, a self-parent). An orphaned feature
                       carries its `stories`. Normally empty.
      other_notations — every live FR the story map cannot place: other
                       notations, and pages with a missing or unknown notation
                       or level (still visible, never silently Agile).
    """
    # A deprecated item has been retired — split, superseded or withdrawn — so it
    # is not part of the live hierarchy and must not be counted, drawn, or listed as
    # an orphan. Same rule as the context projection applies to a deprecated
    # interface. A live child of a retired parent correctly becomes an orphan.
    all_pages = [p for p in wiki.load_type("functional-requirement")
                 if p.status != "deprecated"]
    pages = [p for p in all_pages
             if _fr_notation(p) == "agile" and _fr_level(p) in AGILE_LEVELS]
    by_stem = {p.stem: p for p in pages}
    uc_by_stem = {p.stem: p for p in all_pages
                  if _fr_notation(p) == "use-case" and _fr_level(p) in UC_REFINABLE_LEVELS}

    parent_stem = _fr_first_parent

    children: dict[str, list["wiki.Page"]] = {}
    for p in pages:
        ps = parent_stem(p)
        if ps:
            children.setdefault(ps, []).append(p)

    def kids(stem: str, level: str) -> list["wiki.Page"]:
        return sorted((c for c in children.get(stem, []) if _fr_level(c) == level),
                      key=_fr_sort_key)

    epics = sorted((p for p in pages if _fr_level(p) == "epic"), key=_fr_sort_key)
    epic_rows = []
    total_features = total_stories = 0

    def breakdown(root: "wiki.Page") -> dict:
        feats = kids(root.stem, "feature")
        feature_rows = [
            {**_fr_node(f), "stories": [_fr_node(s) for s in kids(f.stem, "story")]}
            for f in feats
        ]
        direct_stories = [_fr_node(s) for s in kids(root.stem, "story")]
        # n_stories counts exactly what the page renders — the root's direct
        # stories plus the stories of its direct features (the model is two
        # levels: root→feature→story / root→story, the root an epic or a use
        # case). Computed from the built
        # structure, not by recursion, so a malformed/cyclic parent: edge can
        # never run away and 500 the dashboard.
        return {
            "n_features": len(feats),
            "n_stories": len(direct_stories) + sum(len(f["stories"]) for f in feature_rows),
            "features": feature_rows,
            "direct_stories": direct_stories,
        }

    for e in epics:
        b = breakdown(e)
        total_features += b["n_features"]
        total_stories += b["n_stories"]
        epic_rows.append({**_fr_node(e),
                          "release": str(e.meta.get("release") or "").strip(), **b})

    # A use case at level sea or fish that Agile features or stories refine
    # (DR-038 amendment) is a root beside the epics; an epic never names a use
    # case. Use cases without such children are listed under other_notations.
    uc_rows = []
    for u in sorted(uc_by_stem.values(), key=_fr_sort_key):
        if not (kids(u.stem, "feature") or kids(u.stem, "story")):
            continue
        b = breakdown(u)
        total_features += b["n_features"]
        total_stories += b["n_stories"]
        uc_rows.append({**_fr_node(u), "url": links_module._page_url(u.folder, u.stem), **b})

    # A parent that exists does not place a page: only a root shows features,
    # and only a root or a feature shows stories. A feature no root shows is an
    # orphan and keeps its stories, so every story of a feature shows once.
    def level_of(stem: str | None) -> str:
        return _fr_level(by_stem[stem]) if stem in by_stem else ""

    orphans = []
    for p in pages:
        st = _fr_level(p)
        ps = parent_stem(p)
        under_root = ps in uc_by_stem or level_of(ps) == "epic"
        if st == "feature" and not under_root:
            stories = [_fr_node(s) for s in kids(p.stem, "story")]
            orphans.append({**_fr_node(p), "stories": stories})
            total_features += 1
            total_stories += len(stories)
        elif st == "story" and not under_root and level_of(ps) != "feature":
            orphans.append(_fr_node(p))
            total_stories += 1

    placed = set(by_stem) | {u["stem"] for u in uc_rows}
    return {
        "epics": epic_rows,
        "use_cases": uc_rows,
        "total_epics": len(epics),
        "total_features": total_features,
        "total_stories": total_stories,
        "orphans": orphans,
        "other_notations": sorted((_fr_node(p) for p in all_pages if p.stem not in placed),
                                  key=lambda r: r["id"]),
    }


def _mermaid_goal_epic_tree(goals: dict, hierarchy: dict,
                            links: list[dict] | None = None) -> str | None:
    """Compact top-of-hierarchy map: each Objective links down to the Epics that
    contribute to it (FR `goal:` coverage, DR-018). Enabler epics (lane
    platform or display) hang under a shared `Platform / Enabler` node, epics
    that name no goal under `No goal`, so both stay visible. Two
    levels only — it must stay readable as the hierarchy grows, which is exactly
    why the old full Epic→Feature→Story tree was split out to the epic pages.
    Goal nodes jump to their card on /goals; epic nodes open their epic page.
    Use cases with a `goal:` (DR-038) hang under their goals beside the epics.
    Returns None when there are neither epics nor goal-linked use cases.
    `links`, when given, receives every node that opens a page (QR-001)."""
    epics = hierarchy.get("epics") or []
    coverage = goals.get("coverage") or {}
    has_uc = any(_fr_notation(p) == "use-case" for ps in coverage.values() for p in ps)
    if not epics and not has_uc:
        return None
    epic_by_id = {e["id"]: e for e in epics}
    objectives = goals.get("objectives") or []
    enablers = goals.get("enablers") or []

    lines = ["graph TD"]
    seen: set[str] = set()
    drawn: list[dict] = []

    def epic_edge(parent_nid: str, e: dict) -> None:
        # An epic may contribute to several goals (a DAG): declare its node with
        # label + click once, then reference it by id on every further edge.
        nid = project.common._diagram_node_id(e["id"])
        if e["id"] in seen:
            lines.append(f'  {parent_nid} --> {nid}')
            return
        label = project.common._clean_label(e["title"])
        lines.append(f'  {parent_nid} --> {nid}["{e["id"]}<br/>{label}"]:::epic')
        lines.append(f'  click {nid} "/functional-requirements/{e["stem"]}"')
        drawn.append({"id": e["id"], "title": e["title"], "url": f'/functional-requirements/{e["stem"]}'})
        seen.add(e["id"])

    def uc_edge(parent_nid: str, uc: wiki.Page) -> None:
        nid = project.common._diagram_node_id(uc.id)
        if uc.id in seen:
            lines.append(f'  {parent_nid} --> {nid}')
            return
        label = project.common._clean_label(uc.title)
        lines.append(f'  {parent_nid} --> {nid}["{uc.id}<br/>{label}"]:::usecase')
        lines.append(f'  click {nid} "{links_module._page_url(uc.folder, uc.stem)}"')
        drawn.append(project.common._node_link(uc))
        seen.add(uc.id)

    for o in objectives:
        gid = project.common._diagram_node_id(o.id)
        glabel = project.common._clean_label(project.common._short_title(o))
        lines.append(f'  {gid}["{o.id}<br/>{glabel}"]:::goal')
        lines.append(f'  click {gid} "/goals#{o.id}"')
        drawn.append({"id": o.id, "title": o.title, "url": f"/goals#{o.id}"})
        for fr in coverage.get(o.id, []):
            if _fr_notation(fr) == "use-case":
                uc_edge(gid, fr)
                continue
            e = epic_by_id.get(fr.id)
            if e:  # only epics belong on this map (features/stories carry no goal:)
                epic_edge(gid, e)

    enabler_epics = [epic_by_id[fr.id] for fr in enablers if fr.id in epic_by_id]
    if enabler_epics:
        lines.append('  ENABLER["Platform / Enabler"]:::enabler')
        for e in enabler_epics:
            epic_edge("ENABLER", e)

    # epics that break rule-fr-traces-to-goal: no enabler, but still on the map
    untraced_epics = [epic_by_id[fr.id] for fr in goals.get("untraced") or []
                      if fr.id in epic_by_id and fr.id not in seen]
    if untraced_epics:
        lines.append('  NOGOAL["No goal"]:::nogoal')
        for e in untraced_epics:
            epic_edge("NOGOAL", e)

    lines += [
        "  classDef goal fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef enabler fill:#3a3f4b,stroke:#7a8497,color:#ffffff,font-weight:bold;",
        "  classDef epic fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef usecase fill:#eef1f6,stroke:#9aa3b2,color:#15202e,stroke-dasharray:4 3;",
        # the warning colour of the matrix's "no goal" flag (--warn)
        "  classDef nogoal fill:#5a3d0c,stroke:#ffb454,color:#ffffff,stroke-width:2px,font-weight:bold;",
    ]
    if links is not None:
        links.extend(drawn)
    return "\n".join(lines)


def fr_building_blocks(stem: str) -> list[wiki.Page]:
    """The building blocks whose `drivers:` name this requirement (rel-drivers),
    by id. The link is stored on the block only, never on the requirement."""
    return [p for p in sorted(wiki.load_type("building-block"), key=lambda q: q.id)
            if stem in links_module.links_of(p, "drivers")]


def _mermaid_fr_subtree(node: dict | None, blocks: list[wiki.Page] | None = None,
                        links: list[dict] | None = None) -> str | None:
    """One FR's detail diagram (FR-047), drawn on its FR page so the hierarchy
    overview can stay compact: its breakdown and its building blocks. Handles
    an epic root (→ its Features → their Stories, plus stories hung straight
    off the epic), a feature root (→ its Stories) and a leaf. `blocks` are the
    root's own building blocks, joined by a dashed edge. Every node but the
    root clicks through to its page and is added to `links`, the text links
    beside the diagram (QR-001). `node` needs `id` and `title` only.
    Returns None when the root has neither children nor building blocks."""
    if not node:
        return None
    blocks = blocks or []
    feats = node.get("features") or []
    own_stories = node.get("stories") or []          # set when the root is a feature
    direct = node.get("direct_stories") or []        # epic's stories without a feature
    if not feats and not own_stories and not direct and not blocks:
        return None
    rid = project.common._diagram_node_id(node["id"])
    lines = ["graph TD", f'  {rid}["{node["id"]}<br/>{project.common._clean_label(node["title"])}"]:::root']
    drawn: list[dict] = []

    def child(parent_nid: str, rec: dict, css: str) -> str:
        nid = project.common._diagram_node_id(rec["id"])
        label = project.common._clean_label(rec["title"])
        url = f'/functional-requirements/{rec["stem"]}'
        lines.append(f'  {parent_nid} --> {nid}["{rec["id"]}<br/>{label}"]:::{css}')
        lines.append(f'  click {nid} "{url}"')
        drawn.append({"id": rec["id"], "title": rec["title"], "url": url})
        return nid

    for f in feats:
        fid = child(rid, f, "feature")
        for s in f.get("stories") or []:
            child(fid, s, "story")
    for s in own_stories:
        child(rid, s, "story")
    for s in direct:
        child(rid, s, "story")
    for b in blocks:
        nid = project.common._diagram_node_id(b.id)
        lines.append(f'  {rid} -.-> {nid}[["{b.id}<br/>{project.common._clean_label(b.title)}"]]:::block')
        lines.append(f'  click {nid} "{links_module._page_url(b.folder, b.stem)}"')
        drawn.append(project.common._node_link(b))

    lines += [
        "  classDef root fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef feature fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef story fill:#f3f6fb,stroke:#c4ccd9,color:#15202e;",
        "  classDef block fill:#e3efe6,stroke:#6f9b7c,color:#15202e;",
    ]
    if links is not None:
        links.extend(drawn)
    return "\n".join(lines)


def _fr_hierarchy_node(hierarchy: dict, stem: str) -> tuple[dict | None, str | None]:
    """Locate the built hierarchy node for a stem within build_fr_hierarchy()'s tree.
    Returns (node, level) with level ∈ {epic, feature, story}, or the use case's
    own level (sea, fish) for a use case that roots Agile children. An orphan
    is found too, with its stories if it is a feature. (None, None) if the
    stem is not an FR in the hierarchy (another notation, or an unknown page)."""
    use_cases = hierarchy.get("use_cases") or []
    for root, is_uc in [(e, False) for e in hierarchy["epics"]] + [(u, True) for u in use_cases]:
        if root["stem"] == stem:
            return root, (root["level"] if is_uc else "epic")
        for f in root["features"]:
            if f["stem"] == stem:
                return f, "feature"
            for s in f["stories"]:
                if s["stem"] == stem:
                    return s, "story"
        for s in root["direct_stories"]:
            if s["stem"] == stem:
                return s, "story"
    for o in hierarchy.get("orphans") or []:
        if o["stem"] == stem:
            return o, o["level"]
        for s in o.get("stories") or []:
            if s["stem"] == stem:
                return s, "story"
    return None, None


def _fr_ancestors(stem: str) -> list[dict]:
    """The parent chain for an FR (root first), walked over the first-parent
    `parent:` edge across notations (a story may sit under a use case,
    DR-038). Powers the FR-page breadcrumb. Cycle-guarded."""
    pages = {p.stem: p for p in wiki.load_type("functional-requirement")}
    out: list[dict] = []
    cur, seen = pages.get(stem), {stem}
    while cur:
        ps = None
        for ref in cur.as_list("parent"):
            ps = links_module._link_stem(ref)
            if ps:
                break
        if not ps or ps in seen:
            break
        seen.add(ps)
        parent = pages.get(ps)
        if not parent:
            break
        out.append({"id": parent.id, "title": parent.title, "stem": parent.stem,
                    "url": f"/functional-requirements/{parent.stem}"})
        cur = parent
    return list(reversed(out))


_QR_SCENARIO = ("Source", "Stimulus", "Environment", "Response", "Measure")
_INLINE_EMPHASIS_RE = re.compile(r"\*(\S[^*]*?)\*")


def _emphasis(html: str) -> str:
    """Turn `*text*` into <em>text</em> in sanitised HTML. Only the text
    between tags is touched, so a `*` inside a tag or an attribute stays as it
    is, and an emphasis never spans a tag."""
    return "".join(part if part.startswith("<") else _INLINE_EMPHASIS_RE.sub(r"<em>\1</em>", part)
                   for part in re.split(r"(<[^>]*>)", html))


def _qr_details(page: wiki.Page, titles: dict[str, str],
                links: dict[str, tuple[str, str]]) -> dict:
    """What a quality requirement needs on the block list besides its title:
    its Q42 dimensions (DR-003), the priority and its Q42 quality scenario, so
    the list reads without opening every page. Empty scenario parts are left out."""
    scenario = [(label, _emphasis(html)) for label in _QR_SCENARIO
                if (html := render.extract_pam_bullet(page, label, titles, links))]
    dims = page.meta.get("dimensions") or []
    if isinstance(dims, str):
        dims = [dims]
    return {"dimensions": [str(d).strip() for d in dims if str(d).strip()],
            "priority": str(page.meta.get("priority") or "").strip(),
            "scenario": scenario}
