"""A vault with broken, oddly typed and hostile pages — no pytest.

The dashboard walks the whole vault on every render (title and link
indexes), so one bad file used to be a 500 on *every* page: frontmatter that
is a string instead of a mapping, a blank `title:`, a single value where a
list belongs, bytes that are not UTF-8. And wiki text is written from
sources in raw/ (emails, tickets), so markup in a title or a body must come
out inert, not run in the room's browsers. Every route that takes a folder
or a file name must stay inside the folder it serves.

Run from the dashboard dir:
    .venv/bin/python tests/test_hostile_vault.py
"""
import os
import re
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "glossary", "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "data-models", "activity-models", "use-cases", "functional-requirements",
    "quality-requirements", "constraints", "issues", "building-blocks", "decisions",
    "concepts", "runtime-scenarios", "deployment-nodes",
]

_tmp = Path(tempfile.mkdtemp())
_repo = _tmp / "repo"
_wiki = _repo / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
(_wiki / ".obsidian").mkdir()
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
_docs = _repo / "docs"
_docs.mkdir()


def _page(folder, stem, frontmatter, body="# T\n"):
    (_wiki / folder / f"{stem}.md").write_text(f"---\n{frontmatter}\n---\n{body}", encoding="utf-8")


# broken frontmatter: a string, a list
_page("issues", "ISS-001-string-frontmatter", "just a string")
_page("constraints", "CON-001-list-frontmatter", "- a\n- b")
# blank title, scalars where lists belong
_page("glossary", "GLO-001-blank-title", "id: GLO-001\ntitle:\nstatus: draft\ntags: single\naliases: Alias\nrelated: 7",
      "**Definition.** plain.\n")
_page("functional-requirements", "FR-001-scalar-parent",
      "id: FR-001\ntitle: Scalar parent\nstereotype: story\nparent: 7\ngoal: 7\nrelated: 7")
_page("use-cases", "UC-001-scalar-goal", "id: UC-001\ntitle: Use case\ngoal: 7\nrelated: 7\nparent: 7")
_page("stakeholders", "STK-001-list-influence",
      "id: STK-001\ntitle: Lists\ninfluence: [high]\ninterest: [low]\nprovides: 7\nreceives: 7")
_page("context", "CTX-001-scalar-flows", "id: CTX-001\ntitle: Ctx\nrelated: 7")
_page("external-interfaces", "EIF-001-scalar-flows", "id: EIF-001\ntitle: Eif\npartner: x\nflows: 7")
_page("data-models", "DM-001-scalar-relationships", "id: DM-001\ntitle: Entity\nrelationships: 7\nparent: 7\nrelated: 7")
_page("domain-terms", "DT-001-scalar-lists",
      "id: DT-001\ntitle: Term\nstereotype: entity\nattributes: 7\nrelationships: 7\nrelated: 7\naliases: 7",
      "**Definition.** A term.\n")
_page("quality-requirements", "QR-001-scalar-dimensions", "id: QR-001\ntitle: Quality\ndimensions: 7\nrelated: 7")
_page("building-blocks", "BB-001-scalars",
      "id: BB-001\ntitle: Block\nstate: current\nparent: 7\nuses: 7\ndrivers: 7\ndecisions: 7")
_page("deployment-nodes", "DN-001-scalars",
      "id: DN-001\ntitle: Node\nstereotype: host\nstate: current\nparent: 7\nhosts: 7\nconnects: 7")
_page("runtime-scenarios", "RS-001-scalars",
      "id: RS-001\ntitle: Scenario\nstate: current\nsteps: 7\ndrivers: 7")
_page("concepts", "CC-001-scalars", "id: CC-001\ntitle: Concept\nstate: current\napplies-to: 7")
_page("decisions", "DR-001-scalars", "id: DR-001\ntitle: Decision\nkind: 7\ndrivers: 7\ntags: 7")
# not UTF-8
(_wiki / "glossary" / "GLO-002-latin1.md").write_bytes(
    b"---\nid: GLO-002\ntitle: Latin-1\n---\n**Definition.** Gr\xfc\xdfe.\n")
