"""The context flows (req42 section 03).

Owns the flow table beneath the context diagram (build_context_flows) and
what it shares with the diagram: the layout bands, the node and edge labels
and an interface's flows by direction.

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
