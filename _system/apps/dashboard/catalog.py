"""The Systems42 section catalog: three areas, eighteen sections, following
`systems42-sections-en-v2.svg` (R = req42, A = arc42, C = common). One place
for every label, folder, route and colour the dashboard needs to lay out the
home page, the area pages, breadcrumbs and the area colour bar — replacing the
former REQ42_BLOCKS list and the tile list that used to restate it (DR-033).

Colours mean *place*, never action: "req" green = requirements (req42's colour,
problem space), "arc" blue = architecture (arc42's colour, solution space), "org" red = organisation
and project. A section drawn with a blend in the diagram lists two colours.

`scope`: "in" = captured in wiki folders · "out" = deliberately not captured
(no route) · "planned" = arc42, no wiki folders yet (DR-033 follow-on).
"""
from __future__ import annotations

AREAS: list[dict] = [
    {"key": "requirements", "label": "Requirements", "subtitle": "goals, needs, constraints",
     "href": "/req42", "colors": ["req"]},
    {"key": "architecture", "label": "Architecture", "subtitle": "structure, interfaces, views",
     "href": "/arc42", "colors": ["arc"]},
    {"key": "commons", "label": "Commons", "subtitle": "shared by both peaks",
     "href": "/commons", "colors": ["req", "arc"]},
]

_OUT = "Deliberately not captured in this wiki."

SECTIONS: list[dict] = [
    # --- req42 -------------------------------------------------------------
    {"id": "R1", "area": "requirements", "title": "Vision & Goals", "folders": ["goals"],
     "href": "/goals", "slug": None, "scope": "in", "colors": ["org"], "note": ""},
    {"id": "R2", "area": "requirements", "title": "Resources & Staff", "folders": [],
     "href": None, "slug": None, "scope": "out", "colors": ["org"],
     "note": "Project resources — " + _OUT.lower()},
    {"id": "R3", "area": "requirements", "title": "Functional Requirements",
     "folders": ["functional-requirements", "use-cases"], "href": "/req42/functional-requirements", "slug": "functional-requirements",
     "scope": "in", "colors": ["req"],
     "note": "One type, stereotype epic|feature|story; hierarchy via parent: (DR-012). Use cases are FRs too (DR-011)."},
    {"id": "R4", "area": "requirements", "title": "Supporting Models",
     "folders": ["activity-models", "data-models"], "href": "/req42/models",
     "slug": "models", "scope": "in", "colors": ["req"], "note": ""},
    {"id": "R5", "area": "requirements", "title": "Team Structure", "folders": [],
     "href": None, "slug": None, "scope": "out", "colors": ["org"],
     "note": "Organisation / team setup — " + _OUT.lower()},
    {"id": "R6", "area": "requirements", "title": "Roadmap", "folders": [],
     "href": None, "slug": None, "scope": "out", "colors": ["org"],
     "note": "Release planning — " + _OUT.lower()},
    # --- arc42 (A1 planned: no content type yet) ------------------------------
    {"id": "A1", "area": "architecture", "title": "Solution Strategy", "folders": [],
     "href": None, "slug": None, "scope": "planned", "colors": ["arc"], "note": ""},
    {"id": "A2", "area": "architecture", "title": "Building Block View",
     "folders": ["building-blocks"], "href": "/arc42/building-blocks", "slug": "building-blocks",
     "scope": "in", "colors": ["arc"], "note": ""},
    {"id": "A3", "area": "architecture", "title": "Deployment View",
     "folders": ["deployment-nodes"], "href": "/arc42/deployment", "slug": "deployment",
     "scope": "in", "colors": ["arc"], "note": ""},
    {"id": "A4", "area": "architecture", "title": "Runtime View",
     "folders": ["runtime-scenarios"], "href": "/arc42/runtime", "slug": "runtime",
     "scope": "in", "colors": ["arc"], "note": ""},
    {"id": "A5", "area": "architecture", "title": "Crosscutting Concepts",
     "folders": ["concepts"], "href": "/arc42/concepts", "slug": "concepts",
     "scope": "in", "colors": ["arc"], "note": ""},
    # --- common ------------------------------------------------------------
    {"id": "C1", "area": "commons", "title": "Quality Requirements",
     "folders": ["quality-requirements"], "href": "/req42/quality", "slug": "quality",
     "scope": "in", "colors": ["req"], "note": ""},
    {"id": "C2", "area": "commons", "title": "Constraints", "folders": ["constraints"],
     "href": "/req42/constraints", "slug": "constraints", "scope": "in", "colors": ["req"],
     "note": ""},
    {"id": "C3", "area": "commons", "title": "Scope & Context",
     "folders": ["context", "external-interfaces"], "href": "/req42/scope", "slug": "scope",
     "scope": "in", "colors": ["req", "arc"], "note": ""},
    {"id": "C4", "area": "commons", "title": "Stakeholders", "folders": ["stakeholders"],
     "href": "/stakeholders", "slug": None, "scope": "in", "colors": ["req", "arc"], "note": ""},
    {"id": "C5", "area": "commons", "title": "Domain Terms", "folders": ["glossary"],
     "href": "/glossary", "slug": None, "scope": "in", "colors": ["req"], "note": ""},
    {"id": "C6", "area": "commons", "title": "Risks & Assumptions", "folders": ["issues"],
     "href": "/issues", "slug": None, "scope": "in", "colors": ["org", "arc"],
     "note": "Issues (especially kind: risk) plus [!assumption] markers."},
    {"id": "C7", "area": "commons", "title": "Decisions", "folders": ["decisions"],
     "href": "/decisions", "slug": None, "scope": "in", "colors": ["req", "arc"],
     "note": "Decision records of kind architecture, business or undefined (FR-009)."},
]

AREA_BY_KEY: dict[str, dict] = {a["key"]: a for a in AREAS}
SECTION_BY_ID: dict[str, dict] = {s["id"]: s for s in SECTIONS}
SECTION_BY_SLUG: dict[str, dict] = {s["slug"]: s for s in SECTIONS if s["slug"]}
_SECTION_BY_FOLDER: dict[str, dict] = {f: s for s in SECTIONS for f in s["folders"]}

# Routes that are not a section href but still belong to an area.
_EXTRA_PATH_PREFIXES: dict[str, str] = {
    "/functional-requirements/": "requirements",   # FR detail pages
    "/data-model": "requirements",                  # R4 projection
    "/graph/glossary": "commons",                   # C5 term network
}


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