# hostile markup
_page("glossary", "GLO-003-hostile-title", 'id: GLO-003\ntitle: "<img src=x onerror=alert(1)>"',
      "**Definition.** <script>alert(2)</script> see [[GLO-004-linker]].\n")
_page("glossary", "GLO-004-linker", "id: GLO-004\ntitle: Linker",
      "**Definition.** Points at [[GLO-003-hostile-title]] and "
      "[[GLO-003-hostile-title|<b>an alias</b>]].\n\n"
      '<a href="javascript:alert(3)">click</a> <img src=x onerror=alert(4)>\n\n'
      '<div id="settings-dialog" class="fbtn">hijack</div>\n\n'
      "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n```mermaid\ngraph TD; A-->B\n```\n\n"
      "A note.[^1]\n\n[^1]: The footnote.\n")
_page("goals", "GOAL-001-vision", "id: GOAL-001\ntitle: Vision\nstereotype: vision",
      "# Vision\n\n## Vision\n\nA vision <script>alert(5)</script>.\n")
_page("goals", "GOAL-002-hostile-metric",
      'id: GOAL-002\ntitle: Objective\nstereotype: objective\nparent: "[[GOAL-001-vision]]"\n'
      'metric: "<b>bold</b> [[GLO-004-linker]]"\nbeneficiary: "[[STK-001-list-influence|The Beneficiary]]"')
_page("goals", "GOAL-003-numeric-beneficiary",
      'id: GOAL-003\ntitle: Numeric beneficiary\nstereotype: objective\nbeneficiary: 7')
# a source record whose ingested pages are one string, with markup
(_sources / "SRC-001-hostile.md").write_text(
    '---\nid: SRC-001\ntitle: Source\ntype: source\ningested-pages: "<b>x</b> [[GLO-004-linker]]"\n'
    "tags: one\n---\n# Source\n\n<script>alert(6)</script>\n", encoding="utf-8")
# markdown files beside and above wiki/, which /page/../ used to serve
(_repo / "outside.md").write_text("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n", encoding="utf-8")
(_wiki / ".obsidian" / "outside.md").write_text("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n",
                                                encoding="utf-8")
(_wiki / "outside.md").write_text("---\nid: OUT\ntitle: Outside\n---\nTOP SECRET\n", encoding="utf-8")
# the about page, an HTML file beside it, a file outside docs/
(_docs / "about.md").write_text("# About\n\n<script>alert(7)</script> ![m](mark.svg)\n", encoding="utf-8")
(_docs / "mark.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(8)</script></svg>',
                                encoding="utf-8")
(_docs / "page.html").write_text("<script>alert(9)</script>", encoding="utf-8")
(_repo / "secret.txt").write_text("TOP SECRET", encoding="utf-8")
# a brand folder whose intro is a symlink out of the folder
_brand = _repo / "brand"
_brand.mkdir()
for _m in ("mark-dark.svg", "mark-light.svg", "favicon.svg"):
    (_brand / _m).write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
(_repo / "elsewhere.html").write_text("<p>OUTSIDE INTRO</p>", encoding="utf-8")
(_brand / "intro.html").symlink_to(_repo / "elsewhere.html")
(_brand / "secret.svg").write_text("<svg>TOP SECRET</svg>", encoding="utf-8")
(_tmp / "wiki.yaml").write_text("system_name: Hostile\nabout: docs/about.md\nbrand: brand\n",
                                encoding="utf-8")

os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_docs)
os.environ["METAMODEL_DIR"] = str(Path(__file__).resolve().parents[2] / "metamodel")
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _get(path):
    resp = app.app.test_client().get(path, follow_redirects=True)
    return resp.status_code, resp.get_data(as_text=True)


def _plain_get_routes():
    return sorted(str(r) for r in app.app.url_map.iter_rules()
                  if "GET" in r.methods and "<" not in str(r)
                  and str(r) not in ("/presence/count", "/presence/list"))


