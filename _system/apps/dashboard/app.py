"""Requirements-Wiki Dashboard.

A small read-only Flask app that parses the Obsidian-style requirements wiki
(markdown + YAML frontmatter + [[wikilinks]]) live on each request and renders
it as a tiled dashboard. The wiki folder is mounted into the container; nothing
is ever written back.
"""
from __future__ import annotations

import mimetypes
import os
import re
import secrets
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, unquote
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import markdown as md
from flask import (Flask, abort, g, has_request_context, make_response,
                   render_template, request, send_file)
from markupsafe import escape

import catalog  # the section catalog (DR-033)
import metamodel  # reader for _system/metamodel/ (DR-035)
import render  # sanitizer, wikilinks and Markdown
import session  # presence, the Keyholder role, the view and the lifecycle
import settings  # wiki.yaml, the brand, the about page and what the view hides
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import wiki  # paths, pages, parse cache and loaders
import project.architecture  # decisions, building blocks, runtime, deployment, traces
import project.common  # what several projections share
import project.context  # the context diagram and its flows
import project.goals  # vision, objectives and goal coverage
import project.requirements  # requirement hierarchy, its Mermaid trees, quality scenarios
import project.terms  # term network, relations and entity diagram
import web.common  # what several route groups share
import web.pages  # home, areas, section lists, page and source detail, changes
import web.projections  # goals, requirements, terms, arc42 views, decisions, stakeholders, issues
import web.search_session  # search, join, presence, reload, the view and Disconnect all

# some slim base images lack a webp entry in their mime.types
mimetypes.add_type("image/webp", ".webp")

app = Flask(__name__)

# Timezone for the "last refreshed" footer; honours the container's TZ env.
# Empty (not "UTC") when unset, so inject_refresh_time can fall back to the
# host's own local zone instead of forcing UTC.
DISPLAY_TZ = os.environ.get("TZ") or ""


def _build_cache() -> dict | None:
    """The builder cache of the current request (wiki._request_cached), or
    None outside a request."""
    return g.setdefault("_build_cache", {}) if has_request_context() else None


wiki.use_request_cache(_build_cache)

# The route groups, one blueprint each. None has a URL prefix.
app.register_blueprint(web.pages.bp)
app.register_blueprint(web.projections.bp)
app.register_blueprint(web.search_session.bp)


@app.context_processor
def inject_refresh_time():
    """Every render carries the moment its data was (re)parsed — pages parse the
    wiki live, so this is effectively the page load / data refresh time."""
    tz = None
    if DISPLAY_TZ:
        try:
            tz = ZoneInfo(DISPLAY_TZ)
        except (ZoneInfoNotFoundError, ValueError):
            tz = None
    now = datetime.now(tz) if tz else datetime.now().astimezone()   # host's local zone
    # ISO-ish and locale-free: "06.09.2026" reads as 9 June to half the room.
    return {"refreshed_at": now.strftime("%Y-%m-%d %H:%M:%Sh")}


# The dashboard's own release, shown in the footer.
try:
    DASHBOARD_VERSION = (Path(__file__).resolve().parent / "VERSION").read_text(encoding="utf-8").strip()
except OSError:
    DASHBOARD_VERSION = ""


# A file the dashboard serves as it is (a brand mark, a file under docs/) is
# shown from the dashboard's own origin. Opened directly, an SVG or HTML file
# with a script in it would run with the dashboard's rights; sandboxed and
# without script it is only a picture.
_FILE_CSP = "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"


def _inert_file(resp):
    resp.headers["Content-Security-Policy"] = _FILE_CSP
    resp.headers["X-Content-Type-Options"] = "nosniff"
    return resp


# The policy of every HTML page the dashboard renders. Script runs only from
# the dashboard's own files and from the inline blocks of its templates, which
# carry the nonce of this response: markup that slips past sanitize_html()
# still cannot run. Everything a page loads comes from the dashboard itself,
# which also keeps it offline. `style-src 'unsafe-inline'` stays, because
# mermaid and the maturity bars write inline styles, and CSS cannot run script.
_PAGE_CSP = ("default-src 'self'; script-src 'self' 'nonce-{nonce}'; "
             "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
             "font-src 'self' data:; connect-src 'self'; frame-src 'self'; "
             "object-src 'none'; base-uri 'none'; form-action 'self'; "
             "frame-ancestors 'none'")


