"""Reader for `_system/metamodel/` (DR-035) — the explicit metamodel the
`/metamodel` help page explains.

Pure and Flask-free, like `catalog.py`: it parses the markdown pages (YAML
frontmatter = the contract, body = the explanation) into plain dicts and adds
nothing of its own. What the dashboard shows on top — colours, example pages
from the live wiki, the graph — is built in `app.py`.

The folder is listed on every call, but a page is parsed again only when its
file changes (`_CACHE`): the issue views ask it once per issue.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

import yaml

_env = os.environ.get("METAMODEL_DIR")
METAMODEL_DIR = (Path(_env) if _env
                 else Path(__file__).resolve().parents[2] / "metamodel")

_FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)
_H1 = re.compile(r"^#\s+.*$", re.MULTILINE)
_H2 = re.compile(r"^##\s+(.*)$", re.MULTILINE)

# Framework order on the page and in the graph: the problem space first, then
# what both peaks share, then the planned solution space.
_FRAMEWORK_ORDER = ["req42", "commons", "arc42"]


# path -> ((mtime_ns, size), parsed page or None). The dashboard asks the
# metamodel per issue on every page view (FR-027), so a parse is kept until
# its file changes, like the wiki pages in app.py's _PARSE_CACHE.
_CACHE: dict[Path, tuple[tuple[int, int], dict | None]] = {}


def _read(path: Path) -> dict | None:
    """One metamodel page as a dict (a fresh shallow copy, callers may add
    keys), or None. Parsed again only when the file's mtime or size changes."""
    try:
        st = path.stat()
    except OSError:
        _CACHE.pop(path, None)
        return None
    stamp = (st.st_mtime_ns, st.st_size)
    hit = _CACHE.get(path)
    if hit is None or hit[0] != stamp:
        hit = (stamp, _parse(path))
        _CACHE[path] = hit
    return dict(hit[1]) if hit[1] is not None else None