def test_no_route_breaks_on_a_bad_page():
    pages = [app._page_url(p.parent.name, p.stem) for p in _wiki.glob("*/*.md")
             if not p.parent.name.startswith(".")]
    failed = []
    for path in _plain_get_routes() + pages + ["/source/SRC-001-hostile"]:
        status, _ = _get(path)
        if status != 200:
            failed.append(f"{path} -> {status}")
    assert not failed, "\n".join(failed)


def test_bad_fields_fall_back_instead_of_crashing():
    page = app._parse(_wiki / "glossary" / "GLO-001-blank-title.md", "glossary")
    assert page.title == "GLO-001-blank-title", page.title
    assert page.aliases == ["Alias"], page.aliases
    assert page.as_list("tags") == ["single"]
    assert app._parse(_wiki / "issues" / "ISS-001-string-frontmatter.md", "issues").meta == {}
    assert app._parse(_wiki / "constraints" / "CON-001-list-frontmatter.md", "constraints").meta == {}
    _, body = _get("/page/glossary/GLO-002-latin1")
    assert "Latin-1" in body and "Gr��e" in body


def test_titles_and_bodies_render_inert():
    _, body = _get("/page/glossary/GLO-004-linker")
    assert not re.search(r"<img[^>]*onerror", body), "a title or body ran as markup"
    assert "&lt;img src=x onerror=alert(1)&gt;" in body, "the hostile title is not shown escaped"
    assert "&lt;b&gt;an alias&lt;/b&gt;" in body, "a wikilink alias ran as markup"
    assert "javascript:alert" not in body
    assert "<script>alert" not in body
    assert body.count('id="settings-dialog"') == 1, "wiki text took over the settings dialog's id"
    assert 'class="fbtn"' not in body, "wiki text took over a filter button class"
    # what the wiki legitimately uses survives the sanitizer
    assert 'style="text-align:left"' in body, "table alignment lost"
    assert 'class="language-mermaid"' in body, "mermaid block lost its class"
    assert '<a class="wl" href="/page/glossary/GLO-003-hostile-title">' in body
    assert 'id="fn:1"' in body and 'class="footnote-ref"' in body, "footnotes lost"
    _, body = _get("/page/glossary/GLO-003-hostile-title")
    assert "<script>alert(2)" not in body
    for route in ("/domain-terms", "/search", "/"):
        _, listing = _get(route)
        assert "<script>alert(2)" not in listing and not re.search(r"<img[^>]*onerror", listing), route


def test_frontmatter_strings_are_escaped():
    _, body = _get("/goals")
    assert "&lt;b&gt;bold&lt;/b&gt;" in body, "a frontmatter string rendered as markup"
    assert 'href="/page/glossary/GLO-004-linker"' in body, "its wikilink no longer resolves"
    assert "<script>alert(5)" not in body, "the vision paragraph ran as markup"
    _, body = _get("/source/SRC-001-hostile")
    assert "<b>x</b>" not in body and "&lt;b&gt;x&lt;/b&gt;" in body, "ingested-pages ran as markup"
    assert 'href="/page/glossary/GLO-004-linker"' in body
    assert "<script>alert(6)" not in body


def test_a_single_beneficiary_is_shown():
    # `beneficiary: "[[STK-…]]"` is one beneficiary (it used to be iterated
    # letter by letter and vanish); `beneficiary: 7` must not crash /goals
    status, body = _get("/goals")
    assert status == 200
    assert "The Beneficiary" in body, "a single-string beneficiary was dropped"





if __name__ == "__main__":
    test_no_route_breaks_on_a_bad_page()
    test_bad_fields_fall_back_instead_of_crashing()
    test_titles_and_bodies_render_inert()
    test_frontmatter_strings_are_escaped()
    test_a_single_beneficiary_is_shown()
    print("OK: broken, oddly typed and hostile pages render safely")
