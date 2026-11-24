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
import socket
import time
import zlib
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import markdown as md
from flask import (Flask, abort, g, has_request_context, jsonify, make_response,
                   redirect, render_template, request, send_file, url_for)
from markupsafe import escape

import catalog  # the section catalog (DR-033)
import metamodel  # reader for _system/metamodel/ (DR-035)
import render  # sanitizer, wikilinks and Markdown
import search  # search records
import session  # presence, the Keyholder role, the view and the lifecycle
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import wiki  # paths, pages, parse cache and loaders
import project.architecture  # decisions, building blocks, runtime, deployment, traces
import project.common  # what several projections share
import project.context  # the context diagram and its flows
import project.goals  # vision, objectives and goal coverage
import project.requirements  # requirement hierarchy, its Mermaid trees, quality scenarios
import project.terms  # term network, relations and entity diagram

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


def dashboard_config() -> dict:
    """`hidden`: the view's area keys / section IDs, in catalog order."""
    return {"hidden": list(session._view_hidden)}


def is_hidden(key_or_id: str) -> bool:
    hidden = set(dashboard_config()["hidden"])
    if key_or_id in hidden:
        return True
    s = catalog.SECTION_BY_ID.get(key_or_id)
    return bool(s and s["area"] in hidden)


def visible_areas() -> list[dict]:
    return [a for a in catalog.AREAS if not is_hidden(a["key"])]


def visible_sections(area_key: str) -> list[dict]:
    return [s for s in catalog.sections_of(area_key) if not is_hidden(s["id"])]


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


DEFAULT_SYSTEM_NAME = "Requirements Wiki"

# The dashboard's own release, shown in the footer.
try:
    DASHBOARD_VERSION = (Path(__file__).resolve().parent / "VERSION").read_text(encoding="utf-8").strip()
except OSError:
    DASHBOARD_VERSION = ""

# Brands: marks, favicon and an optional intro (contract: brands/README.md).
# One brand ships in brands/; a wiki may name its own folder instead.
BRANDS_DIR = Path(__file__).resolve().parent / "brands"
EXAMPLE_BRANDS = ("systems42",)
DEFAULT_BRAND = "systems42"
BRAND_MARKS = ("mark-dark.svg", "mark-light.svg", "favicon.svg")
BRAND_INTRO = "intro.html"


def _intro_on(value) -> bool:
    """`intro:` in wiki.yaml. YAML reads a bare `off` as False, a quoted one
    as a string, so both count. Missing or anything else means on."""
    if value is False:
        return False
    return str(value).strip().lower() not in ("off", "false", "no", "0")

def wiki_config() -> dict:
    """Project identity from `_system/wiki.yaml`.

    Returns `system_name` (never empty — falls back to DEFAULT_SYSTEM_NAME),
    `system_name_set` (False while the vault is still unnamed) and `tagline`.
    A missing, empty or malformed file yields the defaults rather than an
    error: an unnamed vault is the normal state on day one.

    The vault ships named `Systems42` and that is a real name, not a
    placeholder — renaming it is bootstrap.md step 1, and the workflow is where
    that is asked for. The dashboard does not second-guess the configured name.
    """
    data = wiki._config_data()
    name = str(data.get("system_name") or "").strip()
    about = about_doc(data.get("about"))
    version = data.get("dashboard_version")
    if version is not None and not isinstance(version, str):
        # unquoted, YAML reads 1.10 as the float 1.1
        _config_warning(f"dashboard_version: {version!r} is not text, quote it, e.g. \"1.10.0\"")
    brand = data.get("brand")
    if brand is not None and not isinstance(brand, str):
        _config_warning(f"brand: {brand!r}: brand must be a name or a folder path, showing {DEFAULT_BRAND}")
        brand = None
    return {
        "brand": (brand or "").strip() or DEFAULT_BRAND,
        "intro": _intro_on(data.get("intro")),
        "dashboard_version": "" if version is None else str(version).strip(),
        "system_name": name or DEFAULT_SYSTEM_NAME,
        "system_name_set": bool(name),
        "tagline": str(data.get("tagline") or "").strip(),
        # /about exists only while `about:` names a readable file under docs/
        "about_href": "/about" if about else "",
        "about_label": str(data.get("about_label") or "").strip()
                       or f"About {name or DEFAULT_SYSTEM_NAME}",
        # the notation new functional requirements get (FR-004, DR-038); agile when unset
        "default_notation": str(data.get("default_notation") or "").strip().lower() or "agile",
    }


# Project documentation (`docs/`), mounted read-only. Only `/about` reads it:
# the page `about:` in wiki.yaml names, plus the files that page links to.
_env_docs = os.environ.get("DOCS_DIR")
DOCS_DIR = Path(_env_docs) if _env_docs else wiki.REPO_DIR / "docs"


def about_doc(value) -> Path | None:
    """The markdown file `about:` names (`docs/...`, vault-relative), or None.

    Anything outside docs/, missing, or not markdown yields None, so a wrong
    entry hides the About link instead of breaking the home page."""
    rel = str(value or "").strip().lstrip("/")
    if not rel.startswith("docs/") or not rel.endswith(".md"):
        return None
    return docs_file(rel[len("docs/"):])


def docs_file(rel: str) -> Path | None:
    """`rel` (relative to docs/) as a file inside docs/, or None.

    Resolved before the check, so neither `..` nor a symlink pointing out of
    docs/ gets past it."""
    root = DOCS_DIR.resolve()
    path = (root / rel).resolve()
    return path if root in path.parents and path.is_file() else None


_config_warned: set[str] = set()


def _config_warning(message: str) -> None:
    """Log a wiki.yaml problem once per process, not on every request."""
    if message not in _config_warned:
        _config_warned.add(message)
        app.logger.warning(message)


def brand_dir(value: str) -> Path:
    """The folder of the brand `brand:` names, resolved and checked.

    The shipped brand name wins, anything else is a folder relative to the
    wiki repository root. A folder that leaves the root (`..`, an absolute
    path, a symlink) or lacks one of the three marks yields the default
    brand and a log warning. The folder is only ever read (CON-002)."""
    default = BRANDS_DIR / DEFAULT_BRAND
    name = str(value or "").strip() or DEFAULT_BRAND
    if name in EXAMPLE_BRANDS:
        return BRANDS_DIR / name
    root = wiki.REPO_DIR.resolve()
    path = (root / name).resolve()
    if not wiki._inside(root, path):
        _config_warning(f"brand: {name!r} is outside the wiki repository, showing {DEFAULT_BRAND}")
        return default
    if not path.is_dir():
        _config_warning(f"brand: {name!r} is no folder in the wiki repository, showing {DEFAULT_BRAND}")
        return default
    missing = [f for f in BRAND_MARKS if _brand_file(path, f) is None]
    if missing:
        _config_warning(f"brand: {name!r} lacks {', '.join(missing)}, showing {DEFAULT_BRAND}")
        return default
    return path


def _brand_file(folder: Path, name: str) -> Path | None:
    """`folder/name` if it is a file that stays inside `folder`, else None."""
    path = (folder / name).resolve()
    return path if path.parent == folder.resolve() and path.is_file() else None


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


def _brand_checksum(path: Path | None) -> str:
    try:
        return f"{zlib.crc32(path.read_bytes()):08x}"
    except (OSError, AttributeError):
        return ""


def _brand_url(folder: Path, name: str) -> str:
    """/brand/<name> with a content checksum, so switching brands or editing
    a mark changes the URL and the browser cannot show a cached one."""
    v = _brand_checksum(_brand_file(folder, name))
    return f"/brand/{name}?v={v}" if v else f"/brand/{name}"


