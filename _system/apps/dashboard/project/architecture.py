"""The architecture projections (arc42 sections 4 to 9).

Owns the decision records, the levels of building blocks and deployment nodes,
the white box, `state:` and the lifecycle marks in diagrams, the drivers and
the trace panels of a page, the steps and the sequence diagram of a runtime
scenario, and the deployment diagram.

May import `wiki`, `links`, `render`, `catalog` and `project.common`. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import re
from pathlib import Path

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes
import project.common  # what several projections share
import render  # sanitizer, wikilinks and Markdown
import wiki  # paths, pages, parse cache and loaders


# --- decision records (wiki/decisions/, MADR, DR-034) ----------------------

DECISION_KINDS = ["architecture", "business", "undefined"]


@wiki._request_cached
def load_decisions() -> list[dict]:
    """Decision records (wiki/decisions/) as list rows with rendered bodies, in
    ID order. `kind` outside architecture|business falls back to undefined."""
    titles = links_module.title_index()
    out = []
    for p in sorted(wiki.load_type("decision-record"), key=lambda p: p.id):
        kind = str(p.meta.get("kind") or "").strip().lower()
        decided = p.meta.get("decided") or p.meta.get("created") or ""
        out.append({
            "id": p.id,
            "stem": p.stem,
            "title": render._strip_inline_markdown(str(p.title)),
            "status": str(p.status or "draft").strip().lower(),
            "kind": kind if kind in DECISION_KINDS else "undefined",
            "decided": str(decided) or "—",
            "aliases": p.aliases,
            "url": links_module._page_url(p.folder, p.stem),
            "drivers": [l for g in build_drivers(p.stem) for l in g["links"]],
            "html": render.render_markdown(p.body, titles),
        })
    return out


# --- arc42 building blocks (A2) and the `drivers` link ----------------------
#
# One page per building block; levels come from `parent:` (a block whose parent
# is empty, a context page or missing is level 1). The tree, a block's white box
# and the "addressed by" side of `drivers:` are projections, never stored.


def _bb_parent(p: wiki.Page, bb_stems: set[str]) -> str | None:
    return next((s for s in links_module.links_of(p, "parent") if s in bb_stems), None)


def _level_tree(type_name: str, keep=None) -> list[dict]:
    """The `parent:` levels of one type as nested dicts, level 1 first, by ID.
    A page whose parent is empty, of another type, missing or filtered out by
    `keep` is level 1. Every page appears exactly once: one caught in a
    `parent:` cycle has no level-1 ancestor, so it is promoted to level 1
    instead of vanishing."""
    pages = {p.stem: p for p in wiki.load_type(type_name) if keep is None or keep(p)}
    stems = set(pages)
    children: dict[str | None, list[str]] = {}
    for s, p in pages.items():
        parent = next((x for x in links_module.links_of(p, "parent") if x in stems), None)
        children.setdefault(parent, []).append(s)
    seen: set[str] = set()

    def node(s: str) -> dict:
        seen.add(s)
        p = pages[s]
        kids = sorted((k for k in children.get(s, []) if k not in seen), key=lambda k: pages[k].id)
        return {"stem": s, "id": p.id, "title": p.title, "status": p.status,
                "state": page_state(p), "url": links_module._page_url(p.folder, s),
                "children": [node(k) for k in kids if k not in seen]}

    roots = [node(s) for s in sorted(children.get(None, []), key=lambda k: pages[k].id)]
    for s in sorted(stems - seen, key=lambda k: pages[k].id):
        if s not in seen:
            roots.append(node(s))
    return sorted(roots, key=lambda n: n["id"])


def build_bb_tree() -> list[dict]:
    """The building-block levels (see _level_tree)."""
    return _level_tree("building-block")


def _bb_find(nodes: list[dict], stem: str) -> dict | None:
    for n in nodes:
        if n["stem"] == stem:
            return n
        hit = _bb_find(n["children"], stem)
        if hit:
            return hit
    return None


# Lifecycle marks on architecture diagrams (DR-010): planned and target
# elements dashed when the diagram also shows others, outdated or deprecated
# ones grey, a dotted edge from a replaced element to its successor.
_DASHED = "stroke-dasharray:5 4"
_GREYED = "fill:#eceef2,stroke:#9aa3b2,color:#6b7280"
_FUTURE = ("planned", "target")


def lifecycle(p: wiki.Page) -> str:
    """The page's state, with `status: deprecated` counting as outdated."""
    return "outdated" if p.status == "deprecated" else page_state(p)


