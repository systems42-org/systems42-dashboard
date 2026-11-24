"""The projections as pages: goals, requirements, terms, the arc42 views,
decisions, stakeholders and issues.

Owns the goals page, the functional requirements with the page of one
requirement, the term list, the term network and the entity diagram, the
arc42 views (strategy, building blocks, runtime, deployment, concepts), the
decisions, the stakeholders and the issue list with its filters.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re

from flask import Blueprint, abort, render_template, request

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import metamodel  # reader for _system/metamodel/ (DR-035)
import render  # sanitizer, wikilinks and Markdown
import search  # search records
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders
import project.architecture  # decisions, building blocks, runtime, deployment, traces
import project.common  # what several projections share
import project.goals  # vision, objectives and goal coverage
import project.requirements  # requirement hierarchy, its Mermaid trees, quality scenarios
import project.terms  # term network, relations and entity diagram
import web.common  # what several route groups share

bp = Blueprint("projections", __name__)


@bp.route("/arc42/building-blocks")
def building_blocks_view():
    """A2 Building Block View: the level tree and the level-1 white box."""
    block = catalog.SECTION_BY_SLUG.get("building-blocks") or abort(404)
    pages = wiki.load_type("building-block")
    rows = [_arch_row(p) for p in sorted(pages, key=lambda q: q.id)]
    return render_template(
        "building_blocks.html", block=block, tree=project.architecture.build_bb_tree(), total=len(pages),
        whitebox=project.architecture.build_whitebox(None), maturity=project.common.maturity(p.status for p in pages), rows=rows,
    )


_CONCEPT_CATEGORIES = [
    ("domain", "Domain"), ("user-experience", "User experience"), ("safety-security", "Safety & security"),
    ("patterns", "Architecture & design patterns"), ("under-the-hood", "Under the hood"),
    ("development", "Development"), ("operations", "Operations"),
]


def _arch_row(p: wiki.Page) -> dict:
    return {"id": p.id, "title": p.title, "status": p.status, "state": project.architecture.page_state(p),
            "url": links_module._page_url(p.folder, p.stem)}


@bp.route("/arc42/strategy")
def strategy_view():
    """A1 Solution Strategy: every strategy page, marked by state, with what it
    answers and the decisions it summarises."""
    block = catalog.SECTION_BY_SLUG.get("strategy") or abort(404)
    pages = sorted(wiki.load_type("solution-strategy"), key=lambda q: q.id)
    rows = []
    for p in pages:
        row = _arch_row(p)
        row["drivers"] = project.architecture._link_groups(links_module.links_of(p, "drivers"))
        row["decisions"] = project.architecture._link_groups(links_module.links_of(p, "decisions"))
        row["replaced_by"] = project.architecture._link_groups(links_module.links_of(p, "superseded-by"))
        rows.append(row)
    return render_template("strategy.html", block=block, rows=rows, total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


@bp.route("/arc42/concepts")
def concepts_view():
    """A5 Crosscutting Concepts: grouped by arc42 topic, with what each governs."""
    block = catalog.SECTION_BY_SLUG.get("concepts") or abort(404)
    pages = sorted(wiki.load_type("crosscutting-concept"), key=lambda q: q.id)
    known = dict(_CONCEPT_CATEGORIES)
    groups = []
    for key, label in _CONCEPT_CATEGORIES + [(None, "Uncategorised")]:
        rows = []
        for p in pages:
            raw = str(p.meta.get("category") or "").strip()
            cat = raw.lower()
            if (cat if cat in known else None) != key:
                continue
            row = _arch_row(p)
            row["unknown_category"] = raw if raw and cat not in known else ""
            row["applies_to"] = project.architecture._link_groups(links_module.links_of(p, "applies-to"))
            rows.append(row)
        if rows:
            groups.append({"label": label, "rows": rows})
    flat = []
    for p in pages:
        row = _arch_row(p)
        raw = str(p.meta.get("category") or "").strip()
        row["category"] = known.get(raw.lower(), raw)
        flat.append(row)
    return render_template("concepts.html", block=block, groups=groups, total=len(pages),
                           rows=flat, maturity=project.common.maturity(p.status for p in pages))


@bp.route("/arc42/runtime")
def runtime_view():
    """A4 Runtime View: the scenarios and the requirements they realise."""
    block = catalog.SECTION_BY_SLUG.get("runtime") or abort(404)
    pages = sorted(wiki.load_type("runtime-scenario"), key=lambda q: q.id)
    rows = []
    for p in pages:
        row = _arch_row(p)
        row["realizes"] = project.architecture._link_groups(links_module.links_of(p, "realizes"))
        row["steps"] = len(project.architecture.steps_of(p))
        rows.append(row)
    return render_template("runtime.html", block=block, rows=rows, total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


@bp.route("/arc42/deployment")
def deployment_view():
    """A3 Deployment View: one projected diagram of everything relevant today —
    existing, planned and replaced — and the node levels."""
    block = catalog.SECTION_BY_SLUG.get("deployment") or abort(404)
    pages = wiki.load_type("deployment-node")
    rows = []
    for p in sorted(pages, key=lambda q: q.id):
        row = _arch_row(p)
        row["stereotype"] = str(p.meta.get("stereotype") or "").strip()
        rows.append(row)
    diagram_links: list[dict] = []
    diagram = project.architecture.build_deployment_diagram(links=diagram_links)
    return render_template("deployment.html", block=block, diagram=diagram,
                           diagram_links=[l for l in diagram_links
                                          if not l["url"].startswith(f"/page/{catalog.folder('deployment-node')}/")],
                           hints=project.architecture.deployment_hints(), rows=rows,
                           tree=project.architecture.build_node_tree(), total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


@bp.route("/domain-terms")
def glossary_view():
    titles = links_module.title_index()
    links = links_module.link_index()       # so definition wikilinks render as real hyperlinks
    pages = project.terms.domain_terms()
    rows = []
    for p in pages:
        rows.append({
            "id": p.id,
            "kind": project.terms.term_kind(p),
            "stem": p.stem,
            "folder": p.folder,
            "title": p.title,
            "aliases": p.aliases,
            "definition": render.extract_labeled(p, "Definition", titles, links),
            "relations": len(links_module.linked_stems(p)),
            "status": p.status,
            "created": str(p.meta.get("created", "")),
            "updated": str(p.meta.get("updated", "")),
            "assumption": "[!assumption]" in p.body,
        })
    # Default order is alphabetical by term; other orders are applied client-side.
    rows.sort(key=lambda r: r["title"].lower())
    # the kind filter runs in the browser (static/list-view.js, FR-038)
    return render_template("glossary.html", rows=rows, total=len(rows),
                           kinds=list(project.terms.DOMAIN_MODEL_STEREOTYPES),
                           maturity=project.common.maturity(p.status for p in pages))


@bp.route("/graph/domain-terms")
def glossary_graph_view():
    """Force-directed domain term network (DR-023). The graph data is a
    deterministic server projection; cytoscape.js lays it out client-side."""
    edge_filter = request.args.get("edges", "all")
    if edge_filter not in {"all", "related", "structured"}:
        edge_filter = "all"
    graph = project.terms.build_glossary_graph(edge_filter)
    counts = graph["layer_counts"]
    NAMED = [("STK", "Stakeholder"), ("EIF", "Interface"), ("GOAL", "Goals"),
             ("BB", "Building block")]
    named_keys = {k for k, _ in NAMED}
    named_layers = [{"key": k, "label": l, "count": counts[k]}
                    for k, l in NAMED if counts.get(k)]
    rest_keys = sorted(k for k in counts if k not in named_keys)
    rest = {"types": rest_keys, "count": sum(counts[k] for k in rest_keys)}
    n_glo = sum(1 for n in graph["nodes"] if n["data"].get("type") == "DT")
    # every node as a text link under the canvas (QR-001): terms, then the
    # pages the layer buttons add
    def node_links(core: bool) -> list[dict]:
        found = [n["data"] for n in graph["nodes"] if bool(n["data"].get("core")) == core]
        return [{"id": (search._SOURCE_ID_RE.match(d["id"]) or [""])[0], "title": d["label"], "url": d["url"]}
                for d in sorted(found, key=lambda d: d["label"].lower())]
    return render_template("graph.html", graph=graph, n_glo=n_glo,
                           term_links=node_links(True), nearby_links=node_links(False),
                           named_layers=named_layers, rest=rest, edge_filter=edge_filter)


# ?status= on the issue list: a lifecycle value, or one of these groups
# (open: is_open_issue, closed: the rest)
_ISSUE_STATUS_GROUPS = ("open", "closed")


@bp.route("/issues")
def issues_view():
    """C6: every issue, filtered on the server by status, category, severity,
    section and owner (FR-025). Filters combine and live in the address, so a
    copied link shows the same issues. Unknown values are ignored."""
    titles, links = links_module.title_index(), links_module.link_index()
    pages = sorted(wiki.load_type("issue"), key=lambda x: x.id)
    lifecycle_values = metamodel.lifecycle("issue")
    categories = metamodel.field_values("issue", "category")
    severities = metamodel.field_values("issue", "severity")
    folder_section = {f: s["id"] for s in catalog.SECTIONS for f in s["folders"] if s["id"] != "C6"}

    items = []
    for p in pages:
        sections = sorted({folder_section[links[t][0]] for t in p.link_targets()
                           if t in links and links[t][0] in folder_section})
        items.append({"id": p.id, "title": p.title, **web.common.issue_fields(p, titles, links),
                      "sections": sections, "url": links_module._page_url(p.folder, p.stem)})

    # the filters: only known values count, anything else shows every issue
    # one option per owner: a page by its title, whatever alias an issue uses
    owners = sorted({i["owner_key"]: titles.get(i["owner_key"], i["owner"]) if i["owner_url"] else i["owner"]
                     for i in items if i["owner_key"]}.items(), key=lambda o: o[1].lower())
    sections = [s for s in catalog.SECTIONS if s["folders"] and s["id"] != "C6"]
    arg = lambda name: request.args.get(name, "").strip()
    section = catalog.SECTION_BY_ID.get(arg("section").upper())
    if section not in sections:
        section = None
    status = arg("status") or arg("filter")          # ?filter= was the former name
    if status not in lifecycle_values and status not in _ISSUE_STATUS_GROUPS and status != "all":
        status = ""
    if not status:
        # a section's open issue count opens the list with its open issues (FR-019)
        status = "open" if section else "all"
    chosen = {
        "status": status,
        "category": arg("category") if arg("category") in categories else "",
        "severity": arg("severity") if arg("severity") in severities else "",
        "section": section["id"] if section else "",
        "owner": arg("owner") if arg("owner") in {"none"} | {o[0] for o in owners} else "",
    }

    def keep(i: dict) -> bool:
        st = chosen["status"]
        if st == "open" and not i["is_open"] or st == "closed" and i["is_open"]:
            return False
        if st not in ("all", "open", "closed") and i["status"] != st:
            return False
        if chosen["category"] and i["category"] != chosen["category"]:
            return False
        if chosen["severity"] and i["severity"] != chosen["severity"]:
            return False
        if chosen["section"] and chosen["section"] not in i["sections"]:
            return False
        if chosen["owner"] and i["owner_key"] != ("" if chosen["owner"] == "none" else chosen["owner"]):
            return False
        return True

    shown = [i for i in items if keep(i)]
    open_count = sum(1 for i in items if i["is_open"])
    filtered = any(v for k, v in chosen.items() if k != "status") or chosen["status"] != "all"
    return render_template(
        "issues.html", items=shown, total=len(items), shown=len(shown), filtered=filtered,
        open_count=open_count, section=section, chosen=chosen,
        options={"status": lifecycle_values, "category": categories, "severity": severities,
                 "section": sections, "owner": owners},
        sort=arg("sort"),
        maturity=project.common.maturity(p.status for p in pages),
    )


@bp.route("/stakeholders")
def stakeholders_view():
    titles = links_module.title_index()
    links = links_module.link_index()       # snapshot wikilinks become real hyperlinks
    by_stem = {q.stem: q for q in wiki.load_all_pages()}   # resolve related domain terms
    pages = sorted(wiki.load_type("stakeholder"), key=lambda x: x.id)
    _REL_MAX = 6               # cap chips per row; rest is one click away on the detail page
    rows = []
    for p in pages:
        # domain terms the stakeholder points at — quick links to "additional
        # info" (the snapshot's inline links + `related:`), by id.
        rel = []
        for s in sorted(links_module.linked_stems(p)):
            q = by_stem.get(s)
            if q and wiki._is(q.folder, "domain-term"):
                rel.append({"id": q.id, "label": q.title, "type": "DT",
                            "url": f"/page/{q.folder}/{s}"})
        rel.sort(key=lambda r: r["id"])
        rows.append({
            "id": p.id,
            "stem": p.stem,
            "url": links_module._page_url(p.folder, p.stem),
            "title": p.title,
            "role": p.meta.get("role", ""),
            "snapshot": render.extract_labeled(p, "Snapshot", titles, links),
            "influence": str(p.meta.get("influence") or ""),
            "interest": str(p.meta.get("interest") or ""),
            "rel_links": rel[:_REL_MAX],
            "rel_more": max(0, len(rel) - _REL_MAX),
            "status": p.status,
        })
    return render_template("stakeholders.html", rows=rows, total=len(rows),
                           maturity=project.common.maturity(p.status for p in pages))


@bp.route("/decisions")
def decisions_view():
    """C7 Decisions: every decision record, filterable by kind (FR-009)."""
    items = project.architecture.load_decisions()
    labels = {"architecture": "Architecture", "business": "Business", "undefined": "Undefined"}
    buckets = [{"key": k, "label": labels[k], "count": sum(1 for d in items if d["kind"] == k)}
               for k in project.architecture.DECISION_KINDS]
    return render_template("decisions.html", items=items, total=len(items), buckets=buckets,
                           maturity=project.common.maturity(d["status"] for d in items))


@bp.route("/goals")
def goals_view():
    """req42 Block 01 — Vision + Objectives. Three sections top-down:
    Mermaid tree, full-text cards (vision then objectives), goal-coverage matrix.
    Goal↔Epic edges are read from each FR's `goal:` field (DR-018)."""
    titles = links_module.title_index()
    links = links_module.link_index()       # vision/objective prose wikilinks become real links
    data = project.goals.load_goals()
    vision, objectives = data["vision"], data["objectives"]
    # the flat, sortable list of every goal page (FR-021)
    goal_rows = [{"id": g.id, "title": g.title, "url": links_module._page_url(g.folder, g.stem),
                  "stereotype": str(g.meta.get("stereotype") or "").strip().lower(),
                  "horizon": str(g.meta.get("horizon") or "").strip(), "status": g.status}
                 for g in ([vision] if vision else []) + objectives]

    def _wikilink_list(items) -> list[str]:
        """Render a frontmatter list of '[[X]]' refs as human-readable labels."""
        out = []
        for x in (items or []):
            s = str(x).strip()
            m = re.match(r"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]", s)
            if not m:
                continue
            target, alias = m.group(1).strip(), m.group(2)
            base = target.split("/")[-1]
            out.append(alias.strip() if alias else titles.get(base, base))
        return out

    if vision:
        vision_card = {
            "id": vision.id,
            "title": vision.title,
            "url": links_module._page_url(vision.folder, vision.stem),
            "stereotype": "Vision",
            "maturity": None,
            "beneficiary": _wikilink_list(vision.as_list("beneficiary")),
            # Vision card shows the prose of the `## Vision` section — the
            # objectives list and impact block from the wiki page are projected
            # below as separate objective cards and the coverage matrix.
            "html": "".join(f"<p>{p}</p>" for p in project.goals._vision_paragraphs(vision, titles, links)),
        }
    else:
        # No `stereotype: vision` page yet: a hint takes the vision's place,
        # and the objective cards and the matrix still show. The route must
        # work on workshop day one.
        vision_card = {
            "id": "", "title": "No vision yet", "stereotype": "Vision",
            "maturity": None, "beneficiary": [],
            "html": "<p>No vision yet — capture a GOAL- page with "
                    "<code>stereotype: vision</code>.</p>",
        }

    def _inline(s) -> str:
        """Frontmatter strings may contain `[[wikilinks]]` — render them as
        real hyperlinks when the target resolves."""
        return render.render_wikilinks_text(str(s or "").strip(), titles, links)

    fr_cols, matrix_rows = project.goals._goal_matrix(data)

    objective_cards = []
    for o in objectives:
        objective_cards.append({
            "id": o.id,
            "title": o.title,
            "url": links_module._page_url(o.folder, o.stem),
            "stereotype": "Goal",
            "purpose": render.extract_pam_bullet(o, "Purpose", titles, links),
            "advantage": render.extract_pam_bullet(o, "Advantage", titles, links),
            "metric": _inline(o.meta.get("metric")),
            "target": _inline(o.meta.get("target")),
            "baseline": _inline(o.meta.get("baseline")),
            "beneficiary": _wikilink_list(o.as_list("beneficiary")),
            # every requirement that serves the goal, features and stories
            # too: a superset of its matrix marks, as text (FR-036)
            "epics": [{"id": p.id, "title": p.title, "url": links_module._page_url(p.folder, p.stem)}
                      for p in data["coverage"].get(o.id, [])],
        })

    diagram = project.goals._mermaid_goal_tree(settings.wiki_config()["system_name"], vision, objectives)
    return render_template(
        "goals.html",
        diagram=diagram,
        vision=vision_card,
        objectives=objective_cards,
        fr_cols=fr_cols,
        matrix_rows=matrix_rows,
        needs_mermaid=bool(diagram),
        goal_rows=goal_rows,
    )


