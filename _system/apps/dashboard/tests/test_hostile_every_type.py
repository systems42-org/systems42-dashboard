"""No wiki text reaches a page as live markup, on any route — no pytest.

The dashboard sanitizes where HTML is built from wiki content (render_markdown,
the snippet helpers, escaped labels and frontmatter strings). A new helper that
forgets to would bring the XSS back without any other test noticing, so this
one does not look at helpers at all: it builds a vault from `_templates/` in
which every text field of every content type, every list entry, the body, the
project identity, the About page, the method anchors and the metamodel's prose
carry the same hostile payload, renders every route the app has, and checks
that none of it arrived live.

"Live" means what a browser would build: a script element running the text,
an event-handler attribute, a `javascript:` link, or an id / class that would
take over the page's own controls (the settings dialog, filter buttons). The
page is read with an HTML parser, so escaped text is inert, as it should be.

The brand's intro.html is not covered: it is a fragment with its own inline
script by design (brands/README.md), trusted like code.

Run from the dashboard dir:
    .venv/bin/python tests/test_hostile_every_type.py
"""
import os
import re
import shutil
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[4]          # the repository root (…/_templates)
HERE = Path(__file__).resolve().parent
MARK = "XSSMARK"
PAYLOAD = (f'<script>{MARK}()</script><img src=x onerror={MARK}()>'
           f'<a href="javascript:{MARK}()">j</a>'
           f'<span id="settings-dialog" class="fbtn">{MARK}span</span>')

TYPE_FOLDERS = {
    "domain-term": "domain-terms", "goal": "goals", "stakeholder": "stakeholders",
    "context": "context", "external-interface": "external-interfaces",
    "activity-model": "activity-models", "functional-requirement": "functional-requirements",
    "quality-requirement": "quality-requirements", "constraint": "constraints",
    "building-block": "building-blocks", "deployment-node": "deployment-nodes",
    "runtime-scenario": "runtime-scenarios", "crosscutting-concept": "crosscutting-concepts",
    "solution-strategy": "solution-strategy",
    "decision-record": "decisions", "issue": "issues",
}
# fields that steer which projection a page lands in: kept as the template has
# them in one variant, so the hostile page actually shows up in that projection
STRUCTURAL = {"id", "type", "status", "stereotype", "level", "kind", "parent", "state", "lane"}
# the keys structured list entries use (flows, steps, connects, attributes,
# relationships); link-valued keys point at hostile pages so the entry resolves
_ENTRY = {k: PAYLOAD for k in ("data", "direction", "format", "trigger", "message", "note",
                                "protocol", "name", "type", "label", "kind", "multiplicity",
                                "verb", "cardinality")}
_ENTRY.update({"from": "[[STK-001-hostile]]", "to": "[[BB-001-hostile]]",
               "target": "[[DT-001-hostile]]"})

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
_sources = _tmp / "sources"
_sources.mkdir(parents=True)
_docs = _tmp / "docs"
_docs.mkdir()


def _template_fields(name: str) -> dict:
    text = (ROOT / "_templates" / f"{name}.md").read_text(encoding="utf-8")
    front = text.split("---")[1]
    return yaml.safe_load(re.sub(r"\{\{\w+\}\}", "x", front)) or {}


def _hostile(value, keep: bool):
    if keep:
        return value
    if isinstance(value, list):
        return [PAYLOAD, f"[[{PAYLOAD}]]", dict(_ENTRY)]
    if isinstance(value, dict):
        return {k: PAYLOAD for k in value}
    return PAYLOAD


BODY = (f"# {PAYLOAD}\n\n> follows [[HOSTILE]]\n\n**Definition.** {PAYLOAD} [[HOSTILE]]\n\n"
        f"**Snapshot.** {PAYLOAD}\n\n"
        f"## Vision\n\n{PAYLOAD}\n\n- **Purpose.** {PAYLOAD}\n- **Advantage.** {PAYLOAD}\n\n"
        + "".join(f"- **{k}.** {PAYLOAD}\n" for k in ("Source", "Stimulus", "Environment",
                                                     "Response", "Measure"))
        + f"\n| a | b |\n|---|---|\n| {PAYLOAD} | x |\n\n> [!note] {PAYLOAD}\n\n"
        f"[[{PAYLOAD}|{PAYLOAD}]] [[SRC-001-hostile|{PAYLOAD}]] [[HOSTILE|{PAYLOAD}]]\n\n"
        f"Text {{: #settings-dialog .fbtn }}\n")


