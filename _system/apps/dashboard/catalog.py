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

The folder, ID prefix and label of each type come from its type page in
`_system/metamodel/types/` (via `metamodel.type_decls()`). `folder()`,
`type_of()`, `label()` and the prefix lookups below are the one place the
dashboard asks where a type's pages live and what they are called.

`refresh()` reads the metamodel again. The app calls it once per request, so
an edited framework or type file shows on the next page load.
"""
from __future__ import annotations

import metamodel

AREAS: list[dict] = [
    {"key": "requirements", "label": "Requirements", "subtitle": "goals, needs, constraints",
     "href": "/req42", "colors": ["req"]},
    {"key": "architecture", "label": "Architecture", "subtitle": "structure, interfaces, views",
     "href": "/arc42", "colors": ["arc"]},
    {"key": "commons", "label": "Commons", "subtitle": "shared by both areas",
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
            "id": sid, "area": area, "title": metamodel.block_title(b),
            "folders": list(b.get("folders") or []),
            "href": _href(sid, scope), "slug": known.get("slug"),
            "scope": scope, "colors": list(known.get("colors") or AREA_BY_KEY[area]["colors"]),
            "note": known.get("note") or str(b.get("note") or ""),
            "framework": b.get("framework"),
        })
    order = [a["key"] for a in AREAS]
    return sorted(out, key=lambda s: order.index(s["area"]))


# The types the dashboard has views for, with the folder, ID prefix and label
# the Systems42 metamodel gives them. A value here is used only when the
# repository's metamodel does not declare it (CON-006): a wiki without a
# metamodel folder, or a type page without that key.
_DEFAULT_TYPES: dict[str, dict] = {
    name: {"name": name, "folder": folder, "prefix": prefix, "label": label}
    for name, folder, prefix, label in (
        ("goal", "goals", "GOAL", "Goal"),
        ("context", "context", "CTX", "Context"),
        ("external-interface", "external-interfaces", "EIF", "External interface"),
        ("functional-requirement", "functional-requirements", "FR", "Functional requirement"),
        ("activity-model", "activity-models", "ACT", "Activity model"),
        ("quality-requirement", "quality-requirements", "QR", "Quality requirement"),
        ("constraint", "constraints", "CON", "Constraint"),
        ("domain-term", "domain-terms", "DT", "Domain term"),
        ("stakeholder", "stakeholders", "STK", "Stakeholder"),
        ("issue", "issues", "ISS", "Issue"),
        ("decision-record", "decisions", "DR", "Decision record"),
        ("solution-strategy", "solution-strategy", "SOL", "Solution strategy"),
        ("building-block", "building-blocks", "BB", "Building block"),
        ("crosscutting-concept", "crosscutting-concepts", "CC", "Crosscutting concept"),
        ("runtime-scenario", "runtime-scenarios", "RS", "Runtime scenario"),
        ("deployment-node", "deployment-nodes", "DN", "Deployment node"),
    )
}

# Presentation: the heading of a type's group in the relations and trace
# panels, and the order of the groups. A type without a heading here shows
# its metamodel label.
_GROUP_LABELS: dict[str, str] = {
    "domain-term": "Domain terms", "stakeholder": "Stakeholders", "context": "Context",
    "external-interface": "External interfaces", "goal": "Goals",
    "functional-requirement": "Functional requirements", "activity-model": "Activity models",
    "quality-requirement": "Quality requirements", "constraint": "Constraints",
    "decision-record": "Decisions", "solution-strategy": "Solution strategies",
    "building-block": "Building blocks", "crosscutting-concept": "Crosscutting concepts",
    "runtime-scenario": "Runtime scenarios", "deployment-node": "Deployment nodes",
    "issue": "Issues",
}
_GROUP_ORDER = ["domain-term", "stakeholder", "context", "external-interface", "goal",
                "functional-requirement", "activity-model", "quality-requirement", "constraint",
                "decision-record", "solution-strategy", "building-block", "crosscutting-concept",
                "runtime-scenario", "deployment-node", "issue"]
# UC: a migrated use case keeps its ID as a functional requirement (DR-038).
# The prefix is no type's own, so no type page declares it.
_LEGACY_PREFIXES: dict[str, tuple[str, str]] = {"UC": ("functional-requirement", "Use cases")}

TYPES: dict[str, dict] = {}
_TYPE_DECLS: list[dict] | None = None
_TYPE_BY_FOLDER: dict[str, str] = {}
_TYPE_BY_PREFIX: dict[str, str] = {}
_PREFIX_ORDER: list[str] = []


def build_types(decls: list[dict]) -> dict[str, dict]:
    """Every type by name, as `{name, folder, prefix, label}`: what the type
    pages declare (`metamodel.type_decls()`), filled from `_DEFAULT_TYPES`
    where a page leaves a key out, plus the default types no page declares."""
    out: dict[str, dict] = {}
    for d in decls:
        base = _DEFAULT_TYPES.get(d["name"], {})
        out.setdefault(d["name"], {
            "name": d["name"],
            "folder": d["folder"] or base.get("folder", ""),
            "prefix": d["prefix"] or base.get("prefix", ""),
            "label": d["label"] or base.get("label", d["name"]),
        })
    for name, base in _DEFAULT_TYPES.items():
        out.setdefault(name, dict(base))
    return out


def _refresh_types() -> None:
    global TYPES, _TYPE_DECLS, _TYPE_BY_FOLDER, _TYPE_BY_PREFIX, _PREFIX_ORDER
    decls = metamodel.type_decls()
    if decls == _TYPE_DECLS:
        return
    types = build_types(decls)
    by_folder: dict[str, str] = {}
    by_prefix: dict[str, str] = {}
    # declared types first, so a declared folder or prefix wins over a default
    for t in types.values():
        if t["folder"]:
            by_folder.setdefault(t["folder"], t["name"])
        if t["prefix"]:
            by_prefix.setdefault(t["prefix"], t["name"])
    order: list[str] = []
    for name in _GROUP_ORDER:
        order.append(types[name]["prefix"])
        order.extend(p for p, (owner, _) in _LEGACY_PREFIXES.items()
                     if owner == name and p not in by_prefix)
    for prefix, (owner, _) in _LEGACY_PREFIXES.items():
        by_prefix.setdefault(prefix, owner)
    TYPES, _TYPE_DECLS = types, decls
    _TYPE_BY_FOLDER, _TYPE_BY_PREFIX, _PREFIX_ORDER = by_folder, by_prefix, order


def folder(type_name: str) -> str:
    """The wiki folder that holds the pages of a type, "" for an unknown type."""
    t = TYPES.get(type_name)
    return t["folder"] if t else ""


def type_of(folder_name: str) -> str | None:
    """The type whose pages live in `wiki/<folder_name>`, or None."""
    return _TYPE_BY_FOLDER.get(folder_name)


def label(folder_name: str) -> str:
    """The label of the type whose pages live in the folder, else the folder
    name: the "Type" of a page in lists, search and on its detail page."""
    t = TYPES.get(_TYPE_BY_FOLDER.get(folder_name, ""))
    return t["label"] if t else folder_name


def type_for_prefix(prefix: str) -> str | None:
    """The type whose IDs start with `prefix` (`DT`, `FR`), or None."""
    return _TYPE_BY_PREFIX.get(prefix)


def folder_for_prefix(prefix: str) -> str | None:
    """The folder a page with this ID prefix belongs in, or None."""
    return folder(_TYPE_BY_PREFIX.get(prefix, "")) or None


def group_label(prefix: str) -> str:
    """The heading of the group that collects links to pages with this ID
    prefix. An unknown prefix is its own heading."""
    name = _TYPE_BY_PREFIX.get(prefix)
    legacy = _LEGACY_PREFIXES.get(prefix)
    if legacy and legacy[0] == name and TYPES[name]["prefix"] != prefix:
        return legacy[1]
    return _GROUP_LABELS.get(name) or (TYPES[name]["label"] if name else prefix)


def prefix_order() -> list[str]:
    """The ID prefixes in the order their groups show."""
    return _PREFIX_ORDER


SECTIONS: list[dict] = []
SECTION_BY_ID: dict[str, dict] = {}
SECTION_BY_SLUG: dict[str, dict] = {}
_SECTION_BY_FOLDER: dict[str, dict] = {}


def refresh() -> None:
    """Read the types and the sections from the metamodel again. The lookups
    change only when the declarations do."""
    global SECTIONS, SECTION_BY_ID, SECTION_BY_SLUG, _SECTION_BY_FOLDER
    _refresh_types()
    sections = build(metamodel.blocks())
    if sections == SECTIONS:
        return
    folder_owner: dict[str, dict] = {}
    for s in sections:
        for f in s["folders"]:
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
