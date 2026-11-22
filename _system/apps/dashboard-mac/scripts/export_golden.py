"""Writes the golden data of every fixture from the Go dashboard's answers.

Called by export-golden.sh. Starts the dashboard on each fixture, reads
/search.json and the HTML pages, and writes Tests/Golden/<fixture>/. The
extraction rules are in Tests/Golden/README.md. Python 3 standard library only.
"""
from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
AREAS = ("req42", "arc42", "commons")


# ---------------------------------------------------------------- HTML tree

class Node:
    def __init__(self, tag: str, attrs: dict[str, str], parent: "Node | None") -> None:
        self.tag = tag
        self.attrs = attrs
        self.parent = parent
        self.children: list[Node | str] = []

    @property
    def classes(self) -> list[str]:
        return self.attrs.get("class", "").split()

    def has(self, cls: str) -> bool:
        return cls in self.classes

    def walk(self):
        for c in self.children:
            if isinstance(c, Node):
                yield c
                yield from c.walk()

    def find_all(self, tag: str | None = None, cls: str | None = None, **attrs: str) -> "list[Node]":
        out = []
        for n in self.walk():
            if tag and n.tag != tag:
                continue
            if cls and not n.has(cls):
                continue
            if any(n.attrs.get(k.replace("_", "-")) != v for k, v in attrs.items()):
                continue
            out.append(n)
        return out

    def find(self, tag: str | None = None, cls: str | None = None, **attrs: str) -> "Node | None":
        found = self.find_all(tag, cls, **attrs)
        return found[0] if found else None

    def raw_text(self) -> str:
        return "".join(c if isinstance(c, str) else c.raw_text() for c in self.children)

    def text(self) -> str:
        return " ".join(self.raw_text().split())


