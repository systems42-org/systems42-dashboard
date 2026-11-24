"""Links between pages: the resolver and the indexes it reads.

Owns the title, page, link and source indexes, the page URL, the reading of a
link's page name and the one resolver for links (#178), with the helpers that
read a page's links and link fields.

May import `wiki`. No Flask import and no import of `app` here
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re

import wiki  # paths, pages, parse cache and loaders


@wiki._request_cached
def title_index() -> dict[str, str]:
    """Map every page stem -> human title, for resolving wikilinks to text.
    Built from load_all_pages(), so it knows exactly the pages link_index()
    and the lists know (a nested or root-level .md is none of them)."""
    return {p.stem: p.title for p in wiki.load_all_pages()}


def _page_url(folder: str, stem: str) -> str:
    """Canonical dashboard URL for a wiki page. FRs have their own rich route;
    everything else uses the generic /page view."""
    if wiki._is(folder, "functional-requirement"):
        return f"/functional-requirements/{stem}"
    return f"/page/{folder}/{stem}"


@wiki._request_cached
def page_index() -> dict[str, wiki.Page]:
    """Map each page's stem and id -> its Page: the names a link may use for
    a page. A file name always names its own page. An ID names the first page
    that carries it, unless it is another page's file name."""
    idx: dict[str, wiki.Page] = {}
    pages = wiki.load_all_pages()
    for p in pages:
        idx[p.stem] = p
    for p in pages:
        idx.setdefault(p.id, p)
    return idx


@wiki._request_cached
def link_index() -> dict[str, tuple[str, str]]:
    """page_index() as (folder, stem), so body wikilinks like
    `[[STK-006-…|Backoffice]]` or `[[FR-008]]` resolve to a real target URL."""
    return {name: (p.folder, p.stem) for name, p in page_index().items()}


def link_name(spelling: object) -> str:
    """The page name inside a link: '[[wiki/goals/GOAL-002#Metric|waiting]]'
    -> 'GOAL-002'. Drops the brackets, the alias, the heading and the path. A
    value without brackets is read the same way."""
    t = str(spelling or "").strip()
    m = re.search(r"\[\[([^\]]+)\]\]", t)
    if m:
        t = m.group(1)
    t = t.split("|")[0].split("#")[0].strip()
    return t.split("/")[-1].strip()


def resolve_link(spelling: object, index: dict):
    """The one resolver for links (#178): what `index` holds for the page a
    link names, or None. The body text, the relations panel and every
    projection over a link field call it, so a link that opens a page in the
    text counts for that page everywhere. `index` is page_index() or
    link_index(): a full file name or an ID alone, case-sensitive. One dict
    lookup per link, because the relations panel asks every page (#68)."""
    return index.get(link_name(spelling))


def _link_stem(spelling: object) -> str:
    """The file name of the page a link names, or the name as written when no
    page has it (a hint can then say which name is missing)."""
    p = resolve_link(spelling, page_index())
    return p.stem if p else link_name(spelling)


def linked_stems(page: wiki.Page) -> set[str]:
    """The pages `page` links to, each once however often and however it is
    spelled, without itself. A name no page has stays as written."""
    return {s for s in map(_link_stem, page.link_targets()) if s != page.stem}


def links_to(page: wiki.Page, target: wiki.Page) -> bool:
    """Whether `page` links to `target`, by any name that resolves to it."""
    index = page_index()
    names = {n for n in (target.stem, target.id) if index.get(n) is target}
    return page is not target and not names.isdisjoint(page.link_targets())


@wiki._request_cached
def source_index() -> dict[str, wiki.Page]:
    """Map each raw/sources/ record's stem and id -> its Page, so a page's
    `sources:` wikilinks (and the /source/<stem> route) can resolve either
    form."""
    idx: dict[str, wiki.Page] = {}
    for p in wiki.load_sources():
        idx.setdefault(p.stem, p)
        idx.setdefault(p.id, p)
    return idx

def _stem_of_link(raw: object) -> str:
    """A `related:` entry like '[[DT-026-eaqua|EAquA]]' -> 'DT-026-eaqua'."""
    return link_name(raw)


def links_of(page: wiki.Page, field: str) -> list[str]:
    """Existing target stems of a link field, in order, without duplicates.
    Accepts '[[stem]]', '[[stem|alias]]', a bare stem, a single value or a
    list, and the nested list YAML makes of an unquoted [[stem]]. A value
    counts when page_index() has a page for it: the index holds every file
    name, so no walk over all pages per call is needed (#206)."""
    index = page_index()
    out: list[str] = []

    def walk(v: object) -> None:
        if isinstance(v, (list, tuple)):
            for x in v:
                walk(x)
            return
        p = resolve_link(v, index) if v else None
        if p is not None and p.stem not in out:
            out.append(p.stem)

    walk(page.meta.get(field))
    return out
