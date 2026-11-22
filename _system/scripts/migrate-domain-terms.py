#!/usr/bin/env python3
"""Move legacy glossary and data-model pages into one domain-term folder."""

import argparse
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from tempfile import NamedTemporaryFile
import hashlib
import json
import os
import re
import stat
import sys


OLD = {"glossary": "glossary-term", "data-models": "data-model"}
FRONT = re.compile(r"\A---\s*\n(.*?)\n---(?:\n|\Z)", re.DOTALL)
ID = re.compile(r"^(?:GLO|DM|DT)-(\d+)\b")
LINK = re.compile(r"\[\[([^\]|#]+)([^\]]*)\]\]")
PENDING = ".domain-terms-migration.json"
ATTRIBUTE = re.compile(r"^\s*-\s+`([^\x60]+)`\s*(?::\s*(.*))?$")


@dataclass
class Page:
    path: Path
    meta: dict
    body: str

    @property
    def id(self):
        return self.meta["id"]


def front(text):
    match = FRONT.match(text)
    return (match[1], text[match.end():]) if match else ("", text)


def legacy_pages(root):
    for path in sorted((root / "wiki").glob("*/*.md")):
        fm, _ = front(path.read_text(encoding="utf-8"))
        if path.parent.name in OLD or re.search(
            r"""^type:\s*['"]?(?:glossary-term|data-model)['"]?\s*(?:#.*)?$""", fm, re.M
        ):
            yield path


def read_page(path, yaml):
    fm, body = front(path.read_text(encoding="utf-8"))
    meta = yaml.safe_load(fm)
    if not isinstance(meta, dict) or not ID.fullmatch(str(meta.get("id", ""))):
        raise ValueError(f"{path}: expected a legacy or DT page ID")
    return Page(path, meta, body)


def values(meta, key):
    value = meta.get(key)
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def stem(link):
    return str(link).strip("[]").split("|")[0].split("#")[0].rsplit("/", 1)[-1]


def same_name(term, model):
    title = term.meta.get("title")
    other_title = model.meta.get("title")
    return (bool(title and other_title and str(title).casefold() == str(other_title).casefold())
            or term.path.stem.split("-", 2)[-1] == model.path.stem.split("-", 2)[-1])


def pair_terms(glossary, models):
    pairs = {}
    for model in models:
        links = {stem(link) for link in values(model.meta, "related")}
        candidates = [term for term in glossary if {term.id, term.path.stem} & links]
        if len(candidates) > 1:
            candidates = [term for term in candidates if same_name(term, model)] or candidates
        if not candidates:
            candidates = [
                term for term in glossary
                if term.meta.get("bounded-context") == model.meta.get("bounded-context")
                and same_name(term, model)
            ]
        if len(candidates) > 1 or any(term.path in pairs for term in candidates):
            raise ValueError(f"{model.path}: ambiguous GLO/DM pair; resolve it before migrating")
        if candidates:
            pairs[candidates[0].path] = model
    return pairs


def model_fields(page):
    meta = dict(page.meta)
    if meta.get("source-of-truth") and meta.get("stereotype") != "entity":
        raise ValueError(f"{page.path}: source-of-truth {meta['source-of-truth']!r} belongs on an entity; "
                         "review the stereotype or preserve the information in prose before migration")
    body = page.body
    if any(len(re.findall(rf"^\*\*{section}\.\*\*", body, re.M)) > 1
           for section in ("Identity", "Attributes")):
        raise ValueError(f"{page.path}: several model sections; split the entities before migrating")
    attributes = []
    block = re.search(r"^\*\*Attributes\.\*\*\s*\n(.*?)(?=^\*\*|^#|^>|\Z)",
                      body, re.M | re.S)
    for line in (block[1].splitlines() if block else []):
        if not line.lstrip().startswith("-"):
            continue
        match = ATTRIBUTE.fullmatch(line)
        if not match:
            print(f"Review unparsed attribute in {page.path.name}: {line.strip()}")
            continue
        name, details = match.groups()
        type_name = re.split(r"\s+[—–]\s+|\s+-\s+", details or "", maxsplit=1)[0]
        modality = re.search(r"\s+(mandatory|optional)\??\s*$", type_name, re.I)
        attr = {"name": name}
        if modality:
            attr["multiplicity"] = "1" if modality[1].lower() == "mandatory" else "0..1"
            type_name = type_name[:modality.start()]
        if type_name.strip():
            attr["type"] = type_name.strip()
        attributes.append(attr)
    if attributes and not meta.get("attributes"):
        meta["attributes"] = attributes
    relationships = []
    for old in values(meta, "relationships"):
        if not isinstance(old, dict) or not (old.get("to") or old.get("target")):
            raise ValueError(f"{page.path}: invalid relationship {old!r}")
        entry = {key: value for key, value in old.items()
                 if key not in {"verb", "target", "cardinality", "mandatory"}}
        entry["to"] = old.get("to") or old["target"]
        entry["kind"] = str(old.get("kind") or "association").replace("inheritance", "generalization")
        if old.get("verb") and "label" not in entry:
            entry["label"] = old["verb"]
        if entry["kind"] == "generalization":
            entry.pop("multiplicity", None)
        elif "multiplicity" not in entry:
            if old.get("cardinality") is not None:
                entry["multiplicity"] = str(old["cardinality"])
            elif isinstance(old.get("mandatory"), bool):
                entry["multiplicity"] = "1" if old["mandatory"] else "0..1"
        relationships.append(entry)
    if relationships:
        meta["relationships"] = relationships
    return meta