def _parse(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _FM.match(text)
    if not m:
        return None
    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return None
    if not isinstance(meta, dict) or meta.get("type") != "metamodel":
        return None
    body = m.group(2).strip()
    meta["_body"] = body
    meta["_summary"] = summary_of(body)
    meta["_file"] = path.name
    return meta


def summary_of(body: str) -> str:
    """The first paragraph of a page body, heading dropped, as one line of
    markdown — the 'definition' column of the type table."""
    text = _H1.sub("", body, count=1).strip()
    head = re.split(r"\n\s*\n", text, maxsplit=1)[0]
    # a body that opens with a list has no lead paragraph; show nothing then
    if head.lstrip().startswith(("-", "*", "|", "#")):
        return ""
    return " ".join(line.strip() for line in head.splitlines())


def _load(folder: str, construct: str) -> list[dict]:
    d = METAMODEL_DIR / folder
    if not d.is_dir():
        return []
    out = []
    for p in sorted(d.glob("*.md")):
        fm = _read(p)
        if fm and fm.get("construct") == construct:
            out.append(fm)
    return out


def load() -> dict:
    """Everything the page needs, as plain dicts:

      meta         the meta-metamodel page (universal fields, lifecycles, constructs)
      frameworks   in display order, each with its `blocks`
      blocks       flat, in framework order, each with `framework` added
      types        in block order (then page order); `block_title` added
      relations    page order; `edges` as declared
      projections  page order
      altitude     the altitude-scale page or {}
      rules        page order
      present      False when the folder is missing or empty
    """
    meta = _read(METAMODEL_DIR / "meta-metamodel.md") or {}
    frameworks = _load("frameworks", "framework")
    frameworks.sort(key=lambda f: (_FRAMEWORK_ORDER.index(f["name"])
                                   if f.get("name") in _FRAMEWORK_ORDER else 99))
    blocks: list[dict] = []
    for fw in frameworks:
        for b in fw.get("blocks") or []:
            blocks.append({**b, "framework": fw.get("name"), "area": fw.get("area")})
    block_pos = {b["id"]: i for i, b in enumerate(blocks)}
    block_by_id = {b["id"]: b for b in blocks}

    types = _load("types", "type")
    for t in types:
        b = block_by_id.get(t.get("block"))
        t["block_title"] = b["title"] if b else ""
        t["block_area"] = b["area"] if b else None
    types.sort(key=lambda t: (block_pos.get(t.get("block"), len(blocks)), t.get("name", "")))

    altitude = _read(METAMODEL_DIR / "altitude.md") or {}
    if altitude.get("construct") != "altitude-scale":
        altitude = {}

    return {
        "meta": meta,
        "frameworks": frameworks,
        "blocks": blocks,
        "types": types,
        "relations": _load("relations", "relation"),
        "projections": _load("projections", "projection"),
        "altitude": altitude,
        "rules": _load("rules", "rule"),
        "present": bool(types),
    }


def sort_orders(type_name: str) -> list[dict]:
    """The useful list orders a type page declares (FR-021), as
    `[{label, keys}]`. A type without any, or an unknown type, has none."""
    for t in _load("types", "type"):
        if t.get("name") == type_name:
            out = []
            for so in t.get("sort_orders") or []:
                if isinstance(so, dict) and so.get("label") and so.get("keys"):
                    out.append({"label": str(so["label"]), "keys": [str(k) for k in so["keys"]]})
            return out
    return []


def _type_page(type_name: str) -> dict:
    return next((t for t in _load("types", "type") if t.get("name") == type_name), {})


def field_values(type_name: str, field: str) -> list[str]:
    """The closed list of values a type's enum field allows, or []."""
    for f in _type_page(type_name).get("fields") or []:
        if isinstance(f, dict) and f.get("name") == field:
            return [str(v) for v in f.get("values") or []]
    return []


def lifecycle(type_name: str) -> list[str]:
    """The status values a type's lifecycle allows, or []."""
    meta = _read(METAMODEL_DIR / "meta-metamodel.md") or {}
    name = _type_page(type_name).get("lifecycle")
    return [str(v) for v in (meta.get("lifecycles") or {}).get(name) or []]


def type_for_folder(folder: str) -> str | None:
    """The type whose pages live in `wiki/<folder>`, or None."""
    for t in _load("types", "type"):
        if Path(str(t.get("folder", ""))).name == folder:
            return str(t.get("name"))
    return None


# --- method anchors (meta-metamodel section 5) -------------------------------
#
# The anchors are a metamodel construct whose pages live in `_system/anchors/`
# (frontmatter `type: anchor`), not in this folder. The dashboard shows them on
# /metamodel and links every `[[MADR]]` there (FR-035); it adds nothing to
# them (CON-004).

_aenv = os.environ.get("ANCHORS_DIR")
ANCHORS_DIR = (Path(_aenv) if _aenv
               else Path(__file__).resolve().parents[2] / "anchors")

_URL = re.compile(r"https?://[^\s<>()\]]+")
_SLUG = re.compile(r"[^a-z0-9]+")
# path -> ((mtime_ns, size), parsed anchor or None), like _CACHE
_ANCHOR_CACHE: dict[Path, tuple[tuple[int, int], dict | None]] = {}


def _parse_anchor(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _FM.match(text)
    if not m:
        return None
    try:
        meta = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return None
    if not isinstance(meta, dict) or meta.get("type") != "anchor":
        return None
    body = _H1.sub("", m.group(2).strip(), count=1).strip()
    slug = _SLUG.sub("-", path.stem.lower()).strip("-")
    url = _URL.search(body)
    applies = meta.get("applies-to") or []
    return {
        "name": str(meta.get("title") or path.stem),
        "slug": slug,
        "id": f"anchor-{slug}",
        "aliases": [str(a) for a in meta.get("aliases") or [] if a],
        "applies_to": [str(a) for a in (applies if isinstance(applies, list) else [applies]) if a],
        "definition": _definition(body),
        "reference": url.group(0).rstrip(".,;:") if url else "",
        "file": path.name,
    }


def _definition(body: str) -> str:
    """The first prose paragraph: a note (`> …`), a list, a table or a heading
    before it is not the definition."""
    for para in re.split(r"\n\s*\n", body):
        head = para.lstrip()
        if head and not head.startswith((">", "-", "*", "|", "#", "<!--")):
            return " ".join(line.strip() for line in para.strip().splitlines())
    return ""


def method_anchors() -> list[dict]:
    """Every anchor page, by name: `name`, `slug`, `id` (`anchor-<slug>`, the
    entry's id on /metamodel), `aliases`, `applies_to` (as written),
    `definition` (markdown, first prose paragraph) and `reference` (the first
    outside URL, or ""). Parsed again only when a file changes."""
    if not ANCHORS_DIR.is_dir():
        return []
    out = []
    for p in sorted(ANCHORS_DIR.glob("*.md")):
        try:
            st = p.stat()
        except OSError:
            continue
        stamp = (st.st_mtime_ns, st.st_size)
        hit = _ANCHOR_CACHE.get(p)
        if hit is None or hit[0] != stamp:
            hit = (stamp, _parse_anchor(p))
            _ANCHOR_CACHE[p] = hit
        if hit[1] is not None:
            out.append(dict(hit[1]))
    return sorted(out, key=lambda a: a["name"].lower())


def anchor_index(found: list[dict]) -> dict[str, dict]:
    """Lower-cased title, aliases and file name → the anchor, so `[[madr]]`
    and `[[MADR]]` find the same entry."""
    idx: dict[str, dict] = {}
    for a in found:
        for key in (a["name"], a["slug"], *a["aliases"]):
            idx.setdefault(str(key).strip().lower(), a)
    return idx


def anchors(mm: dict) -> dict[str, str]:
    """Every page name and alias → the in-page anchor id the `/metamodel` page
    gives that construct (`type-goal`, `rel-goal`, `proj-…`, `rule-…`,
    `fw-…`, `altitude`), for resolving the `[[wikilinks]]` metamodel pages use
    among themselves. Prefixed, because a type and a relation may share a name."""
    out: dict[str, str] = {}
    # types last, so a bare `[[goal]]` means the type, not the relation
    for key, prefix in (("relations", "rel-"), ("frameworks", "fw-"), ("projections", "proj-"),
                        ("rules", "rule-"), ("types", "type-")):
        for p in mm[key]:
            anchor = prefix + str(p["name"])
            out[str(p["name"])] = anchor
            for a in p.get("aliases") or []:
                out[str(a)] = anchor
    if mm["altitude"]:
        out["altitude"] = "altitude"
        out[str(mm["altitude"].get("name"))] = "altitude"
        for a in mm["altitude"].get("aliases") or []:
            out[str(a)] = "altitude"
    return out
