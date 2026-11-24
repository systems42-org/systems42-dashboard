"""The domain terms: the term network, a page's relations and the entity diagram.

Owns the domain term pages, the term network and a term's own network
(DR-023), the outbound and inbound links of a page, a term's kind, attributes
and relationships, and the entity diagram with its catalog (DR-027).

May import `wiki`, `links`, `render`, `catalog` and `project.common`. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import re
import unicodedata

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes
import project.common  # what several projections share
import render  # sanitizer, wikilinks and Markdown
import wiki  # paths, pages, parse cache and loaders


# --- domain term network (DR-023) ----------------------------------------
#
# A force-directed graph of the domain terms, projected from the `related:` edges.
# The server emits cytoscape elements ({nodes, edges}); the browser lays them
# out (cytoscape.js). Single source of truth stays the typed edges — only the
# layout is client-side. Default view is terms only; cross-type neighbours (1-hop)
# are revealed per type by buttons. Edges are undirected & deduplicated and come
# ONLY from `related:` frontmatter (body wikilinks would add uncurated noise, so
# link_targets() is deliberately NOT used here).


def domain_terms() -> list[wiki.Page]:
    return wiki.load_type("domain-term")


def build_glossary_graph(edge_filter: str = "all") -> dict:
    """Project simple links and structured relationships over the terminology."""
    glossary = domain_terms()
    glo_stems = {p.stem for p in glossary}
    by_stem = {p.stem: p for p in wiki.load_all_pages()}   # existence + title/folder

    seen_pairs: set[frozenset] = set()
    edges: list[dict] = []
    glo_degree: dict[str, int] = {s: 0 for s in glo_stems}
    neighbour_stems: set[str] = set()

    for p in glossary:                       # src is always a domain term
        src = p.stem
        for raw in p.as_list("related") if edge_filter != "structured" else []:
            tgt = links_module._link_stem(raw)
            if not tgt or tgt == src or tgt not in by_stem:
                continue                     # self / dangling / non-page
            pair = frozenset((src, tgt))
            if pair in seen_pairs:
                continue                     # undirected dedup
            seen_pairs.add(pair)
            cross = tgt not in glo_stems
            edge = {"id": f"e{len(edges)}", "source": src, "target": tgt, "cross": cross, "kind": "related"}
            if cross:
                edge["ntype"] = project.common._type_of(tgt)
                neighbour_stems.add(tgt)
            else:
                glo_degree[src] += 1
                glo_degree[tgt] += 1
            edges.append(edge)

    if edge_filter != "related":
        seen_structure = set()
        for relation in data_model_edges():
            src, tgt = relation["source"], relation["target"]
            if src not in glo_stems or tgt not in glo_stems:
                continue
            kind, label = relation["kind"], relation["verb"]
            key = (src, tgt, kind, label, relation["cardinality"])
            if key in seen_structure:
                continue
            seen_structure.add(key)
            edges.append({"id": f"e{len(edges)}", "source": src, "target": tgt,
                          "cross": False, "kind": kind, "label": label or kind})
            glo_degree[src] += 1
            glo_degree[tgt] += 1

    nodes: list[dict] = []
    for p in glossary:
        state = ("deprecated" if p.status == "deprecated"
                 else "agreed" if p.meta.get("agreed") is True
                 else "draft")
        nodes.append({
            "id": p.stem, "label": p.title, "type": "DT", "core": True,
            "url": f"/page/{p.folder}/{p.stem}",
            "degree": glo_degree.get(p.stem, 0),
            "state": state,
            "assumption": "[!assumption]" in p.body,
            "aliases": ", ".join(p.aliases),
        })
    named = {"STK", "EIF", "GOAL", "BB"}   # types with their own colour + button
    for stem in sorted(neighbour_stems):
        pg = by_stem[stem]
        ntype = project.common._type_of(stem)
        node = {
            "id": stem, "label": pg.title, "type": ntype, "core": False,
            "url": f"/page/{pg.folder}/{stem}",
        }
        if ntype not in named:
            node["rest"] = 1   # CTX/FR/CON/ISS/… → grey, selected via node[rest]
        nodes.append(node)

    layer_counts: dict[str, int] = {}
    for e in edges:
        if e["cross"]:
            layer_counts[e["ntype"]] = layer_counts.get(e["ntype"], 0) + 1

    return {
        "nodes": [{"data": n} for n in nodes],
        "edges": [{"data": e} for e in edges],
        "layer_counts": layer_counts,
    }


# Neighbour types the per-term ego snippet offers as buttons (DR-023): terms shown by
# default, STK/GOAL/BB revealed on demand. A focused 1-hop slice for a term's detail page.
_EGO_TYPES = {"DT", "STK", "GOAL", "BB"}


def build_glossary_ego_graph(stem: str) -> dict | None:
    """1-hop ego network of a single domain term for the detail-page snippet
    (DR-023): the focal term + its immediate neighbours of type DT/STK/GOAL/BB
    and the edges among them. A pure filtered projection of build_glossary_graph();
    returns None if the term has no node (not a domain term page)."""
    full = build_glossary_graph()
    node_by_id = {n["data"]["id"]: n["data"] for n in full["nodes"]}
    if stem not in node_by_id:
        return None

    nbrs: set[str] = set()
    for e in full["edges"]:
        d = e["data"]
        if d["source"] == stem:
            nbrs.add(d["target"])
        elif d["target"] == stem:
            nbrs.add(d["source"])

    ego_ids = {stem} | {n for n in nbrs
                        if node_by_id.get(n, {}).get("type") in _EGO_TYPES}

    nodes = []
    for nid in ego_ids:
        data = dict(node_by_id[nid])
        if nid == stem:
            data["focus"] = True
        nodes.append({"data": data})
    edges = [e for e in full["edges"]
             if e["data"]["source"] in ego_ids and e["data"]["target"] in ego_ids]

    layer_counts: dict[str, int] = {}
    for e in edges:
        d = e["data"]
        if d.get("cross") and d.get("ntype") in _EGO_TYPES:
            layer_counts[d["ntype"]] = layer_counts.get(d["ntype"], 0) + 1

    return {"nodes": nodes, "edges": edges, "layer_counts": layer_counts}


def build_relations_panel(stem: str, exclude: set[str] | None = None) -> dict:
    """Outbound links (this page's `related:` + body wikilinks) and inbound
    backlinks (other pages that reference it), grouped by type, as link dicts.
    A pure projection over the link graph (DR-018) — powers the outbound
    / inbound relations section on a detail page. `exclude` drops stems the
    page already lists in a typed panel (drivers, addressed by, …). A linked
    issue carries its `status` and whether it is `closed`."""
    exclude = exclude or set()
    titles = links_module.title_index()
    pages = wiki.load_all_pages()
    by_stem = {p.stem: p for p in pages}

    def info(s: str) -> dict:
        ntype = project.common._type_of(s)
        folder = by_stem[s].folder if s in by_stem else catalog.folder_for_prefix(ntype)
        if folder and wiki._is(folder, "functional-requirement"):
            url = f"/functional-requirements/{s}"
        elif folder:
            url = f"/page/{folder}/{s}"
        else:
            url = f"/page/{by_stem[s].folder}/{s}"
        item = {"id": by_stem[s].id if s in by_stem else s,
                "label": titles.get(s, s), "url": url, "type": ntype,
                "status": "", "closed": False}
        if s in by_stem and wiki._is(by_stem[s].folder, "issue"):
            # a linked issue says how firm it is, closed the way the issues
            # panel says it (FR-034, FR-027)
            st = by_stem[s].status
            item["status"] = st if st in project.common._issue_vocab()["status"] else ""
            item["closed"] = not project.common.is_open_issue(st)
        return item

    me = by_stem.get(stem)
    outbound = sorted(s for s in (links_module.linked_stems(me) if me else ())
                      if s in by_stem and s not in exclude)
    # every page that links here, also one this page links to (FR-034)
    inbound = sorted(q.stem for q in (pages if me else ())
                     if q.stem not in exclude and links_module.links_to(q, me))

    def grouped(stems: list) -> list:
        buckets: dict[str, list] = {}
        for s in stems:
            i = info(s)
            buckets.setdefault(i["type"], []).append(i)
        order = catalog.prefix_order()
        ordered = order + [t for t in buckets if t not in order]
        return [{"type": t, "label": catalog.group_label(t), "links": buckets[t]}
                for t in ordered if t in buckets]

    return {"outbound": grouped(outbound), "inbound": grouped(inbound)}


# --- entity diagram projection (R4, DR-027) -------------------------------
#
# A domain term with `stereotype: entity | value-object | sum-type` is a class
# in the diagram: identity, `attributes:` and a `relationships:` list in
# frontmatter, which is where the edges come from. Body prose is for humans;
# frontmatter is for the projection, the same split that makes the context
# diagram work (`flows:`, DR-026).

DOMAIN_MODEL_STEREOTYPES = ("entity", "value-object", "sum-type")


def data_model_pages() -> list[wiki.Page]:
    """The structured domain terms, by id."""
    return sorted((page for page in wiki.load_type("domain-term")
                   if str(page.meta.get("stereotype") or "").strip().lower() in DOMAIN_MODEL_STEREOTYPES),
                  key=lambda page: page.id)


# `kind:` -> (mermaid arrow, cardinalities are meaningful). Inheritance is the
# odd one out: mermaid wants `Base <|-- Derived`, i.e. the edge is emitted
# backwards from how the page states it, and a multiplicity on it is nonsense.
_DM_ARROWS = {
    "association": ("-->", True),
    "aggregation": ("o--", True),
    "composition": ("*--", True),
    "inheritance": ("<|--", False),
}


# German umlauts and ß have a conventional ASCII spelling; every other accent
# is dropped via NFKD below (é→e). Without this, the ASCII split treated "ü" as
# a word boundary and the glossary term "Durchführungsart" was drawn as
# "DurchfHrungsart" — legal mermaid, nonsense on a wall (atrium, 2026-10-14).
_DM_TRANSLIT = str.maketrans({
    "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
    "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ẞ": "Ss",
})


def _dm_ascii(label: str) -> str:
    """`label` with umlauts transliterated and remaining diacritics stripped."""
    s = label.translate(_DM_TRANSLIT)
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def _dm_class_name(label: str, taken: set) -> str:
    """A mermaid-safe class name that still reads like the entity. Collisions
    are resolved rather than silently merged — two entities sharing a sanitised
    name would otherwise become one box."""
    # Capitalise each word BEFORE stripping separators, or "Piece for sale"
    # becomes "Pieceforsale" — legal mermaid, unreadable on a wall.
    words = re.split(r"[^A-Za-z0-9]+", _dm_ascii(project.common._clean_label(label)))
    base = "".join(w[:1].upper() + w[1:] for w in words if w) or "Entity"
    if base[0].isdigit():
        base = "E" + base
    name, n = base, 2
    while name in taken:
        name, n = f"{base}{n}", n + 1
    taken.add(name)
    return name


@wiki._request_cached
def data_model_nodes() -> list[dict]:
    """Every class in the model: one per structured domain term."""
    return [{
        "key": p.stem,
        "id": p.id,
        "label": p.title,
        "context": str(p.meta.get("bounded-context") or "").strip(),
        "stereotype": str(p.meta.get("stereotype") or "").strip().lower(),
        "attributes": _extract_dm_attribute_names(p),
        "aliases": p.aliases,
        "url": f"/page/{p.folder}/{p.stem}",
    } for p in data_model_pages()]


@wiki._request_cached
def data_model_edges() -> list[dict]:
    """Relationships, read from `relationships:` frontmatter on structured terms. An
    entry pointing at a page that does not exist is dropped, not drawn as a
    dangling stub — a typo should leave a gap you notice, not a ghost class."""
    by_stem = {n["key"] for n in data_model_nodes()}
    out = []
    for p in data_model_pages():
        # A sum-type variant already names its sum type in `parent:` (DR-019).
        # Draw that as the inheritance it is, rather than make the author repeat
        # it as a relationship entry — one fact, one place.
        for raw in p.as_list("parent"):
            tgt = links_module._link_stem(raw)
            if tgt and tgt in by_stem and tgt != p.stem:
                out.append({"source": p.stem, "target": tgt, "verb": "",
                            "cardinality": "", "kind": "inheritance"})
        out.extend(r for r in _dm_relationships(p) if r["target"] in by_stem)
    return out


def _dm_relationships(page: wiki.Page) -> list[dict]:
    """The entries of a term's `relationships:` that name a target, as edges.
    The target may be a stem no structured term has: the entity diagram drops
    those, the term page lists them (FR-039)."""
    out = []
    for entry in page.as_list("relationships"):
        if not isinstance(entry, dict):
            continue
        tgt = links_module._link_stem(entry.get("to"))
        if not tgt:
            continue
        kind = str(entry.get("kind") or "association").strip().lower()
        if kind == "generalization":
            kind = "inheritance"
        multiplicity = entry.get("multiplicity")
        if tgt == page.stem and kind == "inheritance":
            continue                   # a term may refer to itself, not inherit from itself
        out.append({
            "source": page.stem,
            "target": tgt,
            "verb": project.common._clean_label(str(entry.get("label") or "")),
            "cardinality": str(multiplicity if multiplicity is not None else "").strip(),
            "kind": kind if kind in _DM_ARROWS else "association",
        })
    return out


@wiki._request_cached
def data_model_contexts() -> list[str]:
    """The bounded contexts present in the model, for the filter control."""
    return sorted({n["context"] for n in data_model_nodes() if n["context"]})


def build_data_model_full_diagram(context: str | None = None,
                                  focus: str | None = None) -> str | None:
    """Project a mermaid class diagram of the model (DR-027).

    `context` narrows to one bounded context; `focus` narrows to one entity and
    its direct neighbours, which is what makes this readable in a room — the
    context diagram's own regression was fourteen nodes drawn at once (DR-026)
    and this model will get larger than that.

    Returns None when nothing survives the filter. `data_model.html` guards on
    `entities`, not on this diagram, so None stays a valid answer.
    """
    nodes = data_model_nodes()
    edges = data_model_edges()
    if context:
        keep = {n["key"] for n in nodes if n["context"] == context}
    else:
        keep = {n["key"] for n in nodes}
    if focus:
        if focus not in keep:
            return None
        neighbours = {focus}
        for e in edges:
            if e["source"] == focus:
                neighbours.add(e["target"])
            elif e["target"] == focus:
                neighbours.add(e["source"])
        keep &= neighbours
    nodes = [n for n in nodes if n["key"] in keep]
    if not nodes:
        return None

    taken: set[str] = set()
    name_of = {n["key"]: _dm_class_name(n["label"], taken) for n in nodes}

    def _decl(n) -> str:
        # The identifier is ASCII; the box shows the page's real title via a
        # mermaid class label (`class Id["Title"]`) whenever the two differ, so
        # "Durchführungsart" is drawn as written, not as "Durchfuehrungsart".
        ident = name_of[n["key"]]
        label = project.common._clean_label(n["label"]).replace('"', "'")
        return f'{ident}["{label}"]' if label != ident else ident

    lines = ["classDiagram"]
    for n in nodes:
        body = []
        if n["stereotype"] and n["stereotype"] != "entity":
            body.append(f"    <<{n['stereotype']}>>")
        for name in n["attributes"]:
            # Encode punctuation so Mermaid reads it as part of the member name.
            member = re.sub(r"[^\w -]", lambda m: f"#{ord(m[0])};", " ".join(name.split()))
            body.append(f"    +{member}")
        if body:
            lines.append(f"  class {_decl(n)} {{")
            lines += ["  " + b for b in body]
            lines.append("  }")
        else:
            lines.append(f"  class {_decl(n)}")

    for e in edges:
        if e["source"] not in keep or e["target"] not in keep:
            continue
        arrow, carded = _DM_ARROWS[e["kind"]]
        src, dst = name_of[e["source"]], name_of[e["target"]]
        if e["kind"] == "inheritance":
            # mermaid draws `Base <|-- Derived`; the page says "Derived is-a Base"
            src, dst = dst, src
        # `cardinality:` describes the TARGET end only. Deriving a source
        # multiplicity from it looked tidier and was wrong: "0..*" would have
        # drawn a zero on the owning side, which means nothing.
        multiplicity = project.common._clean_label(e["cardinality"], drop_parenthetical=False).replace('\\', "")
        if carded and multiplicity:
            line = f'  {src} {arrow} "{multiplicity}" {dst}'
        else:
            line = f"  {src} {arrow} {dst}"
        if e["verb"]:
            line += f" : {e['verb']}"
        lines.append(line)

    return "\n".join(lines)


# Section/callout extractors for the /entity-diagram catalog: each structured term is
# rendered as bold-led sections (**Purpose.**, **Attributes.**, **Relationships.**,
# **Invariants / rules.** …) plus 0..n `> [!note] X` callouts (Open points,
# deliberately omitted). Order from the file is preserved so the on-page detail
# reads the same as the markdown source.

_DM_SECTION_RE = re.compile(
    r"^\*\*(?P<label>[^*\n]+?)\.\*\*\s*\n?(?P<body>.*?)"
    r"(?=^\*\*[^*\n]+?\.\*\*|^>\s*\[!|^##\s|\Z)",
    re.DOTALL | re.MULTILINE,
)

_DM_NOTE_RE = re.compile(
    r"^>\s*\[!note\]\s*(?P<title>[^\n]+)\n(?P<body>(?:^>.*\n?)+)",
    re.MULTILINE,
)


def _extract_dm_attribute_names(page: wiki.Page) -> list[str]:
    """Just the attribute *names* from frontmatter `attributes:` — used for the
    compact summary table at the top of /entity-diagram and the class boxes."""
    return [a["name"] for a in _dm_attributes(page)]


def _dm_scalar(value: object) -> str:
    """A frontmatter value as text if it is a string or a whole number, else ""."""
    if isinstance(value, str) or isinstance(value, int) and not isinstance(value, bool):
        return str(value).strip()
    return ""


def _dm_attributes(page: wiki.Page) -> list[dict]:
    """The entries of frontmatter `attributes:` that carry a name, as
    `{name, type, multiplicity, identifier}`."""
    attributes = page.meta.get("attributes")
    if not isinstance(attributes, list):
        return []
    return [{"name": name, "type": _dm_scalar(entry.get("type")),
             "multiplicity": _dm_scalar(entry.get("multiplicity")),
             "identifier": entry.get("identifier") is True}
            for entry in attributes if isinstance(entry, dict)
            and isinstance(name := entry.get("name"), str) and name.strip()]


def term_kind(page: wiki.Page) -> str:
    """A domain term's kind: its stereotype, or "" for a plain term (FR-038)."""
    stereotype = str(page.meta.get("stereotype") or "").strip().lower()
    return stereotype if stereotype in DOMAIN_MODEL_STEREOTYPES else ""


def term_fields(page: wiki.Page) -> dict:
    """What the term page shows beside its text (FR-039): kind, aliases,
    attributes and relationships. A relationship whose target is a page
    names it by id and title and links it. Any other target stays as written."""
    links = links_module.link_index()
    by_stem = {p.stem: p for p in wiki.load_all_pages()}
    relationships = []
    for r in _dm_relationships(page):
        target = by_stem.get(links.get(r["target"], ("", ""))[1])
        relationships.append({
            "kind": "generalization" if r["kind"] == "inheritance" else r["kind"],
            "label": r["verb"],
            "target": target.title if target else r["target"],
            "target_id": target.id if target else "",
            "url": links_module._page_url(target.folder, target.stem) if target else "",
            # a multiplicity on a generalization means nothing, as in the diagram
            "multiplicity": r["cardinality"] if _DM_ARROWS[r["kind"]][1] else "",
        })
    return {"kind": term_kind(page), "aliases": page.aliases,
            "attributes": _dm_attributes(page), "relationships": relationships}


def _extract_dm_sections(page: wiki.Page, titles: dict[str, str]) -> list[tuple[str, str]]:
    """`(label, rendered-html)` pairs for every `**Label.**` section in a term's body,
    in source order. Bullets / inline code are preserved by routing the section
    body back through `render_markdown`."""
    out = []
    for m in _DM_SECTION_RE.finditer(page.body):
        label = m.group("label").strip()
        body = m.group("body").rstrip()
        out.append((label, render.render_markdown(body, titles)))
    return out


def _extract_dm_notes(page: wiki.Page, titles: dict[str, str]) -> list[dict]:
    """`> [!note] Title` callouts as `{title, html}` records. Quote markers
    (`> `) are stripped before the body is re-rendered as markdown."""
    out = []
    for m in _DM_NOTE_RE.finditer(page.body):
        title = m.group("title").strip()
        body_lines = m.group("body").splitlines()
        cleaned = "\n".join(re.sub(r"^>\s?", "", line) for line in body_lines).strip()
        out.append({"title": title, "html": render.render_markdown(cleaned, titles)})
    return out


def data_model_entities() -> list[dict]:
    """One record per structured term with its sections + notes ready to render —
    the per-entity catalog rendered below the projection diagram on /entity-diagram."""
    titles = links_module.title_index()
    pages = data_model_pages()
    out = []
    for p in pages:
        out.append({
            "id": p.id,
            "stem": p.stem,
            "url": f"/page/{p.folder}/{p.stem}",
            "title": p.title,
            "status": p.status,
            "stereotype": str(p.meta.get("stereotype") or "").strip(),
            "source_of_truth": str(p.meta.get("source-of-truth") or "").strip(),
            "attributes": _extract_dm_attribute_names(p),
            "sections": _extract_dm_sections(p, titles),
            "notes": _extract_dm_notes(p, titles),
        })
    return out


def supporting_model_count() -> int:
    """R4's headline: the structured domain terms plus the activity models."""
    return len(data_model_pages()) + len(wiki.load_type("activity-model"))