def merged(term, model):
    meta = dict(term.meta)
    body = term.body
    if model:
        contexts = {page.meta.get("bounded-context") for page in (term, model)} - {None, ""}
        if len(contexts) > 1:
            raise ValueError(f"{term.path} and {model.path}: different bounded contexts; review the pair")
        structure = model_fields(model)
        if contexts:
            meta["bounded-context"] = next(iter(contexts))
        if meta.get("stereotype") and meta["stereotype"] != structure.get("stereotype"):
            raise ValueError(f"{term.path} and {model.path}: conflicting stereotypes; resolve before migrating")
        for key in ("stereotype", "parent", "source-of-truth", "attributes", "relationships"):
            if key in structure:
                meta[key] = structure[key]
        for key in ("sources", "tags", "aliases", "related"):
            meta[key] = list(dict.fromkeys(values(meta, key) + values(structure, key)))
        meta["related"] = [link for link in meta["related"]
                           if stem(link) not in {term.id, term.path.stem, model.id, model.path.stem}]
        model_title = model.meta.get("title")
        if model_title and not meta.get("title"):
            meta["title"] = model_title
        elif model_title and model_title != meta.get("title"):
            meta["aliases"].append(model_title)
        dates = [str(value) for value in (meta.get("created"), structure.get("created")) if value]
        if dates:
            meta["created"] = min(dates)
        meta["updated"] = date.today().isoformat()
        if "accepted" in (meta.get("status"), structure.get("status")):
            meta["status"] = "review"
        extra = re.sub(r"^\s*# .+\n", "", model.body, count=1).strip()
        body = f"{body.rstrip()}\n\n<!-- Review prose merged from {model.id}. -->\n\n{extra}\n"
    elif term.meta.get("type") == "data-model" or term.path.parent.name == "data-models":
        meta = model_fields(term)
        if "**Definition.**" not in body:
            print(f"Review definition for {term.id}; its original purpose was retained")
    return meta, body


def rewrite_provenance(text, rewrite, yaml):
    """Edit only scalar entries of ingested-pages, keeping comments and other fields verbatim."""
    fm = FRONT.match(text)
    if not fm or "ingested-pages" not in fm[1]:
        return text
    mapping = yaml.compose(fm[1])
    if not isinstance(mapping, yaml.MappingNode):
        return text
    for key, value in mapping.value:
        if key.value != "ingested-pages":
            continue
        entries = value.value if isinstance(value, yaml.SequenceNode) else [value]
        # An alias node points back to the anchor's source position. Never
        # patch another field, or patch the same scalar twice for repeated aliases.
        for start, end in sorted({(e.start_mark.index, e.end_mark.index) for e in entries
                                  if isinstance(e, yaml.ScalarNode)}, reverse=True):
            raw = fm[1][start:end]
            revised = rewrite(raw)
            if revised != raw:
                if start < key.end_mark.index:
                    raise ValueError("ingested-pages references an earlier YAML anchor; "
                                     "expand that alias before migration")
                offset = fm.start(1)
                text = text[:offset + start] + revised + text[offset + end:]
        break
    return text


def index_target(row):
    wiki = LINK.match(row, 2)
    if wiki:
        return wiki[1].rsplit("/", 1)[-1]
    markdown = re.match(r"^- \[.*?\]\(([^)#]+)\.md(?:#[^)]*)?\)", row)
    return markdown[1].rsplit("/", 1)[-1] if markdown else None


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def replace_file(path, content, mode):
    """Publish a complete file in one rename, preserving access permissions."""
    if path.exists() and not os.access(path, os.W_OK):
        raise PermissionError(f"{path} is read-only")
    with NamedTemporaryFile(dir=path.parent, delete=False) as temp:
        staged = Path(temp.name)
        try:
            temp.write(content)
            temp.flush()
            staged.chmod(stat.S_IMODE(path.stat().st_mode) if path.exists() else mode)
            temp.close()
            staged.replace(path)
        finally:
            staged.unlink(missing_ok=True)


