"""The Systems42 section catalog: three areas and the sections the
repository's metamodel declares (FR-044, CON-006), following
`systems42-sections-en-v2.svg` (R = req42, A = arc42, C = common).

Each section's id, title, folders, scope and note come from the framework
blocks in `_system/metamodel/frameworks/` (via `metamodel.blocks()`), its area
from the `area:` of the framework file that declares it. This module adds only
presentation: the areas, and for the sections the dashboard knows, their route
and colours. A section it does not know gets the generic route
`/section/<id>` and its area's colours.

Colours mean *place*, never action: "req" green = requirements (req42's colour,
problem space), "arc" blue = architecture (arc42's colour, solution space), "org" red = organisation
and project. A section drawn with a blend in the diagram lists two colours.

`scope`: "in" = captured in wiki folders · "out" = deliberately not captured
(no route) · "planned" = no wiki folders yet. Only an "in" section has a route.

`refresh()` reads the metamodel again. The app calls it once per request, so
an edited framework file shows on the next page load.
"""
from __future__ import annotations

import metamodel

AREAS: list[dict] = [
    {"key": "requirements", "label": "Requirements", "subtitle": "goals, needs, constraints",
     "href": "/req42", "colors": ["req"]},
    {"key": "architecture", "label": "Architecture", "subtitle": "structure, interfaces, views",
     "href": "/arc42", "colors": ["arc"]},
    {"key": "commons", "label": "Commons", "subtitle": "shared by both peaks",
     "href": "/commons", "colors": ["req", "arc"]},
]

AREA_BY_KEY: dict[str, dict] = {a["key"]: a for a in AREAS}

_OUT = "Deliberately not captured in this wiki."

# How the dashboard shows the sections it has views for: the page a section
# opens (`href`), the slug of its /req42/<slug> or /arc42 view, the colours of
# its chip, and the tile text of a section left out. The metamodel decides
# whether a section exists, what it is called and which folders it holds.
_KNOWN: dict[str, dict] = {
    "R1": {"href": "/goals", "colors": ["org"]},
    "R2": {"colors": ["org"], "note": "Project resources — " + _OUT.lower()},
    "R3": {"href": "/req42/functional-requirements", "slug": "functional-requirements", "colors": ["req"]},
    "R4": {"href": "/req42/models", "slug": "models", "colors": ["req"]},
    "R5": {"colors": ["org"], "note": "Organisation / team setup — " + _OUT.lower()},
    "R6": {"colors": ["org"], "note": "Release planning — " + _OUT.lower()},
    "A1": {"href": "/arc42/strategy", "slug": "strategy", "colors": ["arc"]},
    "A2": {"href": "/arc42/building-blocks", "slug": "building-blocks", "colors": ["arc"]},
    "A3": {"href": "/arc42/deployment", "slug": "deployment", "colors": ["arc"]},
    "A4": {"href": "/arc42/runtime", "slug": "runtime", "colors": ["arc"]},
    "A5": {"href": "/arc42/concepts", "slug": "concepts", "colors": ["arc"]},
    "C1": {"href": "/req42/quality", "slug": "quality", "colors": ["req"]},
    "C2": {"href": "/req42/constraints", "slug": "constraints", "colors": ["req"]},
    "C3": {"href": "/req42/scope", "slug": "scope", "colors": ["req", "arc"]},
    "C4": {"href": "/stakeholders", "colors": ["req", "arc"]},
    "C5": {"href": "/domain-terms", "colors": ["req"]},
    "C6": {"href": "/issues", "colors": ["org", "arc"]},
    "C7": {"href": "/decisions", "colors": ["req", "arc"]},
}

# DR-039 renamed wiki/glossary/ to wiki/domain-terms/. A section holding one
# of them reads both, so the dashboard shows the terms of a wiki on either
# side of the rename.
_RENAMED_FOLDERS = {"glossary": "domain-terms", "domain-terms": "glossary"}


def _href(sid: str, scope: str) -> str | None:
    """The page an "in" section opens: its own view, else the generic list."""
    if scope != "in":
        return None
    return _KNOWN.get(sid, {}).get("href") or f"/section/{sid}"


