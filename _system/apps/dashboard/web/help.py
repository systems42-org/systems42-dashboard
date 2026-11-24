"""The pages that explain: help, the method and the metamodel.

Owns the help page, the method page with the three loops, and the
/metamodel page with the builders of its graph, tables and examples.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re
from pathlib import Path

import markdown as md
from flask import Blueprint, render_template
from markupsafe import escape

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import metamodel  # reader for _system/metamodel/ (DR-035)
import render  # sanitizer, wikilinks and Markdown
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders
import project.common  # what several projections share
import web.common  # what several route groups share

bp = Blueprint("help", __name__)


# The issue that holds the open definition of the clarify loop. Matched by
# its full stem: a project numbers its own issues, so a bare ISS-002 there is
# a different question.
CLARIFY_ISSUE = "ISS-002-define-the-clarify-loop"


@bp.route("/method")
def method_view():
    """The three loops, capture, inspect and clarify, by their principles
    (FR-011). Clarify links its issue while that issue is open."""
    issue = next((p for p in wiki.load_type("issue")
                  if p.stem == CLARIFY_ISSUE and project.common.is_open_issue(p.status)), None)
    clarify = ({"id": issue.id, "title": issue.title, "url": links_module._page_url(issue.folder, issue.stem)}
               if issue else None)
    return render_template("method.html", clarify_issue=clarify)


@bp.route("/help")
def help_view():
    """Dashboard help, rendered from help.md: how to read the page, and the
    Systems42 model in brief with the sections diagram (DR-033)."""
    try:
        text = settings.HELP_PATH.read_text(encoding="utf-8")
    except OSError:
        text = "# Help\n\nhelp.md is missing from the image."
    img = (f'<figure class="help-diagram"><img src="{web.common.static_url("systems42-sections.svg")}" '
           f'alt="Systems42 sections: req42, arc42 and Common" width="660" height="608"></figure>')
    html = render.wrap_tables(md.markdown(text.replace("{{DIAGRAM}}", img), extensions=["extra", "sane_lists"]))
    return render_template("help.html", html=html)

# --- /metamodel: the explicit metamodel as a help page (DR-035) --------------
#
# The schema lives in `_system/metamodel/` (one page per type, relation,
# framework section, projection and rule; `metamodel.py` reads it). This page
# explains it the way the term network explains the glossary: a graph of the
# types with their declared relations as edges, grouped by section, and
# tables with the definition of each construct plus a live example from the
# wiki. Nothing here is a second statement of the schema — every cell comes
# from the metamodel pages, and the examples from the vault.

_MM_DR_RE = re.compile(r"^DR-\d{3}\b")
# a same-site path only: `//host` and `/\host` would leave the site
_MM_ROUTE_RE = re.compile(r"^(/(?![/\\])[^\s,;)]*)")


def _mm_dr_link(ref: str, label: str = "") -> str:
    """A decision record a metamodel page cites, as a link to its page — only
    when the vault has a page with exactly that stem. The metamodel ships to
    every project, but meta's decisions do not (DR-034), and a project numbers
    its own from DR-001: a bare 'DR-013' there is a different decision. So a
    bare ID is never linked, and a full stem ('DR-013-data-flows-as-…') the
    vault lacks stays plain text instead of a link that 404s."""
    text = escape(label or ref)
    if ref in {p.stem for p in wiki.load_type("decision-record")}:
        return f'<a class="wl" href="{escape(links_module._page_url(catalog.folder("decision-record"), ref))}">{text}</a>'
    return str(text)


def _mm_wikilinks(text: str, anchors: dict[str, str]) -> str:
    """Resolve the wikilinks metamodel pages use among themselves: another
    metamodel page → an in-page anchor, a method anchor (PAM, INVEST, …) → its
    entry in the Anchors section, a decision record → its page, anything else
    → a chip."""
    def repl(m: re.Match) -> str:
        target, alias = m.group(1).strip(), (m.group(2) or "").strip()
        base = target.split("/")[-1]
        # a framework has no row of its own, so `[[req42]]` means the anchor
        if base in anchors and not anchors[base].startswith("fw-"):
            return f'<a class="wl" href="#{anchors[base]}">{escape(alias or base)}</a>'
        if a := render.anchor_lookup().get(base.lower()):
            return (f'<a class="wl wl-anchor" href="#{a["id"]}" '
                    f'title="{escape(render.anchor_title(a))}">{escape(alias or a["name"])}</a>')
        if base in anchors:
            return f'<a class="wl" href="#{anchors[base]}">{escape(alias or base)}</a>'
        if _MM_DR_RE.match(base):
            return _mm_dr_link(base, alias)
        return f'<span class="mm-anchor">{escape(alias or base)}</span>'
    return render.outside_code(text, lambda t: wiki.WIKILINK_RE.sub(repl, t))


def _mm_html(text: str, anchors: dict[str, str]) -> str:
    """A metamodel page body (or a summary line) as HTML."""
    return render.sanitize_html(render.wrap_tables(md.markdown(_mm_wikilinks(render._unwrap_prose(text or ""), anchors),
                                                 extensions=["extra", "sane_lists"])))


def _mm_inline(text: str, anchors: dict[str, str]) -> str:
    """One line of markdown without the wrapping paragraph, for a table cell."""
    html = _mm_html(text, anchors).strip()
    if html.startswith("<p>") and html.endswith("</p>") and html.count("<p>") == 1:
        html = html[3:-4]
    return html


# Which page of a folder serves as the example: the most mature first, then the
# lowest ID — the page a reader would open first anyway.
_MM_EXAMPLE_RANK = {"accepted": 0, "review": 1, "draft": 2,
                    "open": 0, "in-progress": 1, "resolved": 2, "wontfix": 3,
                    "ingested": 0}


def _mm_example(t: dict) -> dict:
    """A live example page for a type: `{count}` plus, when the folder has
    pages, the id / title / url / status of the one that represents it best."""
    folder = str(t.get("folder") or "")
    if folder.startswith("raw/"):
        pages = wiki.load_sources()
        url = lambda p: f"/source/{p.stem}"             # noqa: E731
    else:
        name = Path(folder).name
        pages = wiki.load_folder(name)
        url = lambda p: links_module._page_url(name, p.stem)         # noqa: E731
    if not pages:
        return {"count": 0}
    best = min(pages, key=lambda p: (_MM_EXAMPLE_RANK.get(p.status, 9), p.id))
    return {"count": len(pages), "id": best.id, "title": best.title, "url": url(best),
            "status": best.status, "stereotype": best.meta.get("stereotype") or "",
            "notation": best.meta.get("notation") or "", "level": best.meta.get("level") or ""}


def build_metamodel_graph(mm: dict) -> dict:
    """The metamodel as cytoscape elements: one node per type, a compound
    parent per framework block that holds a type, one directed edge per
    declared relation edge between two named types. Relations declared on
    `any` (sources, related) would connect everything to everything, so they
    are returned separately as `universal` and the page states them in words.
    Pure and dict-only, so it is testable without a request."""
    nodes: list[dict] = []
    edges: list[dict] = []
    by_name = {t["name"]: t for t in mm["types"]}
    used_blocks = {t.get("block") for t in mm["types"] if t.get("block")}
    for b in mm["blocks"]:
        if b["id"] in used_blocks:
            nodes.append({"data": {"id": f"block:{b['id']}", "label": f"{b['id']} · {b['title']}",
                                   "is_block": True, "area": b.get("area") or ""}})
    for t in mm["types"]:
        d = {"id": t["name"], "label": t.get("label") or t["name"], "prefix": t.get("prefix") or "",
             "label_de": t.get("label_de") or "", "url": f"#type-{t['name']}",
             "stereotypes": ", ".join(t.get("stereotypes") or []), "block_id": t.get("block") or ""}
        if t.get("block"):
            d["parent"] = f"block:{t['block']}"
        nodes.append({"data": d})
    universal: list[dict] = []
    loops: dict[str, int] = {}
    for r in mm["relations"]:
        for e in r.get("edges") or []:
            src, tgt = e.get("from"), e.get("to")
            if src == "any" or tgt == "any":
                universal.append({"field": r["field"], "from": src, "to": tgt,
                                  "direction": r.get("direction"), "cardinality": e.get("cardinality") or "",
                                  "note": e.get("note") or ""})
                continue
            if src not in by_name or tgt not in by_name:
                continue
            d = {"id": f"e{len(edges)}", "source": src, "target": tgt, "label": r["field"],
                 "cardinality": str(e.get("cardinality") or ""), "semantics": r.get("semantics") or "",
                 "symmetric": r.get("direction") == "symmetric", "note": e.get("note") or ""}
            if src == tgt:
                # several loops on one node (DM: parent + relationships) fan out
                k = loops.get(src, 0)
                loops[src] = k + 1
                d["loop_dir"] = ("-45deg", "45deg", "135deg", "-135deg")[k % 4]
            edges.append({"data": d})
    return {"nodes": nodes, "edges": edges, "universal": universal}


def _mm_anchor_ref(name: object) -> dict:
    """An anchor a metamodel page names (`anchors:`, `anchor:`): its label and,
    when `_system/anchors/` has it, the in-page link to its entry."""
    a = render.anchor_lookup().get(str(name).strip().lower())
    if not a:
        return {"name": str(name), "href": "", "title": ""}
    return {"name": a["name"], "href": f"#{a['id']}", "title": render.anchor_title(a)}


def build_mm_anchors(mm: dict, anchors: dict[str, str]) -> list[dict]:
    """One entry per method anchor for /metamodel (FR-035): name, definition,
    reference and the types it applies to. A type applies when its page lists
    the anchor under `anchors:` or the anchor's `applies-to` names the type;
    an `applies-to` entry that is no type is shown as written."""
    by_name = {t["name"]: t for t in mm["types"]}
    out = []
    for a in metamodel.method_anchors():
        keys = {a["name"].lower(), a["slug"], *(x.lower() for x in a["aliases"])}
        types = [t["name"] for t in mm["types"]
                 if keys & {str(x).strip().lower() for x in t.get("anchors") or []}]
        other = []
        for entry in a["applies_to"]:
            ref = anchors.get(entry, "")
            if ref.startswith("type-"):
                if ref[5:] not in types:
                    types.append(ref[5:])
            else:
                other.append(entry)
        out.append({
            "id": a["id"], "name": a["name"],
            "aliases": [x for x in a["aliases"] if x.lower() != a["name"].lower()],
            "definition_html": _mm_inline(a["definition"], anchors),
            "reference": a["reference"],
            # a definition that already cites its reference does not repeat it
            "show_reference": bool(a["reference"]) and a["reference"] not in a["definition"],
            "types": [{"label": _mm_type_label(n, by_name), "href": f"#type-{n}"} for n in types],
            "other": other,
        })
    return out


def _mm_type_label(name: object, by_name: dict) -> str:
    if name == "any":
        return "any page"
    t = by_name.get(str(name))
    return t.get("label") if t else str(name)


@bp.route("/metamodel")
def metamodel_view():
    """The metamodel, explained: graph + tables, every cell from
    `_system/metamodel/` and every example from the live wiki (DR-035)."""
    mm = metamodel.load()
    anchors = metamodel.anchors(mm)
    by_name = {t["name"]: t for t in mm["types"]}
    meta = mm["meta"]
    universal_fields = [{**f, "doc_html": _mm_inline(str(f.get("doc") or ""), anchors)}
                        for f in meta.get("universal_fields") or []]

    types = []
    for t in mm["types"]:
        fields = []
        # a type page lists only its own fields; a non-universal one (Source)
        # lists all of them, because the universal set does not apply to it
        for f in t.get("fields") or []:
            fields.append({
                "name": f.get("name"), "kind": f.get("kind") or "", "values": f.get("values") or [],
                "required": bool(f.get("required")), "relation": f.get("relation") or "",
                "doc": _mm_inline(str(f.get("doc") or ""), anchors),
            })
        types.append({
            "name": t["name"], "anchor": f"type-{t['name']}", "prefix": t.get("prefix") or "",
            "label": t.get("label") or t["name"], "label_de": t.get("label_de") or "",
            "block": t.get("block") or "", "block_title": t.get("block_title") or "",
            "folder": t.get("folder") or "", "template": t.get("template") or "",
            "lifecycle": t.get("lifecycle") or "", "stereotypes": t.get("stereotypes") or [],
            "naming": t.get("naming") or "", "universal": t.get("universal", True),
            "fields": fields, "anchors": [_mm_anchor_ref(a) for a in t.get("anchors") or []],
            "projections": t.get("projections") or [],
            "summary_html": _mm_inline(t.get("_summary") or "", anchors),
            "example": _mm_example(t),
        })

    relations = []
    for r in mm["relations"]:
        relations.append({
            "name": r["name"], "anchor": f"rel-{r['name']}", "field": r.get("field") or r["name"],
            "direction": r.get("direction") or "", "semantics": r.get("semantics") or "",
            "inverse": r.get("inverse") or "", "inverse_stored": bool(r.get("inverse_stored")),
            "inverse_field": r.get("inverse_field") or "", "reciprocity": r.get("reciprocity") or "none",
            "edges": [{"from": _mm_type_label(e.get("from"), by_name), "to": _mm_type_label(e.get("to"), by_name),
                       "from_anchor": anchors.get(str(e.get("from")), ""), "to_anchor": anchors.get(str(e.get("to")), ""),
                       "cardinality": str(e.get("cardinality") or ""),
                       "note": _mm_inline(str(e.get("note") or ""), anchors)}
                      for e in r.get("edges") or []],
            "summary_html": _mm_inline(r.get("_summary") or "", anchors),
        })

    projections = []
    for pr in mm["projections"]:
        impl = str(pr.get("implemented") or "none")
        m = _MM_ROUTE_RE.match(impl)
        projections.append({
            "name": pr["name"], "anchor": f"proj-{pr['name']}", "output": pr.get("output") or "",
            "reads": [{"type": _mm_type_label(rd.get("type"), by_name),
                       "type_anchor": anchors.get(str(rd.get("type")), ""),
                       "fields": rd.get("fields") or []} for rd in pr.get("reads") or []],
            "implemented": impl, "href": m.group(1) if m else "",
            "anchor_ref": _mm_anchor_ref(pr["anchor"]) if pr.get("anchor") else None,
            "decisions_html": ", ".join(_mm_dr_link(d.strip(), d.strip()[:6])
                                        for d in str(pr.get("decision") or "").split(",") if d.strip()),
            "summary_html": _mm_inline(pr.get("_summary") or "", anchors),
        })

    # requirement notations (DR-038): the default one first, then by name.
    # Names compare without case, as an FR's `notation:` does (_fr_notation).
    default_notation = settings.wiki_config()["default_notation"]
    notations = []
    for n in sorted(mm["notations"], key=lambda n: (n["name"].lower() != default_notation,
                                                    n["name"].lower())):
        notations.append({
            "name": n["name"], "anchor": f"notation-{n['name']}",
            "title": n.get("title") or n["name"], "default": n["name"].lower() == default_notation,
            "levels": n.get("levels") or [],
            "sections": n.get("_sections") or [],
            "fields": [f for f in n.get("fields") or [] if isinstance(f, dict)],
            "summary_html": _mm_inline(str(n.get("summary") or ""), anchors),
        })

    def _qualifier(ap: dict) -> str:
        # a rule may narrow its type by stereotype, notation and level
        parts = []
        for key in ("stereotype", "notation", "level"):
            v = ap.get(key)
            if v:
                parts.append(f"{key} " + ", ".join(str(x) for x in (v if isinstance(v, list) else [v])))
        return "; ".join(parts)

    rules = []
    for ru in mm["rules"]:
        ap = ru.get("applies_to") or {}
        rules.append({
            "name": ru["name"], "anchor": f"rule-{ru['name']}",
            "applies_type": _mm_type_label(ap.get("type"), by_name),
            "applies_anchor": anchors.get(str(ap.get("type")), ""),
            "applies_qualifier": _qualifier(ap),
            "check": _mm_inline(str(ru.get("check") or ""), anchors),
            "confidence": ru.get("confidence") or "", "action": ru.get("action") or "",
            "source": ru.get("source") or "",
            "summary_html": _mm_inline(ru.get("_summary") or "", anchors),
        })

    graph = build_metamodel_graph(mm)
    n_in = sum(1 for b in mm["blocks"] if b.get("scope") == "in")
    return render_template(
        "metamodel.html", present=mm["present"], types=types, relations=relations,
        projections=projections, notations=notations, rules=rules, graph=graph,
        method_anchors=build_mm_anchors(mm, anchors),
        universal=graph["universal"], universal_fields=universal_fields,
        lifecycles=meta.get("lifecycles") or {}, constructs=meta.get("constructs") or [],
        field_kinds=meta.get("field_kinds") or [],
        frameworks=mm["frameworks"], n_blocks_in=n_in, n_blocks=len(mm["blocks"]),
        n_examples=sum(1 for t in types if t["example"]["count"]),
        decision_html=_mm_dr_link("DR-035-explicit-metamodel", "DR-035"),
    )