def _mixed(pages: list[wiki.Page]) -> bool:
    lcs = {lifecycle(p) for p in pages}
    return bool(lcs & set(_FUTURE)) and bool(lcs - set(_FUTURE))


def _lifecycle_lines(shown: dict[str, tuple[str, wiki.Page]]) -> list[str]:
    """Style lines and replaced-by edges for the elements of one diagram,
    given as {stem: (mermaid id, page)}."""
    mixed = _mixed([p for _, p in shown.values()])
    lines: list[str] = []
    for s, (nid, p) in shown.items():
        lc = lifecycle(p)
        if lc == "outdated":
            lines.append(f"  style {nid} {_GREYED}")
        elif lc in _FUTURE and mixed:
            lines.append(f"  style {nid} {_DASHED}")
        lines += [f'  {nid} -. "replaced by" .-> {shown[x][0]}'
                  for x in links_module.links_of(p, "superseded-by") if x in shown]
    return lines


def _lifecycle_suffix(p: wiki.Page, mixed: bool) -> str:
    lc = lifecycle(p)
    if lc == "outdated" or (lc in _FUTURE and mixed):
        return f" · {lc}"
    return " · being replaced" if links_module.links_of(p, "superseded-by") else ""


def build_whitebox(stem: str | None) -> str | None:
    """Mermaid flowchart of a block's inside (stem=None: the whole system, i.e.
    level 1): its children as boxes, their `uses:` among each other as arrows,
    external interfaces they use as neighbour boxes; lifecycle marks per
    _lifecycle_lines. None for a leaf."""
    tree = build_bb_tree()
    if stem is None:
        kids = tree
    else:
        me = _bb_find(tree, stem)
        kids = me["children"] if me else []
    if not kids:
        return None
    inside = {n["stem"] for n in kids}
    pages = {p.stem: p for p in wiki.load_type("building-block")}
    eifs = {p.stem: p for p in wiki.load_type("external-interface")}
    lines = ["flowchart LR"]
    mixed = _mixed([pages[n["stem"]] for n in kids])
    for n in kids:
        sfx = _lifecycle_suffix(pages[n["stem"]], mixed)
        lines.append(f'  {project.common._diagram_node_id(n["id"])}["{n["id"]} · {project.common._clean_label(n["title"])}{sfx}"]:::block')
    neighbours: list[str] = []
    edges: list[str] = []
    outside: list[str] = []
    for n in kids:
        for t in links_module.links_of(pages[n["stem"]], "uses"):
            if t in inside:
                edges.append(f'  {project.common._diagram_node_id(n["id"])} --> {project.common._diagram_node_id(pages[t].id)}')
            elif t in pages:
                # a block elsewhere in the tree: drawn as a neighbour, so the
                # dependency stays visible on this level
                if t not in outside:
                    outside.append(t)
                edges.append(f'  {project.common._diagram_node_id(n["id"])} --> {project.common._diagram_node_id(pages[t].id)}')
            elif t in eifs:
                if t not in neighbours:
                    neighbours.append(t)
                edges.append(f'  {project.common._diagram_node_id(n["id"])} --> {project.common._diagram_node_id(eifs[t].id)}')
    for t in outside:
        lines.append(f'  {project.common._diagram_node_id(pages[t].id)}["{pages[t].id} · {project.common._clean_label(pages[t].title)}'
                     f'{_lifecycle_suffix(pages[t], mixed)}"]:::outside')
    for t in neighbours:
        lines.append(f'  {project.common._diagram_node_id(eifs[t].id)}["{project.common._clean_label(eifs[t].title)}"]:::system')
    lines += edges
    lines += _lifecycle_lines({s: (project.common._diagram_node_id(pages[s].id), pages[s])
                               for s in [n["stem"] for n in kids] + outside})
    lines += [
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef outside fill:#e3ecf7,stroke:#2f6fb3,stroke-dasharray:4 3,color:#15202e;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)


def _link_groups(stems: list[str]) -> list[dict]:
    """Stems as link dicts grouped by type prefix, in the relations-panel order."""
    by_stem = {p.stem: p for p in wiki.load_all_pages()}
    buckets: dict[str, list] = {}
    for s in stems:
        p = by_stem[s]
        t = project.common._type_of(s)
        buckets.setdefault(t, []).append({"id": p.id, "label": p.title, "type": t,
                                          "url": links_module._page_url(p.folder, s)})
    order = catalog.prefix_order()
    ordered = order + [t for t in buckets if t not in order]
    return [{"type": t, "label": catalog.group_label(t), "links": buckets[t]}
            for t in ordered if t in buckets]


def build_drivers(stem: str) -> list[dict]:
    """The requirements a decision record or building block rests on."""
    p = next((q for q in wiki.load_all_pages() if q.stem == stem), None)
    return _link_groups(links_module.links_of(p, "drivers")) if p else []


# --- arc42 A1/A3/A4/A5 and `state` (DR-010) ----------------------------------
#
# Every architecture page says whether it describes today's landscape or the
# target (`state:`); a replaced current-state page names its successor in
# `superseded-by:`. Crosscutting concepts govern blocks and nodes
# (`applies-to:`), runtime scenarios order interactions (`steps:`) and name the
# requirement they carry out (`realizes:`), nodes host blocks and connect to
# each other. All reverse sides are projected here, never stored.

ARCH_TYPES = ("solution-strategy", "building-block", "crosscutting-concept", "runtime-scenario",
              "deployment-node")
# The types whose `drivers:` the Addressed-by panel reads (proj-addressed-by).
# A runtime scenario names its requirement in `realizes:` instead.
_DRIVER_TYPES = ("decision-record",) + tuple(t for t in ARCH_TYPES if t != "runtime-scenario")
_STATES = ("outdated", "current", "planned", "target")


def page_state(p: wiki.Page) -> str:
    """'current' or 'target'; empty or unknown values count as target."""
    v = str(p.meta.get("state") or "").strip().lower()
    return v if v in _STATES else "target"


def _scalar(v: object) -> object:
    """An unquoted `[[stem]]` in YAML is a nested list [['stem']]: unwrap it to
    'stem' so structured entries accept the same link forms as links_of."""
    while isinstance(v, (list, tuple)):
        v = v[0] if v else ""
    return v


def _struct_targets(p: wiki.Page, field: str, keys: tuple[str, ...]) -> list[str]:
    """Existing target stems named under `keys` in a structured-list field
    (`steps:` from/to, `connects:` to), in order, without duplicates."""
    by_stem = {q.stem for q in wiki.load_all_pages()}
    out: list[str] = []
    entries = p.meta.get(field) or []
    for e in entries if isinstance(entries, list) else []:
        if not isinstance(e, dict):
            continue
        for k in keys:
            v = _scalar(e.get(k))
            t = links_module._link_stem(v) if v else ""
            if t and t in by_stem and t not in out:
                out.append(t)
    return out


def build_addressed_by(stem: str) -> list[dict]:
    """Decision records and architecture pages whose `drivers:` name this page."""
    hits = [p.stem for t in _DRIVER_TYPES for p in sorted(wiki.load_type(t), key=lambda q: q.id)
            if stem in links_module.links_of(p, "drivers")]
    return _link_groups(hits)


def build_realized_by(stem: str) -> list[dict]:
    """The runtime scenarios whose `realizes:` name this page (rel-realizes)."""
    return _link_groups([p.stem for p in sorted(wiki.load_type("runtime-scenario"), key=lambda q: q.id)
                         if stem in links_module.links_of(p, "realizes")])


# Requirement types a `drivers:` link may point at (rel-drivers).
_ADDRESSABLE = ("goal", "functional-requirement", "quality-requirement", "constraint",
                "activity-model")
# Types a runtime scenario's `realizes:` may point at (rel-realizes).
_REALIZABLE = ("functional-requirement", "activity-model")


def build_trace(stem: str, folder: str) -> dict:
    """The typed traceability panels of one page: drivers + shaped-by on
    architecture pages and decision records, the arc42 forward and reverse
    links, addressed-by and realized-by on a requirement. Empty lists where a
    panel does not apply."""
    keys = ("drivers", "realizes", "shaped_by", "used_by", "addressed_by", "realized_by", "replaced_by",
            "replaces", "applies_to", "governed_by", "hosts", "deployed_on", "takes_part_in")
    trace: dict = {k: [] for k in keys}
    me = (next((p for p in wiki.load_folder(folder) if p.stem == stem), None)
          if wiki._is(folder, *ARCH_TYPES, "decision-record") else None)
    if wiki._is(folder, *_DRIVER_TYPES):
        trace["drivers"] = build_drivers(stem)
    if wiki._is(folder, "runtime-scenario") and me:
        trace["realizes"] = _link_groups(links_module.links_of(me, "realizes"))
    if me and not wiki._is(folder, "decision-record"):
        trace["shaped_by"] = _link_groups(links_module.links_of(me, "decisions"))
    if me:
        trace["replaced_by"] = _link_groups(links_module.links_of(me, "superseded-by"))
        trace["replaces"] = _link_groups([p.stem for p in sorted(wiki.load_folder(folder), key=lambda q: q.id)
                                          if stem in links_module.links_of(p, "superseded-by")])
    if wiki._is(folder, "building-block"):
        trace["used_by"] = _link_groups([p.stem for p in sorted(wiki.load_folder(folder), key=lambda q: q.id)
                                         if stem in links_module.links_of(p, "uses")])
        trace["deployed_on"] = _link_groups([p.stem for p in sorted(wiki.load_type("deployment-node"), key=lambda q: q.id)
                                             if stem in links_module.links_of(p, "hosts")])
    if wiki._is(folder, "building-block", "deployment-node"):
        trace["governed_by"] = _link_groups([p.stem for p in sorted(wiki.load_type("crosscutting-concept"), key=lambda q: q.id)
                                             if stem in links_module.links_of(p, "applies-to")])
    if wiki._is(folder, "building-block", "deployment-node", "external-interface", "stakeholder"):
        trace["takes_part_in"] = _link_groups(
            [p.stem for p in sorted(wiki.load_type("runtime-scenario"), key=lambda q: q.id)
             if stem in _struct_targets(p, "steps", ("from", "to"))])
    if wiki._is(folder, "crosscutting-concept") and me:
        trace["applies_to"] = _link_groups(links_module.links_of(me, "applies-to"))
    if wiki._is(folder, "deployment-node") and me:
        trace["hosts"] = _link_groups(links_module.links_of(me, "hosts"))
    if wiki._is(folder, *_ADDRESSABLE):
        trace["addressed_by"] = build_addressed_by(stem)
    if wiki._is(folder, *_REALIZABLE):
        trace["realized_by"] = build_realized_by(stem)
    # the stories that realize a use case are its breakdown on the FR page
    # (DR-038); realized_by holds the runtime scenarios only
    return trace


# Runtime scenario (A4): the `steps:` list is the model, the sequence diagram
# its projection.

def _endpoint_stem(text: str, by_stem: dict) -> str:
    """The stem a `from`/`to` names: a wikilink's target, or plain text that is
    a page stem or a path ending in one. Other plain text keeps every
    character, `/` included ("TCP/IP Gateway")."""
    if "[[" in text:
        return links_module._link_stem(text)
    if text in by_stem:
        return text
    last = text.rsplit("/", 1)[-1].strip()
    return last if last in by_stem else text


def _endpoint(raw: object, by_stem: dict) -> tuple[str | None, str]:
    """(stem or None, label) of one `from`/`to`: an existing page gives its
    stem and 'ID · title' (a stakeholder or interface just its title); a
    dangling link or plain text keeps its text as the label."""
    text = str(_scalar(raw) or "").strip()
    stem = _endpoint_stem(text, by_stem) if text else ""
    p = by_stem.get(stem)
    if not p:
        return None, stem or "?"
    if wiki._is(p.folder, "stakeholder", "external-interface"):
        return stem, project.common._clean_label(p.title)
    return stem, f"{p.id} · {project.common._clean_label(p.title)}"


def _entries(p: wiki.Page, field: str) -> list:
    v = p.meta.get(field) or []
    return v if isinstance(v, list) else [v]


def steps_of(p: wiki.Page) -> list[dict]:
    """The scenario's steps in order, each with its 1-based position in
    `steps:`. Entries that are not mappings are not steps; runtime_hints
    names them."""
    by_stem = {q.stem: q for q in wiki.load_all_pages()}
    out: list[dict] = []
    for n, e in enumerate(_entries(p, "steps"), 1):
        if not isinstance(e, dict):
            continue
        fs, fl = _endpoint(e.get("from"), by_stem)
        ts, tl = _endpoint(e.get("to"), by_stem)
        out.append({"n": n, "from_stem": fs, "from_label": fl, "to_stem": ts, "to_label": tl,
                    "message": str(e.get("message") or ""), "note": str(e.get("note") or "")})
    return out


_MM_ENTITY = {"#": "#35;", ";": "#59;"}


def _mm_escape(s: str) -> str:
    """`#` and `;` as mermaid entity codes, in one pass (a second pass would
    re-escape the `;` of `#35;`), whitespace collapsed."""
    return re.sub(r"[#;]", lambda m: _MM_ENTITY[m.group()], " ".join(s.split()))


def _seq_text(s: str) -> str:
    """Message/note text that cannot end the mermaid statement early."""
    return _mm_escape(s)


def build_sequence_diagram(stem: str) -> str | None:
    """Mermaid sequenceDiagram of a runtime scenario: one participant per distinct
    end in order of first appearance (stakeholders as actors), one arrow per
    step, the step's note over the receiver. None without steps."""
    p = next((q for q in wiki.load_type("runtime-scenario") if q.stem == stem), None)
    steps = steps_of(p) if p else []
    if not steps:
        return None
    by_stem = {q.stem: q for q in wiki.load_all_pages()}
    # Ids are L1, L2, … per distinct end — an existing page by its stem, any
    # other end by its text — so no name can collide with a mermaid keyword
    # (`end`, `box`, `note` …) or sanitise onto another end's id.
    order: list[tuple[str, str, str]] = []          # (participant id, label, keyword)
    nid_of: dict[str, str] = {}

    def key(sstem: str | None, label: str) -> str:
        return f"page:{sstem}" if sstem else f"text:{label}"

    for st in steps:
        for sstem, label in ((st["from_stem"], st["from_label"]), (st["to_stem"], st["to_label"])):
            k = key(sstem, label)
            if k in nid_of:
                continue
            nid_of[k] = f"L{len(nid_of) + 1}"
            kw = "actor" if sstem and wiki._is(by_stem[sstem].folder, "stakeholder") else "participant"
            order.append((nid_of[k], _seq_text(label), kw))
    lines = ["sequenceDiagram"] + [f"  {kw} {nid} as {label}" for nid, label, kw in order]
    for st in steps:
        a = nid_of[key(st["from_stem"], st["from_label"])]
        b = nid_of[key(st["to_stem"], st["to_label"])]
        lines.append(f"  {a}->>{b}: {_seq_text(st['message']) or ' '}")
        if st["note"]:
            lines.append(f"  Note over {b}: {_seq_text(st['note'])}")
    return "\n".join(lines)


def _bb_ancestors(stem: str, pages: dict) -> list[str]:
    """The block and its `parent:` chain, cycle-safe."""
    out: list[str] = []
    while stem and stem not in out and stem in pages:
        out.append(stem)
        stem = _bb_parent(pages[stem], set(pages))
    return out


def runtime_hints(stem: str) -> list[str]:
    """Where a scenario disagrees with the rest of the wiki
    (rule-runtime-matches-uses): entries that are not steps, empty ends, ends
    that name no page, and steps between two blocks with no `uses:` edge
    between them or their ancestors. Advisory."""
    p = next((q for q in wiki.load_type("runtime-scenario") if q.stem == stem), None)
    if not p:
        return []
    blocks = {q.stem: q for q in wiki.load_type("building-block")}
    hints: list[str] = []
    for n, e in enumerate(_entries(p, "steps"), 1):
        if not isinstance(e, dict):
            hints.append(f"step {n}: not a {{from, to, message}} entry, not drawn")
    for st in steps_of(p):
        for end in ("from", "to"):
            label, sstem = st[f"{end}_label"], st[f"{end}_stem"]
            h = f"step {st['n']}: {end}: is empty" if label == "?" else f"{label}: no such page"
            if not sstem and h not in hints:
                hints.append(h)
        a, b = st["from_stem"], st["to_stem"]
        if a in blocks and b in blocks and a != b:
            targets = set(_bb_ancestors(b, blocks))
            if not any(set(links_module.links_of(blocks[x], "uses")) & targets for x in _bb_ancestors(a, blocks)):
                h = f"{blocks[a].id} → {blocks[b].id}: no uses: edge"
                if h not in hints:
                    hints.append(h)
    return hints


# Deployment view (A3): nodes nested by `parent:`, the blocks they host inside
# them, `connects:` as protocol-labelled edges. One diagram per state, so
# today's landscape and the target are never mixed.

def build_node_tree() -> list[dict]:
    """The deployment-node levels."""
    return _level_tree("deployment-node")


def _edge_text(s: object) -> str:
    """Edge label text that survives inside mermaid's double quotes."""
    return _mm_escape(str(s or "")).replace('"', "'")


def build_deployment_diagram(root: str | None = None,
                             links: list[dict] | None = None) -> str | None:
    """Mermaid flowchart of every deployment node — existing, planned and
    replaced in one picture, marked per _lifecycle_lines — or of the subtree
    under `root`. A node with children or hosted blocks is a subgraph; hosted
    blocks are boxes inside it; `connects:` edges carry their protocol;
    external interfaces are neighbour boxes. None when no node matches. Edges
    to nodes outside a subtree are left out; deployment_hints names the
    entries that cannot be drawn. `links`, when given, receives every page
    drawn as a node: deployment nodes, then blocks, then interfaces (QR-001)."""
    tree = build_node_tree()
    if root is not None:
        me = _bb_find(tree, root)
        tree = [me] if me else []
    if not tree:
        return None
    nodes = {p.stem: p for p in wiki.load_type("deployment-node")}
    blocks = {p.stem: p for p in wiki.load_type("building-block")}
    eifs = {p.stem: p for p in wiki.load_type("external-interface")}
    shown: set[str] = set()
    marked: dict[str, tuple[str, wiki.Page]] = {}
    lines = ["flowchart TB"]

    def walk(ns: list[dict]):
        for n in ns:
            yield n
            yield from walk(n["children"])

    inside = [nodes[n["stem"]] for n in walk(tree)]
    inside += [blocks[b] for p in inside for b in links_module.links_of(p, "hosts") if b in blocks]
    mixed = _mixed(inside)

    def emit(n: dict, depth: int) -> None:
        p, pad = nodes[n["stem"]], "  " * depth
        nid = project.common._diagram_node_id(p.id)
        label = f'{p.id} · {project.common._clean_label(p.title)}'
        tech = project.common._clean_label(p.meta.get("technology") or "")
        if tech:
            label += f" ({tech})"
        label += _lifecycle_suffix(p, mixed)
        shown.add(n["stem"])
        marked[n["stem"]] = (nid, p)
        hosted = [b for b in links_module.links_of(p, "hosts") if b in blocks]
        if not n["children"] and not hosted:
            lines.append(f'{pad}{nid}["{label}"]:::infra')
            return
        lines.append(f'{pad}subgraph {nid}["{label}"]')
        for b in hosted:
            bp = blocks[b]
            bid = f"{nid}_{project.common._diagram_node_id(bp.id)}"
            marked[f"{n['stem']}/{b}"] = (bid, bp)
            lines.append(f'{pad}  {bid}["{bp.id} · {project.common._clean_label(bp.title)}{_lifecycle_suffix(bp, mixed)}"]:::block')
        for c in n["children"]:
            emit(c, depth + 1)
        lines.append(f"{pad}end")

    for n in tree:
        emit(n, 1)
    neighbours: list[str] = []
    edges: list[str] = []
    for s in sorted(shown, key=lambda k: nodes[k].id):
        for e in _entries(nodes[s], "connects"):
            if not isinstance(e, dict):
                continue
            v = _scalar(e.get("to"))
            t = links_module._link_stem(v) if v else ""
            if t in shown:
                target = project.common._diagram_node_id(nodes[t].id)
            elif t in eifs:
                target = project.common._diagram_node_id(eifs[t].id)
                if t not in neighbours:
                    neighbours.append(t)
            else:
                continue
            proto = " · ".join(x for x in (_edge_text(e.get("protocol")), _edge_text(e.get("note"))) if x)
            arrow = f' -- "{proto}" --> ' if proto else " --> "
            edges.append(f"  {project.common._diagram_node_id(nodes[s].id)}{arrow}{target}")
    for t in neighbours:
        lines.append(f'  {project.common._diagram_node_id(eifs[t].id)}["{project.common._clean_label(eifs[t].title)}"]:::system')
    lines += edges
    if links is not None:
        hosted = {b for s in shown for b in links_module.links_of(nodes[s], "hosts") if b in blocks}
        links.extend(project.common._node_link(nodes[s]) for s in sorted(shown, key=lambda k: nodes[k].id))
        links.extend(project.common._node_link(blocks[b]) for b in sorted(hosted, key=lambda k: blocks[k].id))
        links.extend(project.common._node_link(eifs[t]) for t in neighbours)
    lines += _lifecycle_lines(dict(sorted(marked.items(), key=lambda kv: kv[1][0])))
    lines += [
        "  classDef infra fill:#e3ecf7,stroke:#2f6fb3,color:#15202e;",
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)


def deployment_hints(stem: str | None = None) -> list[str]:
    """What the deployment diagrams leave out, for one node or all: `connects:`
    entries that are not mappings or name no page, `hosts:` entries that are
    not building blocks. Advisory."""
    nodes = {p.stem: p for p in wiki.load_type("deployment-node")}
    blocks = {p.stem for p in wiki.load_type("building-block")}
    pages = {p.stem for p in wiki.load_all_pages()}
    hints: list[str] = []
    for s in sorted(nodes, key=lambda k: nodes[k].id) if stem is None else [stem]:
        p = nodes.get(s)
        if not p:
            continue
        for n, e in enumerate(_entries(p, "connects"), 1):
            if not isinstance(e, dict):
                hints.append(f"{p.id} connects entry {n}: not a {{to, protocol}} entry, not drawn")
                continue
            v = _scalar(e.get("to"))
            t = links_module._link_stem(v) if v else ""
            if not t:
                hints.append(f"{p.id} connects entry {n}: to: is empty, not drawn")
            elif t not in pages:
                hints.append(f"{p.id} connects {t}: no such page")
        for b in links_module.links_of(p, "hosts"):
            if b not in blocks:
                hints.append(f"{p.id} hosts {b}: not a building block, not drawn")
    return hints


def trace_stems(trace: dict) -> set[str]:
    """Every page a trace panel already shows, to keep it out of the generic one."""
    return {Path(l["url"]).name for groups in trace.values() for g in groups for l in g["links"]}
