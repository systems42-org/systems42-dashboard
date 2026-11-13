"""Reader for `_system/metamodel/` (DR-035) — the explicit metamodel the
`/metamodel` help page explains.

Pure and Flask-free, like `catalog.py`: it parses the markdown pages (YAML
frontmatter = the contract, body = the explanation) into plain dicts and adds
nothing of its own. What the dashboard shows on top — colours, example pages
from the live wiki, the graph — is built in `app.py`.

The folder is read on every call. It is a dozen small files and changes only
when the schema changes, so no cache is worth its invalidation.
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


def _read(path: Path) -> dict | None:
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


def type_for_folder(folder: str) -> str | None:
    """The type whose pages live in `wiki/<folder>`, or None."""
    for t in _load("types", "type"):
        if Path(str(t.get("folder", ""))).name == folder:
            return str(t.get("name"))
    return None


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