@bp.route("/entity-diagram")
def data_model_view():
    """R4 entity diagram: the class diagram of the structured domain terms
    (build_data_model_full_diagram()) plus the per-entity catalog below, every
    section and callout of every structured term on one page."""
    contexts = project.terms.data_model_contexts()
    context = request.args.get("context") or None
    if context not in contexts:
        context = None                     # an unknown filter shows everything
    nodes = project.terms.data_model_nodes()
    focus = request.args.get("focus") or None
    if focus and focus not in {n["key"] for n in nodes}:
        matches = [n["key"] for n in nodes if focus in n["aliases"]]
        focus = matches[0] if len(matches) == 1 else None
    diagram = project.terms.build_data_model_full_diagram(context=context, focus=focus)
    return render_template("data_model.html", diagram=diagram, **web.common._crumb_of(catalog.section_for_path("/entity-diagram")),
                           entities=project.terms.data_model_entities(), nodes=nodes,
                           contexts=contexts, context=context, focus=focus,
                           needs_mermaid=True)


@bp.route("/req42/functional-requirements")
def functional_requirements_view():
    """req42 block 04 — Functional Requirements across notation-specific levels
    (DR-038): the Agile story map (epics, and the use cases Agile features and
    stories refine), then every requirement the story map cannot place.
    A dedicated rich view for the `functional-requirements` slug (the other /req42/<slug> blocks
    use the generic list). Flask matches this static rule ahead of the dynamic
    /req42/<slug>. Doubles as the home `functional-requirements` tile's click-target."""
    hierarchy = project.requirements.build_fr_hierarchy()
    goals = project.goals.load_goals()
    diagram_links: list[dict] = []
    diagram = project.requirements._mermaid_goal_epic_tree(goals, hierarchy, diagram_links)
    block = catalog.SECTION_BY_SLUG.get("functional-requirements") or abort(404)
    # the flat list under the hierarchy (FR-021): every requirement of every
    # notation once, sortable by priority, release and order
    rows = []
    for p in sorted(wiki.load_type("functional-requirement"), key=lambda q: q.id):
        rows.append({"id": p.id, "title": p.title,
                     "url": f"/functional-requirements/{p.stem}",
                     "notation": project.requirements._fr_notation(p), "level": project.requirements._fr_level(p),
                     "priority": str(p.meta.get("priority") or "").strip(),
                     "release": str(p.meta.get("release") or "").strip(),
                     "order": str(p.meta.get("order") if p.meta.get("order") is not None else "").strip(),
                     "status": p.status})
    return render_template(
        "functional-requirements.html", hierarchy=hierarchy, diagram=diagram, diagram_links=diagram_links,
        block=block, needs_mermaid=bool(diagram), rows=rows,
    )