def apply_plan(root, plan, dry_run=False):
    # A retry replays the original allocations, even if only part of a GLO/DM
    # pair remains on disk. Refuse to overwrite edits made since planning.
    for relative, before, content, mode in plan:
        path = root / relative
        wiki_page = path.parent.parent == root / "wiki" and path.suffix == ".md"
        source = path.parent == root / "raw/sources" and path.suffix == ".md"
        if (path.resolve() != path or not (wiki_page or source or path == root / "_system/index.md")
                or (content is None and not wiki_page)):
            raise ValueError(f"invalid migration path: {relative}")
        current = file_hash(path)
        data = None if content is None else content.encode("utf-8")
        after = None if data is None else hashlib.sha256(data).hexdigest()
        if current == after:
            continue
        if current != before:
            raise ValueError(f"{path} changed since migration was planned; review before retrying")
        if dry_run:
            print(f"Pending {'remove' if data is None else 'write'} {relative}")
        elif data is None:
            path.unlink()
        else:
            replace_file(path, data, mode)


def finish(root, plan):
    folder = root / "wiki/domain-terms"
    folder.mkdir(exist_ok=True)
    (folder / ".gitkeep").touch()
    apply_plan(root, plan)
    for old in OLD:
        directory = root / "wiki" / old
        if directory.is_dir() and all(p.name == ".gitkeep" for p in directory.iterdir()):
            (directory / ".gitkeep").unlink(missing_ok=True)
            directory.rmdir()
    (root / PENDING).unlink()