class Tree(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", {}, None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, {k: (v or "") for k, v in attrs}, self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, {k: (v or "") for k, v in attrs}, self.cur))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def parse(html: str) -> Node:
    t = Tree()
    t.feed(html)
    t.close()
    return t.root


# ------------------------------------------------------------------ server

class Dashboard:
    def __init__(self, binary: str, wiki: Path) -> None:
        env = dict(os.environ, DASH_NO_SHUTDOWN="1")
        self.proc = subprocess.Popen(
            [binary, "--port", "0", "--host", "127.0.0.1", "--ready-json", str(wiki)],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env,
        )
        line = self.proc.stdout.readline()
        if not line.startswith("READY "):
            raise SystemExit(f"dashboard did not start on {wiki}: {line!r}")
        self.base = json.loads(line[len("READY "):])["url"]

    def get(self, path: str) -> str:
        with urllib.request.urlopen(self.base + path, timeout=30) as r:
            return r.read().decode("utf-8")

    def tree(self, path: str) -> Node:
        return parse(self.get(path))

    def stop(self) -> None:
        self.proc.send_signal(signal.SIGTERM)
        self.proc.wait(timeout=10)


# ------------------------------------------------------------------ output

def dump(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def dump_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip("\n") + "\n", encoding="utf-8")


# -------------------------------------------------------------- page index

def page_index(search: dict) -> dict[str, dict]:
    """Maps id to {url, folder, stem} from the records of /search.json."""
    out = {}
    for rec in search["records"]:
        parts = rec["url"].strip("/").split("/")
        # /page/<folder>/<stem> or /functional-requirements/<stem>
        folder, stem = (parts[1], parts[2]) if parts[0] == "page" else (parts[0], parts[1])
        out[rec["id"]] = {"url": rec["url"], "folder": folder, "stem": stem}
    return out


# -------------------------------------------------------------- pages.json

def ids_in(section: Node) -> list[str]:
    return sorted({c.text() for c in section.find_all("code")})


def extract_page(dash: Dashboard, url: str, type_label: str) -> tuple[dict, Node]:
    main = dash.tree(url)
    head = main.find(cls="detail-head")
    status = head.find(cls="status") if head else None
    links_to: list[str] = []
    linked_from: list[str] = []
    for block in main.find_all(cls="rel-block"):
        h = block.find(cls="rel-h").text()
        ids = [li.find("code").text() for li in block.find_all("li")]
        (links_to if h == "Links to" else linked_from).extend(ids)
    page = {
        "id": head.find(cls="detail-id").text(),
        "title": main.find(cls="page-h1").text(),
        "status": status.text() if status else "",
        "type": type_label,
        "links_to": sorted(set(links_to)),
        "linked_from": sorted(set(linked_from)),
    }
    return page, main


# ------------------------------------------------------------ diagrams

def blocks_of(main_or_root: Node) -> tuple[list[str], dict[str, str]]:
    """Mermaid texts in page order, and JSON script blocks by their id."""
    mermaid = [p.raw_text().strip() for p in main_or_root.find_all("pre", cls="mermaid") if p.raw_text().strip()]
    data = {}
    for s in main_or_root.find_all("script", type="application/json"):
        data[s.attrs.get("id", "data")] = s.raw_text()
    return mermaid, data


def write_blocks(out: Path, name: str, mermaid: list[str], data: dict[str, str]) -> None:
    for i, text in enumerate(mermaid):
        dump_text(out / "diagrams" / (f"{name}.mmd" if i == 0 else f"{name}-{i + 1}.mmd"), text)
    for key in sorted(data):
        suffix = "" if len(data) == 1 and key in ("graph-data", "mm-graph-data") else f"-{key.removesuffix('-data')}"
        dump(out / "diagrams" / f"{name}{suffix}.json", json.loads(data[key]))


# route, name. A route that serves several blocks gets -2, -3 ... after the name.
DIAGRAM_ROUTES = [
    ("/req42/scope", "context"),
    ("/entity-diagram", "data-model"),
    ("/req42/models", "models"),
    ("/goals", "goals"),
    ("/req42/functional-requirements", "story-map"),
    ("/arc42/building-blocks", "building-blocks"),
    ("/arc42/deployment", "deployment"),
    ("/arc42/runtime", "runtime"),
    ("/arc42/strategy", "strategy"),
    ("/arc42/concepts", "concepts"),
    ("/graph/domain-terms", "term-network"),
    ("/graph/domain-terms?edges=related", "term-network-related"),
    ("/graph/domain-terms?edges=structured", "term-network-structured"),
    ("/metamodel", "metamodel-graph"),
]


def goal_matrix(main: Node) -> dict | None:
    sec = main.find(cls="goal-matrix")
    table = sec.find("table") if sec else None
    if not table:
        return None
    cols = []
    for th in table.find("thead").find_all("th", cls="gm-th"):
        cols.append({
            "id": th.find("a").text(),
            "status": th.attrs.get("data-status", ""),
            "enabler": th.has("gm-enabler"),
            "no_goal": th.has("gm-nogoal"),
        })
    rows = {}
    for tr in table.find("tbody").find_all("tr"):
        cells = [bool(td.find(cls="gm-dot")) for td in tr.find_all("td") if not td.has("gm-row-head")]
        served = tr.find(cls="gm-served")
        rows[tr.attrs["data-goal"]] = {
            "status": tr.attrs.get("data-status", ""),
            "gap": "data-gap" in tr.attrs,
            "gap_accepted": "data-gap-accepted" in tr.attrs,
            "serves": [c["id"] for c, on in zip(cols, cells) if on],
            "served_by": sorted({a.text() for a in served.find_all("a")}) if served else [],
        }
    return {"columns": cols, "rows": rows}


# ----------------------------------------------------------------- sections

def section_folders(types: list[dict]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for t in types:
        if t["block"]:
            folder = t["folder"].removeprefix("wiki/").strip("/")
            out.setdefault(t["block"], []).append(folder)
    return {k: sorted(v) for k, v in out.items()}


def extract_sections(dash: Dashboard, types: list[dict], index: dict[str, dict]) -> dict:
    folders = section_folders(types)
    by_stem = {(v["folder"], v["stem"]): k for k, v in index.items()}
    sections = {}
    for area in AREAS:
        for tile in dash.tree(f"/{area}").find_all(cls="tile"):
            tid = tile.attrs.get("id", "")
            if not tid.startswith("tile-"):
                continue
            sid = tid[len("tile-"):].upper()
            if sid in sections:
                raise SystemExit(f"section {sid} appears twice")
            fl = folders.get(sid, [])
            pages: set[str] = set()
            stretch = tile.find("a", cls="tile-stretch")
            href = tile.attrs.get("href") or (stretch.attrs["href"] if stretch else None)
            if href and fl:
                for a in dash.tree(href).find_all("a"):
                    link = a.attrs.get("href", "").strip("/").split("/")
                    key = (link[1], link[2]) if link[0] == "page" and len(link) == 3 else (
                        (link[0], link[1]) if len(link) == 2 and link[0] == "functional-requirements" else None)
                    if key and key[0] in fl and key in by_stem:
                        pages.add(by_stem[key])
            sections[sid] = {
                "title": tile.find(cls="tile-title").text(),
                "area": area,
                "folders": fl,
                "pages": sorted(pages),
            }
    return sections


# ---------------------------------------------------------------- metamodel

def code_of(node: Node | None) -> str:
    return node.text() if node else ""


def without(cell: Node, *classes: str) -> str:
    """Text of a cell, leaving out the child elements with one of the classes."""
    def rec(n: Node) -> str:
        out = []
        for c in n.children:
            if isinstance(c, str):
                out.append(c)
            elif not any(c.has(k) for k in classes):
                out.append(rec(c))
        return "".join(out)
    return " ".join(rec(cell).split())


def fields_of(dl: Node) -> list[dict]:
    out = []
    kids = [c for c in dl.children if isinstance(c, Node)]
    for dt, dd in zip(kids[0::2], kids[1::2]):
        kind, _, target = dt.find(cls="mm-kind").text().partition("→")
        values = dd.find(cls="mm-values")
        out.append({
            "name": code_of(dt.find("code")),
            "required": dt.find(cls="mm-req") is not None,
            "kind": kind.strip(),
            "relation": target.strip(),
            "values": [v.strip() for v in values.text().split("|")] if values else [],
            "description": without(dd, "mm-values"),
        })
    return out


def extract_types(main: Node) -> list[dict]:
    out = []
    for tr in main.find("section", id="types").find_all("tr", cls="mm-row"):
        term, block, definition, structure, example = tr.find_all("td")
        aliases = term.find_all(cls="aliases")
        chip = block.find(cls="mm-block-chip")
        details = structure.find(cls="mm-fields")
        dl = details.find("dl") if details else None
        notes = {p.text().split(":")[0]: p for p in (details.find_all("p", cls="mm-small") if details else [])}
        ex = example.find("a")
        out.append({
            "name": tr.attrs["id"].removeprefix("type-"),
            "label": term.find(cls="term").text(),
            "german": aliases[0].text().split(" · ")[0],
            "id_pattern": code_of(term.find("code", cls="mm-id")),
            "folder": code_of(aliases[1].find("code")),
            "block": chip.text() if chip else None,
            "block_title": code_of(block.find(cls="mm-block-title")) if chip else None,
            "lifecycle": code_of(block.find(cls="aliases")).removeprefix("lifecycle: "),
            "definition": without(definition, "mm-naming"),
            "naming": code_of(definition.find(cls="mm-naming")),
            "stereotypes": [s.text() for s in structure.find_all(cls="mm-stereo")],
            "fields": fields_of(dl) if dl else [],
            "standards": [a.text() for a in notes["Standards"].find_all("a")] if "Standards" in notes else [],
            "read_by": [a.text() for a in notes["Read by"].find_all("a")] if "Read by" in notes else [],
            "example": {
                "id": code_of(ex.find("code")),
                "summary": code_of(example.find(cls="aliases")),
            } if ex else None,
        })
    return out


def type_of(anchor: str) -> str:
    return anchor.removeprefix("#type-")


def extract_relations(main: Node) -> list[dict]:
    out = []
    for tr in main.find("section", id="relations").find_all("tr", cls="mm-row"):
        field, connects, meaning, inverse = tr.find_all("td")
        edges = []
        for e in connects.find_all(cls="mm-edge"):
            sides: list[list[str]] = [[]]
            for c in e.children:
                if isinstance(c, Node) and c.has("mm-arrow"):
                    sides.append([])
                elif isinstance(c, Node) and c.tag == "a":
                    sides[-1].append(type_of(c.attrs["href"]))
                elif isinstance(c, str) and c.strip():
                    sides[-1].append(c.strip())
            edges.append({
                "from": " ".join(sides[0]),
                "to": " ".join(sides[1]) if len(sides) > 1 else "",
                "cardinality": code_of(e.find(cls="mm-cardinality")),
                "note": code_of(e.find(cls="mm-note")),
            })
        out.append({
            "field": code_of(field.find(cls="mm-field")),
            "direction": field.find(cls="aliases").text(),
            "edges": edges,
            "semantics": code_of(meaning.find(cls="mm-sem")),
            "meaning": without(meaning, "mm-sem"),
            "inverse": code_of(inverse.find("em")),
            "inverse_storage": code_of(inverse.find(cls="aliases")),
        })
    return out


def extract_projections(main: Node) -> list[dict]:
    out = []
    for tr in main.find("section", id="projections").find_all("tr", cls="mm-row"):
        name, reads, shows, where = tr.find_all("td")
        al = name.find(cls="aliases")
        out.append({
            "name": name.find(cls="term").text(),
            "output": al.text().split(" · ")[0],
            "reads": [
                {"type": type_of(r.find("a").attrs["href"]),
                 "fields": [c.text() for c in r.find_all("code")]}
                for r in reads.find_all(cls="mm-reads")
            ],
            "summary": without(shows, "aliases"),
            "where": where.text(),
        })
    return out


def extract_rules(main: Node) -> list[dict]:
    out = []
    for tr in main.find("section", id="rules").find_all("tr", cls="mm-row"):
        name, applies, check, action = tr.find_all("td")
        link = applies.find("a")
        qualifier = applies.find(cls="aliases")
        out.append({
            "name": name.find(cls="term").text(),
            "source": code_of(name.find(cls="aliases")),
            "applies_to": type_of(link.attrs["href"]) if link else without(applies, "aliases"),
            "qualifier": code_of(qualifier),
            "check": without(check, "aliases"),
            "summary": code_of(check.find(cls="aliases")),
            "action": code_of(action.find(cls="mm-action")),
            "confidence": code_of(action.find(cls="aliases")).removeprefix("confidence "),
        })
    return out


def extract_anchors(main: Node) -> list[dict]:
    out = []
    for tr in main.find("section", id="anchors").find_all("tr", cls="mm-row"):
        name, definition, applies = tr.find_all("td")
        al = name.find(cls="aliases")
        out.append({
            "id": tr.attrs["id"].removeprefix("anchor-"),
            "name": name.find(cls="term").text(),
            "aliases": [a.strip() for a in al.text().split("·")] if al else [],
            "definition": without(definition, "aliases"),
            "applies_to": [type_of(a.attrs["href"]) for a in applies.find_all("a")],
            "applies_other": code_of(applies.find(cls="aliases")),
        })
    return out


def extract_version(main: Node) -> dict:
    sec = main.find("section", id="version")
    dd = sec.find_all("dd")
    codes = dd[0].find_all("code")
    note = sec.find(cls="mm-small")
    lead = sec.find(cls="mm-lead")
    state = "supported" if note else ("missing" if "cannot tell" in lead.text() else "unsupported")
    return {
        "wiki": codes[0].text() if codes and "from" in dd[0].text() else "",
        "file": codes[1].text().removeprefix("_system/metamodel/") if len(codes) > 1 else "",
        "supported": [c.text() for c in dd[1].find_all("code")],
        "state": state,
    }


def extract_language(main: Node) -> dict:
    sec = main.find("section", id="language")
    cards = sec.find_all(cls="mm-card")
    universal = fields_of(cards[0].find("dl"))
    lifecycles = {}
    kids = [c for c in cards[1].find("dl").children if isinstance(c, Node)]
    for dt, dd in zip(kids[0::2], kids[1::2]):
        lifecycles[dt.text()] = [s.strip() for s in dd.text().split("→")]
    small = [p for p in cards[1].find_all("p", cls="mm-small")]
    fw_text = small[2].text()
    frameworks = [
        {"name": m.group(1), "blocks": int(m.group(2))}
        for m in re.finditer(r"(\S+) \((\d+) blocks\)", fw_text.split("—")[0])
    ]
    captured = re.search(r"(\d+) of (\d+) blocks", fw_text)
    return {
        "constructs": [c.text() for c in sec.find_all(cls="mm-construct")],
        "universal_fields": universal,
        "lifecycles": lifecycles,
        "field_kinds": [c.text() for c in small[1].find_all("code")],
        "frameworks": frameworks,
        "blocks_in_folders": int(captured.group(1)),
        "blocks_total": int(captured.group(2)),
    }


def extract_metamodel(main: Node) -> dict:
    language = extract_language(main)
    return {
        "version": extract_version(main),
        "types": extract_types(main),
        "relations": extract_relations(main),
        "frameworks": language.pop("frameworks"),
        "blocks_in_folders": language.pop("blocks_in_folders"),
        "blocks_total": language.pop("blocks_total"),
        "projections": extract_projections(main),
        "rules": extract_rules(main),
        "anchors": extract_anchors(main),
        "language": language,
    }


# --------------------------------------------------------------------- main

def export_fixture(binary: str, fixture: Path, out: Path) -> None:
    dash = Dashboard(binary, fixture)
    try:
        search = json.loads(dash.get("/search.json"))
        dump(out / "search.json", search)
        index = page_index(search)
        types_by_id = {r["id"]: r["type"] for r in search["records"]}

        metamodel_root = dash.tree("/metamodel")
        metamodel = extract_metamodel(metamodel_root)
        dump(out / "metamodel.json", metamodel)
        sections = extract_sections(dash, metamodel["types"], index)
        listed = [pid for sec in sections.values() for pid in sec["pages"]]
        if sorted(listed) != sorted(index):
            missing = sorted(set(index) - set(listed))
            raise SystemExit(f"{fixture.name}: pages not in exactly one section list: {missing}")
        dump(out / "sections.json", sections)

        pages = {}
        for pid in sorted(index):
            page, main = extract_page(dash, index[pid]["url"], types_by_id[pid])
            if page["id"] != pid:
                raise SystemExit(f"{index[pid]['url']} shows {page['id']}, search.json says {pid}")
            pages[pid] = page
            mermaid, data = blocks_of(main)
            for i, text in enumerate(mermaid):
                dump_text(out / "diagrams" / f"page-{pid}{'' if i == 0 else f'-{i + 1}'}.mmd", text)
            for key in sorted(data):
                dump(out / "diagrams" / f"page-{pid}-{key.removesuffix('-data')}.json", json.loads(data[key]))
        dump(out / "pages.json", pages)

        for route, name in DIAGRAM_ROUTES:
            main = metamodel_root if route == "/metamodel" else dash.tree(route)
            mermaid, data = blocks_of(main)
            write_blocks(out, name, mermaid, data)
            if route == "/goals":
                matrix = goal_matrix(main)
                if matrix:
                    dump(out / "diagrams" / "goal-matrix.json", matrix)
    finally:
        dash.stop()


def main() -> None:
    binary, fixtures, golden = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    for fixture in sorted(p for p in fixtures.iterdir() if p.is_dir()):
        export_fixture(binary, fixture, golden / fixture.name)
        print(f"  {fixture.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