def _write(path: Path, meta: dict) -> None:
    path.write_text("---\n" + yaml.safe_dump(meta, allow_unicode=True) + "---\n" + BODY,
                    encoding="utf-8")


for _name, _folder in TYPE_FOLDERS.items():
    (_wiki / _folder).mkdir(parents=True)
    fields = _template_fields(_name)
    prefix = str(fields.get("id") or "X-000").split("-")[0]
    for n, structural_kept in enumerate((True, False), start=1):
        meta = {k: _hostile(v, structural_kept and k in STRUCTURAL) for k, v in fields.items()}
        meta["id"] = f"{prefix}-00{n}"
        meta["title"] = PAYLOAD
        if "parent" in meta and structural_kept:
            meta["parent"] = []
        _write(_wiki / _folder / f"{prefix}-00{n}-hostile.md", meta)
# a second goal that is the vision, so the objective above has one to hang under
_write(_wiki / "goals" / "GOAL-009-vision.md",
       {"id": "GOAL-009", "title": PAYLOAD, "stereotype": "vision", "beneficiary": [PAYLOAD],
        "tile_claim": PAYLOAD, "short_title": PAYLOAD})
# domain terms: add the fields of the fixture's structured term to the template's pages
_dt = (HERE / "fixtures/domain-model/wiki/domain-terms/DT-001-customer.md").read_text(encoding="utf-8")
_dt_fields = yaml.safe_load(_dt.split("---")[1])
(_wiki / "domain-terms").mkdir(exist_ok=True)
for n, kept in enumerate((True, False), start=1):
    meta = {k: _hostile(v, kept and k in STRUCTURAL) for k, v in _dt_fields.items()}
    meta.update(id=f"DT-00{n}", title=PAYLOAD)
    _write(_wiki / "domain-terms" / f"DT-00{n}-hostile.md", meta)
# requirement notations (DR-038): one page per place the FR views put it —
# Agile epic → feature, a sea-level use case refined by an Agile story (a root
# with "Refined by"), another notation, and a notation and level that are
# the payload themselves (listed outside the Agile hierarchy)
_fr = {k: _hostile(v, k in STRUCTURAL) for k, v in _template_fields("functional-requirement").items()}
_fr.pop("stereotype", None)
for _stem, _extra in (
        ("FR-011-agile-epic", {"notation": "agile", "level": "epic", "parent": []}),
        ("FR-012-agile-feature", {"notation": "agile", "level": "feature",
                                  "parent": ["[[FR-011-agile-epic]]"]}),
        ("UC-011-use-case", {"notation": "use-case", "level": "sea", "parent": [],
                             "primary-actor": "[[STK-001-hostile]]",
                             "scope-building-block": "[[BB-001-hostile]]"}),
        ("FR-013-story-under-use-case", {"notation": "agile", "level": "story",
                                         "parent": "[[UC-011-use-case]]", "goal": []}),
        ("FR-014-ears", {"notation": "ears", "level": "requirement", "parent": []}),
        ("FR-015-payload-notation", {"notation": PAYLOAD, "level": PAYLOAD, "parent": [PAYLOAD]})):
    _write(_wiki / "functional-requirements" / f"{_stem}.md",
           {**_fr, "id": _stem[:6], "title": PAYLOAD, **_extra})

_src = {k: _hostile(v, k in {"id", "type"}) for k, v in _template_fields("source").items()}
_src.update(id="SRC-001", title=PAYLOAD,
            **{"ingested-pages": [PAYLOAD, "[[DT-001-hostile]]"]})
_write(_sources / "SRC-001-hostile.md", _src)

# method anchors: one with a plain name the pages link to, one named by the payload
_anchors = _tmp / "anchors"
_anchors.mkdir()
for stem, title in (("hostile", "HOSTILE"), ("payload", PAYLOAD)):
    (_anchors / f"{stem}.md").write_text(
        "---\n" + yaml.safe_dump({"type": "anchor", "title": title, "aliases": [PAYLOAD],
                                  "applies-to": [PAYLOAD, "goal"]}, allow_unicode=True)
        + f"---\n# {PAYLOAD}\n\n{PAYLOAD} [x]({PAYLOAD}) https://example.org\n", encoding="utf-8")