@app.context_processor
def inject_identity():
    """Make the project identity and the active brand available to every
    template. `active_brand.intro_url` is the address of the brand's intro
    (brand_intro), or "" when there is none or `intro: off`."""
    cfg = wiki_config()
    folder = brand_dir(cfg["brand"])
    intro = _brand_file(folder, BRAND_INTRO) if cfg["intro"] else None
    cfg["active_brand"] = {
        "mark_dark": _brand_url(folder, "mark-dark.svg"),
        "mark_light": _brand_url(folder, "mark-light.svg"),
        "favicon": _brand_url(folder, "favicon.svg"),
        "intro_url": _brand_url(folder, BRAND_INTRO) if intro else "",
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
    cfg = wiki_config()
    path = _brand_file(brand_dir(cfg["brand"]), BRAND_INTRO) if cfg["intro"] else None
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
    if name not in BRAND_MARKS:
        abort(404)
    path = _brand_file(brand_dir(wiki_config()["brand"]), name)
    if path is None:
        abort(404)
    # The page links each mark with its checksum. When ?v= matches, the file
    # behind this URL never changes, so the browser may keep it for a year.
    # Any other request revalidates, so a stale ?v= never sticks.
    fresh = request.args.get("v") == _brand_checksum(path)
    return _inert_file(send_file(path, mimetype="image/svg+xml", max_age=31536000 if fresh else 0))


@app.context_processor
def inject_area():
    """The area the current page belongs to (None on home, help…), for
    the breadcrumb's area level and the colour bar. A hidden area yields None
    so its bar disappears while its pages stay reachable by URL."""
    if not has_request_context():
        return {"current_area": None}
    area = catalog.area_for_path(request.path)
    if area and is_hidden(area["key"]):
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
        own = bool(here) and any(k == here["id"] and not is_hidden(k) for k, _, _ in _nav_entries())
        return bool(area and area["key"] == key and not own)
    return bool(here and here["id"] == key) or path.startswith(href)


@app.context_processor
def inject_nav():
    """`nav_items` for base.html: (href, label, current), hidden entries dropped."""
    if not has_request_context():
        return {"nav_items": [(h, l, False) for _, h, l in _nav_entries()]}
    area = catalog.area_for_path(request.path)
    return {"nav_items": [(h, l, _nav_current(k, h, request.path, area))
                          for k, h, l in _nav_entries() if not is_hidden(k)]}


def static_url(filename: str) -> str:
    """`url_for('static', ...)` with the file's own mtime as a cache buster.

    Flask serves static files with a long-lived cache header, so an edited
    stylesheet or script keeps rendering from the browser's cache until
    someone thinks to hard-refresh — the one kind of staleness a server-side
    cache flush cannot reach. Stamping the mtime makes the URL change exactly
    when the file does. A missing file falls back to the plain URL: a 404 is
    the honest answer there, not a crash mid-render."""
    url = url_for("static", filename=filename)
    try:
        mtime = int((Path(app.static_folder) / filename).stat().st_mtime)
    except OSError:
        return url
    return f"{url}?v={mtime}"


app.jinja_env.globals["static_url"] = static_url


# Multi-column sort presets per type (FR-021). They are presentation, so they
# live here and not in the metamodel (CON-006). `keys` are field names, most
# significant first; each sorts in its column's natural direction.
SORT_PRESETS: dict[str, list[dict]] = {
    "functional-requirement": [{"label": "Priority › release › order", "keys": ["priority", "release", "order"]}],
    "issue": [{"label": "Status › severity", "keys": ["status", "severity"]}],
    "decision-record": [{"label": "Newest first", "keys": ["decided"]}],
    "domain-term": [{"label": "A to Z", "keys": ["title"]}],
    "stakeholder": [{"label": "Influence › interest", "keys": ["influence", "interest"]}],
    "quality-requirement": [{"label": "Priority", "keys": ["priority"]}],
}


def sort_presets(type_name: str) -> list[dict]:
    """The presets a type's list offers, as copies. A type without presets
    sorts by single columns only. A preset key the pages lack is skipped by
    static/list-view.js."""
    return [{"label": p["label"], "keys": list(p["keys"])} for p in SORT_PRESETS.get(type_name, [])]


def list_spec(type_name: str) -> dict:
    """What a section list declares for static/list-view.js (FR-021): its type
    and the sort presets the dashboard offers for it."""
    return {"type": type_name, "orders": sort_presets(type_name)}


app.jinja_env.globals["list_spec"] = list_spec
# the folder a type's pages live in, for the hints that name it (CON-006)
app.jinja_env.globals["type_folder"] = catalog.folder


def _relative_when(ts: float, now: float | None = None) -> str:
    """'just now' / '12 min ago' / '3 h ago' / '2026-09-06' — coarse on purpose."""
    now = time.time() if now is None else now
    d = max(0, int(now - ts))
    if d < 60:
        return "just now"
    if d < 3600:
        return f"{d // 60} min ago"
    if d < 86400:
        return f"{d // 3600} h ago"
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def recent_changes(n: int | None = 5) -> list[dict]:
    """The n most recently modified wiki pages (file mtime — the cheapest
    'what changed' there is; the vault is regenerated a few times per
    workshop, nobody watches it live)."""
    pages = sorted(wiki.load_all_pages(), key=lambda p: -p.mtime)[:n]
    return [{"id": p.id, "title": p.title, "kind": catalog.label(p.folder),
             "url": links_module._page_url(p.folder, p.stem), "when": _relative_when(p.mtime)} for p in pages]


def vault_status() -> dict:
    """The one-line state of the vault under the hero: how much is captured,
    what is still open, how much source material it rests on, and how fresh
    the whole thing is."""
    pages = wiki.load_all_pages()
    issues = wiki.load_type("issue")
    last = max((p.mtime for p in pages), default=0.0)
    return {"pages": len(pages),
            "open_issues": sum(1 for i in issues if project.common.is_open_issue(i.status)),
            "sources": len(wiki.load_sources()),
            "last_change": _relative_when(last) if last else "—"}


@app.route("/arc42/building-blocks")
def building_blocks_view():
    """A2 Building Block View: the level tree and the level-1 white box."""
    block = catalog.SECTION_BY_SLUG.get("building-blocks") or abort(404)
    pages = wiki.load_type("building-block")
    rows = [_arch_row(p) for p in sorted(pages, key=lambda q: q.id)]
    return render_template(
        "building_blocks.html", block=block, tree=project.architecture.build_bb_tree(), total=len(pages),
        whitebox=project.architecture.build_whitebox(None), maturity=project.common.maturity(p.status for p in pages), rows=rows,
    )


_CONCEPT_CATEGORIES = [
    ("domain", "Domain"), ("user-experience", "User experience"), ("safety-security", "Safety & security"),
    ("patterns", "Architecture & design patterns"), ("under-the-hood", "Under the hood"),
    ("development", "Development"), ("operations", "Operations"),
]


def _arch_row(p: wiki.Page) -> dict:
    return {"id": p.id, "title": p.title, "status": p.status, "state": project.architecture.page_state(p),
            "url": links_module._page_url(p.folder, p.stem)}


@app.route("/arc42/strategy")
def strategy_view():
    """A1 Solution Strategy: every strategy page, marked by state, with what it
    answers and the decisions it summarises."""
    block = catalog.SECTION_BY_SLUG.get("strategy") or abort(404)
    pages = sorted(wiki.load_type("solution-strategy"), key=lambda q: q.id)
    rows = []
    for p in pages:
        row = _arch_row(p)
        row["drivers"] = project.architecture._link_groups(links_module.links_of(p, "drivers"))
        row["decisions"] = project.architecture._link_groups(links_module.links_of(p, "decisions"))
        row["replaced_by"] = project.architecture._link_groups(links_module.links_of(p, "superseded-by"))
        rows.append(row)
    return render_template("strategy.html", block=block, rows=rows, total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


@app.route("/arc42/concepts")
def concepts_view():
    """A5 Crosscutting Concepts: grouped by arc42 topic, with what each governs."""
    block = catalog.SECTION_BY_SLUG.get("concepts") or abort(404)
    pages = sorted(wiki.load_type("crosscutting-concept"), key=lambda q: q.id)
    known = dict(_CONCEPT_CATEGORIES)
    groups = []
    for key, label in _CONCEPT_CATEGORIES + [(None, "Uncategorised")]:
        rows = []
        for p in pages:
            raw = str(p.meta.get("category") or "").strip()
            cat = raw.lower()
            if (cat if cat in known else None) != key:
                continue
            row = _arch_row(p)
            row["unknown_category"] = raw if raw and cat not in known else ""
            row["applies_to"] = project.architecture._link_groups(links_module.links_of(p, "applies-to"))
            rows.append(row)
        if rows:
            groups.append({"label": label, "rows": rows})
    flat = []
    for p in pages:
        row = _arch_row(p)
        raw = str(p.meta.get("category") or "").strip()
        row["category"] = known.get(raw.lower(), raw)
        flat.append(row)
    return render_template("concepts.html", block=block, groups=groups, total=len(pages),
                           rows=flat, maturity=project.common.maturity(p.status for p in pages))


@app.route("/arc42/runtime")
def runtime_view():
    """A4 Runtime View: the scenarios and the requirements they realise."""
    block = catalog.SECTION_BY_SLUG.get("runtime") or abort(404)
    pages = sorted(wiki.load_type("runtime-scenario"), key=lambda q: q.id)
    rows = []
    for p in pages:
        row = _arch_row(p)
        row["realizes"] = project.architecture._link_groups(links_module.links_of(p, "realizes"))
        row["steps"] = len(project.architecture.steps_of(p))
        rows.append(row)
    return render_template("runtime.html", block=block, rows=rows, total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


@app.route("/arc42/deployment")
def deployment_view():
    """A3 Deployment View: one projected diagram of everything relevant today —
    existing, planned and replaced — and the node levels."""
    block = catalog.SECTION_BY_SLUG.get("deployment") or abort(404)
    pages = wiki.load_type("deployment-node")
    rows = []
    for p in sorted(pages, key=lambda q: q.id):
        row = _arch_row(p)
        row["stereotype"] = str(p.meta.get("stereotype") or "").strip()
        rows.append(row)
    diagram_links: list[dict] = []
    diagram = project.architecture.build_deployment_diagram(links=diagram_links)
    return render_template("deployment.html", block=block, diagram=diagram,
                           diagram_links=[l for l in diagram_links
                                          if not l["url"].startswith(f"/page/{catalog.folder('deployment-node')}/")],
                           hints=project.architecture.deployment_hints(), rows=rows,
                           tree=project.architecture.build_node_tree(), total=len(pages),
                           maturity=project.common.maturity(p.status for p in pages))


# --- views -----------------------------------------------------------------

def build_section_tile(section: dict) -> dict:
    """The tile payload for one catalog section, keyed by section ID: a count,
    the maturity bar and the open-issue flag, nothing more (FR-019). The
    count is what the unit says: R4 counts model pages, C3 external
    interfaces, C6 all issues with the open ones as its flag."""
    sid = section["id"]
    folders = list(section["folders"])
    base = {"key": sid.lower(), "id": sid, "label": section["title"],
            "eyebrow": f"{sid} · {section['title']}", "href": section["href"],
            "folders": folders, "scope": section["scope"],
            "colors": section["colors"], "note": section["note"],
            "links": [], "active": section["scope"] == "in",
            "unit": "page", "unit_many": None, "count": 0}
    if section["scope"] != "in":
        base["maturity"] = project.common.maturity([])
        base["open_issues"] = 0
        return base
    pages = [p for f in folders for p in wiki.load_folder(f)]
    flags = project.common.open_issue_counts()
    # union, not sum: an issue linking pages in two of this section's folders
    # must count once, not twice.
    t = {**base, "count": len(pages), "maturity": project.common.maturity(p.status for p in pages),
         "open_issues": len(set().union(*(flags.get(f, set()) for f in folders))),
         "open_issues_href": f"/issues?section={sid}",
         "open_issues_title": "Show the open issues that point at pages of this section"}
    if sid == "R1":
        t["unit"] = "goal"
    elif sid == "R3":
        # every functional requirement of every notation (DR-038)
        t["unit"] = "requirement"
    elif sid == "R4":
        t.update({"unit": "model page",
                  "count": project.terms.supporting_model_count()})
    elif sid == "C1":
        t["unit"] = "scenario"
    elif sid == "C2":
        t["unit"] = "constraint"
    elif sid == "C3":
        # folders carries both (maturity and issue flags span the context page
        # too), but the headline number is what the unit says: interfaces.
        t.update({"unit": "external interface", "count": len(wiki.load_type("external-interface"))})
    elif sid == "C4":
        t["unit"] = "persona"
    elif sid == "C5":
        t.update({"unit": "term",
                  "links": [{"label": "Table", "href": "/domain-terms"},
                            {"label": "Term network", "href": "/graph/domain-terms"}]})
    elif sid == "C6":
        t.update({"unit": "issue",
                  "open_issues": sum(1 for i in pages if project.common.is_open_issue(i.status)),
                  "open_issues_href": "/issues?status=open",
                  "open_issues_title": "Show the open issues"})
    return t


def build_area_tile(area: dict) -> dict:
    """Home-page tile for one cabinet: count, maturity and open-issue flag
    over its visible, captured sections, plus the section list as links, each
    with its section tile's count (FR-018)."""
    sections = visible_sections(area["key"])
    folders = [f for s in sections for f in s["folders"]]
    pages = [p for f in folders for p in wiki.load_folder(f)]
    flags = project.common.open_issue_counts()
    tiles = {s["id"]: build_section_tile(s) for s in sections if s["scope"] == "in"}
    return {
        "key": area["key"], "label": area["label"], "subtitle": area["subtitle"],
        "href": area["href"], "colors": area["colors"],
        "count": len(pages), "maturity": project.common.maturity(p.status for p in pages),
        "open_issues": len(set().union(*(flags.get(f, set()) for f in folders if not wiki._is(f, "issue")))),
        "sections": [{"id": s["id"], "title": s["title"], "href": s["href"], "scope": s["scope"],
                      **({"count": tiles[s["id"]]["count"], "unit": tiles[s["id"]]["unit"],
                          "unit_many": tiles[s["id"]]["unit_many"]} if s["id"] in tiles else {})}
                     for s in sections],
        "planned": not sections or all(s["scope"] == "planned" for s in sections),
    }


def build_valley() -> dict:
    """What the agent did: the vault's state, what moved last, what is open.
    Sits between the two peaks on the home page (DR-033)."""
    issues = wiki.load_type("issue")
    open_issues = sorted((i for i in issues if project.common.is_open_issue(i.status)),
                         key=lambda i: ({"blocker": 0, "major": 1, "minor": 2}
                                        .get(str(i.meta.get("severity") or ""), 3), i.id))
    return {
        "status": vault_status(),
        "changes": recent_changes(4),
        "open_issues": [{"id": i.id, "title": i.title, "stem": i.stem,
                         "url": links_module._page_url(i.folder, i.stem),
                         "severity": str(i.meta.get("severity") or "")} for i in open_issues[:5]],
        "open_total": len(open_issues),
        "decision_count": len(wiki.load_type("decision-record")),
    }


@app.route("/")
def index():
    """Home: Requirements and Architecture as two peaks, the valley between
    them showing the agent's work, Commons as the ground both stand on."""
    areas = {a["key"]: build_area_tile(a) for a in visible_areas()}
    join_url = public_url()
    return render_template("index.html", areas=areas, valley=build_valley(),
                           vision_sentence=project.goals.vision_sentence(project.goals.vision_page(), links_module.title_index()),
                           join_url=join_url, join_qr=qr_svg(join_url))


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


@app.route("/changes")
def changes_view():
    """Every wiki page, most recently changed first. The first page shows the
    last few and links here (FR-018)."""
    return render_template("changes.html", changes=recent_changes(None))


@app.route("/domain-terms")
def glossary_view():
    titles = links_module.title_index()
    links = links_module.link_index()       # so definition wikilinks render as real hyperlinks
    pages = project.terms.domain_terms()
    rows = []
    for p in pages:
        rows.append({
            "id": p.id,
            "kind": project.terms.term_kind(p),
            "stem": p.stem,
            "folder": p.folder,
            "title": p.title,
            "aliases": p.aliases,
            "definition": render.extract_labeled(p, "Definition", titles, links),
            "relations": len(links_module.linked_stems(p)),
            "status": p.status,
            "created": str(p.meta.get("created", "")),
            "updated": str(p.meta.get("updated", "")),
            "assumption": "[!assumption]" in p.body,
        })
    # Default order is alphabetical by term; other orders are applied client-side.
    rows.sort(key=lambda r: r["title"].lower())
    # the kind filter runs in the browser (static/list-view.js, FR-038)
    return render_template("glossary.html", rows=rows, total=len(rows),
                           kinds=list(project.terms.DOMAIN_MODEL_STEREOTYPES),
                           maturity=project.common.maturity(p.status for p in pages))


@app.route("/graph/domain-terms")
def glossary_graph_view():
    """Force-directed domain term network (DR-023). The graph data is a
    deterministic server projection; cytoscape.js lays it out client-side."""
    edge_filter = request.args.get("edges", "all")
    if edge_filter not in {"all", "related", "structured"}:
        edge_filter = "all"
    graph = project.terms.build_glossary_graph(edge_filter)
    counts = graph["layer_counts"]
    NAMED = [("STK", "Stakeholder"), ("EIF", "Interface"), ("GOAL", "Goals"),
             ("BB", "Building block")]
    named_keys = {k for k, _ in NAMED}
    named_layers = [{"key": k, "label": l, "count": counts[k]}
                    for k, l in NAMED if counts.get(k)]
    rest_keys = sorted(k for k in counts if k not in named_keys)
    rest = {"types": rest_keys, "count": sum(counts[k] for k in rest_keys)}
    n_glo = sum(1 for n in graph["nodes"] if n["data"].get("type") == "DT")
    # every node as a text link under the canvas (QR-001): terms, then the
    # pages the layer buttons add
    def node_links(core: bool) -> list[dict]:
        found = [n["data"] for n in graph["nodes"] if bool(n["data"].get("core")) == core]
        return [{"id": (search._SOURCE_ID_RE.match(d["id"]) or [""])[0], "title": d["label"], "url": d["url"]}
                for d in sorted(found, key=lambda d: d["label"].lower())]
    return render_template("graph.html", graph=graph, n_glo=n_glo,
                           term_links=node_links(True), nearby_links=node_links(False),
                           named_layers=named_layers, rest=rest, edge_filter=edge_filter)


def _issue_owner(p: wiki.Page, titles: dict[str, str],
                 links: dict[str, tuple[str, str]]) -> dict:
    """Who is expected to answer an issue (FR-028): `key` for the filter,
    `label` to show, `url` when it names a wiki page. An empty owner gives
    key "" (nobody yet)."""
    raw = str(project.architecture._scalar(p.meta.get("owner")) or "").strip()
    if raw.lower() in ("", "none", "null"):
        return {"key": "", "label": "", "url": None}
    # "[[stem|label]]" quoted, or "stem|label" when YAML read the unquoted
    # form as a nested list (the template writes it unquoted)
    linked = raw.startswith("[[") and raw.endswith("]]")
    inner = raw[2:-2] if linked else raw
    target, _, alias = (part.strip() for part in inner.partition("|"))
    target = target.split("#")[0].strip()
    if target in links:
        folder, stem = links[target]
        return {"key": stem, "label": alias or titles.get(stem, stem), "url": links_module._page_url(folder, stem)}
    if linked or alias:
        return {"key": raw, "label": alias or target, "url": None}
    return {"key": raw, "label": raw, "url": None}


# ?status= on the issue list: a lifecycle value, or one of these groups
# (open: is_open_issue, closed: the rest)
_ISSUE_STATUS_GROUPS = ("open", "closed")


def issue_fields(p: wiki.Page, titles: dict[str, str], links: dict[str, tuple[str, str]]) -> dict:
    """An issue's own fields as the list and its page show them (FR-025 to
    FR-028). A value outside the metamodel's list comes back empty."""
    vocab = project.common._issue_vocab()
    def known(field: str) -> str:
        v = str(p.meta.get(field) or "").strip()
        return v if v in vocab[field] else ""
    status = p.status if p.status in vocab["status"] else ""
    owner = _issue_owner(p, titles, links)
    return {"status": status, "is_open": project.common.is_open_issue(p.status),
            "severity": known("severity"), "kind": known("kind"), "category": known("category"),
            "owner": owner["label"], "owner_key": owner["key"], "owner_url": owner["url"]}


_SEVERITY_RANK = {"blocker": 0, "major": 1, "minor": 2}


@wiki._request_cached
def _issue_backlinks() -> dict[str, list[dict]]:
    """page stem -> the issues that link to it, by frontmatter or body
    wikilink (FR-027). A mere mention without a link does not count."""
    titles, links = links_module.title_index(), links_module.link_index()
    out: dict[str, list[dict]] = {}
    for iss in wiki.load_type("issue"):
        f = issue_fields(iss, titles, links)
        item = {"id": iss.id, "title": iss.title, "status": f["status"], "severity": f["severity"],
                "is_open": f["is_open"], "url": links_module._page_url(iss.folder, iss.stem)}
        for stem in {links[t][1] for t in iss.link_targets() if t in links}:
            out.setdefault(stem, []).append(item)
    return out


def open_issues_for(stem: str) -> list[dict]:
    """The issues that link to a page, open ones first, then by severity
    (blocker first), then by ID (FR-027)."""
    return sorted(_issue_backlinks().get(stem, []),
                  key=lambda i: (not i["is_open"], _SEVERITY_RANK.get(i["severity"], 3), i["id"]))


@app.route("/issues")
def issues_view():
    """C6: every issue, filtered on the server by status, category, severity,
    section and owner (FR-025). Filters combine and live in the address, so a
    copied link shows the same issues. Unknown values are ignored."""
    titles, links = links_module.title_index(), links_module.link_index()
    pages = sorted(wiki.load_type("issue"), key=lambda x: x.id)
    lifecycle_values = metamodel.lifecycle("issue")
    categories = metamodel.field_values("issue", "category")
    severities = metamodel.field_values("issue", "severity")
    folder_section = {f: s["id"] for s in catalog.SECTIONS for f in s["folders"] if s["id"] != "C6"}

    items = []
    for p in pages:
        sections = sorted({folder_section[links[t][0]] for t in p.link_targets()
                           if t in links and links[t][0] in folder_section})
        items.append({"id": p.id, "title": p.title, **issue_fields(p, titles, links),
                      "sections": sections, "url": links_module._page_url(p.folder, p.stem)})

    # the filters: only known values count, anything else shows every issue
    # one option per owner: a page by its title, whatever alias an issue uses
    owners = sorted({i["owner_key"]: titles.get(i["owner_key"], i["owner"]) if i["owner_url"] else i["owner"]
                     for i in items if i["owner_key"]}.items(), key=lambda o: o[1].lower())
    sections = [s for s in catalog.SECTIONS if s["folders"] and s["id"] != "C6"]
    arg = lambda name: request.args.get(name, "").strip()
    section = catalog.SECTION_BY_ID.get(arg("section").upper())
    if section not in sections:
        section = None
    status = arg("status") or arg("filter")          # ?filter= was the former name
    if status not in lifecycle_values and status not in _ISSUE_STATUS_GROUPS and status != "all":
        status = ""
    if not status:
        # a section's open issue count opens the list with its open issues (FR-019)
        status = "open" if section else "all"
    chosen = {
        "status": status,
        "category": arg("category") if arg("category") in categories else "",
        "severity": arg("severity") if arg("severity") in severities else "",
        "section": section["id"] if section else "",
        "owner": arg("owner") if arg("owner") in {"none"} | {o[0] for o in owners} else "",
    }

    def keep(i: dict) -> bool:
        st = chosen["status"]
        if st == "open" and not i["is_open"] or st == "closed" and i["is_open"]:
            return False
        if st not in ("all", "open", "closed") and i["status"] != st:
            return False
        if chosen["category"] and i["category"] != chosen["category"]:
            return False
        if chosen["severity"] and i["severity"] != chosen["severity"]:
            return False
        if chosen["section"] and chosen["section"] not in i["sections"]:
            return False
        if chosen["owner"] and i["owner_key"] != ("" if chosen["owner"] == "none" else chosen["owner"]):
            return False
        return True

    shown = [i for i in items if keep(i)]
    open_count = sum(1 for i in items if i["is_open"])
    filtered = any(v for k, v in chosen.items() if k != "status") or chosen["status"] != "all"
    return render_template(
        "issues.html", items=shown, total=len(items), shown=len(shown), filtered=filtered,
        open_count=open_count, section=section, chosen=chosen,
        options={"status": lifecycle_values, "category": categories, "severity": severities,
                 "section": sections, "owner": owners},
        sort=arg("sort"),
        maturity=project.common.maturity(p.status for p in pages),
    )


@app.route("/stakeholders")
def stakeholders_view():
    titles = links_module.title_index()
    links = links_module.link_index()       # snapshot wikilinks become real hyperlinks
    by_stem = {q.stem: q for q in wiki.load_all_pages()}   # resolve related domain terms
    pages = sorted(wiki.load_type("stakeholder"), key=lambda x: x.id)
    _REL_MAX = 6               # cap chips per row; rest is one click away on the detail page
    rows = []
    for p in pages:
        # domain terms the stakeholder points at — quick links to "additional
        # info" (the snapshot's inline links + `related:`), by id.
        rel = []
        for s in sorted(links_module.linked_stems(p)):
            q = by_stem.get(s)
            if q and wiki._is(q.folder, "domain-term"):
                rel.append({"id": q.id, "label": q.title, "type": "DT",
                            "url": f"/page/{q.folder}/{s}"})
        rel.sort(key=lambda r: r["id"])
        rows.append({
            "id": p.id,
            "stem": p.stem,
            "url": links_module._page_url(p.folder, p.stem),
            "title": p.title,
            "role": p.meta.get("role", ""),
            "snapshot": render.extract_labeled(p, "Snapshot", titles, links),
            "influence": str(p.meta.get("influence") or ""),
            "interest": str(p.meta.get("interest") or ""),
            "rel_links": rel[:_REL_MAX],
            "rel_more": max(0, len(rel) - _REL_MAX),
            "status": p.status,
        })
    return render_template("stakeholders.html", rows=rows, total=len(rows),
                           maturity=project.common.maturity(p.status for p in pages))


@app.route("/decisions")
def decisions_view():
    """C7 Decisions: every decision record, filterable by kind (FR-009)."""
    items = project.architecture.load_decisions()
    labels = {"architecture": "Architecture", "business": "Business", "undefined": "Undefined"}
    buckets = [{"key": k, "label": labels[k], "count": sum(1 for d in items if d["kind"] == k)}
               for k in project.architecture.DECISION_KINDS]
    return render_template("decisions.html", items=items, total=len(items), buckets=buckets,
                           maturity=project.common.maturity(d["status"] for d in items))


def _is_wiki_folder(folder: str) -> bool:
    """True when `folder` is a direct, non-hidden subfolder of WIKI_DIR that,
    symlinks resolved, stays inside it."""
    if not folder or folder.startswith(".") or "/" in folder or "\\" in folder:
        return False
    d = wiki.WIKI_DIR / folder
    return d.is_dir() and wiki._resolves_inside(wiki.WIKI_DIR, d)


@app.route("/page/<folder>/<stem>")
def page_detail(folder, stem):
    """Detail page for a single content unit (any wiki page). Search results
    link here."""
    titles = links_module.title_index()
    # FRs have their own rich page (full text + hierarchy breakdown) under the
    # functional-requirements/ path; send any /page link there so the whole
    # hierarchy stays on one route.
    if wiki._is(folder, "functional-requirement"):
        return redirect(f"/functional-requirements/{stem}", code=302)

    # `folder` must name one of the wiki's own content folders: the route
    # takes any single path segment, and `..` or `.` would otherwise reach a
    # markdown file beside or above wiki/ (the repository root under
    # `dashboard.sh local`, /repo under Docker).
    if not _is_wiki_folder(folder):
        abort(404)
    path = wiki.WIKI_DIR / folder / f"{stem}.md"
    page = wiki._parse(path, folder) if path.is_file() else None
    if not page:
        abort(404)
    kind = catalog.label(folder)
    # drop the leading "# Title" heading from the body — shown in the page header
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)
    body_html = render.render_markdown(body, titles)
    # context pages carry the system-context diagram, projected live (DR-013)
    diagram_links: list[dict] = []
    context_diagram = project.context.build_context_diagram(wiki_config()["system_name"], links=diagram_links) if wiki._is(folder, "context") else None
    context_flows = project.context.build_context_flows() if wiki._is(folder, "context") else None
    # domain terms carry a focused ego-graph snippet above the definition (DR-023)
    ego_graph = project.terms.build_glossary_ego_graph(stem) if wiki._is(folder, "domain-term") else None
    trace = project.architecture.build_trace(stem, folder)
    whitebox = project.architecture.build_whitebox(stem) if wiki._is(folder, "building-block") else None
    sequence = project.architecture.build_sequence_diagram(stem) if wiki._is(folder, "runtime-scenario") else None
    hints = (project.architecture.runtime_hints(stem) if wiki._is(folder, "runtime-scenario")
             else project.architecture.deployment_hints(stem) if wiki._is(folder, "deployment-node") else [])
    deployment = project.architecture.build_deployment_diagram(stem, diagram_links) if wiki._is(folder, "deployment-node") else None
    ego_layers = None
    if ego_graph:
        c = ego_graph["layer_counts"]
        ego_layers = [{"key": k, "label": l} for k, l in
                      (("STK", "Stakeholder"), ("GOAL", "Goals"), ("BB", "Building block"))
                      if c.get(k)]
        for L in ego_layers:
            L["count"] = c[L["key"]]
    return render_template(
        "detail.html", kind=kind, id=page.id, title=page.title,
        status=page.status, **page_head(page),
        body_html=body_html, **_section_crumb(folder),
        context_diagram=context_diagram, context_flows=context_flows,
        relations=project.terms.build_relations_panel(stem, exclude=project.architecture.trace_stems(trace)),
        trace=trace, whitebox=whitebox,
        state=project.architecture.page_state(page) if wiki._is(folder, *project.architecture.ARCH_TYPES) else None,
        sequence=sequence, hints=hints, deployment=deployment, diagram_links=diagram_links,
        ego_graph=ego_graph, ego_layers=ego_layers,
        needs_mermaid=bool(context_diagram or whitebox or sequence or deployment) or "language-mermaid" in body_html,
        sources=project.common.provenance(page),
        issue=issue_fields(page, titles, links_module.link_index()) if wiki._is(folder, "issue") else None,
        page_issues=open_issues_for(stem),
        formats=render.format_labels(page.body),
        term=project.terms.term_fields(page) if wiki._is(folder, "domain-term") else None,
    )


def page_head(page) -> dict:
    """Created date, updated date and tags for the head of a page (FR-034).
    Every detail view takes them from here and renders them with the
    `page_meta` macro, so no view can leave them out. A date is text as
    written, a blank field is empty."""
    def text(key):
        value = page.meta.get(key)
        return "" if value is None else str(value)
    return {"created": text("created"), "updated": text("updated"), "tags": page.as_list("tags")}


def _section_crumb(folder: str) -> dict:
    """The section level of a wiki page's path (FR-020): where the page
    belongs, not how the reader got there. A folder outside the sections
    gives no section level, so the path reads Home › page."""
    return _crumb_of(catalog.section_for_folder(folder))


def _crumb_of(sec: dict | None) -> dict:
    return {"crumb": sec["title"], "crumb_href": catalog.section_href(sec)} if sec else {"crumb": None, "crumb_href": None}


@app.route("/source/<stem>")
def source_detail(stem):
    """Detail page for one raw/sources/ provenance record: what it is, where it
    came from, and which wiki pages it fed (`ingested-pages:`). Reached from a
    provenance chip on any sourced page; no standalone sources list exists yet,
    so its path is Home › source (FR-020)."""
    src = links_module.source_index().get(stem)
    if not src:
        abort(404)
    titles = links_module.title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", src.body, count=1)
    # frontmatter values are human-entered and never trusted: escape every one
    # before it lands in body_html, which the template renders with `| safe`.
    facts = [("Type", str(src.meta.get("source-type") or "—")),
             ("Origin", str(src.meta.get("origin") or "—")),
             ("Captured", str(src.meta.get("captured") or "—")),
             ("Checksum", str(src.meta.get("sha256") or "—")[:16])]
    facts_html = "".join(f"<dt>{k}</dt><dd>{escape(v)}</dd>" for k, v in facts)
    # each ref is plain text: escaped around its wikilinks, label escaped
    # inside them, so a hostile one comes out as inert entities whether or
    # not it resolves to a real page.
    ingested = ", ".join(render.render_wikilinks_text(str(r), titles, links_module.link_index()) for r in src.as_list("ingested-pages")) or "—"
    body_html = f'<dl class="source-facts">{facts_html}<dt>Ingested pages</dt><dd>{ingested}</dd></dl>' + render.render_markdown(body, titles)
    return render_template("detail.html", kind="Source", id=src.id, title=src.title, status=src.status,
                           **page_head(src), body_html=body_html, crumb=None, crumb_href=None,
                           context_diagram=None, context_flows=None,
                           relations=None, ego_graph=None, ego_layers=None,
                           needs_mermaid=False, sources=None)


@app.route("/search.json")
def search_index():
    """The search index for the topbar's incremental search popup
    (static/search-popup.js); ranked client-side by static/search-rank.js,
    the same code the /search page uses."""
    return jsonify(search.build_search_index())


@app.route("/search")
def search_view():
    """Global search across all wiki content. Results render once and are
    filtered incrementally client-side; type facets allow browsing by content type."""
    index = search.build_search_index()
    tally: dict[str, int] = {}
    for r in index["records"]:
        tally[r["type"]] = tally.get(r["type"], 0) + 1
    facets = sorted(tally.items(), key=lambda kv: (-kv[1], kv[0]))
    return render_template("search.html", index=index, total=len(index["records"]), facets=facets,
                           filters=_search_filters())


_PRIORITY_ORDER = ["must", "should", "could", "wont", "won't"]


def _search_filters() -> dict[str, list[dict]]:
    """The values offered by /search's status, priority and tag filters
    (FR-009): every value some page carries, as {value, label}. The value is
    lower-case, as the ranker compares it; the label is how the wiki writes
    it (the first spelling found)."""
    labels: dict[str, dict[str, str]] = {"status": {}, "priority": {}, "tags": {}}
    for p in wiki.load_all_pages():
        for key, seen in labels.items():
            raw = p.meta.get(key)
            for x in raw if isinstance(raw, list) else [raw]:
                written = str(x).strip() if x is not None else ""
                if written:
                    seen.setdefault(written.lower(), written)   # same value as _search_fields

    def opts(key, order=None):
        vals = labels[key]
        rank = (lambda v: (v not in order, order.index(v) if v in order else 0, v)) if order else None
        return [{"value": v, "label": vals[v]} for v in sorted(vals, key=rank)]
    return {"status": opts("status"), "priority": opts("priority", _PRIORITY_ORDER), "tag": opts("tags")}


@app.route("/goals")
def goals_view():
    """req42 Block 01 — Vision + Objectives. Three sections top-down:
    Mermaid tree, full-text cards (vision then objectives), goal-coverage matrix.
    Goal↔Epic edges are read from each FR's `goal:` field (DR-018)."""
    titles = links_module.title_index()
    links = links_module.link_index()       # vision/objective prose wikilinks become real links
    data = project.goals.load_goals()
    vision, objectives = data["vision"], data["objectives"]
    # the flat, sortable list of every goal page (FR-021)
    goal_rows = [{"id": g.id, "title": g.title, "url": links_module._page_url(g.folder, g.stem),
                  "stereotype": str(g.meta.get("stereotype") or "").strip().lower(),
                  "horizon": str(g.meta.get("horizon") or "").strip(), "status": g.status}
                 for g in ([vision] if vision else []) + objectives]

    def _wikilink_list(items) -> list[str]:
        """Render a frontmatter list of '[[X]]' refs as human-readable labels."""
        out = []
        for x in (items or []):
            s = str(x).strip()
            m = re.match(r"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]", s)
            if not m:
                continue
            target, alias = m.group(1).strip(), m.group(2)
            base = target.split("/")[-1]
            out.append(alias.strip() if alias else titles.get(base, base))
        return out

    if vision:
        vision_card = {
            "id": vision.id,
            "title": vision.title,
            "url": links_module._page_url(vision.folder, vision.stem),
            "stereotype": "Vision",
            "maturity": None,
            "beneficiary": _wikilink_list(vision.as_list("beneficiary")),
            # Vision card shows the prose of the `## Vision` section — the
            # objectives list and impact block from the wiki page are projected
            # below as separate objective cards and the coverage matrix.
            "html": "".join(f"<p>{p}</p>" for p in project.goals._vision_paragraphs(vision, titles, links)),
        }
    else:
        # No `stereotype: vision` page yet: a hint takes the vision's place,
        # and the objective cards and the matrix still show. The route must
        # work on workshop day one.
        vision_card = {
            "id": "", "title": "No vision yet", "stereotype": "Vision",
            "maturity": None, "beneficiary": [],
            "html": "<p>No vision yet — capture a GOAL- page with "
                    "<code>stereotype: vision</code>.</p>",
        }

    def _inline(s) -> str:
        """Frontmatter strings may contain `[[wikilinks]]` — render them as
        real hyperlinks when the target resolves."""
        return render.render_wikilinks_text(str(s or "").strip(), titles, links)

    fr_cols, matrix_rows = project.goals._goal_matrix(data)

    objective_cards = []
    for o in objectives:
        objective_cards.append({
            "id": o.id,
            "title": o.title,
            "url": links_module._page_url(o.folder, o.stem),
            "stereotype": "Goal",
            "purpose": render.extract_pam_bullet(o, "Purpose", titles, links),
            "advantage": render.extract_pam_bullet(o, "Advantage", titles, links),
            "metric": _inline(o.meta.get("metric")),
            "target": _inline(o.meta.get("target")),
            "baseline": _inline(o.meta.get("baseline")),
            "beneficiary": _wikilink_list(o.as_list("beneficiary")),
            # every requirement that serves the goal, features and stories
            # too: a superset of its matrix marks, as text (FR-036)
            "epics": [{"id": p.id, "title": p.title, "url": links_module._page_url(p.folder, p.stem)}
                      for p in data["coverage"].get(o.id, [])],
        })

    diagram = project.goals._mermaid_goal_tree(wiki_config()["system_name"], vision, objectives)
    return render_template(
        "goals.html",
        diagram=diagram,
        vision=vision_card,
        objectives=objective_cards,
        fr_cols=fr_cols,
        matrix_rows=matrix_rows,
        needs_mermaid=bool(diagram),
        goal_rows=goal_rows,
    )


@app.route("/entity-diagram")
def data_model_view():
    """R4 entity diagram: the class diagram of the structured domain terms
    (build_data_model_full_diagram()) plus the per-entity catalog below, every
    section and callout of every structured term on one page."""
    contexts = project.terms.data_model_contexts()
    context = request.args.get("context") or None
    if context not in contexts:
        context = None                     # an unknown filter shows everything
    nodes = project.terms.data_model_nodes()
    focus = request.args.get("focus") or None
    if focus and focus not in {n["key"] for n in nodes}:
        matches = [n["key"] for n in nodes if focus in n["aliases"]]
        focus = matches[0] if len(matches) == 1 else None
    diagram = project.terms.build_data_model_full_diagram(context=context, focus=focus)
    return render_template("data_model.html", diagram=diagram, **_crumb_of(catalog.section_for_path("/entity-diagram")),
                           entities=project.terms.data_model_entities(), nodes=nodes,
                           contexts=contexts, context=context, focus=focus,
                           needs_mermaid=True)


@app.route("/req42", defaults={"area_key": "requirements"})
@app.route("/arc42", defaults={"area_key": "architecture"})
@app.route("/commons", defaults={"area_key": "commons"})
def area_view(area_key):
    """One cabinet of the Systems42 sections diagram: its visible sections as
    tiles (DR-033). Reachable by URL even when the area is hidden — hiding
    removes tiles and links, never pages."""
    area = catalog.AREA_BY_KEY.get(area_key) or abort(404)
    # Hiding the area hides its sections from the home page; here only a
    # section hidden on its own is dropped.
    tiles = [build_section_tile(s) for s in catalog.sections_of(area_key)
             if s["id"] not in dashboard_config()["hidden"]]
    pages = [p for t in tiles for f in t["folders"] for p in wiki.load_folder(f)]
    return render_template("area.html", area=area, tiles=tiles, count=len(pages),
                           maturity=project.common.maturity(p.status for p in pages), needs_mermaid=False)


@app.route("/req42/functional-requirements")
def functional_requirements_view():
    """req42 block 04 — Functional Requirements across notation-specific levels
    (DR-038): the Agile story map (epics, and the use cases Agile features and
    stories refine), then every requirement the story map cannot place.
    A dedicated rich view for the `functional-requirements` slug (the other /req42/<slug> blocks
    use the generic list). Flask matches this static rule ahead of the dynamic
    /req42/<slug>. Doubles as the home `functional-requirements` tile's click-target."""
    hierarchy = project.requirements.build_fr_hierarchy()
    goals = project.goals.load_goals()
    diagram_links: list[dict] = []
    diagram = project.requirements._mermaid_goal_epic_tree(goals, hierarchy, diagram_links)
    block = catalog.SECTION_BY_SLUG.get("functional-requirements") or abort(404)
    # the flat list under the hierarchy (FR-021): every requirement of every
    # notation once, sortable by priority, release and order
    rows = []
    for p in sorted(wiki.load_type("functional-requirement"), key=lambda q: q.id):
        rows.append({"id": p.id, "title": p.title,
                     "url": f"/functional-requirements/{p.stem}",
                     "notation": project.requirements._fr_notation(p), "level": project.requirements._fr_level(p),
                     "priority": str(p.meta.get("priority") or "").strip(),
                     "release": str(p.meta.get("release") or "").strip(),
                     "order": str(p.meta.get("order") if p.meta.get("order") is not None else "").strip(),
                     "status": p.status})
    return render_template(
        "functional-requirements.html", hierarchy=hierarchy, diagram=diagram, diagram_links=diagram_links,
        block=block, needs_mermaid=bool(diagram), rows=rows,
    )


@app.route("/functional-requirements/<stem>")
def fr_view(stem):
    """Rich detail page for a functional requirement of any notation and level
    (DR-038), mirroring the wiki/functional-requirements/ folder.
    Shows the FR's full text plus — for non-leaf FRs — its own Feature→Story
    breakdown (mermaid + cards); for a use case, the Agile features and
    stories that realize it. Every FR node in the hierarchy diagrams clicks
    here, so the whole hierarchy lives under one sprechenden path with a
    'Functional Requirements' breadcrumb (instead of the generic /page 'Search' crumb).
    404 if `stem` is not an FR page."""
    fr_folder = catalog.folder("functional-requirement")
    path = wiki.WIKI_DIR / fr_folder / f"{stem}.md"
    page = wiki._parse(path, fr_folder) if fr_folder and path.is_file() else None
    if not page:
        abort(404)
    titles = links_module.title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)  # drop leading "# Title"
    body_html = render.render_markdown(body, titles)

    hierarchy = project.requirements.build_fr_hierarchy()
    node, kind = project.requirements._fr_hierarchy_node(hierarchy, stem)
    fr = {
        "id": page.id, "title": page.title, "stem": stem,
        "notation": project.requirements._fr_notation(page),
        "level": kind or project.requirements._fr_level(page),
        "priority": str(page.meta.get("priority") or "").strip(),
        "release": str(page.meta.get("release") or "").strip(),
        "status": page.status,
        "features": (node or {}).get("features") or [],
        "direct_stories": (node or {}).get("direct_stories") or [],
        "stories": (node or {}).get("stories") or [],
    }
    fr["n_features"] = len(fr["features"])
    fr["n_stories"] = (node or {}).get("n_stories")
    if fr["n_stories"] is None:  # feature/story carry no precomputed count
        fr["n_stories"] = len(fr["stories"])

    diagram_links: list[dict] = []
    # a requirement outside the hierarchy (another notation) still shows its blocks
    diagram = project.requirements._mermaid_fr_subtree(node or {"id": page.id, "title": page.title},
                                  project.requirements.fr_building_blocks(stem), diagram_links)
    trace = project.architecture.build_trace(stem, fr_folder)
    return render_template(
        "fr.html", fr=fr, body_html=body_html, diagram=diagram, diagram_links=diagram_links,
        ancestors=project.requirements._fr_ancestors(stem),
        trace=trace,
        relations=project.terms.build_relations_panel(stem, exclude=project.architecture.trace_stems(trace)),
        needs_mermaid=bool(diagram) or "language-mermaid" in body_html,
        sources=project.common.provenance(page),
        page_issues=open_issues_for(stem),
        formats=render.format_labels(page.body),
        **page_head(page),
    )


@app.route("/req42/<slug>")
def req42_block_view(slug):
    """All entries of one req42 block, for blocks without their own rich view."""
    block = catalog.SECTION_BY_SLUG.get(slug)
    # the arc42 sections have slugs too, but their pages live under /arc42/
    if not block or block["href"] != f"/req42/{slug}":
        abort(404)
    return _block_list(block, slug)


@app.route("/section/<sid>")
def section_view(sid):
    """A section the dashboard has no view for (FR-044): the generic list of
    its pages. A section with a view of its own redirects there."""
    block = catalog.SECTION_BY_ID.get(sid) or catalog.SECTION_BY_ID.get(sid.upper())
    if not block or not block["href"]:
        abort(404)
    if block["href"] != f"/section/{block['id']}":
        return redirect(block["href"])
    return _block_list(block, None)


def _block_list(block: dict, slug: str | None):
    titles, links = links_module.title_index(), links_module.link_index()
    rows = [
        {"id": p.id, "type": catalog.label(p.folder),
         "title": p.title, "url": links_module._page_url(p.folder, p.stem),
         "status": p.status, "relations": len(links_module.linked_stems(p)),
         **(project.requirements._qr_details(p, titles, links) if wiki._is(p.folder, "quality-requirement") else {})}
        for p in project.common._block_pages(block)
    ]
    # the Scope block (03) shows the same live-projected system-context diagram
    diagram_links: list[dict] = []
    context_diagram = project.context.build_context_diagram(wiki_config()["system_name"], links=diagram_links) if slug == "scope" else None
    context_flows = project.context.build_context_flows() if slug == "scope" else None
    entity_diagram = project.terms.build_data_model_full_diagram() if slug == "models" else None
    return render_template(
        "req42_block.html", block=block, rows=rows, total=len(rows),
        list_type=catalog.type_of(block["folders"][0]) if block["folders"] else "page",
        context_diagram=context_diagram, context_flows=context_flows, diagram_links=diagram_links,
        entity_diagram=entity_diagram, needs_mermaid=bool(context_diagram or entity_diagram),
        maturity=project.common.maturity(r["status"] for r in rows),
    )


# --- scan-to-join: QR code + /join page -------------------------------------


def _lan_ip() -> str | None:
    """This host's LAN address, best effort. Connecting a UDP socket sends no
    packet; it only makes the OS pick the outbound interface."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        finally:
            s.close()
    except OSError:
        return None


def public_url() -> str:
    """The address other devices in the room should open. DASH_PUBLIC_URL wins
    (dashboard.sh sets it from the host's LAN address — inside Docker the
    container only knows its own bridge address); else the request's port on
    this host's LAN IP; else the request's own origin."""
    env = os.environ.get("DASH_PUBLIC_URL", "").strip()
    if env:
        return env.rstrip("/")
    port = urlsplit(request.host_url).port
    ip = _lan_ip()
    if ip:
        return f"http://{ip}:{port}" if port else f"http://{ip}"
    return request.host_url.rstrip("/")


def qr_svg(url: str, scale: int = 4) -> str:
    """Inline SVG QR code. Segno's SVG writer validates `dark` against a
    strict colour table and rejects the CSS keyword `currentColor` outright,
    so the code is rendered in a throwaway colour and swapped for
    `currentColor` in the markup afterwards — that lets CSS `color` set the
    module colour, so it follows the theme; no background rectangle."""
    import segno
    svg = segno.make(url, error="m").svg_inline(
        scale=scale, border=1, dark="black", light=None, omitsize=True)
    return re.sub(r'stroke="[^"]*"', 'stroke="currentColor"', svg, count=1)


@app.route("/join")
def join_page():
    url = public_url()
    return render_template("join.html", join_url=url, join_qr=qr_svg(url, scale=10))


def _json_object(req) -> dict:
    """The JSON object in the body of a session request (/ping, /leaving,
    /settings, /disconnect-all). No body, an unreadable body and `null` count
    as an empty object. Any other JSON value (array, string, number, boolean)
    ends the request with a 400, before the endpoint touches session state."""
    try:
        data = req.get_json(silent=True, force=True)
    except Exception:
        data = None
    if data is None:
        return {}
    if not isinstance(data, dict):
        abort(make_response({"error": "not-an-object"}, 400))
    return data


def _client_id(req) -> str:
    """The per-tab id a page sends with /ping and /leaving (generated once in
    base.html, kept in sessionStorage so it survives in-tab navigation but
    not a closed tab). Defaulted and length-capped so a missing or malformed
    body can't wedge the presence dict."""
    cid = str(_json_object(req).get("client_id") or "").strip()[:64]
    return cid or "anon"


@app.route("/ping", methods=["POST"])
def heartbeat_ping():
    """Lightweight sign of life from one open page. Updates that client_id's
    `last seen` timestamp and clears any pending "tab is leaving" signal for
    it (a live page pinging means no goodbye after all). Holds no thread —
    replies immediately with the two things the page needs back: this tab's
    name (for the header) and whether it is currently the facilitator (for
    the disconnect-all button — see `_facilitator_client_id`). The first
    facilitator is named "Yoda", everyone else gets a nickname; a name never
    changes once given (`_name_for`). Both are re-sent on every ping, so the
    button follows the role live if it ever transfers (Yoda's tab
    disappearing): the heir gets the button but keeps its own name."""
    cid = _client_id(request)
    ua = request.headers.get("User-Agent", "")[:200]
    with session._lifecycle_lock:
        session._record_ping(cid, ua)
        is_facilitator = cid == session._facilitator_client_id()
        nickname = session._name_for(cid)
    return {"nickname": nickname, "is_facilitator": is_facilitator}


@app.route("/leaving", methods=["POST"])
def heartbeat_leaving():
    """Beacon sent when one page is left (pagehide: tab closed OR navigated).
    Marks that client_id as possibly-gone; if the user was only navigating,
    the next page's immediate `/ping` (same client_id) clears the signal
    again before it expires."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        session._leaving[cid] = time.monotonic()
    return ("", 204)


@app.route("/presence/count")
def presence_count():
    """How many distinct tabs have pinged within `_PRESENCE_WINDOW` — the
    number shown in the footer. Yoda's own tab counts like any other: the
    facilitator alone in the room reads "1 client", not "0 clients" beside
    "Welcome, Yoda" (an earlier version excluded Yoda; see DR-022's
    2026-09-08 note). Polled every few seconds; cheap (an in-memory dict
    scan, no I/O, no thread held)."""
    now = time.monotonic()
    with session._lifecycle_lock:
        count = sum(1 for last in session._clients.values()
                    if now - last <= session._PRESENCE_WINDOW)
    return {"count": count}


@app.route("/presence/list")
def presence_list():
    """Per-client detail for the "who's here" page: a fun deterministic
    nickname, a coarse browser/OS, and how long they've been connected.
    Includes the facilitator, same as /presence/count, marked with
    `is_facilitator: true` so the page can mark the role. Shown to every
    viewer, not facilitator-gated — it's meant as a bit of a moment for
    everyone else, not an admin tool."""
    now = time.monotonic()
    with session._lifecycle_lock:
        yoda = session._facilitator_client_id()
        rows = []
        for cid, last in session._clients.items():
            if now - last > session._PRESENCE_WINDOW:
                continue
            browser, os_name = session._parse_user_agent(session._user_agents.get(cid, ""))
            rows.append({
                "nickname": session._name_for(cid),
                "is_facilitator": cid == yoda,
                "browser": browser,
                "os": os_name,
                "connected_seconds": round(now - session._first_seen.get(cid, last)),
            })
    rows.sort(key=lambda r: r["connected_seconds"], reverse=True)
    return {"clients": rows}


@app.route("/who")
def who_page():
    """The "who's here" page itself — a live list rendered client-side from
    /presence/list (see who.html)."""
    return render_template("who.html")


# --- Reload ---------------------------------------------------------------
@app.route("/reload", methods=["POST"])
def reload_caches():
    """Drop every server-side cache, so the next render re-reads the vault
    and recompiles the templates from disk. The footer button behind this
    posts here and then reloads the page.

    Most of the time nothing here is needed: `_parse` is keyed by (path,
    mtime_ns, size) and the folder listings are re-globbed per request, so a
    fresh ingest's new, edited and deleted pages already show up on an
    ordinary browser refresh. Two things do not, and they are why the button
    exists — a rewrite that lands on the same mtime and size (a restored file,
    a checkout, a timestamp-preserving copy) stays a cache hit forever, and Jinja compiles
    each template once per worker, so an edited template otherwise needs the
    process restarted. Clearing both costs one re-parse of the vault, which
    is milliseconds at workshop scale.

    Open to every viewer, unlike the facilitator-only controls below: it
    reads the same read-only files any page render already reads, and the
    worst a stranger can do with it is make one render slower.

    POST-only on purpose. A GET would let a prefetch or a crawler flush the
    cache on someone else's behalf."""
    _clear_caches()
    return {"ok": True}


def _clear_caches() -> None:
    """Drop the parsed wiki pages, the parsed metamodel and anchor pages, and
    Jinja's compiled templates. Used by /reload and by saving the view."""
    with wiki._PARSE_LOCK:
        wiki._PARSE_CACHE.clear()
    metamodel.clear_caches()
    if app.jinja_env.cache is not None:
        app.jinja_env.cache.clear()


@app.route("/settings", methods=["GET"])
def settings_get():
    """The View dialog's data: the catalog grouped by area plus the
    current hide list. Open to every viewer (it is the same information the
    home page shows); saving is facilitator-only (POST below)."""
    cfg = dashboard_config()
    return {
        "areas": [{"key": a["key"], "label": a["label"], "colors": a["colors"],
                   "sections": [{"id": s["id"], "title": s["title"], "colors": s["colors"],
                                 "scope": s["scope"]}
                                for s in catalog.sections_of(a["key"])]}
                  for a in catalog.AREAS],
        "hidden": cfg["hidden"],
    }


@app.route("/settings", methods=["POST"])
def settings_post():
    """Facilitator-only: replace the view's hide list (in memory, FR-046).
    Same self-asserted client_id check as /disconnect-all — the facilitator is
    whoever connected first and is still here. Unknown IDs are a 400 and
    nothing changes; the dialog only ever sends catalog IDs, so a 400 here
    means a stale page or a hand-crafted request."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        if cid != session._facilitator_client_id():
            abort(403)
    data = _json_object(request)
    valid, unknown = session._validate_hidden(data.get("hidden"))
    if unknown or not isinstance(data.get("hidden"), list):
        return {"error": "unknown", "unknown": unknown}, 400
    session.set_view(valid)
    _clear_caches()
    return {"ok": True, "hidden": valid}


# --- Facilitator-only controls -------------------------------------------
#
# No token, no cookie, no `remote_addr` check (which can't work here anyway:
# under Docker Desktop's NAT, the facilitator's own `localhost:8080` request
# and a tunnel's forwarded client traffic arrive at the container
# looking identical). The facilitator is just "Yoda" — whoever connected
# first and is still here, or the heir once it left (`_facilitator_client_id`) — and the only shared
# secret involved is each tab's own random client_id, which is never shown
# to any other tab (nicknames on /who are derived from it, not equal to it).
# base.html only shows the "Disconnect all" button once a /ping response
# says `is_facilitator: true`; the server enforces the same check again here
# regardless of what the button shows, since the client_id in this POST body
# is otherwise just as self-asserted as a browser's own /ping.
@app.route("/disconnect-all", methods=["POST"])
def disconnect_all():
    """Facilitator-only: end the session for every connected browser by
    shutting the server down outright (`session._shutdown`). Everyone else's
    next /ping then fails, which the footer script turns into a plain
    "session ended" notice (base.html)."""
    cid = _client_id(request)
    with session._lifecycle_lock:
        if cid != session._facilitator_client_id():
            abort(403)
    session._shutdown("disconnect-all requested by facilitator")
    return ("", 204)


HELP_PATH = Path(__file__).resolve().parent / "help.md"


@app.route("/help")
def help_view():
    """Dashboard help, rendered from help.md: how to read the page, and the
    Systems42 model in brief with the sections diagram (DR-033)."""
    try:
        text = HELP_PATH.read_text(encoding="utf-8")
    except OSError:
        text = "# Help\n\nhelp.md is missing from the image."
    img = (f'<figure class="help-diagram"><img src="{static_url("systems42-sections.svg")}" '
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
    default_notation = wiki_config()["default_notation"]
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
    return about_doc(wiki._config_data().get("about"))


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
    root = DOCS_DIR.resolve()
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
    title = wiki_config()["about_label"]
    return render_template("about.html", html=html, title=title)


@app.route("/about/files/<path:name>")
def about_file(name):
    """Files the about page links to (images, SVGs) — inside docs/ only."""
    if _about_path() is None:
        abort(404)
    path = docs_file(name)
    if path is None:
        abort(404)
    return _inert_file(send_file(path))


if __name__ == "__main__":
    session.start_lifecycle()
    app.run(host="0.0.0.0", port=8000, threaded=True)
