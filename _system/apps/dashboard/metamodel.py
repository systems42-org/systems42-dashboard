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
import threading
from pathlib import Path

import yaml

# The metamodel of the repository the dashboard runs on (CON-006): its own
# variable, else `_system/metamodel/` under REPO_DIR (the one mount, FR-042),
# else next to this file's repository for a local run.
_env = os.environ.get("METAMODEL_DIR")
_repo = os.environ.get("REPO_DIR")
METAMODEL_DIR = (Path(_env) if _env
                 else Path(_repo) / "_system" / "metamodel" if _repo
                 else Path(__file__).resolve().parents[2] / "metamodel")
# The project's own requirement notations (`_system/notations/`, FR-023,
# DR-038): its own variable, else the sibling of the metamodel folder.
_env_n = os.environ.get("NOTATIONS_DIR")
NOTATIONS_DIR = Path(_env_n) if _env_n else METAMODEL_DIR.parent / "notations"

_FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)
_H1 = re.compile(r"^#\s+.*$", re.MULTILINE)
_H2 = re.compile(r"^##\s+(.*)$", re.MULTILINE)
# A notation body is a page template cut into blocks by `<!-- levels: a, b -->`
# markers; a block is named by its first `## heading` or `**Label.**`.
_LEVELS = re.compile(r"^<!--\s*levels:\s*(.*?)\s*-->\s*$", re.MULTILINE)
_BLOCK_NAME = re.compile(r"^(?:##\s+(.+?)|\*\*(.+?)\*\*.*)$", re.MULTILINE)

# Framework order on the page and in the graph: the problem space first, then
# what both peaks share, then the planned solution space.
_FRAMEWORK_ORDER = ["req42", "commons", "arc42"]


# (path, parser) -> ((mtime_ns, size), parsed page or None). The dashboard
# asks the metamodel per issue on every page view (FR-027), so a parse is kept
# until its file changes, like the wiki pages in app.py's _PARSE_CACHE.
_CACHE: dict[tuple[Path, object], tuple[tuple[int, int], dict | None]] = {}
# Guards _CACHE and _ANCHOR_CACHE against gunicorn's request threads. Parsing
# runs outside it: a duplicate parse is harmless, a torn update is not.
_LOCK = threading.Lock()


def _key_path(key) -> Path:
    """The file of a cache key: _CACHE keys are (path, parser), others a path."""
    return key[0] if isinstance(key, tuple) else key


def _forget_missing(cache: dict, folder: Path, present: list[Path]) -> None:
    """Drop the entries of files in `folder` that are no longer listed there."""
    keep = set(present)
    with _LOCK:
        for key in [k for k in cache
                    if _key_path(k).parent == folder and _key_path(k) not in keep]:
            del cache[key]


def _read(path: Path, parse=None) -> dict | None:
    """One metamodel page as a dict (a fresh shallow copy, callers may add
    keys), or None. Parsed again only when the file's mtime or size changes.
    `parse` defaults to `_parse`, the reader for metamodel pages."""
    parse = parse or _parse
    key = (path, parse)
    try:
        st = path.stat()
    except OSError:
        with _LOCK:
            _CACHE.pop(key, None)
        return None
    stamp = (st.st_mtime_ns, st.st_size)
    with _LOCK:
        hit = _CACHE.get(key)
    if hit is None or hit[0] != stamp:
        hit = (stamp, parse(path))
        with _LOCK:
            _CACHE[key] = hit
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


# --- metamodel version (FR-043) -----------------------------------------------

# The metamodel versions this dashboard release supports, compared as text.
# A list of exact versions, because the rule for when the version changes is
# still open (ISS-004, meta issue #39). Once it is settled, a range can sit
# next to the list, and `version_check` is the only place that reads it.
SUPPORTED_VERSIONS: tuple[str, ...] = ("0.1",)

# Where the repository declares its metamodel version: the file ISS-004
# proposes, else the meta-metamodel page. The first file that exists decides.
VERSION_FILES = ("metamodel-version.md", "meta-metamodel.md")


