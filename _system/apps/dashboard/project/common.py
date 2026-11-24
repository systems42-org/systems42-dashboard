"""What several projections share.

Owns the meaning of an open issue and the open issues per folder, the maturity
bar, a page's provenance records, the pages of a section, and the node ids,
labels and node links of the Mermaid diagrams.

May import `wiki` and `links`. No Flask import and no import of `app` here
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re

import links as links_module  # link resolver and indexes
import wiki  # paths, pages, parse cache and loaders


def provenance(page: wiki.Page) -> list[dict]:
    """Resolve a page's `sources:` wikilinks to provenance records. Unresolved
    entries are kept (url=None) so the chip can say so instead of vanishing."""
    idx = links_module.source_index()
    rows = []
    refs = page.as_list("sources")          # a bare string is one entry, not a list of characters
    for ref in refs:
        base = _fr_stem_from_ref(ref)           # '[[raw/sources/SRC-001-x]]' -> 'SRC-001-x'
        if not base:
            continue                             # None / empty after stripping — nothing to show
        src = idx.get(base)
        if src:
            rows.append({"id": src.id, "title": src.title, "stem": src.stem,
                         "type": str(src.meta.get("source-type") or ""),
                         "origin": str(src.meta.get("origin") or ""),
                         "captured": str(src.meta.get("captured") or ""),
                         "url": f"/source/{src.stem}"})
        else:
            rows.append({"id": base, "title": base, "stem": base, "type": "", "origin": "", "captured": "", "url": None})
    return rows


@wiki._request_cached
def open_issue_counts() -> dict[str, set[str]]:
    """folder -> ids of OPEN issues whose links (frontmatter `related:` or body
    wikilinks) resolve to a page in that folder. One issue's id can appear in
    several folders' sets; an issue that links nothing resolvable appears in
    none. Sets (not counts) so a caller spanning several folders — e.g. Scope's
    context + external-interfaces — can union them and count each issue once,
    even if it links pages in more than one of those folders."""
    links = links_module.link_index()
    out: dict[str, set[str]] = {}
    for iss in wiki.load_type("issue"):
        if not is_open_issue(iss.status):
            continue
        for folder in {links[t][0] for t in iss.link_targets() if t in links}:
            out.setdefault(folder, set()).add(iss.id)
    return out


# Status values that count as "closed" for the issues filter.
CLOSED_STATUSES = {"resolved", "wontfix"}


def is_open_issue(status: object) -> bool:
    """The one meaning of "open" for an issue: every status except resolved
    and wontfix. A missing or unknown status stays visible as open."""
    return str(status or "").strip().lower() not in CLOSED_STATUSES


# The four-step lifecycle every content type shares (AGENTS.md: draft → review →
# accepted → deprecated). Issue statuses are mapped onto it so one thin
# bar reads the same on every tile.
MATURITY_ORDER = ["accepted", "review", "draft", "deprecated"]
_MATURITY_ALIASES = {
    "proposed": "review", "in-progress": "review",
    "resolved": "accepted", "ingested": "accepted",
    "open": "draft",
    "superseded": "deprecated", "rejected": "deprecated", "wontfix": "deprecated",
}


def maturity(statuses) -> dict:
    """Bucket status strings into MATURITY_ORDER and return the segments of a
    stacked bar (percent widths) plus a text label for the tooltip/aria."""
    counts = {k: 0 for k in MATURITY_ORDER}
    for s in statuses:
        s = _MATURITY_ALIASES.get(str(s or "").strip().lower(), str(s or "").strip().lower())
        counts[s if s in counts else "draft"] += 1
    total = sum(counts.values())
    segments = [{"status": k, "n": counts[k], "pct": round(100 * counts[k] / total)}
                for k in MATURITY_ORDER if counts[k]]
    label = " · ".join(f'{s["n"]} {s["status"]}' for s in segments) or "nothing yet"
    return {"total": total, "segments": segments, "label": label}


def _block_pages(block: dict) -> list[wiki.Page]:
    """All wiki pages feeding one req42 block, sorted by id."""
    pages: list[wiki.Page] = []
    for folder in block["folders"]:
        pages.extend(wiki.load_folder(folder))
    return sorted(pages, key=lambda p: p.id)

_NID_RE = re.compile(r"[^A-Za-z0-9]")


def _diagram_node_id(raw: str) -> str:
    return _NID_RE.sub("", str(raw)) or "N"


def _clean_label(s: object, drop_parenthetical: bool = True) -> str:
    """Resolve [[a|b]]→b / [[a]]→a, optionally drop a trailing (parenthetical),
    strip chars that would break the mermaid/HTML text so labels are always
    render-safe.

    `drop_parenthetical=False` for the system name: a vault called
    "Bookshelf (v2)" showed in full in the hero but as "Bookshelf" in every
    diagram, which reads as two different systems on the same screen.
    Square brackets are stripped because mermaid uses them as node-shape
    delimiters; apostrophes are kept — labels are emitted inside double
    quotes, and "Member's card" should stay readable.
    """
    t = str(s or "")
    t = re.sub(r"\[\[[^\]|]+\|([^\]]+)\]\]", r"\1", t)                       # [[a|b]] -> b
    t = re.sub(r"\[\[([^\]]+)\]\]", lambda m: m.group(1).split("/")[-1], t)  # [[a]]   -> a
    if drop_parenthetical:
        t = re.sub(r"\s*\([^)]*\)\s*$", "", t)                               # trailing (…)
    t = t.replace("&", " and ")          # never silently delete: "A & B" -> "A and B"
    t = re.sub(r'[<>"|\[\]]', "", t)
    return re.sub(r"\s+", " ", t).strip()


def _node_link(p: wiki.Page) -> dict:
    """A page drawn as a diagram node, as the text link beside the diagram."""
    return {"id": p.id, "title": p.title, "url": links_module._page_url(p.folder, p.stem)}


def _fr_stem_from_ref(ref: object) -> str:
    """From '[[FR-009-foo]]' / 'FR-009-foo' / a bare stem, return the page stem
    (children are matched to parents by stem)."""
    s = str(ref or "").strip()
    m = re.match(r"\[\[([^\]\|#]+)", s)
    return (m.group(1) if m else s).split("/")[-1].strip()