def build(blocks: list[dict]) -> list[dict]:
    """The sections for `blocks` (as `metamodel.blocks()` returns them), in
    area order, then in the order the framework files declare them. A block
    of an unknown area, or with an id already taken, is left out."""
    out: list[dict] = []
    seen: set[str] = set()
    for b in blocks:
        sid, area = b["id"], b.get("area")
        if area not in AREA_BY_KEY or sid in seen:
            continue
        seen.add(sid)
        known = _KNOWN.get(sid, {})
        scope = str(b.get("scope") or "in")
        out.append({
            "id": sid, "area": area, "title": str(b.get("title") or sid),
            "folders": list(b.get("folders") or []),
            "href": _href(sid, scope), "slug": known.get("slug"),
            "scope": scope, "colors": list(known.get("colors") or AREA_BY_KEY[area]["colors"]),
            "note": known.get("note") or str(b.get("note") or ""),
            "framework": b.get("framework"),
        })
    order = [a["key"] for a in AREAS]
    return sorted(out, key=lambda s: order.index(s["area"]))


SECTIONS: list[dict] = []
SECTION_BY_ID: dict[str, dict] = {}
SECTION_BY_SLUG: dict[str, dict] = {}
_SECTION_BY_FOLDER: dict[str, dict] = {}


def section_folders(section: dict) -> list[str]:
    """The section's folders, plus the other name of a renamed one."""
    out = list(section["folders"])
    for f in section["folders"]:
        other = _RENAMED_FOLDERS.get(f)
        if other and other not in out:
            out.append(other)
    return out


def refresh() -> None:
    """Read the sections from the metamodel again. The lookups below change
    only when the sections do."""
    global SECTIONS, SECTION_BY_ID, SECTION_BY_SLUG, _SECTION_BY_FOLDER
    sections = build(metamodel.blocks())
    if sections == SECTIONS:
        return
    folder_owner: dict[str, dict] = {}
    for s in sections:
        for f in section_folders(s):
            folder_owner.setdefault(f, s)
    SECTIONS = sections
    SECTION_BY_ID = {s["id"]: s for s in sections}
    SECTION_BY_SLUG = {s["slug"]: s for s in sections if s["slug"]}
    _SECTION_BY_FOLDER = folder_owner


refresh()

# Routes that are not a section href but still belong to an area.
_EXTRA_PATH_PREFIXES: dict[str, str] = {
    "/functional-requirements/": "requirements",   # FR detail pages
    "/entity-diagram": "requirements",                  # R4 projection
    "/graph/domain-terms": "commons",                   # C5 term network
}


# Routes that are not a section href but still belong to a section.
_EXTRA_SECTION_PREFIXES: dict[str, str] = {
    "/functional-requirements/": "R3",
    "/entity-diagram": "R4",
    "/graph/domain-terms": "C5",
}


def section_href(section: dict) -> str:
    """Where a link to the section goes: its own page, or its tile on the area
    page when it has none."""
    return section["href"] or f"{AREA_BY_KEY[section['area']]['href']}#tile-{section['id'].lower()}"


def section_for_path(path: str) -> dict | None:
    """Which section a request path belongs to (FR-014, FR-020). None for
    area pages and for pages outside the sections."""
    if path.startswith("/page/"):
        parts = path.split("/", 3)          # ['', 'page', folder, stem]
        return section_for_folder(parts[2]) if len(parts) > 2 else None
    for prefix, sid in _EXTRA_SECTION_PREFIXES.items():
        if path.startswith(prefix):
            return SECTION_BY_ID.get(sid)
    for s in sorted((s for s in SECTIONS if s["href"]), key=lambda s: -len(s["href"])):
        if path == s["href"] or path.startswith(s["href"] + "/") or path.startswith(s["href"] + "?"):
            return s
    return None


def sections_of(area_key: str) -> list[dict]:
    """The area's sections in diagram order."""
    return [s for s in SECTIONS if s["area"] == area_key]


def section_for_folder(folder: str) -> dict | None:
    return _SECTION_BY_FOLDER.get(folder)


def area_for_folder(folder: str) -> dict | None:
    s = _SECTION_BY_FOLDER.get(folder)
    return AREA_BY_KEY[s["area"]] if s else None


def area_for_path(path: str) -> dict | None:
    """Which area a request path belongs to, for the breadcrumb's area level
    and the colour bar under the topbar. None for home, help, search,
    join, who — pages that belong to no cabinet."""
    for a in AREAS:
        if path == a["href"]:
            return a
    if path.startswith("/page/"):
        parts = path.split("/", 3)          # ['', 'page', folder, stem]
        return area_for_folder(parts[2]) if len(parts) > 2 else None
    for prefix, key in _EXTRA_PATH_PREFIXES.items():
        if path.startswith(prefix):
            return AREA_BY_KEY[key]
    # longest href first, so /req42/functional-requirements wins over /req42
    for s in sorted((s for s in SECTIONS if s["href"]), key=lambda s: -len(s["href"])):
        if path == s["href"] or path.startswith(s["href"] + "/") or path.startswith(s["href"] + "?"):
            return AREA_BY_KEY[s["area"]]
    return None
