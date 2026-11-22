#!/usr/bin/env python3
"""Lint `_system/metamodel/` against the files that must agree with it.

The metamodel is the single statement of the schema (DR-035); templates,
wiki folders and anchors are its consumers. Nothing
raises when they drift, so this script diffs them:

  * every template has a type page; every `type` page: template exists, its `id:` prefix and `type:` value
    match, its frontmatter keys equal universal + declared fields (exactly;
    an `optional` universal field may be left out),
    the wiki folder exists, its block is declared by some framework, its
    anchors exist, its projections exist, every link field names a relation
    whose edges allow this type as `from`;
  * every `relation`: `from` / `to` types exist (or `any`), and every `from`
    type declares a field for it;
  * every `framework`: block types exist, every wiki folder sits in exactly
    one block;
  * every `projection`: the types and fields it reads exist;
  * notation definitions: `extends` names a type; levels, extra fields,
    relations, level-scoped anchors and `<!-- levels: … -->` body markers agree;
    `default_notation` in wiki.yaml names one of them;
  * functional-requirement pages: a known notation, one of its levels, only
    declared fields, required fields present and not empty.

Run from the repo root:  python3 _system/scripts/metamodel-lint.py
Exit status 1 on any finding. Requires PyYAML.
"""
from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("metamodel-lint needs PyYAML:  pip install pyyaml")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fr_hierarchy  # noqa: E402

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


def load_notations() -> dict[str, dict]:
    """Built-in notation definitions plus project-specific notation pages."""
    out: dict[str, dict] = {}
    for directory in (MM / "notations", ROOT / "_system" / "notations"):
        for p in sorted(directory.glob("*.md")) if directory.is_dir() else []:
            if p.name == "README.md":
                continue
            fm = frontmatter(p)
            if fm.get("type") != "metamodel" or fm.get("construct") != "notation":
                fail(f"{p.relative_to(ROOT)}: expected type: metamodel, construct: notation")
                continue
            name = str(fm.get("name") or "")
            if not name:
                fail(f"{p.relative_to(ROOT)}: notation has no name")
                continue
            if name in out:
                fail(f"{p.relative_to(ROOT)}: duplicate notation name {name}")
                continue
            fm["_path"] = p
            out[name] = fm
    return out


_LEVEL_MARK = re.compile(r"^<!--\s*levels:\s*(.*?)\s*-->\s*$", re.M)


def empty(value: object) -> bool:
    return value is None or (isinstance(value, (str, list, dict)) and not value)


def lint_domain_terms(spec: dict, universal: list[str]) -> None:
    folder = ROOT / spec["folder"]
    pages = {path.stem: frontmatter(path) for path in sorted(folder.glob("*.md"))}
    allowed = set(universal) | {field["name"] for field in spec["fields"]}
    stereotypes = spec.get("stereotypes", [])
    ids = set()
    def resolve(reference):
        match = re.fullmatch(r"\[\[([^\]#|]+)(?:[|#][^\]]*)?\]\]", str(reference))
        return pages.get(match[1].rsplit("/", 1)[-1]) if match else None

    for stem, data in pages.items():
        where = folder.relative_to(ROOT) / f"{stem}.md"
        term_id = str(data.get("id") or "")
        if not re.fullmatch(rf"{re.escape(spec['prefix'])}-\d{{3,}}", term_id) or not stem.startswith(f"{term_id}-"):
            fail(f"{where}: ID and filename must use the {spec['prefix']}- prefix")
        if term_id in ids:
            fail(f"{where}: duplicate ID {term_id}")
        ids.add(term_id)
        if data.get("type") != spec["name"]:
            fail(f"{where}: type must be {spec['name']}")
        for key in sorted(set(data) - allowed):
            fail(f"{where}: field {key} is not declared by domain-term")
        kind = data.get("stereotype")
        if kind and kind not in stereotypes:
            fail(f"{where}: unknown stereotype {kind}")
        if not kind and any(data.get(key) for key in ("attributes", "relationships", "parent", "source-of-truth")):
            fail(f"{where}: structured fields require a stereotype")
        if kind != "entity" and data.get("source-of-truth"):
            fail(f"{where}: source-of-truth belongs on an entity")

        parents = data.get("parent")
        if parents is not None:
            if not isinstance(parents, list) or len(parents) > 1:
                fail(f"{where}: parent must list at most one sum type")
            else:
                for parent in parents:
                    target = resolve(parent)
                    if target is data or not target or target.get("stereotype") != "sum-type":
                        fail(f"{where}: parent must resolve to another domain term with stereotype sum-type")

        for key, entry_keys in (
            ("attributes", {"name", "type", "multiplicity", "identifier"}),
            ("relationships", {"to", "label", "kind", "multiplicity"}),
        ):
            entries = data.get(key)
            if entries is None:
                continue
            if not isinstance(entries, list):
                fail(f"{where}: {key} must be a list")
                continue
            for entry in entries:
                if not isinstance(entry, dict) or set(entry) - entry_keys:
                    fail(f"{where}: invalid {key} entry")
                    continue
                if key == "attributes":
                    if not isinstance(entry.get("name"), str) or not entry["name"].strip():
                        fail(f"{where}: each attribute needs a name")
                    if "identifier" in entry and not isinstance(entry["identifier"], bool):
                        fail(f"{where}: identifier must be a boolean")
                    if entry.get("identifier") is True and kind != "entity":
                        fail(f"{where}: only entities can have identifier attributes")
                    continue
                target = resolve(entry.get("to", ""))
                if not target or target.get("stereotype") not in stereotypes:
                    fail(f"{where}: relationship target must resolve to a structured domain term")
                relation_kind = entry.get("kind")
                if relation_kind not in ("association", "aggregation", "composition", "generalization"):
                    fail(f"{where}: unknown relationship kind {relation_kind}")
                if relation_kind == "generalization" and target is data:
                    fail(f"{where}: a term cannot generalize itself")
                if relation_kind == "generalization" and "multiplicity" in entry:
                    fail(f"{where}: generalization does not carry multiplicity")