@bp.route("/functional-requirements/<stem>")
def fr_view(stem):
    """Rich detail page for a functional requirement of any notation and level
    (DR-038), mirroring the wiki/functional-requirements/ folder.
    Shows the FR's full text plus — for non-leaf FRs — its own Feature→Story
    breakdown (mermaid + cards); for a use case, the Agile features and
    stories that realize it. Every FR node in the hierarchy diagrams clicks
    here, so the whole hierarchy lives under one sprechenden path with a
    'Functional Requirements' breadcrumb (instead of the generic /page 'Search' crumb).
    404 if `stem` is not an FR page."""
    fr_folder = catalog.folder("functional-requirement")
    path = wiki.WIKI_DIR / fr_folder / f"{stem}.md"
    page = wiki._parse(path, fr_folder) if fr_folder and path.is_file() else None
    if not page:
        abort(404)
    titles = links_module.title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)  # drop leading "# Title"
    body_html = render.render_markdown(body, titles)

    hierarchy = project.requirements.build_fr_hierarchy()
    node, kind = project.requirements._fr_hierarchy_node(hierarchy, stem)
    fr = {
        "id": page.id, "title": page.title, "stem": stem,
        "notation": project.requirements._fr_notation(page),
        "level": kind or project.requirements._fr_level(page),
        "priority": str(page.meta.get("priority") or "").strip(),
        "release": str(page.meta.get("release") or "").strip(),
        "status": page.status,
        "features": (node or {}).get("features") or [],
        "direct_stories": (node or {}).get("direct_stories") or [],
        "stories": (node or {}).get("stories") or [],
    }
    fr["n_features"] = len(fr["features"])
    fr["n_stories"] = (node or {}).get("n_stories")
    if fr["n_stories"] is None:  # feature/story carry no precomputed count
        fr["n_stories"] = len(fr["stories"])

    diagram_links: list[dict] = []
    # a requirement outside the hierarchy (another notation) still shows its blocks
    diagram = project.requirements._mermaid_fr_subtree(node or {"id": page.id, "title": page.title},
                                  project.requirements.fr_building_blocks(stem), diagram_links)
    trace = project.architecture.build_trace(stem, fr_folder)
    return render_template(
        "fr.html", fr=fr, body_html=body_html, diagram=diagram, diagram_links=diagram_links,
        ancestors=project.requirements._fr_ancestors(stem),
        trace=trace,
        relations=project.terms.build_relations_panel(stem, exclude=project.architecture.trace_stems(trace)),
        needs_mermaid=bool(diagram) or "language-mermaid" in body_html,
        sources=project.common.provenance(page),
        page_issues=web.common.open_issues_for(stem),
        formats=render.format_labels(page.body),
        **web.common.page_head(page),
    )
