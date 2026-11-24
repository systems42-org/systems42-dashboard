"""The pages and lists: home, the areas, the section lists, a page, a source
and the changes.

Owns the home page with its area and section tiles and the state of the
vault, the area pages, the generic list of a section, the detail page of a
wiki page and of a source record, and the list of changes.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re
import time
from datetime import datetime

from flask import Blueprint, abort, redirect, render_template
from markupsafe import escape

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import render  # sanitizer, wikilinks and Markdown
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders
import project.architecture  # decisions, building blocks, runtime, deployment, traces
import project.common  # what several projections share
import project.context  # the context diagram and its flows
import project.goals  # vision, objectives and goal coverage
import project.requirements  # requirement hierarchy, its Mermaid trees, quality scenarios
import project.terms  # term network, relations and entity diagram
import web.common  # what several route groups share

bp = Blueprint("pages", __name__)


def _relative_when(ts: float, now: float | None = None) -> str:
    """'just now' / '12 min ago' / '3 h ago' / '2026-09-06' — coarse on purpose."""
    now = time.time() if now is None else now
    d = max(0, int(now - ts))
    if d < 60:
        return "just now"
    if d < 3600:
        return f"{d // 60} min ago"
    if d < 86400:
        return f"{d // 3600} h ago"
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def recent_changes(n: int | None = 5) -> list[dict]:
    """The n most recently modified wiki pages (file mtime — the cheapest
    'what changed' there is; the vault is regenerated a few times per
    workshop, nobody watches it live)."""
    pages = sorted(wiki.load_all_pages(), key=lambda p: -p.mtime)[:n]
    return [{"id": p.id, "title": p.title, "kind": catalog.label(p.folder),
             "url": links_module._page_url(p.folder, p.stem), "when": _relative_when(p.mtime)} for p in pages]


def vault_status() -> dict:
    """The one-line state of the vault under the hero: how much is captured,
    what is still open, how much source material it rests on, and how fresh
    the whole thing is."""
    pages = wiki.load_all_pages()
    issues = wiki.load_type("issue")
    last = max((p.mtime for p in pages), default=0.0)
    return {"pages": len(pages),
            "open_issues": sum(1 for i in issues if project.common.is_open_issue(i.status)),
            "sources": len(wiki.load_sources()),
            "last_change": _relative_when(last) if last else "—"}

# --- views -----------------------------------------------------------------

def build_section_tile(section: dict) -> dict:
    """The tile payload for one catalog section, keyed by section ID: a count,
    the maturity bar and the open-issue flag, nothing more (FR-019). The
    count is what the unit says: R4 counts model pages, C3 external
    interfaces, C6 all issues with the open ones as its flag."""
    sid = section["id"]
    folders = list(section["folders"])
    base = {"key": sid.lower(), "id": sid, "label": section["title"],
            "eyebrow": f"{sid} · {section['title']}", "href": section["href"],
            "folders": folders, "scope": section["scope"],
            "colors": section["colors"], "note": section["note"],
            "links": [], "active": section["scope"] == "in",
            "unit": "page", "unit_many": None, "count": 0}
    if section["scope"] != "in":
        base["maturity"] = project.common.maturity([])
        base["open_issues"] = 0
        return base
    pages = [p for f in folders for p in wiki.load_folder(f)]
    flags = project.common.open_issue_counts()
    # union, not sum: an issue linking pages in two of this section's folders
    # must count once, not twice.
    t = {**base, "count": len(pages), "maturity": project.common.maturity(p.status for p in pages),
         "open_issues": len(set().union(*(flags.get(f, set()) for f in folders))),
         "open_issues_href": f"/issues?section={sid}",
         "open_issues_title": "Show the open issues that point at pages of this section"}
    if sid == "R1":
        t["unit"] = "goal"
    elif sid == "R3":
        # every functional requirement of every notation (DR-038)
        t["unit"] = "requirement"
    elif sid == "R4":
        t.update({"unit": "model page",
                  "count": project.terms.supporting_model_count()})
    elif sid == "C1":
        t["unit"] = "scenario"
    elif sid == "C2":
        t["unit"] = "constraint"
    elif sid == "C3":
        # folders carries both (maturity and issue flags span the context page
        # too), but the headline number is what the unit says: interfaces.
        t.update({"unit": "external interface", "count": len(wiki.load_type("external-interface"))})
    elif sid == "C4":
        t["unit"] = "persona"
    elif sid == "C5":
        t.update({"unit": "term",
                  "links": [{"label": "Table", "href": "/domain-terms"},
                            {"label": "Term network", "href": "/graph/domain-terms"}]})
    elif sid == "C6":
        t.update({"unit": "issue",
                  "open_issues": sum(1 for i in pages if project.common.is_open_issue(i.status)),
                  "open_issues_href": "/issues?status=open",
                  "open_issues_title": "Show the open issues"})
    return t


def build_area_tile(area: dict) -> dict:
    """Home-page tile for one cabinet: count, maturity and open-issue flag
    over its visible, captured sections, plus the section list as links, each
    with its section tile's count (FR-018)."""
    sections = settings.visible_sections(area["key"])
    folders = [f for s in sections for f in s["folders"]]
    pages = [p for f in folders for p in wiki.load_folder(f)]
    flags = project.common.open_issue_counts()
    tiles = {s["id"]: build_section_tile(s) for s in sections if s["scope"] == "in"}
    return {
        "key": area["key"], "label": area["label"], "subtitle": area["subtitle"],
        "href": area["href"], "colors": area["colors"],
        "count": len(pages), "maturity": project.common.maturity(p.status for p in pages),
        "open_issues": len(set().union(*(flags.get(f, set()) for f in folders if not wiki._is(f, "issue")))),
        "sections": [{"id": s["id"], "title": s["title"], "href": s["href"], "scope": s["scope"],
                      **({"count": tiles[s["id"]]["count"], "unit": tiles[s["id"]]["unit"],
                          "unit_many": tiles[s["id"]]["unit_many"]} if s["id"] in tiles else {})}
                     for s in sections],
        "planned": not sections or all(s["scope"] == "planned" for s in sections),
    }