def _parse_version(path: Path) -> dict | None:
    """`version:` from a file's frontmatter, as written: every value is read
    as text, so `0.10` stays `0.10`. The file needs no `type: metamodel`."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _FM.match(text)
    if not m:
        return {"version": ""}
    try:
        meta = yaml.load(m.group(1), Loader=yaml.BaseLoader) or {}
    except yaml.YAMLError:
        return {"version": ""}
    v = meta.get("version") if isinstance(meta, dict) else None
    return {"version": v.strip() if isinstance(v, str) else ""}


def version_check() -> dict:
    """The repository's metamodel version against this release:

      version     the declared version as text, "" when none is declared
      file        the file it was read from, "" when neither file exists
      supported   the versions this release supports
      state       "supported", "unsupported" or "missing"
    """
    version, file = "", ""
    for name in VERSION_FILES:
        path = METAMODEL_DIR / name
        if path.is_file():
            file = name
            version = (_read(path, _parse_version) or {}).get("version", "")
            break
    state = ("missing" if not version
             else "supported" if version in SUPPORTED_VERSIONS else "unsupported")
    return {"version": version, "file": file,
            "supported": list(SUPPORTED_VERSIONS), "state": state}


def summary_of(body: str) -> str:
    """The first paragraph of a page body, heading dropped, as one line of
    markdown — the 'definition' column of the type table."""
    text = _H1.sub("", body, count=1).strip()
    head = re.split(r"\n\s*\n", text, maxsplit=1)[0]
    # a body that opens with a list has no lead paragraph; show nothing then
    if head.lstrip().startswith(("-", "*", "|", "#")):
        return ""
    return " ".join(line.strip() for line in head.splitlines())


def notation_sections(body: str) -> list[dict]:
    """The level-marked blocks of a notation body, in order: `{heading,
    levels}`. Text before the first marker (the Capture comment, the title)
    belongs to every level and is not a section."""
    marks = list(_LEVELS.finditer(body))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        name = _BLOCK_NAME.search(body, m.end(), end)
        heading = (name.group(1) or name.group(2)).strip().rstrip(".") if name else ""
        out.append({"heading": heading,
                    "levels": [s.strip() for s in m.group(1).split(",") if s.strip()]})
    return out


def notations() -> list[dict]:
    """The requirement notations (DR-038), by name: the shipped ones in
    `notations/` of the metamodel, then a project's own in `_system/notations/`.
    Each carries `_sections` (its level-marked page-template blocks)."""
    out = _load("notations", "notation")
    own = sorted(NOTATIONS_DIR.glob("*.md")) if NOTATIONS_DIR.is_dir() else []
    _forget_missing(_CACHE, NOTATIONS_DIR, own)
    for p in own:
        n = _read(p)
        if n and n.get("construct") == "notation":
            out.append(n)
    out = [n for n in out if str(n.get("name") or "").strip()]   # a nameless file defines nothing
    for n in out:
        n["name"] = str(n["name"]).strip()
        n["_sections"] = notation_sections(str(n.get("_body") or ""))
        levels = n.get("levels")
        n["levels"] = [str(v) for v in levels] if isinstance(levels, list) else []
    return sorted(out, key=lambda n: n["name"].lower())


def _load(folder: str, construct: str) -> list[dict]:
    d = METAMODEL_DIR / folder
    paths = sorted(d.glob("*.md")) if d.is_dir() else []
    _forget_missing(_CACHE, d, paths)
    out = []
    for p in paths:
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
      notations    shipped and project-specific FR notation definitions (DR-038)
      projections  page order
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

    return {
        "meta": meta,
        "frameworks": frameworks,
        "blocks": blocks,
        "types": types,
        "notations": notations(),
        "relations": _load("relations", "relation"),
        "projections": _load("projections", "projection"),
        "rules": _load("rules", "rule"),
        "present": bool(types),
    }


def blocks() -> list[dict]:
    """Every framework block, the source of the dashboard's sections (FR-044).
    Frameworks by file name, blocks in file order. Each block keeps its own
    keys and gets `framework`, `area` (the framework's `area:`) and `folders`:
    the wiki folder of each type it lists, from the type page's `folder:`.
    A type without a page adds no folder."""
    folder_of = {str(t.get("name")): Path(str(t.get("folder") or "")).name
                 for t in _load("types", "type") if t.get("folder")}
    out: list[dict] = []
    for fw in _load("frameworks", "framework"):
        for b in fw.get("blocks") or []:
            if not isinstance(b, dict) or not str(b.get("id") or "").strip():
                continue
            names = b.get("types") or []
            names = [names] if isinstance(names, str) else names if isinstance(names, list) else []
            folders = [folder_of[str(n)] for n in names if str(n) in folder_of]
            out.append({**b, "id": str(b["id"]).strip(), "framework": fw.get("name"),
                        "area": fw.get("area"), "folders": folders})
    return out


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

# The anchors sit next to the metamodel folder (`_system/anchors/`), so the
# default is worked out from METAMODEL_DIR, never from this file's own place.
_aenv = os.environ.get("ANCHORS_DIR")
ANCHORS_DIR = Path(_aenv) if _aenv else METAMODEL_DIR.parent / "anchors"

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
    paths = sorted(ANCHORS_DIR.glob("*.md")) if ANCHORS_DIR.is_dir() else []
    _forget_missing(_ANCHOR_CACHE, ANCHORS_DIR, paths)
    out = []
    for p in paths:
        try:
            st = p.stat()
        except OSError:
            with _LOCK:
                _ANCHOR_CACHE.pop(p, None)
            continue
        stamp = (st.st_mtime_ns, st.st_size)
        with _LOCK:
            hit = _ANCHOR_CACHE.get(p)
        if hit is None or hit[0] != stamp:
            hit = (stamp, _parse_anchor(p))
            with _LOCK:
                _ANCHOR_CACHE[p] = hit
        if hit[1] is not None:
            out.append(dict(hit[1]))
    return sorted(out, key=lambda a: a["name"].lower())


def clear_caches() -> None:
    """Forget every parsed metamodel and anchor page, so the next call reads
    them from disk again. The dashboard's POST /reload calls this."""
    with _LOCK:
        _CACHE.clear()
        _ANCHOR_CACHE.clear()


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
    `fw-…`, `notation-agile`), for resolving the `[[wikilinks]]` metamodel pages use
    among themselves. Prefixed, because a type and a relation may share a name."""
    out: dict[str, str] = {}
    # types last, so a bare `[[goal]]` means the type, not the relation
    for key, prefix in (("relations", "rel-"), ("frameworks", "fw-"), ("projections", "proj-"),
                        ("rules", "rule-"), ("notations", "notation-"), ("types", "type-")):
        for p in mm[key]:
            anchor = prefix + str(p["name"])
            out[str(p["name"])] = anchor
            for a in p.get("aliases") or []:
                out[str(a)] = anchor
    return out