def csp_nonce() -> str:
    """The nonce of this response's inline scripts, made on first use.
    Templates write it as `<script nonce="{{ csp_nonce() }}">`."""
    if "csp_nonce" not in g:
        g.csp_nonce = secrets.token_urlsafe(16)
    return g.csp_nonce


app.jinja_env.globals["csp_nonce"] = csp_nonce


@app.after_request
def _page_policy(resp):
    """Every HTML page gets the page policy (_PAGE_CSP). No page may be shown
    inside another site's frame (clickjacking the settings or Disconnect-all
    controls). A response that already has a policy (the file routes, the
    brand intro) keeps it and gains the framing directive if it has none."""
    if resp.mimetype == "text/html":
        csp = resp.headers.get("Content-Security-Policy")
        if not csp:
            resp.headers["Content-Security-Policy"] = _PAGE_CSP.format(nonce=csp_nonce())
        elif "frame-ancestors" not in csp:
            resp.headers["Content-Security-Policy"] = f"{csp}; frame-ancestors 'none'"
        resp.headers.setdefault("X-Frame-Options", "DENY")
    return resp


def _brand_url(folder: Path, name: str) -> str:
    """/brand/<name> with a content checksum, so switching brands or editing
    a mark changes the URL and the browser cannot show a cached one."""
    v = settings._brand_checksum(settings._brand_file(folder, name))
    return f"/brand/{name}?v={v}" if v else f"/brand/{name}"


@app.context_processor
def inject_identity():
    """Make the project identity and the active brand available to every
    template. `active_brand.intro_url` is the address of the brand's intro
    (brand_intro), or "" when there is none or `intro: off`."""
    cfg = settings.wiki_config()
    folder = settings.brand_dir(cfg["brand"])
    intro = settings._brand_file(folder, settings.BRAND_INTRO) if cfg["intro"] else None
    cfg["active_brand"] = {
        "mark_dark": _brand_url(folder, "mark-dark.svg"),
        "mark_light": _brand_url(folder, "mark-light.svg"),
        "favicon": _brand_url(folder, "favicon.svg"),
        "intro_url": _brand_url(folder, settings.BRAND_INTRO) if intro else "",
    }
    cfg["dashboard_version_own"] = DASHBOARD_VERSION
    # `local` is the code of this repository, built by the launcher: no release to differ from.
    cfg["dashboard_version_differs"] = cfg["dashboard_version"] not in ("", "local", DASHBOARD_VERSION)
    return cfg


@app.context_processor
def inject_metamodel_version():
    """The repository's metamodel version against this release (FR-043), for
    the footer notice and the version section of /metamodel."""
    return {"metamodel_check": metamodel.version_check()}


# A brand's intro.html comes from a folder of the wiki repository and holds
# script. It never becomes part of a dashboard page. The home page shows it in
# a frame (templates/index.html), and this response is sandboxed without
# `allow-same-origin`: its script runs in an origin of its own, so it cannot
# read the page around it, call /settings or use the viewer's storage, and it
# can load nothing at all. The document carries the theme tokens of
# static/style.css inline, so the intro's `var(--bg)` and the like still work.
_INTRO_CSP = ("default-src 'none'; script-src 'unsafe-inline'; "
              "style-src 'unsafe-inline'; img-src data:; "
              "sandbox allow-scripts; frame-ancestors 'self'")
_THEME_TOKENS_RE = re.compile(r'^:root(?:\[data-theme="light"\])? \{.*?^\}', re.M | re.S)


def _theme_tokens() -> str:
    """The `:root` blocks of static/style.css: the colour and size tokens of
    the dark and the light theme, without any other rule or font."""
    try:
        css = (Path(app.static_folder) / "style.css").read_text(encoding="utf-8")
    except OSError:
        return ""
    return "\n".join(_THEME_TOKENS_RE.findall(css))