def build_valley() -> dict:
    """What the agent did: the vault's state, what moved last, what is open.
    Sits between the two peaks on the home page (DR-033)."""
    issues = wiki.load_type("issue")
    open_issues = sorted((i for i in issues if project.common.is_open_issue(i.status)),
                         key=lambda i: ({"blocker": 0, "major": 1, "minor": 2}
                                        .get(str(i.meta.get("severity") or ""), 3), i.id))
    return {
        "status": vault_status(),
        "changes": recent_changes(4),
        "open_issues": [{"id": i.id, "title": i.title, "stem": i.stem,
                         "url": links_module._page_url(i.folder, i.stem),
                         "severity": str(i.meta.get("severity") or "")} for i in open_issues[:5]],
        "open_total": len(open_issues),
        "decision_count": len(wiki.load_type("decision-record")),
    }


@bp.route("/")
def index():
    """Home: Requirements and Architecture as two peaks, the valley between
    them showing the agent's work, Commons as the ground both stand on."""
    areas = {a["key"]: build_area_tile(a) for a in settings.visible_areas()}
    join_url = web.common.public_url()
    return render_template("index.html", areas=areas, valley=build_valley(),
                           vision_sentence=project.goals.vision_sentence(project.goals.vision_page(), links_module.title_index()),
                           join_url=join_url, join_qr=web.common.qr_svg(join_url))


@bp.route("/changes")
def changes_view():
    """Every wiki page, most recently changed first. The first page shows the
    last few and links here (FR-018)."""
    return render_template("changes.html", changes=recent_changes(None))


def _is_wiki_folder(folder: str) -> bool:
    """True when `folder` is a direct, non-hidden subfolder of WIKI_DIR that,
    symlinks resolved, stays inside it."""
    if not folder or folder.startswith(".") or "/" in folder or "\\" in folder:
        return False
    d = wiki.WIKI_DIR / folder
    return d.is_dir() and wiki._resolves_inside(wiki.WIKI_DIR, d)