# the metamodel: the repository's own, with the payload as every page's lead
# paragraph (the summaries) and in every doc / note / check string
_mm = _tmp / "metamodel"
shutil.copytree(ROOT / "_system" / "metamodel", _mm)
# the shipped requirement notations, plus the fixture ones
shutil.copytree(HERE / "fixtures" / "notations", _mm / "notations", dirs_exist_ok=True)
# a project notation that is the payload through and through (DR-038)
_own_notations = _tmp / "notations"
_own_notations.mkdir()
(_own_notations / "notation-hostile.md").write_text(
    "---\n" + yaml.safe_dump({"type": "metamodel", "construct": "notation", "name": PAYLOAD,
                              "title": PAYLOAD, "summary": PAYLOAD, "levels": [PAYLOAD, "x"],
                              "fields": [{"name": PAYLOAD, "required": True, "doc": PAYLOAD}]},
                             allow_unicode=True)
    + f"---\n\n# {{{{title}}}}\n\n<!-- levels: {PAYLOAD} -->\n## {PAYLOAD}\n\n"
      f"<!-- levels: x -->\n**{PAYLOAD}.** text\n", encoding="utf-8")


def _poison(value):
    if isinstance(value, dict):
        return {k: (PAYLOAD if k in ("doc", "note", "check") and isinstance(v, str) else _poison(v))
                for k, v in value.items()}
    if isinstance(value, list):
        return [_poison(v) for v in value]
    return value


for _p in _mm.rglob("*.md"):
    _text = _p.read_text(encoding="utf-8")
    _m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", _text, re.DOTALL)
    if not _m:
        continue
    _front = yaml.safe_load(_m.group(1)) or {}
    _body = re.sub(r"^(#\s+[^\n]*\n)", lambda h: h.group(1) + f"\n{PAYLOAD} [[HOSTILE]]\n\n",
                   _m.group(2), count=1)
    _p.write_text("---\n" + yaml.safe_dump(_poison(_front), allow_unicode=True, sort_keys=False)
                  + "---\n" + _body, encoding="utf-8")

# a section the dashboard does not know, named by the payload (FR-044): it
# gets the generic route and tile, and its title lands in every section list
_fw = _mm / "frameworks" / "fw-commons.md"
_m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", _fw.read_text(encoding="utf-8"), re.DOTALL)
_front = yaml.safe_load(_m.group(1))
_front["blocks"].append({"id": "X9", "title": PAYLOAD, "types": [], "scope": "in", "note": PAYLOAD})
_fw.write_text("---\n" + yaml.safe_dump(_front, allow_unicode=True, sort_keys=False)
               + "---\n" + _m.group(2), encoding="utf-8")

(_docs / "about.md").write_text(f"# {PAYLOAD}\n\n{PAYLOAD}\n\n![m](m.svg)\n", encoding="utf-8")
(_docs / "m.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
(_tmp / "wiki.yaml").write_text(yaml.safe_dump({"system_name": PAYLOAD, "tagline": PAYLOAD,
                                                "default_notation": PAYLOAD,
                                                "about_label": PAYLOAD, "about": "docs/about.md"}),
                                encoding="utf-8")

os.environ["REPO_DIR"] = str(_tmp)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_docs)
os.environ["METAMODEL_DIR"] = str(_mm)
os.environ["NOTATIONS_DIR"] = str(_own_notations)
os.environ["ANCHORS_DIR"] = str(_anchors)
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(HERE.parent))  # import app.py

import app  # noqa: E402