# What the frame's document adds after the intro: it tells the home page when
# the intro is over, which is when the intro has removed its element (the
# brand contract) or shows nothing (a hidden element, reduced motion).
_INTRO_DONE_SCRIPT = """<script>
(function () {
  function shown(el) { return !el.hidden && getComputedStyle(el).display !== "none"; }
  function check() {
    var parts = document.body.querySelectorAll(":scope > :not(style):not(script)");
    if (!Array.prototype.some.call(parts, shown)) parent.postMessage("brand-intro-done", "*");
  }
  new MutationObserver(check).observe(document.body, { childList: true });
  setTimeout(check, 100);
})();
</script>"""


@app.route("/brand/intro.html")
def brand_intro():
    """The active brand's intro as a document of its own, for the frame on the
    home page. 404 when the brand has none or `intro: off`."""
    cfg = settings.wiki_config()
    path = settings._brand_file(settings.brand_dir(cfg["brand"]), settings.BRAND_INTRO) if cfg["intro"] else None
    try:
        intro = path.read_text(encoding="utf-8") if path else None
    except (OSError, UnicodeDecodeError):
        intro = None
    if intro is None:
        abort(404)
    theme = ' data-theme="light"' if request.args.get("theme") == "light" else ""
    html = (f'<!doctype html>\n<html lang="en"{theme}>\n<head>\n<meta charset="utf-8">\n'
            f'<style>\n{_theme_tokens()}\n'
            'html, body { margin: 0; background: transparent; }\n</style>\n'
            f'</head>\n<body>\n{intro}\n{_INTRO_DONE_SCRIPT}\n</body>\n</html>\n')
    resp = make_response(html)
    resp.headers["Content-Security-Policy"] = _INTRO_CSP
    resp.headers["X-Frame-Options"] = "SAMEORIGIN"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.route("/brand/<name>")
def brand_mark(name):
    """The active brand's marks and favicon. Nothing else in the folder."""
    if name not in settings.BRAND_MARKS:
        abort(404)
    path = settings._brand_file(settings.brand_dir(settings.wiki_config()["brand"]), name)
    if path is None:
        abort(404)
    # The page links each mark with its checksum. When ?v= matches, the file
    # behind this URL never changes, so the browser may keep it for a year.
    # Any other request revalidates, so a stale ?v= never sticks.
    fresh = request.args.get("v") == settings._brand_checksum(path)
    return _inert_file(send_file(path, mimetype="image/svg+xml", max_age=31536000 if fresh else 0))


@app.context_processor
def inject_area():
    """The area the current page belongs to (None on home, help…), for
    the breadcrumb's area level and the colour bar. A hidden area yields None
    so its bar disappears while its pages stay reachable by URL."""
    if not has_request_context():
        return {"current_area": None}
    area = catalog.area_for_path(request.path)
    if area and settings.is_hidden(area["key"]):
        area = None
    return {"current_area": area}


@app.before_request
def read_sections():
    """The sections come from the repository's metamodel (FR-044). Reading
    them per request shows an edited framework file on the next page load."""
    catalog.refresh()


# Nav entries tagged with the area or section each one opens, so a hidden one
# leaves the nav. Order is the nav order. The header carries content only:
# the two peaks, then the three Commons sections a reader looks up by name.
# Labels come from the catalog, so a section has one name everywhere (FR-017).
# A section the metamodel does not declare, or one without a page, has no entry.
def _nav_entries() -> list[tuple[str, str, str]]:
    out = [(a, catalog.AREA_BY_KEY[a]["href"], catalog.AREA_BY_KEY[a]["label"])
           for a in ("requirements", "architecture")]
    for sid in ("C5", "C7", "C6"):
        s = catalog.SECTION_BY_ID.get(sid)
        if s and s["href"]:
            out.append((sid, s["href"], s["title"]))
    return out