def main() -> int:
    meta = frontmatter(MM / "meta-metamodel.md")
    universal = [f["name"] for f in meta.get("universal_fields", [])]
    # An optional universal field may sit on any page but need not be in a template.
    optional_universal = {f["name"] for f in meta.get("universal_fields", []) if f.get("optional")}
    kinds = set(meta.get("field_kinds", []))
    lifecycles = meta.get("lifecycles", {})

    types = load("type", "types")
    relations = load("relation", "relations")
    frameworks = load("framework", "frameworks")
    projections = load("projection", "projections")
    rules = load("rule", "rules")
    notations = load_notations()
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
        if t.get("universal", True):
            expected -= optional_universal - actual
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
                if src == "functional-requirement":
                    fields += [str(f.get("name")) for n in notations.values()
                               for f in (n.get("fields") or []) if isinstance(f, dict)]
                if r["field"] not in fields and r["field"] not in universal:
                    fail(f"{where}: type {src} declares no field {r['field']}")

    # --- frameworks vs wiki folders ---------------------------------------
    folder_owner: dict[str, str] = {}
    for fw_name, fw in frameworks.items():
        where = fw["_path"].relative_to(ROOT)
        for b in fw.get("blocks", []):
            for projection in b.get("projections", []):
                if projection not in projections:
                    fail(f"{where}: block {b['id']} lists unknown projection {projection}")
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

    # --- notations & rules -------------------------------------------------
    fr_type = types.get("functional-requirement")
    if not fr_type:
        fail("no functional-requirement type for notation definitions")
        fr_type = {}
    fr_fields = {f["name"]: f for f in fr_type.get("fields", [])}
    for name, notation in notations.items():
        where = notation["_path"].relative_to(ROOT)
        if notation.get("extends") not in types:
            fail(f"{where}: extends names no type ({notation.get('extends')})")
        levels = notation.get("levels") or []
        if not levels or not all(isinstance(level, str) and level for level in levels):
            fail(f"{where}: levels must be a non-empty list of names")
        for anchor in notation.get("anchors") or []:
            scoped = anchor if isinstance(anchor, dict) else {"name": anchor}
            if str(scoped.get("name")) not in anchors:
                fail(f"{where}: anchor {scoped.get('name')} not in _system/anchors/")
            for level in scoped.get("levels") or []:
                if level not in levels:
                    fail(f"{where}: anchor {scoped.get('name')} names unknown level {level}")
        marks = _LEVEL_MARK.findall(notation["_path"].read_text(encoding="utf-8"))
        if not marks:
            fail(f"{where}: body has no <!-- levels: … --> markers")
        for mark in marks:
            for level in (x.strip() for x in mark.split(",") if x.strip()):
                if level not in levels:
                    fail(f"{where}: body marker names unknown level {level}")
        seen_fields: set[str] = set()
        for field in notation.get("fields") or []:
            if not isinstance(field, dict) or not field.get("name"):
                fail(f"{where}: each notation field needs a name")
                continue
            field_name = str(field["name"])
            if field_name in seen_fields:
                fail(f"{where}: duplicate field {field_name}")
            seen_fields.add(field_name)
            if field_name in fr_fields or field_name in universal:
                fail(f"{where}: field {field_name} is already declared by functional-requirement")
            if field.get("kind") not in kinds:
                fail(f"{where}: field {field_name} has unknown kind {field.get('kind')}")
            rel = field.get("relation")
            if rel:
                if rel not in relations:
                    fail(f"{where}: field {field_name} names unknown relation {rel}")
                elif not any(e.get("from") in ("functional-requirement", "any")
                             for e in relations[rel].get("edges", [])):
                    fail(f"{where}: relation {rel} has no edge from functional-requirement")
                if field.get("kind") not in ("link", "link-list"):
                    fail(f"{where}: relation field {field_name} must use link or link-list")
        for level in notation.get("implementable_levels", []):
            if level not in levels:
                fail(f"{where}: implementable level {level} is not in levels")
        for dstate in notation.get("delivery_states") or []:
            if dstate not in (fr_fields.get("delivery", {}).get("values") or []):
                fail(f"{where}: delivery state {dstate} is not a functional-requirement delivery value")
    wiki_yaml = ROOT / "_system" / "wiki.yaml"
    try:
        cfg = yaml.safe_load(wiki_yaml.read_text(encoding="utf-8")) if wiki_yaml.is_file() else {}
    except yaml.YAMLError:
        cfg = {}
    default = str((cfg or {}).get("default_notation") or "").strip()
    if default and default not in notations:
        fail(f"_system/wiki.yaml: default_notation {default} is not a notation")

    if "domain-term" in types:
        lint_domain_terms(types["domain-term"], universal)

    # --- functional-requirement instances -------------------------------
    fr_dir = ROOT / str(fr_type.get("folder") or "wiki/functional-requirements")
    common = set(universal) | set(fr_fields)
    fr_pages: dict[str, dict] = {}
    for page in sorted(fr_dir.glob("*.md")) if fr_dir.is_dir() else []:
        where = page.relative_to(ROOT)
        data = frontmatter(page)
        fr_pages[page.stem] = data
        notation_name = str(data.get("notation") or "")
        notation = notations.get(notation_name)
        if not notation:
            fail(f"{where}: notation {notation_name or '(missing)'} is not a notation")
            continue
        level = str(data.get("level") or "")
        if level not in (notation.get("levels") or []):
            fail(f"{where}: level {level or '(missing)'} is not in notation {notation_name}")
        extra = [f for f in notation.get("fields") or [] if isinstance(f, dict)]
        allowed = common | {str(f.get("name")) for f in extra}
        for key in sorted(set(data) - allowed):
            fail(f"{where}: field {key} is not declared by functional-requirement or notation {notation_name}")
        for field in list(fr_fields.values()) + extra:
            if field.get("required") and empty(data.get(field["name"])):
                fail(f"{where}: required field {field['name']} is missing or empty")
        state = data.get("delivery")
        checked = data.get("delivery-checked")
        if state is not None:
            if state not in (fr_fields.get("delivery", {}).get("values") or []):
                fail(f"{where}: invalid delivery state {state}")
            elif state not in (notation.get("delivery_states")
                               or fr_fields.get("delivery", {}).get("values") or []):
                fail(f"{where}: delivery {state} is not allowed in notation {notation_name}")
            if level not in (notation.get("implementable_levels") or []):
                fail(f"{where}: delivery is not allowed at {notation_name} level {level}")
            if checked is None:
                fail(f"{where}: delivery requires delivery-checked")
        elif checked is not None:
            fail(f"{where}: delivery-checked without delivery")
        if checked is not None:
            # YAML turns these into date/datetime objects; str() gives ISO back.
            # A date alone, or a time without a zone, cannot order same-day checks.
            try:
                stamp = datetime.fromisoformat(str(checked).replace("Z", "+00:00"))
            except ValueError:
                stamp = None
            if stamp is None or stamp.tzinfo is None:  # a bare date parses as naive midnight
                fail(f"{where}: delivery-checked must be an ISO 8601 timestamp with time and timezone")
    # A use case refined by Agile features or stories (DR-038 amendment) is
    # `implemented` only when every refining story is (FR-031).
    children = fr_hierarchy.agile_children(fr_pages)
    for stem, d in fr_pages.items():
        if str(d.get("notation") or "") != "use-case" or d.get("delivery") != "implemented":
            continue
        stories, no_stories = fr_hierarchy.refining_stories(stem, fr_pages, children)
        for kid in no_stories:
            fail(f"wiki/functional-requirements/{stem}.md: delivery implemented, but refining {kid} has no stories")
        for st in stories:
            if fr_pages[st].get("delivery") != "implemented":
                fail(f"wiki/functional-requirements/{stem}.md: delivery implemented, but refining story "
                     f"{st} is {fr_pages[st].get('delivery') or 'without delivery'}; the use case is at most partial")

    for name, ru in rules.items():
        where = ru["_path"].relative_to(ROOT)
        tn = (ru.get("applies_to") or {}).get("type")
        if tn not in types and tn != "any":
            fail(f"{where}: applies_to unknown type {tn}")
        ap = ru.get("applies_to") or {}
        if ap.get("notation"):
            if ap["notation"] not in notations:
                fail(f"{where}: applies_to unknown notation {ap['notation']}")
            else:
                lv = ap.get("level") or []
                for level in lv if isinstance(lv, list) else [lv]:
                    if level not in notations[ap["notation"]].get("levels", []):
                        fail(f"{where}: applies_to unknown level {level} of {ap['notation']}")
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
