#!/usr/bin/env python3
"""Lint `_system/metamodel/` against the files that must agree with it.

The metamodel is the single statement of the schema (DR-035); templates,
wiki folders, anchors and the dashboard catalog are its consumers. Nothing
raises when they drift, so this script diffs them:

  * every template has a type page; every `type` page: template exists, its `id:` prefix and `type:` value
    match, its frontmatter keys equal universal + declared fields (exactly),
    its `sort_orders` name only those fields,
    the wiki folder exists, its block is declared by some framework, its
    anchors exist, its projections exist, every link field names a relation
    whose edges allow this type as `from`;
  * every `relation`: `from` / `to` types exist (or `any`), and every `from`
    type declares a field for it;
  * every `framework`: block types exist, every wiki folder sits in exactly
    one block, and the dashboard catalog agrees on id, title and folders;
  * every `projection`: the types and fields it reads exist;
  * the altitude scale: assigned types / stereotypes exist.

Run from the repo root:  python3 _system/scripts/metamodel-lint.py
Exit status 1 on any finding. Requires PyYAML.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("metamodel-lint needs PyYAML:  pip install pyyaml")

ROOT = Path(__file__).resolve().parents[2]
MM = ROOT / "_system" / "metamodel"
TEMPLATES = ROOT / "_templates"
ANCHORS = ROOT / "_system" / "anchors"
_FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_KEY = re.compile(r"^([a-zA-Z][a-zA-Z0-9_-]*)\s*:", re.MULTILINE)

findings: list[str] = []


def fail(msg: str) -> None:
    findings.append(msg)


def frontmatter(path: Path) -> dict:
    if not path.is_file():
        fail(f"{path.relative_to(ROOT)}: missing")
        return {}
    m = _FM.match(path.read_text(encoding="utf-8"))
    if not m:
        fail(f"{path.relative_to(ROOT)}: no frontmatter")
        return {}
    try:
        return yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:  # noqa: PERF203
        fail(f"{path.relative_to(ROOT)}: YAML error: {e}")
        return {}


def template_keys(path: Path) -> set[str]:
    m = _FM.match(path.read_text(encoding="utf-8"))
    return set(_KEY.findall(m.group(1))) if m else set()


def anchor_names() -> set[str]:
    names: set[str] = set()
    for p in ANCHORS.glob("*.md"):
        if p.name == "README.md":
            continue
        names.add(p.stem)
        fm = frontmatter(p)
        names.update(str(a) for a in (fm.get("aliases") or []))
        if fm.get("title"):
            names.add(str(fm["title"]))
    return names


def load(construct: str, folder: str) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for p in sorted((MM / folder).glob("*.md")):
        fm = frontmatter(p)
        if fm.get("type") != "metamodel" or fm.get("construct") != construct:
            fail(f"{p.relative_to(ROOT)}: expected type: metamodel, construct: {construct}")
            continue
        fm["_path"] = p
        out[str(fm.get("name"))] = fm
    return out


def main() -> int:
    meta = frontmatter(MM / "meta-metamodel.md")
    universal = [f["name"] for f in meta.get("universal_fields", [])]
    kinds = set(meta.get("field_kinds", []))
    lifecycles = meta.get("lifecycles", {})

    types = load("type", "types")
    relations = load("relation", "relations")
    frameworks = load("framework", "frameworks")
    projections = load("projection", "projections")
    rules = load("rule", "rules")
    anchors = anchor_names()
    blocks: dict[str, tuple[str, dict]] = {}
    for fw_name, fw in frameworks.items():
        for b in fw.get("blocks", []):
            if b["id"] in blocks:
                fail(f"block {b['id']} is declared by both {blocks[b['id']][0]} and {fw_name}")
            blocks[b["id"]] = (fw_name, b)

    # --- types -------------------------------------------------------------
    for name, t in types.items():
        where = t["_path"].relative_to(ROOT)
        tpl = ROOT / str(t.get("template", ""))
        if not tpl.is_file():
            fail(f"{where}: template {t.get('template')} missing")
            continue
        tfm = _FM.match(tpl.read_text(encoding="utf-8"))
        if not tfm:
            fail(f"{where}: template {t.get('template')} has no frontmatter")
            continue
        tfm_text = tfm.group(1)
        if not re.search(rf"^id:\s*{re.escape(str(t.get('prefix')))}-NNN", tfm_text, re.M):
            fail(f"{where}: template id prefix is not {t.get('prefix')}-NNN")
        if not re.search(rf"^type:\s*{re.escape(name)}\s*$", tfm_text, re.M):
            fail(f"{where}: template `type:` is not {name}")
        declared = [f["name"] for f in t.get("fields", [])]
        expected = set(declared) | (set(universal) if t.get("universal", True) else set())
        actual = template_keys(tpl)
        if expected != actual:
            fail(f"{where}: fields differ from template — only in metamodel: "
                 f"{sorted(expected - actual)}; only in template: {sorted(actual - expected)}")
        for f in t.get("fields", []):
            if f.get("kind") not in kinds:
                fail(f"{where}: field {f.get('name')} has unknown kind {f.get('kind')}")
            if f.get("kind") in ("link", "link-list") and not f.get("relation"):
                fail(f"{where}: link field {f.get('name')} names no relation")
            rel = f.get("relation")
            if rel:
                if rel not in relations:
                    fail(f"{where}: field {f['name']} names unknown relation {rel}")
                elif not any(e.get("from") in (name, "any") for e in relations[rel].get("edges", [])):
                    fail(f"{where}: relation {rel} has no edge from {name}")
        folder = ROOT / str(t.get("folder", ""))
        if not folder.is_dir():
            fail(f"{where}: folder {t.get('folder')} does not exist")
        if t.get("lifecycle") not in lifecycles:
            fail(f"{where}: unknown lifecycle {t.get('lifecycle')}")
        if t.get("block") is not None and t["block"] not in blocks:
            fail(f"{where}: block {t['block']} declared by no framework")
        for a in t.get("anchors", []):
            if a not in anchors:
                fail(f"{where}: anchor {a} not in _system/anchors/")
        for pr in t.get("projections", []):
            if pr not in projections:
                fail(f"{where}: projection {pr} has no page")
        for so in t.get("sort_orders") or []:
            label = so.get("label") if isinstance(so, dict) else None
            keys = so.get("keys") if isinstance(so, dict) else None
            if not label or not keys:
                fail(f"{where}: sort order {so!r} needs a label and keys")
                continue
            for k in keys:
                if k not in expected:
                    fail(f"{where}: sort order '{label}' names {k}, "
                         f"which is neither a field of {name} nor universal")
    claimed = {(ROOT / str(t.get("template", ""))).resolve() for t in types.values()}
    for tpl in sorted(TEMPLATES.glob("*.md")):
        if tpl.resolve() not in claimed:
            fail(f"_templates/{tpl.name} has no type page in _system/metamodel/types/")

    # --- relations ---------------------------------------------------------
    for name, r in relations.items():
        where = r["_path"].relative_to(ROOT)
        if r.get("direction") not in ("directed", "symmetric"):
            fail(f"{where}: direction must be directed | symmetric")
        for e in r.get("edges", []):
            for end in ("from", "to"):
                if e.get(end) != "any" and e.get(end) not in types:
                    fail(f"{where}: edge {end} {e.get(end)} is not a type")
            src = e.get("from")
            if src != "any":
                fields = [f["name"] for f in types[src].get("fields", [])] if src in types else []
                if r["field"] not in fields and r["field"] not in universal:
                    fail(f"{where}: type {src} declares no field {r['field']}")

    # --- frameworks vs wiki folders vs dashboard catalog -------------------
    folder_owner: dict[str, str] = {}
    for fw_name, fw in frameworks.items():
        where = fw["_path"].relative_to(ROOT)
        for b in fw.get("blocks", []):
            for tn in b.get("types", []):
                if tn not in types:
                    fail(f"{where}: block {b['id']} lists unknown type {tn}")
                    continue
                folder = Path(types[tn]["folder"]).name
                if folder in folder_owner:
                    fail(f"{where}: folder {folder} is in {folder_owner[folder]} and {b['id']}")
                folder_owner[folder] = b["id"]
    wiki = ROOT / "wiki"
    for d in sorted(wiki.iterdir()) if wiki.is_dir() else []:
        if d.is_dir() and d.name not in folder_owner:
            fail(f"wiki/{d.name}/ belongs to no framework block")
    try:
        sys.path.insert(0, str(ROOT / "_system" / "apps" / "dashboard"))
        import catalog  # type: ignore
        cat = {s["id"]: s for s in catalog.SECTIONS}
        for bid, (fw_name, b) in blocks.items():
            s = cat.get(bid)
            if not s:
                fail(f"dashboard catalog has no section {bid}")
                continue
            if s["title"] != b["title"]:
                fail(f"{bid}: title '{b['title']}' (metamodel) vs '{s['title']}' (catalog)")
            want = sorted(Path(types[tn]["folder"]).name for tn in b.get("types", []) if tn in types)
            if sorted(s["folders"]) != want:
                fail(f"{bid}: folders {want} (metamodel) vs {sorted(s['folders'])} (catalog)")
            if s["scope"] != b.get("scope"):
                fail(f"{bid}: scope {b.get('scope')} (metamodel) vs {s['scope']} (catalog)")
        for sid in cat:
            if sid not in blocks:
                fail(f"catalog section {sid} is declared by no framework")
    except ImportError:
        fail("could not import the dashboard catalog (_system/apps/dashboard/catalog.py)")

    # --- projections -------------------------------------------------------
    for name, pr in projections.items():
        where = pr["_path"].relative_to(ROOT)
        if pr.get("stored") is not False:
            fail(f"{where}: a projection is never stored")
        for d in str(pr.get("decision") or "").split(","):
            if re.fullmatch(r"DR-\d{3}", d.strip()):
                fail(f"{where}: decision {d.strip()} is a bare ID; name the full stem (DR-NNN-slug)")
        for rd in pr.get("reads", []):
            tn = rd.get("type")
            if tn not in types:
                fail(f"{where}: reads unknown type {tn}")
                continue
            have = {f["name"] for f in types[tn].get("fields", [])} | set(universal)
            for fld in rd.get("fields", []):
                if fld not in have:
                    fail(f"{where}: reads {tn}.{fld}, which is not declared")

    # --- altitude & rules --------------------------------------------------
    # optional, like in the dashboard's reader (metamodel.py)
    alt = frontmatter(MM / "altitude.md") if (MM / "altitude.md").is_file() else {}
    for a in alt.get("assignments", []):
        tn = a.get("type")
        if tn not in types:
            fail(f"altitude.md: unknown type {tn}")
        elif a.get("stereotype") and a["stereotype"] not in types[tn].get("stereotypes", []):
            fail(f"altitude.md: {tn} has no stereotype {a['stereotype']}")
        if a.get("rung") not in alt.get("rungs", []) and a.get("status") != "open":
            fail(f"altitude.md: {tn} assigned to unknown rung {a.get('rung')}")
    for name, ru in rules.items():
        where = ru["_path"].relative_to(ROOT)
        tn = (ru.get("applies_to") or {}).get("type")
        if tn not in types and tn != "any":
            fail(f"{where}: applies_to unknown type {tn}")
        if ru.get("action") not in ("auto-fix", "ask", "issue"):
            fail(f"{where}: action must be auto-fix | ask | issue")

    if findings:
        print(f"metamodel-lint: {len(findings)} finding(s)")
        for f in findings:
            print("  -", f)
        return 1
    print(f"metamodel-lint: OK — {len(types)} types, {len(relations)} relations, "
          f"{len(blocks)} blocks, {len(projections)} projections, {len(rules)} rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