def _nav_current(key: str, href: str, path: str, area: dict | None) -> bool:
    """An area entry is current on every page of that area, except on the
    pages of a section that has its own entry. A section entry is current on
    every page of that section, its wiki pages included (FR-014)."""
    here = catalog.section_for_path(path)
    if key in catalog.AREA_BY_KEY:
        own = bool(here) and any(k == here["id"] and not settings.is_hidden(k) for k, _, _ in _nav_entries())
        return bool(area and area["key"] == key and not own)
    return bool(here and here["id"] == key) or path.startswith(href)


@app.context_processor
def inject_nav():
    """`nav_items` for base.html: (href, label, current), hidden entries dropped."""
    if not has_request_context():
        return {"nav_items": [(h, l, False) for _, h, l in _nav_entries()]}
    area = catalog.area_for_path(request.path)
    return {"nav_items": [(h, l, _nav_current(k, h, request.path, area))
                          for k, h, l in _nav_entries() if not settings.is_hidden(k)]}


app.jinja_env.globals["static_url"] = web.common.static_url


app.jinja_env.globals["list_spec"] = web.common.list_spec
# the folder a type's pages live in, for the hints that name it (CON-006)
app.jinja_env.globals["type_folder"] = catalog.folder


# The issue that holds the open definition of the clarify loop. Matched by
# its full stem: a project numbers its own issues, so a bare ISS-002 there is
# a different question.
CLARIFY_ISSUE = "ISS-002-define-the-clarify-loop"


@app.route("/method")
def method_view():
    """The three loops, capture, inspect and clarify, by their principles
    (FR-011). Clarify links its issue while that issue is open."""
    issue = next((p for p in wiki.load_type("issue")
                  if p.stem == CLARIFY_ISSUE and project.common.is_open_issue(p.status)), None)
    clarify = ({"id": issue.id, "title": issue.title, "url": links_module._page_url(issue.folder, issue.stem)}
               if issue else None)
    return render_template("method.html", clarify_issue=clarify)


@app.errorhandler(404)
def not_found(_err):
    """A missing page keeps the header and footer, so the reader can go on
    from here (FR-013)."""
    return render_template("not_found.html"), 404


HELP_PATH = Path(__file__).resolve().parent / "help.md"


@app.route("/help")
def help_view():
    """Dashboard help, rendered from help.md: how to read the page, and the
    Systems42 model in brief with the sections diagram (DR-033)."""
    try:
        text = HELP_PATH.read_text(encoding="utf-8")
    except OSError:
        text = "# Help\n\nhelp.md is missing from the image."
    img = (f'<figure class="help-diagram"><img src="{web.common.static_url("systems42-sections.svg")}" '
           f'alt="Systems42 sections: req42, arc42 and Common" width="660" height="608"></figure>')
    html = render.wrap_tables(md.markdown(text.replace("{{DIAGRAM}}", img), extensions=["extra", "sane_lists"]))
    return render_template("help.html", html=html)


# --- /metamodel: the explicit metamodel as a help page (DR-035) --------------
#
# The schema lives in `_system/metamodel/` (one page per type, relation,
# framework section, projection and rule; `metamodel.py` reads it). This page
# explains it the way the term network explains the glossary: a graph of the
# types with their declared relations as edges, grouped by section, and
# tables with the definition of each construct plus a live example from the
# wiki. Nothing here is a second statement of the schema — every cell comes
# from the metamodel pages, and the examples from the vault.

_MM_DR_RE = re.compile(r"^DR-\d{3}\b")
# a same-site path only: `//host` and `/\host` would leave the site
_MM_ROUTE_RE = re.compile(r"^(/(?![/\\])[^\s,;)]*)")


def _mm_dr_link(ref: str, label: str = "") -> str:
    """A decision record a metamodel page cites, as a link to its page — only
    when the vault has a page with exactly that stem. The metamodel ships to
    every project, but meta's decisions do not (DR-034), and a project numbers
    its own from DR-001: a bare 'DR-013' there is a different decision. So a
    bare ID is never linked, and a full stem ('DR-013-data-flows-as-…') the
    vault lacks stays plain text instead of a link that 404s."""
    text = escape(label or ref)
    if ref in {p.stem for p in wiki.load_type("decision-record")}:
        return f'<a class="wl" href="{escape(links_module._page_url(catalog.folder("decision-record"), ref))}">{text}</a>'
    return str(text)