class _LiveMarkup(HTMLParser):
    """Collects what a browser would really build from the page: elements and
    attributes, not text (escaped markup in text or attribute values is inert,
    and so is JSON inside <script type="application/json"> with < escaped)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.problems, self.dialog_ids, self._script, self._last = [], 0, None, ("", {})

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        for name, value in attrs:
            if name.startswith("on") and MARK in (value or ""):
                self.problems.append(f"<{tag} {name}=…> event handler from wiki text")
            if name in ("href", "src", "action", "formaction") and \
                    re.sub(r"\s", "", value or "").lower().startswith("javascript:"):
                self.problems.append(f"<{tag} {name}=javascript:…>")
        if a.get("id") == "settings-dialog":
            self.dialog_ids += 1
        if tag == "script":
            self._script = (a.get("type") or "").lower()
        self._last = (tag, a)

    def handle_endtag(self, tag):
        if tag == "script":
            self._script = None

    def handle_data(self, data):
        if self._script is not None and self._script != "application/json" and MARK in data:
            self.problems.append(f"<script> running wiki text: {data[:60]!r}")
        # the payload's own <span>, built as an element: it must have lost its id and class
        if data.strip() == f"{MARK}span" and self._last[0] == "span":
            attrs = self._last[1]
            if attrs.get("id") or "fbtn" in (attrs.get("class") or "").split():
                self.problems.append(f"a wiki element kept the page's own id/class: {attrs}")


def _routes() -> list[str]:
    urls = [str(r) for r in app.app.url_map.iter_rules()
            if "GET" in r.methods and "<" not in str(r)
            and str(r) not in ("/presence/count", "/presence/list")]
    urls += [app._page_url(p.parent.name, p.stem) for p in _wiki.rglob("*.md")]
    urls += [f"/source/{p.stem}" for p in _sources.glob("*.md")]
    urls += [f"/req42/{slug}" for slug in app.catalog.SECTION_BY_SLUG]
    urls += [f"/section/{sid}" for sid in app.catalog.SECTION_BY_ID]
    urls += [f"/brand/{name}" for name in app.BRAND_MARKS] + ["/about/files/m.svg"]
    urls += ["/entity-diagram?focus=DT-001-hostile", "/entity-diagram?focus=DT-002-hostile",
             "/entity-diagram?context=" + PAYLOAD, "/graph/domain-terms?edges=structured",
             "/search?q=" + PAYLOAD, "/issues?status=" + PAYLOAD + "&section=R1&category=" + PAYLOAD]
    return urls


def _param_rules_are_covered(urls: list[str]) -> list[str]:
    """Every GET rule with a parameter has at least one URL above, so a new
    route cannot slip past this test."""
    adapter = app.app.url_map.bind("localhost")
    hit = set()
    for u in urls:
        try:
            rule, _ = adapter.match(u.split("?")[0], method="GET", return_rule=True)
            hit.add(str(rule))
        except Exception:  # noqa: BLE001 — a redirect or 404 still counts as no hit
            pass
    return sorted(str(r) for r in app.app.url_map.iter_rules()
                  if "GET" in r.methods and "<" in str(r) and str(r) not in hit
                  and not str(r).startswith("/static/"))


def test_every_route_is_rendered():
    missing = _param_rules_are_covered(_routes())
    assert not missing, f"routes this test does not render: {missing}"


def test_no_route_renders_wiki_text_as_live_markup():
    client = app.app.test_client()
    problems = []
    for url in _routes():
        resp = client.get(url, follow_redirects=True)
        if resp.status_code >= 500:
            problems.append(f"{url}: HTTP {resp.status_code}")
            continue
        if not (resp.mimetype or "").startswith("text/html"):
            continue
        parser = _LiveMarkup()
        parser.feed(resp.get_data(as_text=True))
        problems += [f"{url}: {p}" for p in parser.problems]
        if parser.dialog_ids > 1:
            problems.append(f"{url}: a second element with id=settings-dialog")
    assert not problems, "\n".join(problems)


def test_the_payload_was_actually_rendered():
    # guard against a vacuous pass: the hostile text must reach the pages, escaped
    client = app.app.test_client()
    for url in ("/page/domain-terms/DT-001-hostile", "/metamodel", "/about", "/goals",
                "/page/runtime-scenarios/RS-002-hostile", "/req42/functional-requirements",
                "/functional-requirements/UC-011-use-case"):
        body = client.get(url).get_data(as_text=True)
        assert MARK in body and "&lt;script&gt;" in body, url
    # the notation pages reached the projections they were written for
    h = app.build_fr_hierarchy()
    assert [e["id"] for e in h["epics"]] == ["FR-011"], h["epics"]
    assert [u["id"] for u in h["use_cases"]] == ["UC-011"], h["use_cases"]
    assert {"FR-014", "FR-015"} <= {o["id"] for o in h["other_notations"]}, h["other_notations"]
    assert "Refined by" in client.get("/functional-requirements/UC-011-use-case").get_data(as_text=True)
    body = client.get("/metamodel").get_data(as_text=True)
    assert body.count('class="mm-row"') and 'id="notation-agile"' in body


if __name__ == "__main__":
    test_the_payload_was_actually_rendered()
    test_every_route_is_rendered()
    test_no_route_renders_wiki_text_as_live_markup()
    print(f"OK: {len(_routes())} routes render a hostile vault inert")
