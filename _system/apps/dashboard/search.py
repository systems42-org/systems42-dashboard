"""The search records: what the search index holds for each page.

Owns the searched frontmatter fields, the reader's text of a page body
(search_plain), a page's neighbours by link, the flat list of records the
browser ranks, the synonyms from the domain terms and the search index.

May import `wiki`, `links`, `render`, `catalog` and `project.terms`. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import re

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes
import project.terms  # the domain terms
import render  # sanitizer, wikilinks and Markdown
import wiki  # paths, pages, parse cache and loaders


# Frontmatter fields searched as plain words (FR-006). Link fields (parent,
# sources, related, drivers …) are left out: their values are file names.
SEARCH_FIELDS = ["tags", "status", "stereotype", "notation", "level", "priority", "kind", "state",
                 "category", "dimensions"]

_MD_LINK_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_HTML_TAG_RE = re.compile(r"<[^>]+>")
_SOURCE_ID_RE = re.compile(r"[A-Z]+-\d+")
# Lines that label a page's structure rather than say something: headings,
# callout titles and bold-only lines such as **PROBLEM / GOAL**. A bold lead
# label such as **Snapshot.** goes too, the text after it stays. The note
# "> follows [[MADR]]" goes before, by the page's own test (drop_follows).
_HEADING_LINE_RE = re.compile(r"^\s*(?:#{1,6}\s|>\s*\[![\w-]+\]|\*\*[^*]+\*\*\s*$)")
_LEAD_LABEL_RE = re.compile(r"^(\s*(?:[-*+]\s+)?)\*\*[^*]{1,60}[.:]\*\*\s+")
_LINE_MARK_RE = re.compile(r"^\s*(?:#{1,6}\s+|>\s*(?:\[![\w-]+\][-+]?\s*)?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+")
_EMPHASIS_RE = re.compile(r"\*\*|__|~~|`|(?<!\w)\*(?=\S)|(?<=\S)\*(?!\w)")


def search_plain(page: wiki.Page, titles: dict[str, str]) -> str:
    """A page body as the reader sees it, for search: wikilinks become their
    label (or the target's title), markdown and HTML markup go, hard-wrapped
    prose is joined. One line per paragraph or list item, so the ranker can
    cut passages. Headings and labels go (`_HEADING_LINE_RE`), and so do the
    "follows" notes the page shows as head labels (`drop_follows`).
    An unlabelled provenance link to raw/sources becomes the source's ID
    (`SRC-006`): its file name or title would match words such as
    "grilling" on most pages, and dropping it leaves "came from ." holes."""
    def link_text(m: re.Match) -> str:
        target, label = m.group(1).strip(), m.group(2)
        base = target.split("/")[-1]
        if label:
            return label.strip()
        if target.startswith("raw/") or base.startswith("SRC-"):
            src = links_module.source_index().get(base)
            return src.id if src else _SOURCE_ID_RE.match(base).group(0) if _SOURCE_ID_RE.match(base) else ""
        return titles.get(base, target)

    body = render._unwrap_prose(render.drop_follows(page.body))
    body = wiki.WIKILINK_RE.sub(link_text, body)
    body = _MD_LINK_RE.sub(lambda m: m.group(1), body)
    body = _HTML_TAG_RE.sub(" ", body)
    lines = []
    for line in body.splitlines():
        if line.strip().startswith("```") or render._TABLE_SEP_RE.match(line) or _HEADING_LINE_RE.match(line):
            continue
        line = _LEAD_LABEL_RE.sub(r"\1", line)
        line = _LINE_MARK_RE.sub("", line)
        line = _EMPHASIS_RE.sub("", line).replace("|", " ")
        line = re.sub(r"\s+", " ", line).strip()
        if line and line != "---":
            lines.append(line)
    return "\n".join(lines)


def _search_fields(page: wiki.Page) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for key in SEARCH_FIELDS:
        v = page.meta.get(key)
        vals = v if isinstance(v, list) else [v]
        vals = [str(x).strip().lower() for x in vals if x is not None and str(x).strip()]
        if vals:
            out[key] = vals
    return out


def _search_links(pages: list[wiki.Page]) -> dict[str, set[str]]:
    """page id -> ids one link step away, in either direction (FR-008)."""
    idx = links_module.link_index()
    by_stem = {p.stem: p for p in pages}
    out: dict[str, set[str]] = {p.id: set() for p in pages}
    for p in pages:
        for t in p.link_targets():
            dest = idx.get(t)
            if not dest or dest[1] not in by_stem:
                continue
            other = by_stem[dest[1]].id
            if other != p.id:
                out[p.id].add(other)
                out.setdefault(other, set()).add(p.id)
    return out


def build_search_records() -> list[dict]:
    """A flat index over every wiki page, ranked client-side by
    static/search-rank.js. Each record links to that unit's own detail page
    and carries the reader's text (`plain`), `aliases`, the searched `fields`
    (lower-cased) and the ids of its neighbours (`links`)."""
    pages = wiki.load_all_pages()
    titles = links_module.title_index()
    neighbours = _search_links(pages)
    records = []
    for p in pages:
        records.append({
            "id": p.id,
            "type": catalog.label(p.folder),
            "title": p.title,
            "status": p.status,
            "url": links_module._page_url(p.folder, p.stem),
            "aliases": [str(a) for a in p.aliases],
            "plain": search_plain(p, titles),
            "fields": _search_fields(p),
            "links": sorted(neighbours.get(p.id, ())),
        })
    return records


# --- global search ---------------------------------------------------------


def search_synonyms() -> list[list[str]]:
    """Each domain term's title plus its aliases, lower-cased. The search
    treats a group as one word (FR-003)."""
    return [[str(w).strip().lower() for w in [p.title, *p.aliases] if str(w).strip()]
            for p in project.terms.domain_terms()]


def build_search_index() -> dict:
    """What /search.json serves and /search embeds: {records, synonyms}."""
    return {"records": build_search_records(), "synonyms": search_synonyms()}