def _mm_wikilinks(text: str, anchors: dict[str, str]) -> str:
    """Resolve the wikilinks metamodel pages use among themselves: another
    metamodel page → an in-page anchor, a method anchor (PAM, INVEST, …) → its
    entry in the Anchors section, a decision record → its page, anything else
    → a chip."""
    def repl(m: re.Match) -> str:
        target, alias = m.group(1).strip(), (m.group(2) or "").strip()
        base = target.split("/")[-1]
        # a framework has no row of its own, so `[[req42]]` means the anchor
        if base in anchors and not anchors[base].startswith("fw-"):
            return f'<a class="wl" href="#{anchors[base]}">{escape(alias or base)}</a>'
        if a := render.anchor_lookup().get(base.lower()):
            return (f'<a class="wl wl-anchor" href="#{a["id"]}" '
                    f'title="{escape(render.anchor_title(a))}">{escape(alias or a["name"])}</a>')
        if base in anchors:
            return f'<a class="wl" href="#{anchors[base]}">{escape(alias or base)}</a>'
        if _MM_DR_RE.match(base):
            return _mm_dr_link(base, alias)
        return f'<span class="mm-anchor">{escape(alias or base)}</span>'
    return render.outside_code(text, lambda t: wiki.WIKILINK_RE.sub(repl, t))


def _mm_html(text: str, anchors: dict[str, str]) -> str:
    """A metamodel page body (or a summary line) as HTML."""
    return render.sanitize_html(render.wrap_tables(md.markdown(_mm_wikilinks(render._unwrap_prose(text or ""), anchors),
                                                 extensions=["extra", "sane_lists"])))


def _mm_inline(text: str, anchors: dict[str, str]) -> str:
    """One line of markdown without the wrapping paragraph, for a table cell."""
    html = _mm_html(text, anchors).strip()
    if html.startswith("<p>") and html.endswith("</p>") and html.count("<p>") == 1:
        html = html[3:-4]
    return html


# Which page of a folder serves as the example: the most mature first, then the
# lowest ID — the page a reader would open first anyway.
_MM_EXAMPLE_RANK = {"accepted": 0, "review": 1, "draft": 2,
                    "open": 0, "in-progress": 1, "resolved": 2, "wontfix": 3,
                    "ingested": 0}


def _mm_example(t: dict) -> dict:
    """A live example page for a type: `{count}` plus, when the folder has
    pages, the id / title / url / status of the one that represents it best."""
    folder = str(t.get("folder") or "")
    if folder.startswith("raw/"):
        pages = wiki.load_sources()
        url = lambda p: f"/source/{p.stem}"             # noqa: E731
    else:
        name = Path(folder).name
        pages = wiki.load_folder(name)
        url = lambda p: links_module._page_url(name, p.stem)         # noqa: E731
    if not pages:
        return {"count": 0}
    best = min(pages, key=lambda p: (_MM_EXAMPLE_RANK.get(p.status, 9), p.id))
    return {"count": len(pages), "id": best.id, "title": best.title, "url": url(best),
            "status": best.status, "stereotype": best.meta.get("stereotype") or "",
            "notation": best.meta.get("notation") or "", "level": best.meta.get("level") or ""}