@bp.route("/page/<folder>/<stem>")
def page_detail(folder, stem):
    """Detail page for a single content unit (any wiki page). Search results
    link here."""
    titles = links_module.title_index()
    # FRs have their own rich page (full text + hierarchy breakdown) under the
    # functional-requirements/ path; send any /page link there so the whole
    # hierarchy stays on one route.
    if wiki._is(folder, "functional-requirement"):
        return redirect(f"/functional-requirements/{stem}", code=302)

    # `folder` must name one of the wiki's own content folders: the route
    # takes any single path segment, and `..` or `.` would otherwise reach a
    # markdown file beside or above wiki/ (the repository root under
    # `dashboard.sh local`, /repo under Docker).
    if not _is_wiki_folder(folder):
        abort(404)
    path = wiki.WIKI_DIR / folder / f"{stem}.md"
    page = wiki._parse(path, folder) if path.is_file() else None
    if not page:
        abort(404)
    kind = catalog.label(folder)
    # drop the leading "# Title" heading from the body — shown in the page header
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)
    body_html = render.render_markdown(body, titles)
    # context pages carry the system-context diagram, projected live (DR-013)
    diagram_links: list[dict] = []
    context_diagram = project.context.build_context_diagram(settings.wiki_config()["system_name"], links=diagram_links) if wiki._is(folder, "context") else None
    context_flows = project.context.build_context_flows() if wiki._is(folder, "context") else None
    # domain terms carry a focused ego-graph snippet above the definition (DR-023)
    ego_graph = project.terms.build_glossary_ego_graph(stem) if wiki._is(folder, "domain-term") else None
    trace = project.architecture.build_trace(stem, folder)
    whitebox = project.architecture.build_whitebox(stem) if wiki._is(folder, "building-block") else None
    sequence = project.architecture.build_sequence_diagram(stem) if wiki._is(folder, "runtime-scenario") else None
    hints = (project.architecture.runtime_hints(stem) if wiki._is(folder, "runtime-scenario")
             else project.architecture.deployment_hints(stem) if wiki._is(folder, "deployment-node") else [])
    deployment = project.architecture.build_deployment_diagram(stem, diagram_links) if wiki._is(folder, "deployment-node") else None
    ego_layers = None
    if ego_graph:
        c = ego_graph["layer_counts"]
        ego_layers = [{"key": k, "label": l} for k, l in
                      (("STK", "Stakeholder"), ("GOAL", "Goals"), ("BB", "Building block"))
                      if c.get(k)]
        for L in ego_layers:
            L["count"] = c[L["key"]]
    return render_template(
        "detail.html", kind=kind, id=page.id, title=page.title,
        status=page.status, **web.common.page_head(page),
        body_html=body_html, **web.common._section_crumb(folder),
        context_diagram=context_diagram, context_flows=context_flows,
        relations=project.terms.build_relations_panel(stem, exclude=project.architecture.trace_stems(trace)),
        trace=trace, whitebox=whitebox,
        state=project.architecture.page_state(page) if wiki._is(folder, *project.architecture.ARCH_TYPES) else None,
        sequence=sequence, hints=hints, deployment=deployment, diagram_links=diagram_links,
        ego_graph=ego_graph, ego_layers=ego_layers,
        needs_mermaid=bool(context_diagram or whitebox or sequence or deployment) or "language-mermaid" in body_html,
        sources=project.common.provenance(page),
        issue=web.common.issue_fields(page, titles, links_module.link_index()) if wiki._is(folder, "issue") else None,
        page_issues=web.common.open_issues_for(stem),
        formats=render.format_labels(page.body),
        term=project.terms.term_fields(page) if wiki._is(folder, "domain-term") else None,
    )


