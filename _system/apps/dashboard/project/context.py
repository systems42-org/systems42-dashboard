"""The context diagram and its flows (req42 section 03).

Owns the context diagram (build_context_diagram), the flow table beneath it
(build_context_flows) and what the two share: the layout bands, the node and
edge labels and an interface's flows by direction. The caller passes the
system's name.

May import `wiki`, `links` and `project.common`. No Flask import and no import
of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import links as links_module  # link resolver and indexes
import project.common  # labels shared by the projections
import wiki  # paths, pages, parse cache and loaders


# Layout bands (DR-026 `tier:`). Neighbours that feed the system are ranked
# BEFORE the centre, those it serves AFTER it, so mermaid's LR layout puts
# supply/support on the left and demand/operations on the right instead of
# scattering fourteen nodes around one box.
_TIER_BANDS = [
    ("supply", "Supply", "left"),
    ("support", "Support", "left"),
    ("demand", "Demand", "right"),
    ("core-operations", "Core operations", "right"),
]
_TIER_LABEL = {k: lbl for k, lbl, _ in _TIER_BANDS}


def _eif_node_label(p) -> str:
    """Short label for a diagram node: `short_title` wins, then `title`, and
    `partner` only as a last resort — `partner` is a full sentence by design and
    is what made the projection unreadable at fourteen nodes."""
    return project.common._clean_label(p.meta.get("short_title") or p.title or p.meta.get("partner"))


def _flow_edge_label(flows: list[dict]) -> str:
    """One label for one line. Each flow's `label:` is a word or two; duplicates
    collapse (a round trip about the same thing reads once), and a flow with no
    label falls back to its `data`, clipped."""
    seen: list[str] = []
    for f in flows:
        lab = project.common._clean_label(f.get("label") or "")
        if not lab:
            lab = project.common._clean_label(f.get("data") or "")
            if len(lab) > 24:
                lab = lab[:23].rstrip() + "…"
        if lab and lab not in seen:
            seen.append(lab)
    return " · ".join(seen)


def _eif_flows(p) -> tuple[list[dict], list[dict], list[dict]]:
    """(inbound, outbound, all-in-document-order) flow dicts for one interface.
    The third is what labels the edge, so the label reads in the order the author
    wrote the flows rather than in-then-out."""
    flows = [f for f in p.as_list("flows") if isinstance(f, dict)]
    d = lambda f: str(f.get("direction", "")).lower()
    return ([f for f in flows if d(f) in ("inbound", "bidirectional")],
            [f for f in flows if d(f) in ("outbound", "bidirectional")],
            flows)


def build_context_flows() -> list[dict]:
    """The diagram's edges, spelled out. One group per neighbour, both
    directions listed — this is where the detail that was removed from the
    node and edge labels goes (DR-026). `unknown`/empty cells come back as
    None so the template can render a dash instead of the word."""
    def cell(v) -> str | None:
        s = project.common._clean_label(v or "")
        return None if not s or s.lower() in ("unknown", "n/a", "none") else s

    groups: list[dict] = []
    for p in wiki.load_type("external-interface"):
        if p.status == "deprecated":
            continue
        ins, outs, ordered = _eif_flows(p)
        if not (ins or outs):
            continue
        rows = []
        for f, direction in [(f, "in") for f in ins] + [(f, "out") for f in outs]:
            rows.append({"direction": direction, "data": cell(f.get("data")) or "—",
                         "format": cell(f.get("format")), "trigger": cell(f.get("trigger"))})
        groups.append({
            "id": p.id, "stem": p.stem, "url": links_module._page_url(p.folder, p.stem), "name": _eif_node_label(p),
            "partner": project.common._clean_label(p.meta.get("partner") or ""),
            "tier": _TIER_LABEL.get(str(p.meta.get("tier") or "").strip().lower(), ""),
            "label": _flow_edge_label(ordered), "rows": rows,
        })
    return groups


# --- context diagram (req42 block 03) --------------------------------------
#
# The system context is NOT stored as a diagram (DR-013, ISS-010): it is
# projected live from the structured edges — each external interface's `flows`
# and each stakeholder's `provides:`/`receives:` — into a mermaid flowchart.
# Center = the system (blueish box); systems/organizations = light-grey boxes;
# human roles = actor symbol ("Person"). Stakeholders are merged/hidden/shaped per their
# `context_role`/`nature` fields (DR-014). No node links (not needed yet).


def build_context_diagram(system_name: str, center: str | None = None,
                          links: list[dict] | None = None) -> str | None:
    """Project a mermaid context diagram from EIF.flows + STK.provides/receives.

    One line per neighbour, not one per direction: an interface with both an
    inbound and an outbound flow draws a single `<-->` edge carrying a single
    label, and the two directions are spelled out in the flow table beneath
    (build_context_flows). Returns None when no edges exist yet. Pure and
    string-only, so it can be reused outside the request cycle. `links`, when
    given, receives every page drawn as a node (QR-001)."""
    center = center or project.common._clean_label(system_name, drop_parenthetical=False)
    drawn: list[dict] = []
    core = "CORE"
    bands: dict[str, list[tuple[str, str, str]]] = {}   # tier -> [(nid, label, cls)]
    loose: list[tuple[str, str, str]] = []
    edges: list[str] = []

    def add_edge(nid: str, ins: list, outs: list, side: str, ordered: list | None = None) -> None:
        """`side` decides which end of the edge the neighbour sits on, which is
        what actually positions it: mermaid ranks the source before the target."""
        if ins and outs:
            lab = _flow_edge_label(ordered if ordered is not None else ins + outs)
            src, arrow, dst = (nid, "<-->", core) if side == "left" else (core, "<-->", nid)
        elif ins:
            lab, src, arrow, dst = _flow_edge_label(ins), nid, "-->", core
        elif outs:
            lab, src, arrow, dst = _flow_edge_label(outs), core, "-->", nid
        else:
            return
        edges.append(f'  {src} {arrow}|"{lab}"| {dst}' if lab else f"  {src} {arrow} {dst}")

    # real external systems — one node each (DR-013), one line each (DR-026).
    # A deprecated interface is one the boundary decision moved *inside* the
    # system (ISS-010), so it is no longer a neighbour and must not be drawn.
    for p in wiki.load_type("external-interface"):
        if p.status == "deprecated":
            continue
        ins, outs, ordered = _eif_flows(p)
        if not (ins or outs):
            continue
        nid = project.common._diagram_node_id(p.id)
        tier = str(p.meta.get("tier") or "").strip().lower()
        side = next((s for k, _, s in _TIER_BANDS if k == tier), "left")
        (bands.setdefault(tier, []) if tier in _TIER_LABEL else loose).append(
            (nid, _eif_node_label(p), "system"))
        add_edge(nid, ins, outs, side, ordered)
        drawn.append(project.common._node_link(p))

    # user roles — flows live on the stakeholder, not as EIF nodes. DR-014:
    # several stakeholders sharing a `context_role` merge into ONE node (union of
    # their flows); `context_role: none` hides the role; `nature: organization`
    # draws a box instead of the person/actor symbol.
    def _union(dst: list, src) -> None:
        for x in (src or []):
            if x not in dst:
                dst.append(x)

    groups: dict[str, dict] = {}   # label -> {prov, recv, cls, order}
    for p in wiki.load_type("stakeholder"):
        prov, recv = p.as_list("provides"), p.as_list("receives")
        if not (prov or recv):
            continue
        raw_role = p.meta.get("context_role")
        if isinstance(raw_role, str) and raw_role.strip().lower() == "none":
            continue
        label = project.common._clean_label(raw_role) if raw_role else project.common._clean_label(p.title)
        is_org = str(p.meta.get("nature", "person")).strip().lower() == "organization"
        g = groups.get(label)
        if g is None:
            g = groups[label] = {"prov": [], "recv": [], "cls": "actor", "order": len(groups)}
        if is_org:
            g["cls"] = "system"          # organizations/systems share the box style
        _union(g["prov"], prov)
        _union(g["recv"], recv)
        drawn.append(project.common._node_link(p))   # a merged role node links each of its stakeholders

    for label, g in sorted(groups.items(), key=lambda kv: kv[1]["order"]):
        nid = project.common._diagram_node_id(label)
        loose.append((nid, label, g["cls"]))
        ins = [{"data": x} for x in g["prov"]]
        outs = [{"data": x} for x in g["recv"]]
        add_edge(nid, ins, outs, "left")

    if not edges:
        return None
    if links is not None:
        links.extend(drawn)

    def node_line(nid: str, label: str, cls: str) -> str:
        # persons get the actor symbol (stadium + "Person"); systems/orgs are boxes
        return (f'  {nid}(["Person · {label}"]):::actor' if cls == "actor"
                else f'  {nid}["{label}"]:::{cls}')

    lines = ["flowchart LR"]
    for tier, tier_label, _ in _TIER_BANDS:
        if not bands.get(tier):
            continue
        lines.append(f'  subgraph {project.common._diagram_node_id(tier)}["{tier_label}"]')
        lines.append("    direction TB")
        lines += ["  " + node_line(*n) for n in bands[tier]]
        lines.append("  end")
    lines.append(f'  {core}["{project.common._clean_label(center)}"]:::core')
    lines += [node_line(*n) for n in loose]
    lines += edges
    lines += [
        "  classDef core fill:#2f6fb3,stroke:#7fc0ff,stroke-width:2px,color:#ffffff,font-weight:bold;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef actor fill:#f3f6fb,stroke:#aeb8c9,color:#15202e;",
    ]
    return "\n".join(lines)