def build_metamodel_graph(mm: dict) -> dict:
    """The metamodel as cytoscape elements: one node per type, a compound
    parent per framework block that holds a type, one directed edge per
    declared relation edge between two named types. Relations declared on
    `any` (sources, related) would connect everything to everything, so they
    are returned separately as `universal` and the page states them in words.
    Pure and dict-only, so it is testable without a request."""
    nodes: list[dict] = []
    edges: list[dict] = []
    by_name = {t["name"]: t for t in mm["types"]}
    used_blocks = {t.get("block") for t in mm["types"] if t.get("block")}
    for b in mm["blocks"]:
        if b["id"] in used_blocks:
            nodes.append({"data": {"id": f"block:{b['id']}", "label": f"{b['id']} · {b['title']}",
                                   "is_block": True, "area": b.get("area") or ""}})
    for t in mm["types"]:
        d = {"id": t["name"], "label": t.get("label") or t["name"], "prefix": t.get("prefix") or "",
             "label_de": t.get("label_de") or "", "url": f"#type-{t['name']}",
             "stereotypes": ", ".join(t.get("stereotypes") or []), "block_id": t.get("block") or ""}
        if t.get("block"):
            d["parent"] = f"block:{t['block']}"
        nodes.append({"data": d})
    universal: list[dict] = []
    loops: dict[str, int] = {}
    for r in mm["relations"]:
        for e in r.get("edges") or []:
            src, tgt = e.get("from"), e.get("to")
            if src == "any" or tgt == "any":
                universal.append({"field": r["field"], "from": src, "to": tgt,
                                  "direction": r.get("direction"), "cardinality": e.get("cardinality") or "",
                                  "note": e.get("note") or ""})
                continue
            if src not in by_name or tgt not in by_name:
                continue
            d = {"id": f"e{len(edges)}", "source": src, "target": tgt, "label": r["field"],
                 "cardinality": str(e.get("cardinality") or ""), "semantics": r.get("semantics") or "",
                 "symmetric": r.get("direction") == "symmetric", "note": e.get("note") or ""}
            if src == tgt:
                # several loops on one node (DM: parent + relationships) fan out
                k = loops.get(src, 0)
                loops[src] = k + 1
                d["loop_dir"] = ("-45deg", "45deg", "135deg", "-135deg")[k % 4]
            edges.append({"data": d})
    return {"nodes": nodes, "edges": edges, "universal": universal}


def _mm_anchor_ref(name: object) -> dict:
    """An anchor a metamodel page names (`anchors:`, `anchor:`): its label and,
    when `_system/anchors/` has it, the in-page link to its entry."""
    a = render.anchor_lookup().get(str(name).strip().lower())
    if not a:
        return {"name": str(name), "href": "", "title": ""}
    return {"name": a["name"], "href": f"#{a['id']}", "title": render.anchor_title(a)}


def build_mm_anchors(mm: dict, anchors: dict[str, str]) -> list[dict]:
    """One entry per method anchor for /metamodel (FR-035): name, definition,
    reference and the types it applies to. A type applies when its page lists
    the anchor under `anchors:` or the anchor's `applies-to` names the type;
    an `applies-to` entry that is no type is shown as written."""
    by_name = {t["name"]: t for t in mm["types"]}
    out = []
    for a in metamodel.method_anchors():
        keys = {a["name"].lower(), a["slug"], *(x.lower() for x in a["aliases"])}
        types = [t["name"] for t in mm["types"]
                 if keys & {str(x).strip().lower() for x in t.get("anchors") or []}]
        other = []
        for entry in a["applies_to"]:
            ref = anchors.get(entry, "")
            if ref.startswith("type-"):
                if ref[5:] not in types:
                    types.append(ref[5:])
            else:
                other.append(entry)
        out.append({
            "id": a["id"], "name": a["name"],
            "aliases": [x for x in a["aliases"] if x.lower() != a["name"].lower()],
            "definition_html": _mm_inline(a["definition"], anchors),
            "reference": a["reference"],
            # a definition that already cites its reference does not repeat it
            "show_reference": bool(a["reference"]) and a["reference"] not in a["definition"],
            "types": [{"label": _mm_type_label(n, by_name), "href": f"#type-{n}"} for n in types],
            "other": other,
        })
    return out


def _mm_type_label(name: object, by_name: dict) -> str:
    if name == "any":
        return "any page"
    t = by_name.get(str(name))
    return t.get("label") if t else str(name)