@bp.route("/source/<stem>")
def source_detail(stem):
    """Detail page for one raw/sources/ provenance record: what it is, where it
    came from, and which wiki pages it fed (`ingested-pages:`). Reached from a
    provenance chip on any sourced page; no standalone sources list exists yet,
    so its path is Home › source (FR-020)."""
    src = links_module.source_index().get(stem)
    if not src:
        abort(404)
    titles = links_module.title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", src.body, count=1)
    # frontmatter values are human-entered and never trusted: escape every one
    # before it lands in body_html, which the template renders with `| safe`.
    facts = [("Type", str(src.meta.get("source-type") or "—")),
             ("Origin", str(src.meta.get("origin") or "—")),
             ("Captured", str(src.meta.get("captured") or "—")),
             ("Checksum", str(src.meta.get("sha256") or "—")[:16])]
    facts_html = "".join(f"<dt>{k}</dt><dd>{escape(v)}</dd>" for k, v in facts)
    # each ref is plain text: escaped around its wikilinks, label escaped
    # inside them, so a hostile one comes out as inert entities whether or
    # not it resolves to a real page.
    ingested = ", ".join(render.render_wikilinks_text(str(r), titles, links_module.link_index()) for r in src.as_list("ingested-pages")) or "—"
    body_html = f'<dl class="source-facts">{facts_html}<dt>Ingested pages</dt><dd>{ingested}</dd></dl>' + render.render_markdown(body, titles)
    return render_template("detail.html", kind="Source", id=src.id, title=src.title, status=src.status,
                           **web.common.page_head(src), body_html=body_html, crumb=None, crumb_href=None,
                           context_diagram=None, context_flows=None,
                           relations=None, ego_graph=None, ego_layers=None,
                           needs_mermaid=False, sources=None)


@bp.route("/req42", defaults={"area_key": "requirements"})
@bp.route("/arc42", defaults={"area_key": "architecture"})
@bp.route("/commons", defaults={"area_key": "commons"})
def area_view(area_key):
    """One cabinet of the Systems42 sections diagram: its visible sections as
    tiles (DR-033). Reachable by URL even when the area is hidden — hiding
    removes tiles and links, never pages."""
    area = catalog.AREA_BY_KEY.get(area_key) or abort(404)
    # Hiding the area hides its sections from the home page; here only a
    # section hidden on its own is dropped.
    tiles = [build_section_tile(s) for s in catalog.sections_of(area_key)
             if s["id"] not in settings.dashboard_config()["hidden"]]
    pages = [p for t in tiles for f in t["folders"] for p in wiki.load_folder(f)]
    return render_template("area.html", area=area, tiles=tiles, count=len(pages),
                           maturity=project.common.maturity(p.status for p in pages), needs_mermaid=False)


@bp.route("/req42/<slug>")
def req42_block_view(slug):
    """All entries of one req42 block, for blocks without their own rich view."""
    block = catalog.SECTION_BY_SLUG.get(slug)
    # the arc42 sections have slugs too, but their pages live under /arc42/
    if not block or block["href"] != f"/req42/{slug}":
        abort(404)
    return _block_list(block, slug)


@bp.route("/section/<sid>")
def section_view(sid):
    """A section the dashboard has no view for (FR-044): the generic list of
    its pages. A section with a view of its own redirects there."""
    block = catalog.SECTION_BY_ID.get(sid) or catalog.SECTION_BY_ID.get(sid.upper())
    if not block or not block["href"]:
        abort(404)
    if block["href"] != f"/section/{block['id']}":
        return redirect(block["href"])
    return _block_list(block, None)


def _block_list(block: dict, slug: str | None):
    titles, links = links_module.title_index(), links_module.link_index()
    rows = [
        {"id": p.id, "type": catalog.label(p.folder),
         "title": p.title, "url": links_module._page_url(p.folder, p.stem),
         "status": p.status, "relations": len(links_module.linked_stems(p)),
         **(project.requirements._qr_details(p, titles, links) if wiki._is(p.folder, "quality-requirement") else {})}
        for p in project.common._block_pages(block)
    ]
    # the Scope block (03) shows the same live-projected system-context diagram
    diagram_links: list[dict] = []
    context_diagram = project.context.build_context_diagram(settings.wiki_config()["system_name"], links=diagram_links) if slug == "scope" else None
    context_flows = project.context.build_context_flows() if slug == "scope" else None
    entity_diagram = project.terms.build_data_model_full_diagram() if slug == "models" else None
    return render_template(
        "req42_block.html", block=block, rows=rows, total=len(rows),
        list_type=catalog.type_of(block["folders"][0]) if block["folders"] else "page",
        context_diagram=context_diagram, context_flows=context_flows, diagram_links=diagram_links,
        entity_diagram=entity_diagram, needs_mermaid=bool(context_diagram or entity_diagram),
        maturity=project.common.maturity(r["status"] for r in rows),
    )