def migrate(root, paths, dry_run, yaml):
    folder = root / "wiki/domain-terms"
    pages = [read_page(path, yaml) for path in paths]
    glossary = [page for page in pages if page.meta.get("type") == "glossary-term"
                or page.path.parent.name == "glossary"]
    models = [page for page in pages if page.path not in {term.path for term in glossary}]
    pairs = pair_terms(glossary, models)
    secondaries = {model.path for model in pairs.values()}
    used = {int(m[1]) for path in folder.glob("DT-*.md") if (m := ID.match(path.stem))}
    next_id = max(used | {int(ID.fullmatch(page.id)[1]) for page in pages}, default=0) + 1
    stems = {}
    id_stems = {}
    ids = {}
    writes = {}
    new_modes = {}

    for page in glossary + models:
        if page.path in secondaries:
            continue
        model = pairs.get(page.path)
        meta, body = merged(page, model)
        number = int(ID.fullmatch(page.id)[1])
        if number in used:
            number = next_id
            next_id += 1
        used.add(number)
        new_id = f"DT-{number:03d}"
        suffix = page.path.stem[len(page.id):] if page.path.stem.startswith(page.id) else ""
        if not suffix.startswith("-"):
            raise ValueError(f"{page.path}: filename must start with {page.id}-")
        dest = folder / f"{new_id}{suffix}.md"
        aliases = values(meta, "aliases")
        for original in (page, model) if model else (page,):
            if original.path.stem in stems or original.id in ids:
                raise ValueError(f"{original.path}: duplicate legacy ID or stem")
            stems[original.path.stem] = dest.stem
            ids[original.id] = new_id
            id_stems[original.id] = dest.stem
            aliases = [*aliases, original.id, original.path.stem]
            print(f"{'Merge' if original is model else 'Move'} {original.path.relative_to(root)} → {dest.relative_to(root)}")
        meta["id"] = new_id
        meta["type"] = "domain-term"
        meta["aliases"] = list(dict.fromkeys(aliases))
        meta["tags"] = list(dict.fromkeys(
            ["domain-term"] + [tag for tag in values(meta, "tags") if tag not in OLD.values() and tag != "glossary"]
        ))
        new_modes[dest] = stat.S_IMODE(page.path.stat().st_mode)
        writes[dest] = f"---\n{yaml.safe_dump(meta, sort_keys=False, allow_unicode=True)}---\n{body}"

    def rewrite(text):
        def wikilink(match):
            target, tail = match.groups()
            old_stem = target.rsplit("/", 1)[-1]
            new = stems.get(old_stem, id_stems.get(old_stem))
            if not new:
                return match[0]
            if "/" in target:
                prefix = target.rsplit("/", 1)[0]
                new_folder = prefix.rsplit("/", 1)[0] + "/domain-terms" if "/" in prefix else "domain-terms"
                new = f"{new_folder}/{new}"
            return f"[[{new}{tail}]]"
        text = LINK.sub(wikilink, text)
        pattern = r"(?<=\()((?:\.\.?/)*(?:wiki/)?)(?:glossary|data-models)/([^)/#\s]+)\.md"
        return re.sub(pattern, lambda m: f"{m[1]}domain-terms/{stems[m[2]]}.md"
                      if m[2] in stems else m[0], text)

    def update(path, new, old):
        if new != old:
            writes[path] = new
            print(f"Rewrite {path.relative_to(root)}")

    writes = {path: rewrite(text) for path, text in writes.items()}
    for path in sorted((root / "wiki").glob("*/*.md")):
        if path not in paths:
            old = path.read_text(encoding="utf-8")
            update(path, rewrite(old), old)
    for path in sorted((root / "raw/sources").glob("*.md")):
        old = path.read_text(encoding="utf-8")
        if paths:
            try:
                update(path, rewrite_provenance(old, rewrite, yaml), old)
            except (ValueError, yaml.YAMLError) as exc:
                raise ValueError(f"{path}: {exc}") from exc
    index = root / "_system/index.md"
    if index.is_file():
        old = index.read_text(encoding="utf-8")
        parts = re.split(r"(?=^## )", old, flags=re.M)
        domain = {}
        for part in parts:
            if part.startswith(("## Glossary\n", "## Data models\n", "## Domain terms\n")):
                for row in part.splitlines()[1:]:
                    if not row.startswith("- ["):
                        continue
                    key = index_target(row)
                    target = stems.get(key) or id_stems.get(key) or key or row
                    label = row.split("]", 1)[0][3:]
                    row = row.replace(f"[{label}]", f"[{ids.get(label, label)}]", 1)
                    # Prefer the surviving term's description regardless of section order.
                    if part.startswith("## Data models\n"):
                        domain.setdefault(target, row)
                    else:
                        domain[target] = row
        sections = [part for part in parts if not part.startswith(("## Glossary\n", "## Data models\n", "## Domain terms\n"))]
        sections.insert(1, "## Domain terms\n\n" + "\n".join(domain.values()) + "\n\n")
        update(index, rewrite("".join(sections)), old)
    if dry_run:
        return
    operations = {**writes, **dict.fromkeys(paths)}
    plan = [(str(path.relative_to(root)), file_hash(path), content, new_modes.get(path, 0o600))
            for path, content in operations.items()]
    # Persist all assignments and intended bytes before changing any wiki file.
    # Publish without clobbering a pending plan from another invocation.
    with NamedTemporaryFile(dir=root, mode="w", encoding="utf-8", delete=False) as temp:
        staged = Path(temp.name)
        try:
            json.dump(plan, temp, ensure_ascii=False)
            temp.flush()
            os.link(staged, root / PENDING)
        finally:
            staged.unlink(missing_ok=True)
    finish(root, plan)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_dir", type=Path)
    options = parser.add_mutually_exclusive_group()
    options.add_argument("--check", action="store_true")
    options.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.project_dir.resolve()
    if not (root / "wiki").is_dir():
        parser.error(f"{root} has no wiki directory")
    if os.name == "posix":
        # Lock the project directory itself: no stale lock file after a crash.
        # This also serializes sync checks with an in-progress migration.
        import fcntl
        directory = os.open(root, os.O_RDONLY)
        try:
            fcntl.flock(directory, fcntl.LOCK_EX)
            return run(root, args)
        finally:
            os.close(directory)
    return run(root, args)


def run(root, args):
    pending = root / PENDING
    if pending.is_file():
        print("An interrupted domain-term migration is pending.")
        if args.check:
            return 1
        try:
            plan = json.loads(pending.read_text(encoding="utf-8"))
            if args.dry_run:
                apply_plan(root, plan, dry_run=True)
            else:
                finish(root, plan)
        except (ValueError, OSError) as exc:
            sys.exit(f"Migration stopped: {exc}")
        return 0
    paths = list(legacy_pages(root))
    old_folders = [root / "wiki" / name for name in OLD if (root / "wiki" / name).is_dir()]
    if args.check:
        for path in paths or old_folders:
            print(path.relative_to(root))
        for folder in old_folders:
            for entry in sorted(folder.iterdir()):
                if entry.name != ".gitkeep" and entry not in paths:
                    print(f"Review remaining entry: {entry.relative_to(root)}")
        return int(bool(paths or old_folders))
    if not (paths or old_folders):
        print("No legacy domain pages.")
        return 0
    if paths:
        try:
            import yaml
        except ImportError:
            sys.exit("Migration needs PyYAML. Install the dashboard dependencies or run with uv run --with pyyaml.")
        failures = (ValueError, OSError, yaml.YAMLError)
    else:
        yaml = None
        failures = (ValueError, OSError)
    try:
        migrate(root, paths, args.dry_run, yaml)
    except failures as exc:
        sys.exit(f"Migration stopped: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