@app.route("/metamodel")
def metamodel_view():
    """The metamodel, explained: graph + tables, every cell from
    `_system/metamodel/` and every example from the live wiki (DR-035)."""
    mm = metamodel.load()
    anchors = metamodel.anchors(mm)
    by_name = {t["name"]: t for t in mm["types"]}
    meta = mm["meta"]
    universal_fields = [{**f, "doc_html": _mm_inline(str(f.get("doc") or ""), anchors)}
                        for f in meta.get("universal_fields") or []]

    types = []
    for t in mm["types"]:
        fields = []
        # a type page lists only its own fields; a non-universal one (Source)
        # lists all of them, because the universal set does not apply to it
        for f in t.get("fields") or []:
            fields.append({
                "name": f.get("name"), "kind": f.get("kind") or "", "values": f.get("values") or [],
                "required": bool(f.get("required")), "relation": f.get("relation") or "",
                "doc": _mm_inline(str(f.get("doc") or ""), anchors),
            })
        types.append({
            "name": t["name"], "anchor": f"type-{t['name']}", "prefix": t.get("prefix") or "",
            "label": t.get("label") or t["name"], "label_de": t.get("label_de") or "",
            "block": t.get("block") or "", "block_title": t.get("block_title") or "",
            "folder": t.get("folder") or "", "template": t.get("template") or "",
            "lifecycle": t.get("lifecycle") or "", "stereotypes": t.get("stereotypes") or [],
            "naming": t.get("naming") or "", "universal": t.get("universal", True),
            "fields": fields, "anchors": [_mm_anchor_ref(a) for a in t.get("anchors") or []],
            "projections": t.get("projections") or [],
            "summary_html": _mm_inline(t.get("_summary") or "", anchors),
            "example": _mm_example(t),
        })

    relations = []
    for r in mm["relations"]:
        relations.append({
            "name": r["name"], "anchor": f"rel-{r['name']}", "field": r.get("field") or r["name"],
            "direction": r.get("direction") or "", "semantics": r.get("semantics") or "",
            "inverse": r.get("inverse") or "", "inverse_stored": bool(r.get("inverse_stored")),
            "inverse_field": r.get("inverse_field") or "", "reciprocity": r.get("reciprocity") or "none",
            "edges": [{"from": _mm_type_label(e.get("from"), by_name), "to": _mm_type_label(e.get("to"), by_name),
                       "from_anchor": anchors.get(str(e.get("from")), ""), "to_anchor": anchors.get(str(e.get("to")), ""),
                       "cardinality": str(e.get("cardinality") or ""),
                       "note": _mm_inline(str(e.get("note") or ""), anchors)}
                      for e in r.get("edges") or []],
            "summary_html": _mm_inline(r.get("_summary") or "", anchors),
        })

    projections = []
    for pr in mm["projections"]:
        impl = str(pr.get("implemented") or "none")
        m = _MM_ROUTE_RE.match(impl)
        projections.append({
            "name": pr["name"], "anchor": f"proj-{pr['name']}", "output": pr.get("output") or "",
            "reads": [{"type": _mm_type_label(rd.get("type"), by_name),
                       "type_anchor": anchors.get(str(rd.get("type")), ""),
                       "fields": rd.get("fields") or []} for rd in pr.get("reads") or []],
            "implemented": impl, "href": m.group(1) if m else "",
            "anchor_ref": _mm_anchor_ref(pr["anchor"]) if pr.get("anchor") else None,
            "decisions_html": ", ".join(_mm_dr_link(d.strip(), d.strip()[:6])
                                        for d in str(pr.get("decision") or "").split(",") if d.strip()),
            "summary_html": _mm_inline(pr.get("_summary") or "", anchors),
        })

    # requirement notations (DR-038): the default one first, then by name.
    # Names compare without case, as an FR's `notation:` does (_fr_notation).
    default_notation = settings.wiki_config()["default_notation"]
    notations = []
    for n in sorted(mm["notations"], key=lambda n: (n["name"].lower() != default_notation,
                                                    n["name"].lower())):
        notations.append({
            "name": n["name"], "anchor": f"notation-{n['name']}",
            "title": n.get("title") or n["name"], "default": n["name"].lower() == default_notation,
            "levels": n.get("levels") or [],
            "sections": n.get("_sections") or [],
            "fields": [f for f in n.get("fields") or [] if isinstance(f, dict)],
            "summary_html": _mm_inline(str(n.get("summary") or ""), anchors),
        })

    def _qualifier(ap: dict) -> str:
        # a rule may narrow its type by stereotype, notation and level
        parts = []
        for key in ("stereotype", "notation", "level"):
            v = ap.get(key)
            if v:
                parts.append(f"{key} " + ", ".join(str(x) for x in (v if isinstance(v, list) else [v])))
        return "; ".join(parts)

    rules = []
    for ru in mm["rules"]:
        ap = ru.get("applies_to") or {}
        rules.append({
            "name": ru["name"], "anchor": f"rule-{ru['name']}",
            "applies_type": _mm_type_label(ap.get("type"), by_name),
            "applies_anchor": anchors.get(str(ap.get("type")), ""),
            "applies_qualifier": _qualifier(ap),
            "check": _mm_inline(str(ru.get("check") or ""), anchors),
            "confidence": ru.get("confidence") or "", "action": ru.get("action") or "",
            "source": ru.get("source") or "",
            "summary_html": _mm_inline(ru.get("_summary") or "", anchors),
        })

    graph = build_metamodel_graph(mm)
    n_in = sum(1 for b in mm["blocks"] if b.get("scope") == "in")
    return render_template(
        "metamodel.html", present=mm["present"], types=types, relations=relations,
        projections=projections, notations=notations, rules=rules, graph=graph,
        method_anchors=build_mm_anchors(mm, anchors),
        universal=graph["universal"], universal_fields=universal_fields,
        lifecycles=meta.get("lifecycles") or {}, constructs=meta.get("constructs") or [],
        field_kinds=meta.get("field_kinds") or [],
        frameworks=mm["frameworks"], n_blocks_in=n_in, n_blocks=len(mm["blocks"]),
        n_examples=sum(1 for t in types if t["example"]["count"]),
        decision_html=_mm_dr_link("DR-035-explicit-metamodel", "DR-035"),
    )


def _about_path() -> Path | None:
    return settings.about_doc(wiki._config_data().get("about"))


# Relative src/href in the rendered page → /about/files/<path under docs/>, so
# the images the about page links to load; absolute URLs, anchors and mailto
# stay as they are.
_REL_URL = re.compile(r'(\s(?:src|href)=")(?![a-z][a-z0-9+.-]*:|/|#)([^"]+)"')


def _about_url(page: Path, url: str) -> str:
    """`url`, relative to `page`, as an /about/files/ route. It is resolved
    against the page's folder here, not left to the browser: `../shared.svg`
    would otherwise become `/about/files/../shared.svg`, which the browser
    turns into `/about/shared.svg`. A URL leading out of docs/ is left as is."""
    target = re.split(r"[?#]", url, maxsplit=1)[0]
    if not target:
        return url
    root = settings.DOCS_DIR.resolve()
    path = (page.parent / unquote(target)).resolve()
    if root not in path.parents:
        return url
    return f"/about/files/{quote(path.relative_to(root).as_posix())}{url[len(target):]}"


@app.route("/about")
def about_view():
    """The project's own About page (`about:` in wiki.yaml), e.g. the brand
    guide explaining the system's name and mark. 404 while none is set."""
    path = _about_path()
    if path is None:
        abort(404)
    html = render.sanitize_html(render.wrap_tables(md.markdown(path.read_text(encoding="utf-8", errors="replace"),
                                                 extensions=["extra", "sane_lists"])), about=True)
    html = _REL_URL.sub(lambda m: f'{m.group(1)}{_about_url(path, m.group(2))}"', html)
    title = settings.wiki_config()["about_label"]
    return render_template("about.html", html=html, title=title)


@app.route("/about/files/<path:name>")
def about_file(name):
    """Files the about page links to (images, SVGs) — inside docs/ only."""
    if _about_path() is None:
        abort(404)
    path = settings.docs_file(name)
    if path is None:
        abort(404)
    return _inert_file(send_file(path))


if __name__ == "__main__":
    session.start_lifecycle()
    app.run(host="0.0.0.0", port=8000, threaded=True)
