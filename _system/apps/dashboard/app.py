"""Requirements-Wiki Dashboard.

A small read-only Flask app that parses the Obsidian-style requirements wiki
(markdown + YAML frontmatter + [[wikilinks]]) live on each request and renders
it as a tiled dashboard. The wiki folder is mounted into the container; nothing
is ever written back.
"""
from __future__ import annotations

import functools
import mimetypes
import os
import re
import signal
import socket
import threading
import time
import unicodedata
import zlib
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import markdown as md
import yaml
from flask import (Flask, abort, g, has_request_context, jsonify, redirect,
                   render_template, request, send_file, url_for)
from markupsafe import Markup, escape

import catalog  # the section catalog (DR-033)
import metamodel  # reader for _system/metamodel/ (DR-035)

# some slim base images lack a webp entry in their mime.types
mimetypes.add_type("image/webp", ".webp")

app = Flask(__name__)

# Timezone for the "last refreshed" footer; honours the container's TZ env.
# Empty (not "UTC") when unset, so inject_refresh_time can fall back to the
# host's own local zone instead of forcing UTC.
DISPLAY_TZ = os.environ.get("TZ") or ""


# Dashboard settings — the ONE file the dashboard writes (DR-033). A hide
# list of area keys / section IDs; everything is visible by default. Read per
# call like wiki.yaml (the Configure dialog and hand edits both land on the
# next request); written in place because under Docker it is a bind-mounted
# single file, and a temp-and-rename would swap the inode out from under the
# mount.
_env_dash = os.environ.get("DASHBOARD_CONFIG")
DASHBOARD_CONFIG_PATH = (Path(_env_dash) if _env_dash
                         else Path(__file__).resolve().parents[2] / "dashboard.yaml")

_DASHBOARD_CONFIG_HEADER = """\
# Dashboard settings — written by the dashboard's Configure dialog (facilitator
# only); hand-editable too. Everything is visible unless listed here.
# `hidden` takes area keys (requirements | architecture | commons) and/or
# section IDs (R1-R6, A1-A5, C1-C7) from the Systems42 sections catalog.
"""

_VALID_HIDE_KEYS = [a["key"] for a in catalog.AREAS] + [s["id"] for s in catalog.SECTIONS]


def _normalise_hide_entry(raw) -> str | None:
    """'c6' → 'C6', ' Architecture ' → 'architecture'; None if not in the catalog."""
    s = str(raw or "").strip()
    if not s:
        return None
    if s.lower() in catalog.AREA_BY_KEY:
        return s.lower()
    if s.upper() in catalog.SECTION_BY_ID:
        return s.upper()
    return None


def _request_cached(func):
    """Memoize a builder for the current request (keyed by name + args). The
    cached objects are treated as read-only by every caller, so sharing the same
    reference across calls within a request is safe."""
    @functools.wraps(func)
    def wrapper(*args):
        if not has_request_context():
            return func(*args)
        cache = g.setdefault("_build_cache", {})
        key = (func.__name__, args)
        if key not in cache:
            cache[key] = func(*args)
        return cache[key]
    return wrapper


def _validate_hidden(entries) -> tuple[list[str], list[str]]:
    """Split raw entries into (valid in catalog order, unknown as given)."""
    valid, unknown = set(), []
    if isinstance(entries, str):          # `hidden: C6` is a one-item list
        entries = [entries]
    for raw in entries if isinstance(entries, list) else []:
        key = _normalise_hide_entry(raw)
        if key:
            valid.add(key)
        else:
            unknown.append(str(raw))
    return [k for k in _VALID_HIDE_KEYS if k in valid], unknown


@_request_cached
def dashboard_config() -> dict:
    """`hidden`: valid area keys / section IDs, deduped, in catalog order.
    `unknown`: entries that match nothing — reported on the home page, never
    an error. A missing, empty or malformed file hides nothing."""
    try:
        data = yaml.safe_load(DASHBOARD_CONFIG_PATH.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    hidden, unknown = _validate_hidden(data.get("hidden"))
    return {"hidden": hidden, "unknown": unknown}


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


def write_dashboard_config(hidden: list[str]) -> None:
    """Rewrite the settings file in place (see the note above)."""
    valid, _ = _validate_hidden(list(hidden))
    body = _DASHBOARD_CONFIG_HEADER + yaml.safe_dump(
        {"hidden": valid}, default_flow_style=None, sort_keys=False)
    with open(DASHBOARD_CONFIG_PATH, "w", encoding="utf-8") as fh:
        fh.write(body)


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

# Root of the wiki layer. In Docker this is a read-only bind mount at /wiki;
# for local runs it falls back to the repo's wiki/ folder (4 levels up from
# _system/apps/dashboard/app.py). The fallback is computed lazily so the
# container path is never resolved.
_env_wiki = os.environ.get("WIKI_DIR")
WIKI_DIR = Path(_env_wiki) if _env_wiki else Path(__file__).resolve().parents[3] / "wiki"

# Provenance records (raw/sources/, Source type, DR-006). Read-only mount at
# /sources in Docker; repo fallback for local runs. Only ever read.
_env_src = os.environ.get("RAW_SOURCES_DIR")
SOURCES_DIR = Path(_env_src) if _env_src else Path(__file__).resolve().parents[3] / "raw" / "sources"

# Project identity. Everything the original demo vault hardcoded (page title,
# footer, hero, goal-tree root, context-diagram centre) reads from here so a
# fresh vault can be renamed in one place. Read per call, never cached: during
# a workshop the group fills this in live and just refreshes the page.
_env_cfg = os.environ.get("WIKI_CONFIG")
CONFIG_PATH = Path(_env_cfg) if _env_cfg else Path(__file__).resolve().parents[2] / "wiki.yaml"

DEFAULT_SYSTEM_NAME = "Requirements Wiki"

# Root of the wiki repository. A wiki's own brand folder (`brand:` in
# wiki.yaml) is a path relative to it. Read-only mount at /repo in Docker.
_env_repo = os.environ.get("REPO_DIR")
REPO_DIR = Path(_env_repo) if _env_repo else Path(__file__).resolve().parents[3]

# The dashboard's own release, shown in the footer.
try:
    DASHBOARD_VERSION = (Path(__file__).resolve().parent / "VERSION").read_text(encoding="utf-8").strip()
except OSError:
    DASHBOARD_VERSION = ""

# Brands: marks, favicon and an optional intro (contract: brands/README.md).
# The example brands ship in brands/; a wiki may name its own folder instead.
BRANDS_DIR = Path(__file__).resolve().parent / "brands"
EXAMPLE_BRANDS = ("systems42", "atrium")
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
    try:
        data = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        data = {}
    if not isinstance(data, dict):
        data = {}
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
    }


# Project documentation (`docs/`), mounted read-only. Only `/about` reads it:
# the page `about:` in wiki.yaml names, plus the files that page links to.
_env_docs = os.environ.get("DOCS_DIR")
DOCS_DIR = Path(_env_docs) if _env_docs else Path(__file__).resolve().parents[3] / "docs"


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


def _inside(root: Path, path: Path) -> bool:
    return path == root or root in path.parents


def brand_dir(value: str) -> Path:
    """The folder of the brand `brand:` names, resolved and checked.

    An example brand name wins, anything else is a folder relative to the
    wiki repository root. A folder that leaves the root (`..`, an absolute
    path, a symlink) or lacks one of the three marks yields the default
    brand and a log warning. The folder is only ever read (CON-002)."""
    default = BRANDS_DIR / DEFAULT_BRAND
    name = str(value or "").strip() or DEFAULT_BRAND
    if name in EXAMPLE_BRANDS:
        return BRANDS_DIR / name
    root = REPO_DIR.resolve()
    path = (root / name).resolve()
    if not _inside(root, path):
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
    template. `active_brand.intro_html` is the intro fragment, inserted as it
    is (never rendered as a template), or "" when there is none or `intro: off`."""
    cfg = wiki_config()
    folder = brand_dir(cfg["brand"])
    intro = _brand_file(folder, BRAND_INTRO) if cfg["intro"] else None
    try:
        intro_html = Markup(intro.read_text(encoding="utf-8")) if intro else ""
    except (OSError, UnicodeDecodeError):
        intro_html = ""
    cfg["active_brand"] = {
        "mark_dark": _brand_url(folder, "mark-dark.svg"),
        "mark_light": _brand_url(folder, "mark-light.svg"),
        "favicon": _brand_url(folder, "favicon.svg"),
        "intro_html": intro_html,
    }
    cfg["dashboard_version_own"] = DASHBOARD_VERSION
    cfg["dashboard_version_differs"] = bool(cfg["dashboard_version"]) and \
        cfg["dashboard_version"] != DASHBOARD_VERSION
    return cfg


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
    return send_file(path, mimetype="image/svg+xml", max_age=31536000 if fresh else 0)


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


# Nav entries tagged with the area or section each one opens, so a hidden one
# leaves the nav. Order is the nav order. The header carries content only:
# the two peaks, then the three Commons sections a reader looks up by name.
# Labels come from the catalog, so a section has one name everywhere (FR-017).
_NAV_ENTRIES = [(a, catalog.AREA_BY_KEY[a]["href"], catalog.AREA_BY_KEY[a]["label"])
                for a in ("requirements", "architecture")] + \
               [(s, catalog.SECTION_BY_ID[s]["href"], catalog.SECTION_BY_ID[s]["title"])
                for s in ("C5", "C7", "C6")]


def _nav_current(key: str, href: str, path: str, area: dict | None) -> bool:
    """An area entry is current on every page of that area, except on the
    pages of a section that has its own entry. A section entry is current on
    every page of that section, its wiki pages included (FR-014)."""
    here = catalog.section_for_path(path)
    if key in catalog.AREA_BY_KEY:
        own = bool(here) and any(k == here["id"] and not is_hidden(k) for k, _, _ in _NAV_ENTRIES)
        return bool(area and area["key"] == key and not own)
    return bool(here and here["id"] == key) or path.startswith(href)


@app.context_processor
def inject_nav():
    """`nav_items` for base.html: (href, label, current), hidden entries dropped."""
    if not has_request_context():
        return {"nav_items": [(h, l, False) for _, h, l in _NAV_ENTRIES]}
    area = catalog.area_for_path(request.path)
    return {"nav_items": [(h, l, _nav_current(k, h, request.path, area))
                          for k, h, l in _NAV_ENTRIES if not is_hidden(k)]}


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


def list_spec(type_name: str) -> dict:
    """What a section list declares for static/list-view.js (FR-021): its type
    and the sort orders the metamodel gives that type."""
    return {"type": type_name, "orders": metamodel.sort_orders(type_name)}


app.jinja_env.globals["list_spec"] = list_spec


# [[target]] | [[target|alias]] | [[target#heading]] | [[path/target|alias]]
WIKILINK_RE = re.compile(r"\[\[([^\]\|#]+)(?:#[^\]\|]+)?(?:\|([^\]]+))?\]\]")
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)


@dataclass
class Page:
    stem: str                       # filename without .md, e.g. GLO-006-kind
    meta: dict                      # parsed frontmatter
    body: str                       # markdown body (frontmatter stripped)
    folder: str                     # owning wiki subfolder, e.g. glossary
    # Last-modified time of the source file. Last field, and defaulted, so every
    # existing positional/keyword construction keeps working. Feeds the home
    # page's "Latest changes" tile — see recent_changes().
    mtime: float = 0.0

    @property
    def id(self) -> str:
        # a blank `id:` (a draft still being written) falls back to the file
        # name, so sorting and linking never meet None
        return str(self.meta.get("id") or self.stem)

    @property
    def title(self) -> str:
        return self.meta.get("title", self.stem)

    @property
    def status(self) -> str:
        return self.meta.get("status", "")

    @property
    def aliases(self) -> list[str]:
        a = self.meta.get("aliases") or []
        return [x for x in a if x]

    def link_targets(self) -> set[str]:
        """Distinct wiki pages this page points to (frontmatter + body),
        excluding self-references and raw/ source provenance links."""
        targets: set[str] = set()
        haystack = yaml.safe_dump(self.meta, allow_unicode=True) + "\n" + self.body
        for m in WIKILINK_RE.finditer(haystack):
            tgt = m.group(1).strip()
            base = tgt.split("/")[-1]              # drop raw/ path prefix
            if tgt.startswith("raw/") or base.startswith("SRC-"):
                continue                            # provenance, not a relation
            if base == self.stem or base == self.id:
                continue                            # self-reference
            targets.add(base)
        return targets


# --- caching ----------------------------------------------------------------
#
# The wiki is parsed live on every request and was, before caching, re-read and
# re-parsed dozens of times per page (every `render_markdown` rebuilt the whole
# link index from disk). Two complementary layers fix that without ever serving
# stale content:
#
#   Tier 1  _parse() is memoized by (path, mtime). A file is re-read only when it
#           changes on disk, so editing a page and refreshing the browser still
#           shows the new text — but repeated reads (within a request and across
#           requests) collapse to a dict lookup. The cache lives for the worker's
#           lifetime; each gunicorn worker warms its own.
#
#   Tier 2  the aggregate builders (load_folder / load_all_pages / title_index /
#           link_index / load_decisions) are memoized for the duration of ONE request
#           via flask.g, so the tree is walked once per request instead of once
#           per markdown block rendered. Outside a request context they run
#           uncached (keeps build_* helpers usable standalone, e.g. for ISS-010).

# (path -> (mtime, parsed Page or None)); folder is deterministic from the path
# (always path.parent.name at every call site), so the path alone is the key.
_PARSE_CACHE: dict[Path, tuple[float, "Page | None"]] = {}


def _parse(path: Path, folder: str) -> Page | None:
    try:
        mtime = path.stat().st_mtime
    except OSError:
        return None
    cached = _PARSE_CACHE.get(path)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    text = path.read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(text)
    if not m:
        page = None
    else:
        try:
            meta = yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError:
            meta = {}
        page = Page(stem=path.stem, meta=meta, body=m.group(2), folder=folder,
                    mtime=mtime)
    _PARSE_CACHE[path] = (mtime, page)
    return page


@_request_cached
def load_folder(folder: str) -> list[Page]:
    d = WIKI_DIR / folder
    if not d.is_dir():
        return []
    pages = [_parse(p, folder) for p in sorted(d.glob("*.md"))]
    return [p for p in pages if p is not None]


@_request_cached
def load_sources() -> list[Page]:
    """Provenance records from raw/sources/ — counted on the home page's status
    strip so the room can see how much material the wiki actually rests on.
    Not a wiki folder: it lives outside WIKI_DIR and is never rendered."""
    if not SOURCES_DIR.is_dir():
        return []
    pages = [_parse(p, "sources") for p in sorted(SOURCES_DIR.glob("*.md"))]
    return [p for p in pages if p is not None]


@_request_cached
def load_all_pages() -> list[Page]:
    """Every wiki page across all content-type folders, for global search."""
    out: list[Page] = []
    if WIKI_DIR.is_dir():
        for d in sorted(WIKI_DIR.iterdir()):
            if d.is_dir():
                out.extend(load_folder(d.name))
    return out


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
    pages = sorted(load_all_pages(), key=lambda p: -p.mtime)[:n]
    return [{"id": p.id, "title": p.title, "kind": FOLDER_LABELS.get(p.folder, p.folder),
             "url": _page_url(p.folder, p.stem), "when": _relative_when(p.mtime)} for p in pages]


def vault_status() -> dict:
    """The one-line state of the vault under the hero: how much is captured,
    what is still open, how much source material it rests on, and how fresh
    the whole thing is."""
    pages = load_all_pages()
    issues = load_folder("issues")
    last = max((p.mtime for p in pages), default=0.0)
    return {"pages": len(pages),
            "open_issues": sum(1 for i in issues if is_open_issue(i.status)),
            "sources": len(load_sources()),
            "last_change": _relative_when(last) if last else "—"}


@_request_cached
def title_index() -> dict[str, str]:
    """Map every page stem -> human title, for resolving wikilinks to text."""
    idx: dict[str, str] = {}
    if not WIKI_DIR.is_dir():
        return idx
    for p in WIKI_DIR.rglob("*.md"):
        page = _parse(p, p.parent.name)
        if page:
            idx[p.stem] = page.title
    return idx


def _page_url(folder: str, stem: str) -> str:
    """Canonical dashboard URL for a wiki page. FRs have their own rich route;
    everything else uses the generic /page view."""
    if folder == "functional-requirements":
        return f"/functional-requirements/{stem}"
    return f"/page/{folder}/{stem}"


@_request_cached
def link_index() -> dict[str, tuple[str, str]]:
    """Map each page's stem and id -> (folder, stem), so body wikilinks like
    `[[STK-006-…|Backoffice]]` or `[[FR-008]]` resolve to a real target URL.
    Stems/ids are unique; first writer wins on the rare collision."""
    idx: dict[str, tuple[str, str]] = {}
    for p in load_all_pages():
        idx.setdefault(p.stem, (p.folder, p.stem))
        idx.setdefault(p.id, (p.folder, p.stem))
    return idx


@_request_cached
def source_index() -> dict[str, Page]:
    """Map each raw/sources/ record's stem and id -> its Page, so a page's
    `sources:` wikilinks (and the /source/<stem> route) can resolve either
    form."""
    idx: dict[str, Page] = {}
    for p in load_sources():
        idx.setdefault(p.stem, p)
        idx.setdefault(p.id, p)
    return idx


def provenance(page: Page) -> list[dict]:
    """Resolve a page's `sources:` wikilinks to provenance records. Unresolved
    entries are kept (url=None) so the chip can say so instead of vanishing."""
    idx = source_index()
    rows = []
    refs = page.meta.get("sources") or []
    if not isinstance(refs, list):
        refs = [refs]                            # a bare string is one entry, not a list of characters
    for ref in refs:
        base = _fr_stem_from_ref(ref)           # '[[raw/sources/SRC-001-x]]' -> 'SRC-001-x'
        if not base:
            continue                             # None / empty after stripping — nothing to show
        src = idx.get(base)
        if src:
            rows.append({"id": src.id, "title": src.title, "stem": src.stem,
                         "type": str(src.meta.get("source-type") or ""),
                         "origin": str(src.meta.get("origin") or ""),
                         "captured": str(src.meta.get("captured") or ""),
                         "url": f"/source/{src.stem}"})
        else:
            rows.append({"id": base, "title": base, "stem": base, "type": "", "origin": "", "captured": "", "url": None})
    return rows


@_request_cached
def open_issue_counts() -> dict[str, set[str]]:
    """folder -> ids of OPEN issues whose links (frontmatter `related:` or body
    wikilinks) resolve to a page in that folder. One issue's id can appear in
    several folders' sets; an issue that links nothing resolvable appears in
    none. Sets (not counts) so a caller spanning several folders — e.g. Scope's
    context + external-interfaces — can union them and count each issue once,
    even if it links pages in more than one of those folders."""
    links = link_index()
    out: dict[str, set[str]] = {}
    for iss in load_folder("issues"):
        if not is_open_issue(iss.status):
            continue
        for folder in {links[t][0] for t in iss.link_targets() if t in links}:
            out.setdefault(folder, set()).add(iss.id)
    return out


# --- rendering helpers -----------------------------------------------------

def render_wikilinks(text: str, titles: dict[str, str],
                     links: dict[str, tuple[str, str]] | None = None) -> str:
    """Replace [[..]] with its alias (or resolved title). When `links` is given
    and the target resolves to a wiki page, a source record or a method anchor,
    emit a real hyperlink; otherwise (inline snippets, or an unresolved target)
    keep the styled-text span."""
    def repl(m: re.Match) -> str:
        target, alias = m.group(1).strip(), m.group(2)
        base = target.split("/")[-1]
        label = alias.strip() if alias else titles.get(base, base)
        if links is not None and (target.startswith("raw/") or base.startswith("SRC-")):
            # a source cited in the text leads to its record (FR-034)
            if src := source_index().get(base):
                return f'<a class="wl" href="/source/{src.stem}">{alias.strip() if alias else escape(src.title)}</a>'
        elif links:
            dest = links.get(base)
            if dest:
                return f'<a class="wl" href="{_page_url(*dest)}">{label}</a>'
        if links is not None and (a := anchor_lookup().get(base.lower())):
            return _anchor_link(a, alias.strip() if alias else str(escape(a["name"])))
        return f'<span class="wl">{label}</span>'
    return WIKILINK_RE.sub(repl, text)


# --- method anchors (FR-035) -------------------------------------------------
#
# `[[MADR]]` names a method anchor, not a wiki page. It leads to the anchor's
# entry on /metamodel, with the short definition as the link's title, so a
# reader learns what the page follows without leaving it.

@_request_cached
def anchor_lookup() -> dict[str, dict]:
    """Lower-cased anchor title, alias and file name → the anchor."""
    return metamodel.anchor_index(metamodel.method_anchors())


_PLAIN_MD_RE = re.compile(r"\*\*([^*]+)\*\*|`([^`]+)`|<(https?://[^>]+)>")


def anchor_title(a: dict) -> str:
    """An anchor's definition as plain text, for a `title` attribute."""
    text = WIKILINK_RE.sub(lambda m: (m.group(2) or m.group(1)).strip(), a.get("definition") or "")
    return _PLAIN_MD_RE.sub(lambda m: m.group(1) or m.group(2) or m.group(3), text)


def anchor_url(a: dict) -> str:
    return f"/metamodel#{a['id']}"


def _anchor_link(a: dict, label: str) -> str:
    return (f'<a class="wl wl-anchor" href="{anchor_url(a)}" '
            f'title="{escape(anchor_title(a))}">{label}</a>')


# A page's note that it follows a standard, a quote line of its own that
# starts with a lowercase "follows": "> follows [[MADR]]", "> follows [[arc42]]
# (section 5, black box)". More than 3 spaces before the ">" is indented code.
_FOLLOWS_RE = re.compile(r"^ {0,3}>[ \t]*follows[ \t]+(\S.*?)[ \t]*$")
_FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
# a note without a link names its format in a few words, not a sentence
_FOLLOWS_PLAIN_MAX_WORDS = 6


def _follows_notes(body: str) -> list[tuple[int, str]]:
    """(line number, text after "follows") of every "follows" note, outside
    fenced code. The one test both the page (drop_follows, format_labels) and
    search (search_plain) use, so both leave out exactly the same lines."""
    out = []
    fence = ""
    for i, line in enumerate(body.split("\n")):
        f = _FENCE_RE.match(line)
        if fence:
            if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence):
                fence = ""
            continue
        if f:
            fence = f.group(1)
            continue
        m = _FOLLOWS_RE.match(line)
        if not m:
            continue
        text = m.group(1)
        if not WIKILINK_RE.search(text) and (len(text.split()) > _FOLLOWS_PLAIN_MAX_WORDS
                                              or re.search(r"[.!?;:]", text)):
            continue                         # an ordinary sentence in a quote
        out.append((i, text))
    return out


def drop_follows(body: str) -> str:
    """The body without its "follows" notes, each line removed with its line
    break, so a callout around it stays whole. They show as labels in the
    page head (format_labels), never as a box before the content."""
    drop = {i for i, _ in _follows_notes(body)}
    if not drop:
        return body
    return "\n".join(line for i, line in enumerate(body.split("\n")) if i not in drop)


def format_labels(body: str) -> list[dict]:
    """The "follows" notes of a page as head labels, one per standard named,
    deduplicated: `label`, `url` and `title` (empty for a standard that is no
    anchor) and `note`, the rest of the line such as "section 5, black box"."""
    titles, links = title_index(), link_index()
    out: list[dict] = []
    seen: set[str] = set()
    for _, line in _follows_notes(body):
        note = WIKILINK_RE.sub("", line).strip(" ,;.").strip()
        note = re.sub(r"^\((.*)\)$", r"\1", note).strip()
        found = []
        for wm in WIKILINK_RE.finditer(line):
            base = wm.group(1).strip().split("/")[-1]
            a = anchor_lookup().get(base.lower())
            if a:
                found.append({"label": a["name"], "url": anchor_url(a), "title": anchor_title(a)})
            elif base in links:
                found.append({"label": titles.get(base, base), "url": _page_url(*links[base]), "title": ""})
            else:
                found.append({"label": (wm.group(2) or base).strip(), "url": "", "title": ""})
        if not found:
            found, note = [{"label": re.sub(r"^the\s+", "", line, flags=re.I), "url": "", "title": ""}], ""
        for i, f in enumerate(found):
            if f["label"].lower() in seen:
                continue
            seen.add(f["label"].lower())
            out.append({**f, "note": note if i == 0 else ""})
    return out


# `[ \t]*`, not `\s*`, after the marker: `\s` would cross the line break and
# take the callout's first text line as its title (`> [!note]` alone on a line)
CALLOUT_RE = re.compile(r"^>[ \t]*\[!(\w+)\][ \t]*(.*)$", re.MULTILINE)

# Lines that START a markdown block. A prose line that follows one of these
# is left for Markdown's own lazy-continuation rules; a prose line that
# follows another prose line is a hard wrap in the source file and is joined.
_BLOCK_START_RE = re.compile(r"^(\s*([-*+]|\d+[.)])\s|\s*#|\s*>|\s*\||\s*```|\s{4,}\S|\t|\s*<)")
_LIST_START_RE = re.compile(r"^\s*([-*+]|\d+[.)])\s")
# A GFM table separator row: "---|---", "|---|:---:|", "| --- | --- |". Must
# contain at least one "|" — a bare "---" is a thematic break, not a table.
_TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")


def _unwrap_prose(body: str) -> str:
    """Join hard-wrapped prose lines into one line per paragraph, and give a
    list that follows a prose line the blank line Python-Markdown needs.
    Agents write wiki pages wrapped at ~80 columns; rendering those wraps as
    <br> (the old `nl2br` extension) produced ragged paragraphs. Fenced code,
    explicit two-space line breaks, lists, quotes, tables and headings are
    passed through untouched. A wrapped *list item* (a plain continuation
    line right after a `- `/`1. ` line) is tracked via `in_list` so it stays
    a lazy continuation of that item — dedented, but without inserting the
    blank line that would turn a tight list into a loose one.

    Tables are recognised by their separator row (`---|---`, `|:---:|…|`),
    not by the mere presence of a "|" — ordinary prose containing a spaced
    pipe (e.g. a wikilink alias `[[FEAT-001|Feature | With Pipe]]`) must
    still be joined. A separator row pulls in the header line right above it
    and every following non-blank row containing "|" as table lines."""
    lines = body.split("\n")

    table_lines: set[int] = set()
    for i, line in enumerate(lines):
        if "|" in line and _TABLE_SEP_RE.match(line):
            table_lines.add(i)
            if i > 0 and "|" in lines[i - 1]:
                table_lines.add(i - 1)
            j = i + 1
            while j < len(lines) and lines[j].strip() and "|" in lines[j]:
                table_lines.add(j)
                j += 1

    out: list[str] = []
    in_fence = False
    in_list = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            in_list = False
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        if not stripped:
            in_list = False
            out.append(line)
            continue

        is_list_start = bool(_LIST_START_RE.match(line))
        is_block_start = (is_list_start or _BLOCK_START_RE.match(line)
                           or idx in table_lines)

        if in_list and not is_block_start:
            # lazy continuation of the current list item — dedent it, stay in the list
            out.append(line.lstrip())
            continue

        prev = out[-1] if out else ""
        prev_is_prose = (bool(prev.strip()) and not _BLOCK_START_RE.match(prev)
                          and (idx - 1) not in table_lines and not in_list)

        if is_block_start:
            if prev_is_prose and is_list_start:
                out.append("")            # prose → list needs a separating blank line
            out.append(line)
            in_list = is_list_start
            continue

        if prev_is_prose and not prev.endswith("  "):
            out[-1] = prev.rstrip() + " " + stripped
        else:
            out.append(line)
    return "\n".join(out)


def render_markdown(body: str, titles: dict[str, str]) -> str:
    # a "follows" note is a head label, never a box in the text (FR-035)
    body = drop_follows(body)
    # unwrap hard-wrapped prose first — before wikilinks turn a leading
    # [[...]] into an <a>, which would otherwise look like an HTML block start
    body = _unwrap_prose(body)
    # full-text bodies get real hyperlinks; inline-snippet helpers keep spans
    body = render_wikilinks(body, titles, link_index())
    # turn Obsidian callouts `> [!type] title` into a bold label line
    body = CALLOUT_RE.sub(lambda m: f"> **{m.group(2) or m.group(1).title()}**", body)
    return md.markdown(body, extensions=["extra", "sane_lists"])


def extract_labeled(page: Page, label: str, titles: dict[str, str],
                    links: dict[str, tuple[str, str]] | None = None) -> str:
    """Pull the paragraph introduced by a bold lead like **Definition.** or
    **Snapshot.**, collapse whitespace, and render its wikilinks. Pass `links`
    (a link index) to turn resolvable targets into real hyperlinks instead of
    styled-text spans."""
    rx = re.compile(r"\*\*" + re.escape(label) + r"\.\*\*\s*(.+?)(?=\n\s*\n|\n\s*\*\*|$)", re.DOTALL)
    m = rx.search(page.body)
    raw = m.group(1).strip() if m else ""
    raw = re.sub(r"\s+", " ", raw)
    return render_wikilinks(raw, titles, links)


_PAM_BULLET_RE = re.compile(
    r"^[ \t]*-\s+\*\*(?P<label>[A-Za-z]+)\.\*\*\s+"
    r"(?P<body>.+?)(?=\n[ \t]*-\s+\*\*|\n##\s|\n\s*\n|\Z)",
    re.DOTALL | re.MULTILINE,
)


def extract_pam_bullet(page: Page, label: str, titles: dict[str, str],
                       links: dict[str, tuple[str, str]] | None = None) -> str:
    """Pull a bullet-style PAM field (`- **Purpose.** …`) from a goal body.
    Bullets can wrap onto continuation lines; stops at the next sibling bullet,
    a new heading, or a blank line. Pass `links` to emit real hyperlinks."""
    for m in _PAM_BULLET_RE.finditer(page.body):
        if m.group("label").lower() == label.lower():
            raw = re.sub(r"\s+", " ", m.group("body")).strip()
            return render_wikilinks(raw, titles, links)
    return ""


# Status values that count as "closed" for the issues filter.
CLOSED_STATUSES = {"resolved", "wontfix"}


def is_open_issue(status: object) -> bool:
    """The one meaning of "open" for an issue: every status except resolved
    and wontfix. A missing or unknown status stays visible as open."""
    return str(status or "").strip().lower() not in CLOSED_STATUSES


# The four-step lifecycle every content type shares (AGENTS.md: draft → review →
# accepted → deprecated). Issue statuses are mapped onto it so one thin
# bar reads the same on every tile.
MATURITY_ORDER = ["accepted", "review", "draft", "deprecated"]
_MATURITY_ALIASES = {
    "proposed": "review", "in-progress": "review",
    "resolved": "accepted", "ingested": "accepted",
    "open": "draft",
    "superseded": "deprecated", "rejected": "deprecated", "wontfix": "deprecated",
}


def maturity(statuses) -> dict:
    """Bucket status strings into MATURITY_ORDER and return the segments of a
    stacked bar (percent widths) plus a text label for the tooltip/aria."""
    counts = {k: 0 for k in MATURITY_ORDER}
    for s in statuses:
        s = _MATURITY_ALIASES.get(str(s or "").strip().lower(), str(s or "").strip().lower())
        counts[s if s in counts else "draft"] += 1
    total = sum(counts.values())
    segments = [{"status": k, "n": counts[k], "pct": round(100 * counts[k] / total)}
                for k in MATURITY_ORDER if counts[k]]
    label = " · ".join(f'{s["n"]} {s["status"]}' for s in segments) or "nothing yet"
    return {"total": total, "segments": segments, "label": label}


# --- decision records (wiki/decisions/, MADR, DR-034) ----------------------

DECISION_KINDS = ["architecture", "business", "undefined"]


_INLINE_MD_RE = re.compile(r"\*\*(?P<b>[^*]+)\*\*|`(?P<c>[^`]+)`|\*(?P<i>[^*]+)\*")


def _strip_inline_markdown(text: str) -> str:
    """Titles are read as raw text, not rendered, so `**bold**` and
    `` `code` `` would reach the /decisions list with their asterisks and
    backticks on screen. Titles are plain text there."""
    return _INLINE_MD_RE.sub(lambda m: m.group("b") or m.group("c") or m.group("i"),
                             text).strip()


@_request_cached
def load_decisions() -> list[dict]:
    """Decision records (wiki/decisions/) as list rows with rendered bodies, in
    ID order. `kind` outside architecture|business falls back to undefined."""
    titles = title_index()
    out = []
    for p in sorted(load_folder("decisions"), key=lambda p: p.id):
        kind = str(p.meta.get("kind") or "").strip().lower()
        decided = p.meta.get("decided") or p.meta.get("created") or ""
        out.append({
            "id": p.id,
            "stem": p.stem,
            "title": _strip_inline_markdown(str(p.title)),
            "status": str(p.status or "draft").strip().lower(),
            "kind": kind if kind in DECISION_KINDS else "undefined",
            "decided": str(decided) or "—",
            "aliases": p.aliases,
            "url": _page_url("decisions", p.stem),
            "drivers": [l for g in build_drivers(p.stem) for l in g["links"]],
            "html": render_markdown(p.body, titles),
        })
    return out


# --- Systems42 sections (DR-033) ------------------------------------------
#
# The section catalog (catalog.py) is the single source: three areas
# (Requirements, Architecture, Commons), eighteen sections R1-R6, A1-A5, C1-C7.
# Each section maps to zero or more wiki folders; an "entry" is one page in
# those folders. "href" is where the section's "View all" link points: an
# existing rich view where one exists (glossary/stakeholders/issues), otherwise
# a generic /req42/<slug> list.

# Human-readable type label per wiki folder, for the "Type" column.
FOLDER_LABELS = {
    "goals": "Goal",
    "context": "Context",
    "external-interfaces": "External interface",
    "functional-requirements": "Functional requirement",
    "use-cases": "Use case",
    "activity-models": "Activity model",
    "data-models": "Data model",
    "quality-requirements": "Quality requirement",
    "constraints": "Constraint",
    "glossary": "Glossary term",
    "stakeholders": "Stakeholder",
    "issues": "Issue",
    "decisions": "Decision record",
    "building-blocks": "Building block",
    "concepts": "Crosscutting concept",
    "runtime-scenarios": "Runtime scenario",
    "deployment-nodes": "Deployment node",
}

REQ42_BY_SLUG = catalog.SECTION_BY_SLUG


def _block_pages(block: dict) -> list[Page]:
    """All wiki pages feeding one req42 block, sorted by id."""
    pages: list[Page] = []
    for folder in block["folders"]:
        pages.extend(load_folder(folder))
    return sorted(pages, key=lambda p: p.id)


# --- context diagram (req42 block 03) --------------------------------------
#
# The system context is NOT stored as a diagram (DR-013, ISS-010): it is
# projected live from the structured edges — each external interface's `flows`
# and each stakeholder's `provides:`/`receives:` — into a mermaid flowchart.
# Center = the system (blueish box); systems/organizations = light-grey boxes;
# human roles = actor symbol ("Person"). Stakeholders are merged/hidden/shaped per their
# `context_role`/`nature` fields (DR-014). No node links (not needed yet).

_NID_RE = re.compile(r"[^A-Za-z0-9]")


def _diagram_node_id(raw: str) -> str:
    return _NID_RE.sub("", str(raw)) or "N"


def _clean_label(s: object, drop_parenthetical: bool = True) -> str:
    """Resolve [[a|b]]→b / [[a]]→a, optionally drop a trailing (parenthetical),
    strip chars that would break the mermaid/HTML text so labels are always
    render-safe.

    `drop_parenthetical=False` for the system name: a vault called
    "Bookshelf (v2)" showed in full in the hero but as "Bookshelf" in every
    diagram, which reads as two different systems on the same screen.
    Square brackets are stripped because mermaid uses them as node-shape
    delimiters; apostrophes are kept — labels are emitted inside double
    quotes, and "Member's card" should stay readable.
    """
    t = str(s or "")
    t = re.sub(r"\[\[[^\]|]+\|([^\]]+)\]\]", r"\1", t)                       # [[a|b]] -> b
    t = re.sub(r"\[\[([^\]]+)\]\]", lambda m: m.group(1).split("/")[-1], t)  # [[a]]   -> a
    if drop_parenthetical:
        t = re.sub(r"\s*\([^)]*\)\s*$", "", t)                               # trailing (…)
    t = t.replace("&", " and ")          # never silently delete: "A & B" -> "A and B"
    t = re.sub(r'[<>"|\[\]]', "", t)
    return re.sub(r"\s+", " ", t).strip()


# Layout bands (DR-026 `tier:`). Neighbours that feed the system are ranked
# BEFORE the centre, those it serves AFTER it, so mermaid's LR layout puts
# supply/support on the left and demand/operations on the right instead of
# scattering fourteen nodes around one box.
_TIER_BANDS = [
    ("supply", "Supply", "left"),
    ("support", "Support", "left"),
    ("demand", "Demand", "right"),
    ("core-operations", "Core operations", "right"),
]
_TIER_LABEL = {k: lbl for k, lbl, _ in _TIER_BANDS}


def _eif_node_label(p) -> str:
    """Short label for a diagram node: `short_title` wins, then `title`, and
    `partner` only as a last resort — `partner` is a full sentence by design and
    is what made the projection unreadable at fourteen nodes."""
    return _clean_label(p.meta.get("short_title") or p.title or p.meta.get("partner"))


def _flow_edge_label(flows: list[dict]) -> str:
    """One label for one line. Each flow's `label:` is a word or two; duplicates
    collapse (a round trip about the same thing reads once), and a flow with no
    label falls back to its `data`, clipped."""
    seen: list[str] = []
    for f in flows:
        lab = _clean_label(f.get("label") or "")
        if not lab:
            lab = _clean_label(f.get("data") or "")
            if len(lab) > 24:
                lab = lab[:23].rstrip() + "…"
        if lab and lab not in seen:
            seen.append(lab)
    return " · ".join(seen)


def _eif_flows(p) -> tuple[list[dict], list[dict], list[dict]]:
    """(inbound, outbound, all-in-document-order) flow dicts for one interface.
    The third is what labels the edge, so the label reads in the order the author
    wrote the flows rather than in-then-out."""
    flows = [f for f in (p.meta.get("flows") or []) if isinstance(f, dict)]
    d = lambda f: str(f.get("direction", "")).lower()
    return ([f for f in flows if d(f) in ("inbound", "bidirectional")],
            [f for f in flows if d(f) in ("outbound", "bidirectional")],
            flows)


def build_context_diagram(center: str | None = None) -> str | None:
    """Project a mermaid context diagram from EIF.flows + STK.provides/receives.

    One line per neighbour, not one per direction: an interface with both an
    inbound and an outbound flow draws a single `<-->` edge carrying a single
    label, and the two directions are spelled out in the flow table beneath
    (build_context_flows). Returns None when no edges exist yet. Pure and
    string-only, so it can be reused outside the request cycle."""
    center = center or _clean_label(wiki_config()["system_name"], drop_parenthetical=False)
    core = "CORE"
    bands: dict[str, list[tuple[str, str, str]]] = {}   # tier -> [(nid, label, cls)]
    loose: list[tuple[str, str, str]] = []
    edges: list[str] = []

    def add_edge(nid: str, ins: list, outs: list, side: str, ordered: list | None = None) -> None:
        """`side` decides which end of the edge the neighbour sits on, which is
        what actually positions it: mermaid ranks the source before the target."""
        if ins and outs:
            lab = _flow_edge_label(ordered if ordered is not None else ins + outs)
            src, arrow, dst = (nid, "<-->", core) if side == "left" else (core, "<-->", nid)
        elif ins:
            lab, src, arrow, dst = _flow_edge_label(ins), nid, "-->", core
        elif outs:
            lab, src, arrow, dst = _flow_edge_label(outs), core, "-->", nid
        else:
            return
        edges.append(f'  {src} {arrow}|"{lab}"| {dst}' if lab else f"  {src} {arrow} {dst}")

    # real external systems — one node each (DR-013), one line each (DR-026).
    # A deprecated interface is one the boundary decision moved *inside* the
    # system (ISS-010), so it is no longer a neighbour and must not be drawn.
    for p in load_folder("external-interfaces"):
        if p.status == "deprecated":
            continue
        ins, outs, ordered = _eif_flows(p)
        if not (ins or outs):
            continue
        nid = _diagram_node_id(p.id)
        tier = str(p.meta.get("tier") or "").strip().lower()
        side = next((s for k, _, s in _TIER_BANDS if k == tier), "left")
        (bands.setdefault(tier, []) if tier in _TIER_LABEL else loose).append(
            (nid, _eif_node_label(p), "system"))
        add_edge(nid, ins, outs, side, ordered)

    # user roles — flows live on the stakeholder, not as EIF nodes. DR-014:
    # several stakeholders sharing a `context_role` merge into ONE node (union of
    # their flows); `context_role: none` hides the role; `nature: organization`
    # draws a box instead of the person/actor symbol.
    def _union(dst: list, src) -> None:
        for x in (src or []):
            if x not in dst:
                dst.append(x)

    groups: dict[str, dict] = {}   # label -> {prov, recv, cls, order}
    for p in load_folder("stakeholders"):
        prov, recv = p.meta.get("provides") or [], p.meta.get("receives") or []
        if not (prov or recv):
            continue
        raw_role = p.meta.get("context_role")
        if isinstance(raw_role, str) and raw_role.strip().lower() == "none":
            continue
        label = _clean_label(raw_role) if raw_role else _clean_label(p.title)
        is_org = str(p.meta.get("nature", "person")).strip().lower() == "organization"
        g = groups.get(label)
        if g is None:
            g = groups[label] = {"prov": [], "recv": [], "cls": "actor", "order": len(groups)}
        if is_org:
            g["cls"] = "system"          # organizations/systems share the box style
        _union(g["prov"], prov)
        _union(g["recv"], recv)

    for label, g in sorted(groups.items(), key=lambda kv: kv[1]["order"]):
        nid = _diagram_node_id(label)
        loose.append((nid, label, g["cls"]))
        ins = [{"data": x} for x in g["prov"]]
        outs = [{"data": x} for x in g["recv"]]
        add_edge(nid, ins, outs, "left")

    if not edges:
        return None

    def node_line(nid: str, label: str, cls: str) -> str:
        # persons get the actor symbol (stadium + "Person"); systems/orgs are boxes
        return (f'  {nid}(["Person · {label}"]):::actor' if cls == "actor"
                else f'  {nid}["{label}"]:::{cls}')

    lines = ["flowchart LR"]
    for tier, tier_label, _ in _TIER_BANDS:
        if not bands.get(tier):
            continue
        lines.append(f'  subgraph {_diagram_node_id(tier)}["{tier_label}"]')
        lines.append("    direction TB")
        lines += ["  " + node_line(*n) for n in bands[tier]]
        lines.append("  end")
    lines.append(f'  {core}["{_clean_label(center)}"]:::core')
    lines += [node_line(*n) for n in loose]
    lines += edges
    lines += [
        "  classDef core fill:#2f6fb3,stroke:#7fc0ff,stroke-width:2px,color:#ffffff,font-weight:bold;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef actor fill:#f3f6fb,stroke:#aeb8c9,color:#15202e;",
    ]
    return "\n".join(lines)


def build_context_flows() -> list[dict]:
    """The diagram's edges, spelled out. One group per neighbour, both
    directions listed — this is where the detail that was removed from the
    node and edge labels goes (DR-026). `unknown`/empty cells come back as
    None so the template can render a dash instead of the word."""
    def cell(v) -> str | None:
        s = _clean_label(v or "")
        return None if not s or s.lower() in ("unknown", "n/a", "none") else s

    groups: list[dict] = []
    for p in load_folder("external-interfaces"):
        if p.status == "deprecated":
            continue
        ins, outs, ordered = _eif_flows(p)
        if not (ins or outs):
            continue
        rows = []
        for f, direction in [(f, "in") for f in ins] + [(f, "out") for f in outs]:
            rows.append({"direction": direction, "data": cell(f.get("data")) or "—",
                         "format": cell(f.get("format")), "trigger": cell(f.get("trigger"))})
        groups.append({
            "id": p.id, "stem": p.stem, "name": _eif_node_label(p),
            "partner": _clean_label(p.meta.get("partner") or ""),
            "tier": _TIER_LABEL.get(str(p.meta.get("tier") or "").strip().lower(), ""),
            "label": _flow_edge_label(ordered), "rows": rows,
        })
    return groups


# --- glossary term network (DR-023) --------------------------------------
#
# A force-directed graph of the glossary, projected from the `related:` edges.
# The server emits cytoscape elements ({nodes, edges}); the browser lays them
# out (cytoscape.js). Single source of truth stays the typed edges — only the
# layout is client-side. Default view is GLO-only; cross-type neighbours (1-hop)
# are revealed per type by buttons. Edges are undirected & deduplicated and come
# ONLY from `related:` frontmatter (body wikilinks would add uncurated noise, so
# link_targets() is deliberately NOT used here).

# Stem prefix -> wiki folder, for click-through URLs (/page/<folder>/<stem>).
_TYPE_FOLDER = {
    "GLO": "glossary", "DM": "data-models", "STK": "stakeholders",
    "EIF": "external-interfaces", "GOAL": "goals", "CTX": "context",
    "FR": "functional-requirements", "CON": "constraints", "ISS": "issues",
    "UC": "use-cases", "ACT": "activity-models", "QR": "quality-requirements",
    "DR": "decisions", "BB": "building-blocks", "CC": "concepts",
    "RS": "runtime-scenarios", "DN": "deployment-nodes",
}


def _stem_of_link(raw: object) -> str:
    """A `related:` entry like '[[GLO-026-eaqua|EAquA]]' -> 'GLO-026-eaqua'."""
    t = str(raw or "").strip()
    m = re.search(r"\[\[([^\]]+)\]\]", t)
    if m:
        t = m.group(1)
    t = t.split("|")[0].split("#")[0].strip()   # drop alias / anchor
    return t.split("/")[-1].strip()             # drop raw/ path prefix


def _type_of(stem: str) -> str:
    return stem.split("-")[0] if "-" in stem else stem


def build_glossary_graph() -> dict:
    """Project the glossary term network from `related:` edges (DR-023).

    Pure and dict-only, so it is testable and reusable outside a request.
    Returns cytoscape elements: {"nodes", "edges", "layer_counts"}. GLO nodes
    carry core=True (shown by default); cross-type neighbours (1-hop) are tagged
    by type for the layer buttons. Edges are undirected and deduplicated and
    sourced only from `related:`."""
    glossary = load_folder("glossary")
    glo_stems = {p.stem for p in glossary}
    by_stem = {p.stem: p for p in load_all_pages()}   # existence + title/folder

    seen_pairs: set[frozenset] = set()
    edges: list[dict] = []
    glo_degree: dict[str, int] = {s: 0 for s in glo_stems}
    neighbour_stems: set[str] = set()

    for p in glossary:                       # src is always a GLO page
        src = p.stem
        for raw in (p.meta.get("related") or []):
            tgt = _stem_of_link(raw)
            if not tgt or tgt == src or tgt not in by_stem:
                continue                     # self / dangling / non-page
            pair = frozenset((src, tgt))
            if pair in seen_pairs:
                continue                     # undirected dedup
            seen_pairs.add(pair)
            cross = tgt not in glo_stems
            edge = {"id": f"e{len(edges)}", "source": src, "target": tgt, "cross": cross}
            if cross:
                edge["ntype"] = _type_of(tgt)
                neighbour_stems.add(tgt)
            else:
                glo_degree[src] += 1
                glo_degree[tgt] += 1
            edges.append(edge)

    nodes: list[dict] = []
    for p in glossary:
        state = ("deprecated" if p.status == "deprecated"
                 else "agreed" if p.meta.get("agreed") is True
                 else "draft")
        nodes.append({
            "id": p.stem, "label": p.title, "type": "GLO", "core": True,
            "url": f"/page/glossary/{p.stem}",
            "degree": glo_degree.get(p.stem, 0),
            "state": state,
            "assumption": "[!assumption]" in p.body,
            "aliases": ", ".join(p.aliases),
        })
    named = {"DM", "STK", "EIF", "GOAL", "BB"}   # types with their own colour + button
    for stem in sorted(neighbour_stems):
        pg = by_stem[stem]
        ntype = _type_of(stem)
        node = {
            "id": stem, "label": pg.title, "type": ntype, "core": False,
            "url": f"/page/{_TYPE_FOLDER.get(ntype, pg.folder)}/{stem}",
        }
        if ntype not in named:
            node["rest"] = 1   # CTX/FR/CON/ISS/… → grey, selected via node[rest]
        nodes.append(node)

    layer_counts: dict[str, int] = {}
    for e in edges:
        if e["cross"]:
            layer_counts[e["ntype"]] = layer_counts.get(e["ntype"], 0) + 1

    return {
        "nodes": [{"data": n} for n in nodes],
        "edges": [{"data": e} for e in edges],
        "layer_counts": layer_counts,
    }


# Neighbour types the per-term ego snippet offers as buttons (DR-023): GLO shown by
# default, DM/STK/GOAL revealed on demand. A focused 1-hop slice for a glossary detail page.
_EGO_TYPES = {"GLO", "DM", "STK", "GOAL", "BB"}


def build_glossary_ego_graph(stem: str) -> dict | None:
    """1-hop ego network of a single glossary term for the detail-page snippet
    (DR-023): the focal GLO node + its immediate neighbours of type GLO/DM/STK/GOAL
    and the edges among them. A pure filtered projection of build_glossary_graph();
    returns None if the term has no node (not a glossary page)."""
    full = build_glossary_graph()
    node_by_id = {n["data"]["id"]: n["data"] for n in full["nodes"]}
    if stem not in node_by_id:
        return None

    nbrs: set[str] = set()
    for e in full["edges"]:
        d = e["data"]
        if d["source"] == stem:
            nbrs.add(d["target"])
        elif d["target"] == stem:
            nbrs.add(d["source"])

    ego_ids = {stem} | {n for n in nbrs
                        if node_by_id.get(n, {}).get("type") in _EGO_TYPES}

    nodes = []
    for nid in ego_ids:
        data = dict(node_by_id[nid])
        if nid == stem:
            data["focus"] = True
        nodes.append({"data": data})
    edges = [e for e in full["edges"]
             if e["data"]["source"] in ego_ids and e["data"]["target"] in ego_ids]

    layer_counts: dict[str, int] = {}
    for e in edges:
        d = e["data"]
        if d.get("cross") and d.get("ntype") in _EGO_TYPES:
            layer_counts[d["ntype"]] = layer_counts.get(d["ntype"], 0) + 1

    return {"nodes": nodes, "edges": edges, "layer_counts": layer_counts}


# Group label per stem-type for the detail-page relations panel.
_TYPE_LABEL = {
    "GLO": "Glossary", "STK": "Stakeholders", "DM": "Data models", "CTX": "Context",
    "EIF": "External interfaces", "GOAL": "Goals", "FR": "Functional requirements",
    "UC": "Use cases", "ACT": "Activity models", "QR": "Quality requirements",
    "CON": "Constraints", "DR": "Decisions", "BB": "Building blocks", "CC": "Concepts",
    "RS": "Runtime scenarios", "DN": "Deployment nodes", "ISS": "Issues",
}
_REL_TYPE_ORDER = ["GLO", "STK", "DM", "CTX", "EIF", "GOAL", "FR", "UC", "ACT", "QR", "CON", "DR", "BB", "CC", "RS", "DN", "ISS"]


def build_relations_panel(stem: str, exclude: set[str] | None = None) -> dict:
    """Outbound links (this page's `related:` + body wikilinks) and inbound
    backlinks (other pages that reference it), grouped by type, as link dicts.
    A pure projection over the link graph (DR-018) — powers the outbound
    / inbound relations section on a detail page. `exclude` drops stems the
    page already lists in a typed panel (drivers, addressed by, …). A linked
    issue carries its `status` and whether it is `closed`."""
    exclude = exclude or set()
    titles = title_index()
    pages = load_all_pages()
    by_stem = {p.stem: p for p in pages}

    def info(s: str) -> dict:
        ntype = _type_of(s)
        folder = _TYPE_FOLDER.get(ntype)
        if folder == "functional-requirements":
            url = f"/functional-requirements/{s}"
        elif folder:
            url = f"/page/{folder}/{s}"
        else:
            url = f"/page/{by_stem[s].folder}/{s}"
        item = {"id": by_stem[s].id if s in by_stem else s,
                "label": titles.get(s, s), "url": url, "type": ntype,
                "status": "", "closed": False}
        if s in by_stem and by_stem[s].folder == "issues":
            # a linked issue says how firm it is, closed the way the issues
            # panel says it (FR-034, FR-027)
            st = by_stem[s].status
            item["status"] = st if st in _issue_vocab()["status"] else ""
            item["closed"] = not is_open_issue(st)
        return item

    me = by_stem.get(stem)
    outbound = sorted(s for s in (me.link_targets() if me else ())
                      if s in by_stem and s not in exclude)
    out_set = set(outbound)
    inbound = sorted(q.stem for q in pages
                     if q.stem != stem and q.stem not in out_set and q.stem not in exclude
                     and stem in q.link_targets())

    def grouped(stems: list) -> list:
        buckets: dict[str, list] = {}
        for s in stems:
            i = info(s)
            buckets.setdefault(i["type"], []).append(i)
        ordered = _REL_TYPE_ORDER + [t for t in buckets if t not in _REL_TYPE_ORDER]
        return [{"type": t, "label": _TYPE_LABEL.get(t, t), "links": buckets[t]}
                for t in ordered if t in buckets]

    return {"outbound": grouped(outbound), "inbound": grouped(inbound)}


# --- goals (req42 block 01: vision + objectives) ---------------------------
#
# One content type `goal` with stereotype `vision | objective` (DR-016).
# The vision is the goal page carrying `stereotype: vision` (bootstrap.md step 3
# writes it as GOAL-001); every other goal page is an objective. Nothing is
# keyed off an ID list — a vault may hold any number of objectives at any IDs,
# and all of them must reach the screen.
# The Goal↔Epic edge is pinned at the Epic (`goal:` field on each FR, DR-018),
# and a use case carries the same field (DR-011); coverage and tile counters are
# pure projections from those edges.


def _goal_id_from_ref(ref: object) -> str:
    """From '[[GOAL-002-foo]]' / 'GOAL-002-foo' / 'GOAL-002', return 'GOAL-002'."""
    s = str(ref or "").strip()
    m = re.match(r"\[\[([^\]\|#]+)", s)
    stem = (m.group(1) if m else s).split("/")[-1].strip()
    parts = stem.split("-", 2)
    if len(parts) >= 2 and parts[0].upper() == "GOAL":
        return f"GOAL-{parts[1]}"
    return stem


def _goal_maturity(p: Page) -> str:
    """PAM until `horizon:` is set, then promotion to SMART (DR-016 / anchor)."""
    return "SMART" if str(p.meta.get("horizon") or "").strip() else "PAM"


_VISION_SECTION_RE = re.compile(r"##\s+Vision\b[^\n]*\n+(.+?)(?=\n##\s|\Z)", re.DOTALL)


def _vision_paragraphs(page: Page, titles: dict[str, str],
                       links: dict[str, tuple[str, str]] | None = None) -> list[str]:
    """Every prose paragraph under `## Vision` in the Vision page, inline
    markdown (`**bold**`, wikilinks) rendered, no <p> wrapper. Pass `links` to
    emit real hyperlinks for resolvable targets.

    Skipped: notes and callouts (`> …`), HTML comments, and the template's
    `*Optional:*` hint and `**Objectives.**` pointer. Only the first paragraph used to be shown, so a
    vision that opened with "> follows the Geoffrey Moore format" showed that
    note and nothing else."""
    if not page:
        return []
    m = _VISION_SECTION_RE.search(page.body)
    if not m:
        return []
    out = []
    for para in m.group(1).split("\n\n"):
        para = para.strip()
        if not para or para.startswith((">", "<!--", "**Objectives.**", "*Optional:*")):
            continue
        para = re.sub(r"\s+", " ", para)
        para = render_wikilinks(para, titles, links)
        out.append(re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", para))
    return out


ENABLER_LANES = ("platform", "display")


def _in_enabler_lane(fr: Page) -> bool:
    return str(fr.meta.get("lane") or "").strip().lower() in ENABLER_LANES


def is_enabler(fr: Page, goals: list) -> bool:
    """rel-goal: an FR that serves no goal (`goals`, its own or its use-case
    parent's) and sits in lane platform or display is an explicit enabler."""
    return not goals and _in_enabler_lane(fr)


def breaks_fr_traces_to_goal(fr: Page, goals: list) -> bool:
    """rule-fr-traces-to-goal: an epic or feature serves a goal (`goals`, its
    own or its use-case parent's) or is an enabler. Advisory only."""
    if str(fr.meta.get("stereotype") or "").strip().lower() not in ("epic", "feature"):
        return False
    return not goals and not _in_enabler_lane(fr)


def load_goals() -> dict:
    """Return everything the tile and /goals page need.

    Shape:
      vision     — the goal Page with `stereotype: vision`, or None
      objectives — every other goal Page, ordered by id (GOAL-002, -003, …)
      coverage   — { 'GOAL-NNN': [FR- or UC-Page, ...] } from goal: backlinks
      enablers   — FR-Pages that serve no goal, in lane platform or display
      untraced   — FR-Pages that break rule-fr-traces-to-goal
      frs        — all FR-Pages sorted by id (column order for the matrix)
      ucs        — all use-case Pages sorted by id (DR-011: use cases are FRs;
                   a UC with goal: [] is simply untraced, not an enabler)

    Derived entirely from the vault, never from a fixed ID list: a group may
    capture any number of objectives at any IDs and every one of them shows up.
    Anything that is not *the* vision counts as an objective, so a goal page
    with a missing or misspelt `stereotype:` is still rendered rather than
    silently dropped. If two pages claim `stereotype: vision`, the
    lowest-id one is the vision and the rest fall through to objectives.
    """
    goals = sorted(load_folder("goals"), key=lambda p: p.id)

    def _stereotype(p: Page) -> str:
        return str(p.meta.get("stereotype") or "").strip().lower()

    visions = [p for p in goals if _stereotype(p) == "vision"]
    vision = visions[0] if visions else None
    objectives = [p for p in goals if p is not vision]

    frs = sorted(load_folder("functional-requirements"), key=lambda p: p.id)
    ucs = sorted(load_folder("use-cases"), key=lambda p: p.id)
    uc_by_stem = {u.stem: u for u in ucs}
    coverage: dict[str, list[Page]] = {o.id: [] for o in objectives}
    objective_by_stem = {o.stem: o for o in objectives}

    def served(p: Page) -> list[str]:
        # only links that resolve to an objective count: the vision, a missing
        # page or a mangled value serves no goal (rule-fr-traces-to-goal)
        return [objective_by_stem[s].id for s in links_of(p, "goal") if s in objective_by_stem]

    enablers: list[Page] = []
    untraced: list[Page] = []
    for fr in frs:
        gids = served(fr)
        if not gids:
            # a feature/story refining a use case serves that use case's goals
            uc = next((uc_by_stem[s] for s in links_of(fr, "parent") if s in uc_by_stem), None)
            gids = served(uc) if uc else []
        if is_enabler(fr, gids):
            enablers.append(fr)
        elif breaks_fr_traces_to_goal(fr, gids):
            untraced.append(fr)
        for gid in gids:
            coverage[gid].append(fr)
    for uc in ucs:
        for gid in served(uc):
            if uc not in coverage[gid]:
                coverage[gid].append(uc)
    return {"vision": vision, "objectives": objectives,
            "coverage": coverage, "enablers": enablers, "untraced": untraced,
            "frs": frs, "ucs": ucs}


def build_vision_tile(data: dict, titles: dict[str, str]) -> dict:
    """The home-tile payload for the Vision card (key='vision')."""
    vision = data["vision"]
    objectives = data["objectives"]
    coverage = data["coverage"]
    if not vision:
        # Day-one state, and the first tile on the projector: no counter, no
        # "Demo" chip — a heading, a next step, and a link to /goals, like
        # every other empty tile. Deliberately carries no `count`/`unit` so
        # index.html renders the empty state rather than a placeholder dash.
        return {
            "key": "vision", "label": "Vision", "eyebrow": "01 · Business Goals",
            "href": "/goals", "folders": ["goals"], "span": 2,
            "rows": [], "active": False,
        }
    claim = str(vision.meta.get("tile_claim") or "").strip()
    rows = [{
        "id": o.id,
        "title": o.title,
        "epics": len(coverage.get(o.id, [])),
    } for o in objectives]
    return {
        "key": "vision", "label": "Vision", "eyebrow": "01 · Business Goals",
        "href": "/goals", "folders": ["goals"], "span": 2,
        "active": True,
        "claim": claim,
        "objective_rows": rows,
    }


# --- functional requirements (req42 block 04: Epic→Feature→Story hierarchy) ---
#
# One content type `functional-requirement` with stereotype epic|feature|story
# (DR-012). The hierarchy edge is the `parent:` wikilink field; build_fr_hierarchy
# is a pure projection over those edges — the single source for both the home
# tile and the /req42/functional-requirements page (cf. load_goals / _mermaid_goal_tree).

def _fr_stem_from_ref(ref: object) -> str:
    """From '[[FR-009-foo]]' / 'FR-009-foo' / a bare stem, return the page stem
    (children are matched to parents by stem)."""
    s = str(ref or "").strip()
    m = re.match(r"\[\[([^\]\|#]+)", s)
    return (m.group(1) if m else s).split("/")[-1].strip()


def _fr_stereotype(p: "Page") -> str:
    return str(p.meta.get("stereotype") or "").strip().lower()


def _fr_sort_key(p: "Page"):
    """Hierarchy order: numeric `order:` field, then id as a stable tiebreak."""
    try:
        order = int(p.meta.get("order"))
    except (TypeError, ValueError):
        order = 9999
    return (order, p.id)


def _fr_node(p: "Page") -> dict:
    """Slim per-page record shared by tile rows, cards, and the diagram."""
    return {
        "id": p.id, "title": p.title, "stem": p.stem,
        "priority": str(p.meta.get("priority") or "").strip(),
        "status": p.status,
    }


def build_fr_hierarchy() -> dict:
    """Project the Epic→Feature→Story hierarchy from each FR's `parent:` field.

    Returns:
      epics          — list of epic dicts in `order` then id order; each carries
                       `features` (with nested `stories`), `direct_stories`
                       (stories hung straight off the epic), `n_features`
                       (direct feature children) and `n_stories` (its direct
                       stories plus the stories of its direct features — exactly
                       what the page renders), plus priority/release/status.
      total_epics / total_features / total_stories — aggregate counters.
      use_cases      — use cases with FR children (rel-parent, DR-011): same
                       shape as an epic row (features, direct_stories, counts).
                       A feature or story may name a use case as its parent.
      orphans        — feature/story pages whose parent does not resolve to a
                       known FR or use case (normally empty; surfaced for visibility).
    """
    # A deprecated item has been retired — split, superseded or withdrawn — so it
    # is not part of the live hierarchy and must not be counted, drawn, or listed as
    # an orphan. Same rule as the context projection applies to a deprecated
    # interface. A live child of a retired parent correctly becomes an orphan.
    pages = [p for p in load_folder("functional-requirements")
             if p.status != "deprecated"]
    by_stem = {p.stem: p for p in pages}

    def parent_stem(p: "Page") -> str | None:
        # The hierarchy is a tree: we take the first parent only. A page with
        # multiple parents is placed under its first; multi-parent graphs are
        # out of scope for this view.
        for ref in (p.meta.get("parent") or []):
            stem = _fr_stem_from_ref(ref)
            if stem:
                return stem
        return None

    children: dict[str, list["Page"]] = {}
    for p in pages:
        ps = parent_stem(p)
        if ps:
            children.setdefault(ps, []).append(p)

    def kids(stem: str, stereo: str) -> list["Page"]:
        return sorted((c for c in children.get(stem, []) if _fr_stereotype(c) == stereo),
                      key=_fr_sort_key)

    epics = sorted((p for p in pages if _fr_stereotype(p) == "epic"), key=_fr_sort_key)
    epic_rows = []
    total_features = total_stories = 0

    def breakdown(root: "Page") -> dict:
        feats = kids(root.stem, "feature")
        feature_rows = [
            {**_fr_node(f), "stories": [_fr_node(s) for s in kids(f.stem, "story")]}
            for f in feats
        ]
        direct_stories = [_fr_node(s) for s in kids(root.stem, "story")]
        # n_stories counts exactly what the page renders — the root's direct
        # stories plus the stories of its direct features (the model is two
        # levels: root→feature→story / root→story, the root an epic or a use
        # case). Computed from the built
        # structure, not by recursion, so a malformed/cyclic parent: edge can
        # never run away and 500 the dashboard.
        return {
            "n_features": len(feats),
            "n_stories": len(direct_stories) + sum(len(f["stories"]) for f in feature_rows),
            "features": feature_rows,
            "direct_stories": direct_stories,
        }

    for e in epics:
        b = breakdown(e)
        total_features += b["n_features"]
        total_stories += b["n_stories"]
        epic_rows.append({**_fr_node(e),
                          "release": str(e.meta.get("release") or "").strip(), **b})

    # A use case is a functional requirement in its own form (DR-011); features
    # and stories that refine it name it in `parent:`. Only use cases that have
    # such children appear here — the others are listed on their own.
    uc_rows = []
    for u in sorted((q for q in load_folder("use-cases") if q.status != "deprecated"),
                    key=lambda q: q.id):
        if u.stem not in children:
            continue
        b = breakdown(u)
        total_features += b["n_features"]
        total_stories += b["n_stories"]
        uc_rows.append({**_fr_node(u), "url": _page_url("use-cases", u.stem), **b})
    uc_stems = {u["stem"] for u in uc_rows}

    orphans = []
    for p in pages:
        st = _fr_stereotype(p)
        if st in ("feature", "story"):
            ps = parent_stem(p)
            if ps is None or (ps not in by_stem and ps not in uc_stems):
                orphans.append({**_fr_node(p), "stereotype": st})

    return {
        "epics": epic_rows,
        "use_cases": uc_rows,
        "total_epics": len(epics),
        "total_features": total_features,
        "total_stories": total_stories,
        "orphans": orphans,
    }


def _mermaid_goal_epic_tree(goals: dict, hierarchy: dict) -> str | None:
    """Compact top-of-hierarchy map: each Objective links down to the Epics that
    contribute to it (FR `goal:` coverage, DR-018). Enabler epics (lane
    platform or display) hang under a shared `Platform / Enabler` node, epics
    that name no goal under `No goal`, so both stay visible. Two
    levels only — it must stay readable as the hierarchy grows, which is exactly
    why the old full Epic→Feature→Story tree was split out to the epic pages.
    Goal nodes jump to their card on /goals; epic nodes open their epic page.
    Use cases with a `goal:` (DR-011) hang under their goals beside the epics.
    Returns None when there are neither epics nor goal-linked use cases."""
    epics = hierarchy.get("epics") or []
    coverage = goals.get("coverage") or {}
    has_uc = any(p.folder == "use-cases" for ps in coverage.values() for p in ps)
    if not epics and not has_uc:
        return None
    epic_by_id = {e["id"]: e for e in epics}
    objectives = goals.get("objectives") or []
    enablers = goals.get("enablers") or []

    lines = ["graph TD"]
    seen: set[str] = set()

    def epic_edge(parent_nid: str, e: dict) -> None:
        # An epic may contribute to several goals (a DAG): declare its node with
        # label + click once, then reference it by id on every further edge.
        nid = _diagram_node_id(e["id"])
        if e["id"] in seen:
            lines.append(f'  {parent_nid} --> {nid}')
            return
        label = _clean_label(e["title"])
        lines.append(f'  {parent_nid} --> {nid}["{e["id"]}<br/>{label}"]:::epic')
        lines.append(f'  click {nid} "/functional-requirements/{e["stem"]}"')
        seen.add(e["id"])

    def uc_edge(parent_nid: str, uc: Page) -> None:
        nid = _diagram_node_id(uc.id)
        if uc.id in seen:
            lines.append(f'  {parent_nid} --> {nid}')
            return
        label = _clean_label(uc.title)
        lines.append(f'  {parent_nid} --> {nid}["{uc.id}<br/>{label}"]:::usecase')
        lines.append(f'  click {nid} "{_page_url("use-cases", uc.stem)}"')
        seen.add(uc.id)

    for o in objectives:
        gid = _diagram_node_id(o.id)
        glabel = _clean_label(_short_title(o))
        lines.append(f'  {gid}["{o.id}<br/>{glabel}"]:::goal')
        lines.append(f'  click {gid} "/goals#{o.id}"')
        for fr in coverage.get(o.id, []):
            if fr.folder == "use-cases":
                uc_edge(gid, fr)
                continue
            e = epic_by_id.get(fr.id)
            if e:  # only epics belong on this map (features/stories carry no goal:)
                epic_edge(gid, e)

    enabler_epics = [epic_by_id[fr.id] for fr in enablers if fr.id in epic_by_id]
    if enabler_epics:
        lines.append('  ENABLER["Platform / Enabler"]:::enabler')
        for e in enabler_epics:
            epic_edge("ENABLER", e)

    # epics that break rule-fr-traces-to-goal: no enabler, but still on the map
    untraced_epics = [epic_by_id[fr.id] for fr in goals.get("untraced") or []
                      if fr.id in epic_by_id and fr.id not in seen]
    if untraced_epics:
        lines.append('  NOGOAL["No goal"]:::nogoal')
        for e in untraced_epics:
            epic_edge("NOGOAL", e)

    lines += [
        "  classDef goal fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef enabler fill:#3a3f4b,stroke:#7a8497,color:#ffffff,font-weight:bold;",
        "  classDef epic fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef usecase fill:#eef1f6,stroke:#9aa3b2,color:#15202e,stroke-dasharray:4 3;",
        # the warning colour of the matrix's "no goal" flag (--warn)
        "  classDef nogoal fill:#5a3d0c,stroke:#ffb454,color:#ffffff,stroke-width:2px,font-weight:bold;",
    ]
    return "\n".join(lines)


def _mermaid_fr_subtree(node: dict | None) -> str | None:
    """One FR's own breakdown as a focused mermaid, drawn on its FR page so the
    hierarchy overview can stay compact. Handles both an epic root (→ its Features
    → their Stories, plus stories hung straight off the epic) and a feature root
    (→ its Stories). Descendant nodes click through to their own FR page.
    Returns None when the node is a leaf (a story, or an un-broken-down FR)."""
    if not node:
        return None
    feats = node.get("features") or []
    own_stories = node.get("stories") or []          # set when the root is a feature
    direct = node.get("direct_stories") or []        # epic's stories without a feature
    if not feats and not own_stories and not direct:
        return None
    rid = _diagram_node_id(node["id"])
    lines = ["graph TD", f'  {rid}["{node["id"]}<br/>{_clean_label(node["title"])}"]:::root']

    def child(parent_nid: str, rec: dict, css: str) -> str:
        nid = _diagram_node_id(rec["id"])
        label = _clean_label(rec["title"])
        lines.append(f'  {parent_nid} --> {nid}["{rec["id"]}<br/>{label}"]:::{css}')
        lines.append(f'  click {nid} "/functional-requirements/{rec["stem"]}"')
        return nid

    for f in feats:
        fid = child(rid, f, "feature")
        for s in f.get("stories") or []:
            child(fid, s, "story")
    for s in own_stories:
        child(rid, s, "story")
    for s in direct:
        child(rid, s, "story")

    lines += [
        "  classDef root fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef feature fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
        "  classDef story fill:#f3f6fb,stroke:#c4ccd9,color:#15202e;",
    ]
    return "\n".join(lines)


def _fr_hierarchy_node(hierarchy: dict, stem: str) -> tuple[dict | None, str | None]:
    """Locate the built hierarchy node for a stem within build_fr_hierarchy()'s tree.
    Returns (node, kind) with kind ∈ {epic, feature, story}; (None, None) if the
    stem is not an FR in the hierarchy (e.g. an orphan or unknown page)."""
    for e in hierarchy["epics"]:
        if e["stem"] == stem:
            return e, "epic"
        for f in e["features"]:
            if f["stem"] == stem:
                return f, "feature"
            for s in f["stories"]:
                if s["stem"] == stem:
                    return s, "story"
        for s in e["direct_stories"]:
            if s["stem"] == stem:
                return s, "story"
    for u in hierarchy.get("use_cases") or []:
        for f in u["features"]:
            if f["stem"] == stem:
                return f, "feature"
            for s in f["stories"]:
                if s["stem"] == stem:
                    return s, "story"
        for s in u["direct_stories"]:
            if s["stem"] == stem:
                return s, "story"
    return None, None


def _fr_ancestors(stem: str) -> list[dict]:
    """The parent chain for an FR (root epic or use case first), walked over the
    first-parent `parent:` edge. Powers the FR-page breadcrumb. Cycle-guarded.
    A use case (DR-011) is always the top of its chain."""
    pages = {p.stem: p for p in load_folder("functional-requirements")}
    ucs = {p.stem: p for p in load_folder("use-cases")}
    out: list[dict] = []
    cur, seen = pages.get(stem), {stem}
    while cur:
        ps = None
        for ref in (cur.meta.get("parent") or []):
            ps = _fr_stem_from_ref(ref)
            if ps:
                break
        if not ps or ps in seen:
            break
        seen.add(ps)
        if ps in ucs:
            u = ucs[ps]
            out.append({"id": u.id, "title": u.title, "stem": u.stem,
                        "url": _page_url("use-cases", u.stem)})
            break
        parent = pages.get(ps)
        if not parent:
            break
        out.append({"id": parent.id, "title": parent.title, "stem": parent.stem,
                    "url": f"/functional-requirements/{parent.stem}"})
        cur = parent
    return list(reversed(out))


# --- arc42 building blocks (A2) and the `drivers` link ----------------------
#
# One page per building block; levels come from `parent:` (a block whose parent
# is empty, a context page or missing is level 1). The tree, a block's white box
# and the "addressed by" side of `drivers:` are projections, never stored.

def links_of(page: Page, field: str) -> list[str]:
    """Existing target stems of a link field, in order, without duplicates.
    Accepts '[[stem]]', '[[stem|alias]]', a bare stem, a single value or a
    list, and the nested list YAML makes of an unquoted [[stem]]."""
    by_stem = {p.stem for p in load_all_pages()}
    out: list[str] = []

    def walk(v: object) -> None:
        if isinstance(v, (list, tuple)):
            for x in v:
                walk(x)
            return
        s = _stem_of_link(v) if v else ""
        if s and s in by_stem and s not in out:
            out.append(s)

    walk(page.meta.get(field))
    return out


def _bb_parent(p: Page, bb_stems: set[str]) -> str | None:
    return next((s for s in links_of(p, "parent") if s in bb_stems), None)


def _level_tree(folder: str, keep=None) -> list[dict]:
    """The `parent:` levels of one folder as nested dicts, level 1 first, by ID.
    A page whose parent is empty, of another type, missing or filtered out by
    `keep` is level 1. Every page appears exactly once: one caught in a
    `parent:` cycle has no level-1 ancestor, so it is promoted to level 1
    instead of vanishing."""
    pages = {p.stem: p for p in load_folder(folder) if keep is None or keep(p)}
    stems = set(pages)
    children: dict[str | None, list[str]] = {}
    for s, p in pages.items():
        parent = next((x for x in links_of(p, "parent") if x in stems), None)
        children.setdefault(parent, []).append(s)
    seen: set[str] = set()

    def node(s: str) -> dict:
        seen.add(s)
        p = pages[s]
        kids = sorted((k for k in children.get(s, []) if k not in seen), key=lambda k: pages[k].id)
        return {"stem": s, "id": p.id, "title": p.title, "status": p.status,
                "state": page_state(p), "url": _page_url(folder, s),
                "children": [node(k) for k in kids if k not in seen]}

    roots = [node(s) for s in sorted(children.get(None, []), key=lambda k: pages[k].id)]
    for s in sorted(stems - seen, key=lambda k: pages[k].id):
        if s not in seen:
            roots.append(node(s))
    return sorted(roots, key=lambda n: n["id"])


def build_bb_tree() -> list[dict]:
    """The building-block levels (see _level_tree)."""
    return _level_tree("building-blocks")


def _bb_find(nodes: list[dict], stem: str) -> dict | None:
    for n in nodes:
        if n["stem"] == stem:
            return n
        hit = _bb_find(n["children"], stem)
        if hit:
            return hit
    return None


# Lifecycle marks on architecture diagrams (DR-010): planned and target
# elements dashed when the diagram also shows others, outdated or deprecated
# ones grey, a dotted edge from a replaced element to its successor.
_DASHED = "stroke-dasharray:5 4"
_GREYED = "fill:#eceef2,stroke:#9aa3b2,color:#6b7280"
_FUTURE = ("planned", "target")


def lifecycle(p: Page) -> str:
    """The page's state, with `status: deprecated` counting as outdated."""
    return "outdated" if p.status == "deprecated" else page_state(p)


def _mixed(pages: list[Page]) -> bool:
    lcs = {lifecycle(p) for p in pages}
    return bool(lcs & set(_FUTURE)) and bool(lcs - set(_FUTURE))


def _lifecycle_lines(shown: dict[str, tuple[str, Page]]) -> list[str]:
    """Style lines and replaced-by edges for the elements of one diagram,
    given as {stem: (mermaid id, page)}."""
    mixed = _mixed([p for _, p in shown.values()])
    lines: list[str] = []
    for s, (nid, p) in shown.items():
        lc = lifecycle(p)
        if lc == "outdated":
            lines.append(f"  style {nid} {_GREYED}")
        elif lc in _FUTURE and mixed:
            lines.append(f"  style {nid} {_DASHED}")
        lines += [f'  {nid} -. "replaced by" .-> {shown[x][0]}'
                  for x in links_of(p, "superseded-by") if x in shown]
    return lines


def _lifecycle_suffix(p: Page, mixed: bool) -> str:
    lc = lifecycle(p)
    if lc == "outdated" or (lc in _FUTURE and mixed):
        return f" · {lc}"
    return " · being replaced" if links_of(p, "superseded-by") else ""


def build_whitebox(stem: str | None) -> str | None:
    """Mermaid flowchart of a block's inside (stem=None: the whole system, i.e.
    level 1): its children as boxes, their `uses:` among each other as arrows,
    external interfaces they use as neighbour boxes; lifecycle marks per
    _lifecycle_lines. None for a leaf."""
    tree = build_bb_tree()
    if stem is None:
        kids = tree
    else:
        me = _bb_find(tree, stem)
        kids = me["children"] if me else []
    if not kids:
        return None
    inside = {n["stem"] for n in kids}
    pages = {p.stem: p for p in load_folder("building-blocks")}
    eifs = {p.stem: p for p in load_folder("external-interfaces")}
    lines = ["flowchart LR"]
    mixed = _mixed([pages[n["stem"]] for n in kids])
    for n in kids:
        sfx = _lifecycle_suffix(pages[n["stem"]], mixed)
        lines.append(f'  {_diagram_node_id(n["id"])}["{n["id"]} · {_clean_label(n["title"])}{sfx}"]:::block')
    neighbours: list[str] = []
    edges: list[str] = []
    outside: list[str] = []
    for n in kids:
        for t in links_of(pages[n["stem"]], "uses"):
            if t in inside:
                edges.append(f'  {_diagram_node_id(n["id"])} --> {_diagram_node_id(pages[t].id)}')
            elif t in pages:
                # a block elsewhere in the tree: drawn as a neighbour, so the
                # dependency stays visible on this level
                if t not in outside:
                    outside.append(t)
                edges.append(f'  {_diagram_node_id(n["id"])} --> {_diagram_node_id(pages[t].id)}')
            elif t in eifs:
                if t not in neighbours:
                    neighbours.append(t)
                edges.append(f'  {_diagram_node_id(n["id"])} --> {_diagram_node_id(eifs[t].id)}')
    for t in outside:
        lines.append(f'  {_diagram_node_id(pages[t].id)}["{pages[t].id} · {_clean_label(pages[t].title)}'
                     f'{_lifecycle_suffix(pages[t], mixed)}"]:::outside')
    for t in neighbours:
        lines.append(f'  {_diagram_node_id(eifs[t].id)}["{_clean_label(eifs[t].title)}"]:::system')
    lines += edges
    lines += _lifecycle_lines({s: (_diagram_node_id(pages[s].id), pages[s])
                               for s in [n["stem"] for n in kids] + outside})
    lines += [
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef outside fill:#e3ecf7,stroke:#2f6fb3,stroke-dasharray:4 3,color:#15202e;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)


def _link_groups(stems: list[str]) -> list[dict]:
    """Stems as link dicts grouped by type prefix, in the relations-panel order."""
    by_stem = {p.stem: p for p in load_all_pages()}
    buckets: dict[str, list] = {}
    for s in stems:
        p = by_stem[s]
        t = _type_of(s)
        buckets.setdefault(t, []).append({"id": p.id, "label": p.title, "type": t,
                                          "url": _page_url(p.folder, s)})
    ordered = _REL_TYPE_ORDER + [t for t in buckets if t not in _REL_TYPE_ORDER]
    return [{"type": t, "label": _TYPE_LABEL.get(t, t), "links": buckets[t]}
            for t in ordered if t in buckets]


def build_drivers(stem: str) -> list[dict]:
    """The requirements a decision record or building block rests on."""
    p = next((q for q in load_all_pages() if q.stem == stem), None)
    return _link_groups(links_of(p, "drivers")) if p else []


# --- arc42 A3/A4/A5 and `state` (DR-010) -------------------------------------
#
# Every architecture page says whether it describes today's landscape or the
# target (`state:`); a replaced current-state page names its successor in
# `superseded-by:`. Concepts govern blocks and nodes (`applies-to:`), runtime
# scenarios order interactions (`steps:`), nodes host blocks and connect to
# each other. All reverse sides are projected here, never stored.

ARCH_FOLDERS = ("building-blocks", "concepts", "runtime-scenarios", "deployment-nodes")
_STATES = ("outdated", "current", "planned", "target")


def page_state(p: Page) -> str:
    """'current' or 'target'; empty or unknown values count as target."""
    v = str(p.meta.get("state") or "").strip().lower()
    return v if v in _STATES else "target"


def _scalar(v: object) -> object:
    """An unquoted `[[stem]]` in YAML is a nested list [['stem']]: unwrap it to
    'stem' so structured entries accept the same link forms as links_of."""
    while isinstance(v, (list, tuple)):
        v = v[0] if v else ""
    return v


def _struct_targets(p: Page, field: str, keys: tuple[str, ...]) -> list[str]:
    """Existing target stems named under `keys` in a structured-list field
    (`steps:` from/to, `connects:` to), in order, without duplicates."""
    by_stem = {q.stem for q in load_all_pages()}
    out: list[str] = []
    entries = p.meta.get(field) or []
    for e in entries if isinstance(entries, list) else []:
        if not isinstance(e, dict):
            continue
        for k in keys:
            v = _scalar(e.get(k))
            t = _stem_of_link(v) if v else ""
            if t and t in by_stem and t not in out:
                out.append(t)
    return out


def _arch_pages() -> list[Page]:
    return [p for f in ARCH_FOLDERS for p in sorted(load_folder(f), key=lambda q: q.id)]


def build_addressed_by(stem: str) -> list[dict]:
    """Decision records and architecture pages whose `drivers:` name this page."""
    hits = [p.stem for p in sorted(load_folder("decisions"), key=lambda q: q.id) + _arch_pages()
            if stem in links_of(p, "drivers")]
    return _link_groups(hits)


# Requirement folders a `drivers:` link may point at (rel-drivers).
_ADDRESSABLE = {"goals", "use-cases", "functional-requirements", "quality-requirements", "constraints",
                "activity-models"}


def build_trace(stem: str, folder: str) -> dict:
    """The typed traceability panels of one page: drivers + shaped-by on
    architecture pages and decision records, the arc42 forward and reverse
    links, addressed-by on a requirement. Empty lists where a panel does not
    apply."""
    keys = ("drivers", "shaped_by", "used_by", "addressed_by", "realized_by", "replaced_by", "replaces",
            "applies_to", "governed_by", "hosts", "deployed_on", "takes_part_in")
    trace: dict = {k: [] for k in keys}
    me = (next((p for p in load_folder(folder) if p.stem == stem), None)
          if folder in ARCH_FOLDERS or folder == "decisions" else None)
    if folder in ARCH_FOLDERS or folder == "decisions":
        trace["drivers"] = build_drivers(stem)
    if me and folder != "decisions":
        trace["shaped_by"] = _link_groups(links_of(me, "decisions"))
    if me:
        trace["replaced_by"] = _link_groups(links_of(me, "superseded-by"))
        trace["replaces"] = _link_groups([p.stem for p in sorted(load_folder(folder), key=lambda q: q.id)
                                          if stem in links_of(p, "superseded-by")])
    if folder == "building-blocks":
        trace["used_by"] = _link_groups([p.stem for p in sorted(load_folder(folder), key=lambda q: q.id)
                                         if stem in links_of(p, "uses")])
        trace["deployed_on"] = _link_groups([p.stem for p in sorted(load_folder("deployment-nodes"), key=lambda q: q.id)
                                             if stem in links_of(p, "hosts")])
    if folder in ("building-blocks", "deployment-nodes"):
        trace["governed_by"] = _link_groups([p.stem for p in sorted(load_folder("concepts"), key=lambda q: q.id)
                                             if stem in links_of(p, "applies-to")])
    if folder in ("building-blocks", "deployment-nodes", "external-interfaces", "stakeholders"):
        trace["takes_part_in"] = _link_groups(
            [p.stem for p in sorted(load_folder("runtime-scenarios"), key=lambda q: q.id)
             if stem in _struct_targets(p, "steps", ("from", "to"))])
    if folder == "concepts" and me:
        trace["applies_to"] = _link_groups(links_of(me, "applies-to"))
    if folder == "deployment-nodes" and me:
        trace["hosts"] = _link_groups(links_of(me, "hosts"))
    if folder in _ADDRESSABLE:
        trace["addressed_by"] = build_addressed_by(stem)
    if folder == "use-cases":
        # features and stories refining this use case (rel-parent, DR-011)
        trace["realized_by"] = _link_groups(
            [p.stem for p in sorted(load_folder("functional-requirements"), key=lambda q: q.id)
             if p.status != "deprecated" and stem in links_of(p, "parent")])
    return trace


# Runtime scenario (A4): the `steps:` list is the model, the sequence diagram
# its projection.

def _endpoint_stem(text: str, by_stem: dict) -> str:
    """The stem a `from`/`to` names: a wikilink's target, or plain text that is
    a page stem or a path ending in one. Other plain text keeps every
    character, `/` included ("TCP/IP Gateway")."""
    if "[[" in text:
        return _stem_of_link(text)
    if text in by_stem:
        return text
    last = text.rsplit("/", 1)[-1].strip()
    return last if last in by_stem else text


def _endpoint(raw: object, by_stem: dict) -> tuple[str | None, str]:
    """(stem or None, label) of one `from`/`to`: an existing page gives its
    stem and 'ID · title' (a stakeholder or interface just its title); a
    dangling link or plain text keeps its text as the label."""
    text = str(_scalar(raw) or "").strip()
    stem = _endpoint_stem(text, by_stem) if text else ""
    p = by_stem.get(stem)
    if not p:
        return None, stem or "?"
    if p.folder in ("stakeholders", "external-interfaces"):
        return stem, _clean_label(p.title)
    return stem, f"{p.id} · {_clean_label(p.title)}"


def _entries(p: Page, field: str) -> list:
    v = p.meta.get(field) or []
    return v if isinstance(v, list) else [v]


def steps_of(p: Page) -> list[dict]:
    """The scenario's steps in order, each with its 1-based position in
    `steps:`. Entries that are not mappings are not steps; runtime_hints
    names them."""
    by_stem = {q.stem: q for q in load_all_pages()}
    out: list[dict] = []
    for n, e in enumerate(_entries(p, "steps"), 1):
        if not isinstance(e, dict):
            continue
        fs, fl = _endpoint(e.get("from"), by_stem)
        ts, tl = _endpoint(e.get("to"), by_stem)
        out.append({"n": n, "from_stem": fs, "from_label": fl, "to_stem": ts, "to_label": tl,
                    "message": str(e.get("message") or ""), "note": str(e.get("note") or "")})
    return out


_MM_ENTITY = {"#": "#35;", ";": "#59;"}


def _mm_escape(s: str) -> str:
    """`#` and `;` as mermaid entity codes, in one pass (a second pass would
    re-escape the `;` of `#35;`), whitespace collapsed."""
    return re.sub(r"[#;]", lambda m: _MM_ENTITY[m.group()], " ".join(s.split()))


def _seq_text(s: str) -> str:
    """Message/note text that cannot end the mermaid statement early."""
    return _mm_escape(s)


def build_sequence_diagram(stem: str) -> str | None:
    """Mermaid sequenceDiagram of a runtime scenario: one participant per distinct
    end in order of first appearance (stakeholders as actors), one arrow per
    step, the step's note over the receiver. None without steps."""
    p = next((q for q in load_folder("runtime-scenarios") if q.stem == stem), None)
    steps = steps_of(p) if p else []
    if not steps:
        return None
    by_stem = {q.stem: q for q in load_all_pages()}
    # Ids are L1, L2, … per distinct end — an existing page by its stem, any
    # other end by its text — so no name can collide with a mermaid keyword
    # (`end`, `box`, `note` …) or sanitise onto another end's id.
    order: list[tuple[str, str, str]] = []          # (participant id, label, keyword)
    nid_of: dict[str, str] = {}

    def key(sstem: str | None, label: str) -> str:
        return f"page:{sstem}" if sstem else f"text:{label}"

    for st in steps:
        for sstem, label in ((st["from_stem"], st["from_label"]), (st["to_stem"], st["to_label"])):
            k = key(sstem, label)
            if k in nid_of:
                continue
            nid_of[k] = f"L{len(nid_of) + 1}"
            kw = "actor" if sstem and by_stem[sstem].folder == "stakeholders" else "participant"
            order.append((nid_of[k], _seq_text(label), kw))
    lines = ["sequenceDiagram"] + [f"  {kw} {nid} as {label}" for nid, label, kw in order]
    for st in steps:
        a = nid_of[key(st["from_stem"], st["from_label"])]
        b = nid_of[key(st["to_stem"], st["to_label"])]
        lines.append(f"  {a}->>{b}: {_seq_text(st['message']) or ' '}")
        if st["note"]:
            lines.append(f"  Note over {b}: {_seq_text(st['note'])}")
    return "\n".join(lines)


def _bb_ancestors(stem: str, pages: dict) -> list[str]:
    """The block and its `parent:` chain, cycle-safe."""
    out: list[str] = []
    while stem and stem not in out and stem in pages:
        out.append(stem)
        stem = _bb_parent(pages[stem], set(pages))
    return out


def runtime_hints(stem: str) -> list[str]:
    """Where a scenario disagrees with the rest of the wiki
    (rule-runtime-matches-uses): entries that are not steps, empty ends, ends
    that name no page, and steps between two blocks with no `uses:` edge
    between them or their ancestors. Advisory."""
    p = next((q for q in load_folder("runtime-scenarios") if q.stem == stem), None)
    if not p:
        return []
    blocks = {q.stem: q for q in load_folder("building-blocks")}
    hints: list[str] = []
    for n, e in enumerate(_entries(p, "steps"), 1):
        if not isinstance(e, dict):
            hints.append(f"step {n}: not a {{from, to, message}} entry, not drawn")
    for st in steps_of(p):
        for end in ("from", "to"):
            label, sstem = st[f"{end}_label"], st[f"{end}_stem"]
            h = f"step {st['n']}: {end}: is empty" if label == "?" else f"{label}: no such page"
            if not sstem and h not in hints:
                hints.append(h)
        a, b = st["from_stem"], st["to_stem"]
        if a in blocks and b in blocks and a != b:
            targets = set(_bb_ancestors(b, blocks))
            if not any(set(links_of(blocks[x], "uses")) & targets for x in _bb_ancestors(a, blocks)):
                h = f"{blocks[a].id} → {blocks[b].id}: no uses: edge"
                if h not in hints:
                    hints.append(h)
    return hints


# Deployment view (A3): nodes nested by `parent:`, the blocks they host inside
# them, `connects:` as protocol-labelled edges. One diagram per state, so
# today's landscape and the target are never mixed.

def build_node_tree() -> list[dict]:
    """The deployment-node levels."""
    return _level_tree("deployment-nodes")


def _edge_text(s: object) -> str:
    """Edge label text that survives inside mermaid's double quotes."""
    return _mm_escape(str(s or "")).replace('"', "'")


def build_deployment_diagram(root: str | None = None) -> str | None:
    """Mermaid flowchart of every deployment node — existing, planned and
    replaced in one picture, marked per _lifecycle_lines — or of the subtree
    under `root`. A node with children or hosted blocks is a subgraph; hosted
    blocks are boxes inside it; `connects:` edges carry their protocol;
    external interfaces are neighbour boxes. None when no node matches. Edges
    to nodes outside a subtree are left out; deployment_hints names the
    entries that cannot be drawn."""
    tree = build_node_tree()
    if root is not None:
        me = _bb_find(tree, root)
        tree = [me] if me else []
    if not tree:
        return None
    nodes = {p.stem: p for p in load_folder("deployment-nodes")}
    blocks = {p.stem: p for p in load_folder("building-blocks")}
    eifs = {p.stem: p for p in load_folder("external-interfaces")}
    shown: set[str] = set()
    marked: dict[str, tuple[str, Page]] = {}
    lines = ["flowchart TB"]

    def walk(ns: list[dict]):
        for n in ns:
            yield n
            yield from walk(n["children"])

    inside = [nodes[n["stem"]] for n in walk(tree)]
    inside += [blocks[b] for p in inside for b in links_of(p, "hosts") if b in blocks]
    mixed = _mixed(inside)

    def emit(n: dict, depth: int) -> None:
        p, pad = nodes[n["stem"]], "  " * depth
        nid = _diagram_node_id(p.id)
        label = f'{p.id} · {_clean_label(p.title)}'
        tech = _clean_label(p.meta.get("technology") or "")
        if tech:
            label += f" ({tech})"
        label += _lifecycle_suffix(p, mixed)
        shown.add(n["stem"])
        marked[n["stem"]] = (nid, p)
        hosted = [b for b in links_of(p, "hosts") if b in blocks]
        if not n["children"] and not hosted:
            lines.append(f'{pad}{nid}["{label}"]:::infra')
            return
        lines.append(f'{pad}subgraph {nid}["{label}"]')
        for b in hosted:
            bp = blocks[b]
            bid = f"{nid}_{_diagram_node_id(bp.id)}"
            marked[f"{n['stem']}/{b}"] = (bid, bp)
            lines.append(f'{pad}  {bid}["{bp.id} · {_clean_label(bp.title)}{_lifecycle_suffix(bp, mixed)}"]:::block')
        for c in n["children"]:
            emit(c, depth + 1)
        lines.append(f"{pad}end")

    for n in tree:
        emit(n, 1)
    neighbours: list[str] = []
    edges: list[str] = []
    for s in sorted(shown, key=lambda k: nodes[k].id):
        for e in _entries(nodes[s], "connects"):
            if not isinstance(e, dict):
                continue
            v = _scalar(e.get("to"))
            t = _stem_of_link(v) if v else ""
            if t in shown:
                target = _diagram_node_id(nodes[t].id)
            elif t in eifs:
                target = _diagram_node_id(eifs[t].id)
                if t not in neighbours:
                    neighbours.append(t)
            else:
                continue
            proto = " · ".join(x for x in (_edge_text(e.get("protocol")), _edge_text(e.get("note"))) if x)
            arrow = f' -- "{proto}" --> ' if proto else " --> "
            edges.append(f"  {_diagram_node_id(nodes[s].id)}{arrow}{target}")
    for t in neighbours:
        lines.append(f'  {_diagram_node_id(eifs[t].id)}["{_clean_label(eifs[t].title)}"]:::system')
    lines += edges
    lines += _lifecycle_lines(dict(sorted(marked.items(), key=lambda kv: kv[1][0])))
    lines += [
        "  classDef infra fill:#e3ecf7,stroke:#2f6fb3,color:#15202e;",
        "  classDef block fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff;",
        "  classDef system fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)


def deployment_hints(stem: str | None = None) -> list[str]:
    """What the deployment diagrams leave out, for one node or all: `connects:`
    entries that are not mappings or name no page, `hosts:` entries that are
    not building blocks. Advisory."""
    nodes = {p.stem: p for p in load_folder("deployment-nodes")}
    blocks = {p.stem for p in load_folder("building-blocks")}
    pages = {p.stem for p in load_all_pages()}
    hints: list[str] = []
    for s in sorted(nodes, key=lambda k: nodes[k].id) if stem is None else [stem]:
        p = nodes.get(s)
        if not p:
            continue
        for n, e in enumerate(_entries(p, "connects"), 1):
            if not isinstance(e, dict):
                hints.append(f"{p.id} connects entry {n}: not a {{to, protocol}} entry, not drawn")
                continue
            v = _scalar(e.get("to"))
            t = _stem_of_link(v) if v else ""
            if not t:
                hints.append(f"{p.id} connects entry {n}: to: is empty, not drawn")
            elif t not in pages:
                hints.append(f"{p.id} connects {t}: no such page")
        for b in links_of(p, "hosts"):
            if b not in blocks:
                hints.append(f"{p.id} hosts {b}: not a building block, not drawn")
    return hints


def trace_stems(trace: dict) -> set[str]:
    """Every page a trace panel already shows, to keep it out of the generic one."""
    return {Path(l["url"]).name for groups in trace.values() for g in groups for l in g["links"]}


@app.route("/arc42/building-blocks")
def building_blocks_view():
    """A2 Building Block View: the level tree and the level-1 white box."""
    block = catalog.SECTION_BY_SLUG["building-blocks"]
    pages = load_folder("building-blocks")
    rows = [_arch_row(p, "building-blocks") for p in sorted(pages, key=lambda q: q.id)]
    return render_template(
        "building_blocks.html", block=block, tree=build_bb_tree(), total=len(pages),
        whitebox=build_whitebox(None), maturity=maturity(p.status for p in pages), rows=rows,
    )


_CONCEPT_CATEGORIES = [
    ("domain", "Domain"), ("user-experience", "User experience"), ("safety-security", "Safety & security"),
    ("patterns", "Architecture & design patterns"), ("under-the-hood", "Under the hood"),
    ("development", "Development"), ("operations", "Operations"),
]


def _arch_row(p: Page, folder: str) -> dict:
    return {"id": p.id, "title": p.title, "status": p.status, "state": page_state(p),
            "url": _page_url(folder, p.stem)}


@app.route("/arc42/concepts")
def concepts_view():
    """A5 Crosscutting Concepts: grouped by arc42 topic, with what each governs."""
    block = catalog.SECTION_BY_SLUG["concepts"]
    pages = sorted(load_folder("concepts"), key=lambda q: q.id)
    known = dict(_CONCEPT_CATEGORIES)
    groups = []
    for key, label in _CONCEPT_CATEGORIES + [(None, "Uncategorised")]:
        rows = []
        for p in pages:
            raw = str(p.meta.get("category") or "").strip()
            cat = raw.lower()
            if (cat if cat in known else None) != key:
                continue
            row = _arch_row(p, "concepts")
            row["unknown_category"] = raw if raw and cat not in known else ""
            row["applies_to"] = _link_groups(links_of(p, "applies-to"))
            rows.append(row)
        if rows:
            groups.append({"label": label, "rows": rows})
    flat = []
    for p in pages:
        row = _arch_row(p, "concepts")
        raw = str(p.meta.get("category") or "").strip()
        row["category"] = known.get(raw.lower(), raw)
        flat.append(row)
    return render_template("concepts.html", block=block, groups=groups, total=len(pages),
                           rows=flat, maturity=maturity(p.status for p in pages))


@app.route("/arc42/runtime")
def runtime_view():
    """A4 Runtime View: the scenarios and the requirements they realise."""
    block = catalog.SECTION_BY_SLUG["runtime"]
    pages = sorted(load_folder("runtime-scenarios"), key=lambda q: q.id)
    rows = []
    for p in pages:
        row = _arch_row(p, "runtime-scenarios")
        row["drivers"] = _link_groups(links_of(p, "drivers"))
        row["steps"] = len(steps_of(p))
        rows.append(row)
    return render_template("runtime.html", block=block, rows=rows, total=len(pages),
                           maturity=maturity(p.status for p in pages))


@app.route("/arc42/deployment")
def deployment_view():
    """A3 Deployment View: one projected diagram of everything relevant today —
    existing, planned and replaced — and the node levels."""
    block = catalog.SECTION_BY_SLUG["deployment"]
    pages = load_folder("deployment-nodes")
    rows = []
    for p in sorted(pages, key=lambda q: q.id):
        row = _arch_row(p, "deployment-nodes")
        row["stereotype"] = str(p.meta.get("stereotype") or "").strip()
        rows.append(row)
    return render_template("deployment.html", block=block, diagram=build_deployment_diagram(),
                           hints=deployment_hints(), rows=rows,
                           tree=build_node_tree(), total=len(pages),
                           maturity=maturity(p.status for p in pages))


# --- global search ---------------------------------------------------------

# Frontmatter fields searched as plain words (FR-006). Link fields (parent,
# sources, related, drivers …) are left out: their values are file names.
SEARCH_FIELDS = ["tags", "status", "stereotype", "priority", "kind", "state",
                 "category", "dimensions"]

_MD_LINK_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_HTML_TAG_RE = re.compile(r"<[^>]+>")
_SOURCE_ID_RE = re.compile(r"[A-Z]+-\d+")
# Lines that label a page's structure rather than say something: headings,
# callout titles and bold-only lines such as **PROBLEM / GOAL**. A bold lead
# label such as **Snapshot.** goes too, the text after it stays. The note
# "> follows [[MADR]]" goes before, by the page's own test (drop_follows).
_HEADING_LINE_RE = re.compile(r"^\s*(?:#{1,6}\s|>\s*\[![\w-]+\]|\*\*[^*]+\*\*\s*$)")
_LEAD_LABEL_RE = re.compile(r"^(\s*(?:[-*+]\s+)?)\*\*[^*]{1,60}[.:]\*\*\s+")
_LINE_MARK_RE = re.compile(r"^\s*(?:#{1,6}\s+|>\s*(?:\[![\w-]+\][-+]?\s*)?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+")
_EMPHASIS_RE = re.compile(r"\*\*|__|~~|`|(?<!\w)\*(?=\S)|(?<=\S)\*(?!\w)")


def search_plain(page: Page, titles: dict[str, str]) -> str:
    """A page body as the reader sees it, for search: wikilinks become their
    label (or the target's title), markdown and HTML markup go, hard-wrapped
    prose is joined. One line per paragraph or list item, so the ranker can
    cut passages. Headings and labels go (`_HEADING_LINE_RE`), and so do the
    "follows" notes the page shows as head labels (`drop_follows`).
    An unlabelled provenance link to raw/sources becomes the source's ID
    (`SRC-006`): its file name or title would match words such as
    "grilling" on most pages, and dropping it leaves "came from ." holes."""
    def link_text(m: re.Match) -> str:
        target, label = m.group(1).strip(), m.group(2)
        base = target.split("/")[-1]
        if label:
            return label.strip()
        if target.startswith("raw/") or base.startswith("SRC-"):
            src = source_index().get(base)
            return src.id if src else _SOURCE_ID_RE.match(base).group(0) if _SOURCE_ID_RE.match(base) else ""
        return titles.get(base, target)

    body = _unwrap_prose(drop_follows(page.body))
    body = WIKILINK_RE.sub(link_text, body)
    body = _MD_LINK_RE.sub(lambda m: m.group(1), body)
    body = _HTML_TAG_RE.sub(" ", body)
    lines = []
    for line in body.splitlines():
        if line.strip().startswith("```") or _TABLE_SEP_RE.match(line) or _HEADING_LINE_RE.match(line):
            continue
        line = _LEAD_LABEL_RE.sub(r"\1", line)
        line = _LINE_MARK_RE.sub("", line)
        line = _EMPHASIS_RE.sub("", line).replace("|", " ")
        line = re.sub(r"\s+", " ", line).strip()
        if line and line != "---":
            lines.append(line)
    return "\n".join(lines)


def _search_fields(page: Page) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for key in SEARCH_FIELDS:
        v = page.meta.get(key)
        vals = v if isinstance(v, list) else [v]
        vals = [str(x).strip().lower() for x in vals if x is not None and str(x).strip()]
        if vals:
            out[key] = vals
    return out


def _search_links(pages: list[Page]) -> dict[str, set[str]]:
    """page id -> ids one link step away, in either direction (FR-008)."""
    idx = link_index()
    by_stem = {p.stem: p for p in pages}
    out: dict[str, set[str]] = {p.id: set() for p in pages}
    for p in pages:
        for t in p.link_targets():
            dest = idx.get(t)
            if not dest or dest[1] not in by_stem:
                continue
            other = by_stem[dest[1]].id
            if other != p.id:
                out[p.id].add(other)
                out.setdefault(other, set()).add(p.id)
    return out


def build_search_records() -> list[dict]:
    """A flat index over every wiki page, ranked client-side by
    static/search-rank.js. Each record links to that unit's own detail page
    and carries the reader's text (`plain`), `aliases`, the searched `fields`
    (lower-cased) and the ids of its neighbours (`links`)."""
    pages = load_all_pages()
    titles = title_index()
    neighbours = _search_links(pages)
    records = []
    for p in pages:
        records.append({
            "id": p.id,
            "type": FOLDER_LABELS.get(p.folder, p.folder),
            "title": p.title,
            "status": p.status,
            "url": (f"/functional-requirements/{p.stem}"
                    if p.folder == "functional-requirements"
                    else f"/page/{p.folder}/{p.stem}"),
            "aliases": [str(a) for a in p.aliases],
            "plain": search_plain(p, titles),
            "fields": _search_fields(p),
            "links": sorted(neighbours.get(p.id, ())),
        })
    return records


def search_synonyms() -> list[list[str]]:
    """Each glossary term's title plus its aliases, lower-cased. The search
    treats a group as one word (FR-003)."""
    return [[str(w).strip().lower() for w in [p.title, *p.aliases] if str(w).strip()]
            for p in load_folder("glossary")]


def build_search_index() -> dict:
    """What /search.json serves and /search embeds: {records, synonyms}."""
    return {"records": build_search_records(), "synonyms": search_synonyms()}


# --- views -----------------------------------------------------------------

def _tile_rows_by_relations(pages):
    return sorted(
        ({"title": p.title, "id": p.id, "relations": len(p.link_targets())} for p in pages),
        key=lambda r: (-r["relations"], r["id"]),
    )


def build_section_tile(section: dict) -> dict:
    """The tile payload for one catalog section, keyed by section ID. Vision
    (R1), Functional Requirements (R3), Supporting Models (R4), Scope (C3), Domain Terms (C5)
    and Issues (C6) keep their special bodies; everything else is a count plus
    a relation-ranked preview."""
    sid = section["id"]
    base = {"key": sid.lower(), "id": sid, "label": section["title"],
            "eyebrow": f"{sid} · {section['title']}", "href": section["href"],
            "folders": section["folders"], "scope": section["scope"],
            "colors": section["colors"], "note": section["note"],
            "links": [], "rows": [], "active": section["scope"] == "in",
            "sub": "", "sub_units": [], "unit": "page", "unit_many": None, "count": 0}
    if section["scope"] != "in":
        base["maturity"] = maturity([])
        base["open_issues"] = 0
        return base
    pages = [p for f in section["folders"] for p in load_folder(f)]
    t = {**base, "count": len(pages), "rows": _tile_rows_by_relations(pages)}
    if sid == "R1":
        t.update(build_vision_tile(load_goals(), title_index()))
        t.update({"key": "r1", "id": "R1", "eyebrow": "R1 · Vision & Goals",
                  "label": "Vision & Goals", "scope": "in", "colors": section["colors"]})
    elif sid == "R3":
        hierarchy = build_fr_hierarchy()
        ucs = sorted(load_folder("use-cases"), key=lambda p: p.id)
        # the headline counts every functional requirement — all FR pages
        # (orphans included) plus use cases (DR-011); the breakdown names only
        # the kinds that exist, so an empty kind never reads "0 epics".
        breakdown = [{"n": hierarchy["total_epics"], "one": "epic", "many": None},
                     {"n": hierarchy["total_features"], "one": "feature", "many": None},
                     {"n": hierarchy["total_stories"], "one": "story", "many": "stories"},
                     {"n": len(ucs), "one": "use case", "many": None}]
        t.update({"count": len(load_folder("functional-requirements")) + len(ucs),
                  "unit": "requirement",
                  # counted nouns, not a pre-built string: the template runs
                  # each through `plural`, so one feature reads "1 feature".
                  "sub_units": [u for u in breakdown if u["n"]],
                  "epic_rows": [{"id": e["id"], "title": e["title"], "n_features": e["n_features"],
                                 "n_stories": e["n_stories"]} for e in hierarchy["epics"]],
                  # use cases are functional requirements too (DR-011)
                  "uc_rows": [{"id": p.id, "title": p.title,
                               "level": str(p.meta.get("level") or "")} for p in ucs]})
    elif sid == "R4":
        # `relations` there is a page count per model type, not a link count
        t.update({"unit": "model page",
                  "rows": [{"title": m["title"], "pages": m["relations"]}
                           for m in _supporting_model_entries()]})
    elif sid == "C1":
        t["unit"] = "scenario"
    elif sid == "C2":
        t["unit"] = "constraint"
    elif sid == "C3":
        # folders carries both (maturity and issue flags span the context page
        # too), but the headline number is what the unit says: interfaces.
        eifs = load_folder("external-interfaces")
        t.update({"unit": "external interface", "count": len(eifs),
                  "rows": _tile_rows_by_relations(eifs),
                  "sub": "context described" if load_folder("context") else "no context page yet"})
    elif sid == "C4":
        t["unit"] = "persona"
    elif sid == "C5":
        t.update({"unit": "term",
                  "links": [{"label": "Table", "href": "/glossary"},
                            {"label": "Term network", "href": "/graph/glossary"}]})
    elif sid == "C6":
        issues = pages
        open_issues = [i for i in issues if is_open_issue(i.status)]
        t.update({"count": len(open_issues), "total": len(issues),
                  # "open" is the adjective, not a noun: it never takes an -s
                  "unit": "open", "unit_many": "open",
                  "href": "/issues?status=open" if open_issues else "/issues",
                  "sub": f"{len(issues)} in total",
                  "rows": [{"id": i.id, "title": i.title, "severity": str(i.meta.get("severity") or "")}
                           for i in sorted(open_issues,
                                           key=lambda i: ({"blocker": 0, "major": 1, "minor": 2}
                                                          .get(str(i.meta.get("severity") or ""), 3), i.id))][:5]})
    t["maturity"] = maturity(p.status for p in pages)
    flags = open_issue_counts()
    # union, not sum: an issue linking pages in two of this section's folders
    # must count once, not twice.
    t["open_issues"] = 0 if sid == "C6" else len(set().union(*(flags.get(f, set()) for f in section["folders"])))
    t["open_issues_href"] = f"/issues?section={sid}"
    return t


def build_area_tile(area: dict) -> dict:
    """Home-page tile for one cabinet: count, maturity and open-issue flag
    over its visible, captured sections, plus the section list as links."""
    sections = visible_sections(area["key"])
    folders = [f for s in sections for f in s["folders"]]
    pages = [p for f in folders for p in load_folder(f)]
    flags = open_issue_counts()
    return {
        "key": area["key"], "label": area["label"], "subtitle": area["subtitle"],
        "href": area["href"], "colors": area["colors"],
        "count": len(pages), "maturity": maturity(p.status for p in pages),
        "open_issues": len(set().union(*(flags.get(f, set()) for f in folders if f != "issues"))),
        "sections": [{"id": s["id"], "title": s["title"], "href": s["href"], "scope": s["scope"]}
                     for s in sections],
        "planned": not sections or all(s["scope"] == "planned" for s in sections),
    }


def build_valley() -> dict:
    """What the agent did: the vault's state, what moved last, what is open.
    Sits between the two peaks on the home page (DR-033)."""
    issues = load_folder("issues")
    open_issues = sorted((i for i in issues if is_open_issue(i.status)),
                         key=lambda i: ({"blocker": 0, "major": 1, "minor": 2}
                                        .get(str(i.meta.get("severity") or ""), 3), i.id))
    cfg = dashboard_config()
    return {
        "status": vault_status(),
        "changes": recent_changes(4),
        "open_issues": [{"id": i.id, "title": i.title, "stem": i.stem,
                         "url": _page_url("issues", i.stem),
                         "severity": str(i.meta.get("severity") or "")} for i in open_issues[:5]],
        "open_total": len(open_issues),
        "decision_count": len(load_folder("decisions")),
        "warnings": [f"Unknown entry in dashboard.yaml: {u}" for u in cfg["unknown"]],
    }


@app.route("/")
def index():
    """Home: Requirements and Architecture as two peaks, the valley between
    them showing the agent's work, Commons as the ground both stand on."""
    areas = {a["key"]: build_area_tile(a) for a in visible_areas()}
    join_url = public_url()
    return render_template("index.html", areas=areas, valley=build_valley(),
                           join_url=join_url, join_qr=qr_svg(join_url))


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


@app.route("/glossary")
def glossary_view():
    titles = title_index()
    links = link_index()       # so definition wikilinks render as real hyperlinks
    pages = load_folder("glossary")
    rows = []
    for p in pages:
        rows.append({
            "id": p.id,
            "stem": p.stem,
            "title": p.title,
            "aliases": p.aliases,
            "definition": extract_labeled(p, "Definition", titles, links),
            "relations": len(p.link_targets()),
            "status": p.status,
            "created": str(p.meta.get("created", "")),
            "updated": str(p.meta.get("updated", "")),
            "assumption": "[!assumption]" in p.body,
        })
    # Default order is alphabetical by term; other orders are applied client-side.
    rows.sort(key=lambda r: r["title"].lower())
    return render_template("glossary.html", rows=rows, total=len(rows),
                           maturity=maturity(p.status for p in pages))


@app.route("/graph/glossary")
def glossary_graph_view():
    """Force-directed glossary term network (DR-023). The graph data is a
    deterministic server projection; cytoscape.js lays it out client-side."""
    graph = build_glossary_graph()
    counts = graph["layer_counts"]
    NAMED = [("DM", "Data model"), ("STK", "Stakeholder"),
             ("EIF", "Interface"), ("GOAL", "Goals"), ("BB", "Building block")]
    named_keys = {k for k, _ in NAMED}
    named_layers = [{"key": k, "label": l, "count": counts[k]}
                    for k, l in NAMED if counts.get(k)]
    rest_keys = [k for k in counts if k not in named_keys]
    rest = {"types": rest_keys, "count": sum(counts[k] for k in rest_keys)}
    n_glo = sum(1 for n in graph["nodes"] if n["data"].get("type") == "GLO")
    return render_template("graph.html", graph=graph, n_glo=n_glo,
                           named_layers=named_layers, rest=rest)


def _issue_owner(p: Page, titles: dict[str, str],
                 links: dict[str, tuple[str, str]]) -> dict:
    """Who is expected to answer an issue (FR-028): `key` for the filter,
    `label` to show, `url` when it names a wiki page. An empty owner gives
    key "" (nobody yet)."""
    raw = str(_scalar(p.meta.get("owner")) or "").strip()
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
        return {"key": stem, "label": alias or titles.get(stem, stem), "url": _page_url(folder, stem)}
    if linked or alias:
        return {"key": raw, "label": alias or target, "url": None}
    return {"key": raw, "label": raw, "url": None}


# ?status= on the issue list: a lifecycle value, or one of these groups
# (open: is_open_issue, closed: the rest)
_ISSUE_STATUS_GROUPS = ("open", "closed")


@_request_cached
def _issue_vocab() -> dict[str, list[str]]:
    """The values the metamodel allows for an issue's status and enum fields,
    read once per request."""
    return {"status": metamodel.lifecycle("issue"),
            **{f: metamodel.field_values("issue", f) for f in ("severity", "kind", "category")}}


def issue_fields(p: Page, titles: dict[str, str], links: dict[str, tuple[str, str]]) -> dict:
    """An issue's own fields as the list and its page show them (FR-025 to
    FR-028). A value outside the metamodel's list comes back empty."""
    vocab = _issue_vocab()
    def known(field: str) -> str:
        v = str(p.meta.get(field) or "").strip()
        return v if v in vocab[field] else ""
    status = p.status if p.status in vocab["status"] else ""
    owner = _issue_owner(p, titles, links)
    return {"status": status, "is_open": is_open_issue(p.status),
            "severity": known("severity"), "kind": known("kind"), "category": known("category"),
            "owner": owner["label"], "owner_key": owner["key"], "owner_url": owner["url"]}


_SEVERITY_RANK = {"blocker": 0, "major": 1, "minor": 2}


@_request_cached
def _issue_backlinks() -> dict[str, list[dict]]:
    """page stem -> the issues that link to it, by frontmatter or body
    wikilink (FR-027). A mere mention without a link does not count."""
    titles, links = title_index(), link_index()
    out: dict[str, list[dict]] = {}
    for iss in load_folder("issues"):
        f = issue_fields(iss, titles, links)
        item = {"id": iss.id, "title": iss.title, "status": f["status"], "severity": f["severity"],
                "is_open": f["is_open"], "url": _page_url("issues", iss.stem)}
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
    titles, links = title_index(), link_index()
    pages = sorted(load_folder("issues"), key=lambda x: x.id)
    lifecycle_values = metamodel.lifecycle("issue")
    categories = metamodel.field_values("issue", "category")
    severities = metamodel.field_values("issue", "severity")
    folder_section = {f: s["id"] for s in catalog.SECTIONS for f in s["folders"] if s["id"] != "C6"}

    items = []
    for p in pages:
        sections = sorted({folder_section[links[t][0]] for t in p.link_targets()
                           if t in links and links[t][0] in folder_section})
        items.append({"id": p.id, "title": p.title, **issue_fields(p, titles, links),
                      "sections": sections, "url": _page_url("issues", p.stem)})

    # the filters: only known values count, anything else shows every issue
    # one option per owner: a page by its title, whatever alias an issue uses
    owners = sorted({i["owner_key"]: titles.get(i["owner_key"], i["owner"]) if i["owner_url"] else i["owner"]
                     for i in items if i["owner_key"]}.items(), key=lambda o: o[1].lower())
    sections = [s for s in catalog.SECTIONS if s["folders"] and s["id"] != "C6"]
    arg = lambda name: request.args.get(name, "").strip()
    section = catalog.SECTION_BY_ID.get(arg("section"))
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
        maturity=maturity(p.status for p in pages),
    )


@app.route("/stakeholders")
def stakeholders_view():
    titles = title_index()
    links = link_index()       # snapshot wikilinks become real hyperlinks
    by_stem = {q.stem: q for q in load_all_pages()}   # resolve related GLO/DM targets
    pages = sorted(load_folder("stakeholders"), key=lambda x: x.id)
    _REL_MAX = 6               # cap chips per row; rest is one click away on the detail page
    rows = []
    for p in pages:
        # related glossary terms & data models the stakeholder points at — quick links
        # to "additional info" (the snapshot's inline links + `related:`), GLO before DM.
        rel = []
        for s in sorted(set(p.link_targets())):
            q = by_stem.get(s)
            if q and _type_of(s) in ("GLO", "DM"):
                rel.append({"id": q.id, "label": q.title, "type": _type_of(s),
                            "url": f"/page/{q.folder}/{s}"})
        rel.sort(key=lambda r: (r["type"] != "GLO", r["id"]))   # GLO first, then by id
        rows.append({
            "id": p.id,
            "stem": p.stem,
            "title": p.title,
            "role": p.meta.get("role", ""),
            "snapshot": extract_labeled(p, "Snapshot", titles, links),
            "influence": p.meta.get("influence", ""),
            "interest": p.meta.get("interest", ""),
            "rel_links": rel[:_REL_MAX],
            "rel_more": max(0, len(rel) - _REL_MAX),
            "status": p.status,
        })
    return render_template("stakeholders.html", rows=rows, total=len(rows),
                           maturity=maturity(p.status for p in pages))


@app.route("/decisions")
def decisions_view():
    """C7 Decisions: every decision record, filterable by kind (FR-009)."""
    items = load_decisions()
    labels = {"architecture": "Architecture", "business": "Business", "undefined": "Undefined"}
    buckets = [{"key": k, "label": labels[k], "count": sum(1 for d in items if d["kind"] == k)}
               for k in DECISION_KINDS]
    return render_template("decisions.html", items=items, total=len(items), buckets=buckets,
                           maturity=maturity(d["status"] for d in items))


@app.route("/adrs")
def adrs_redirect():
    """The former method-ADR list; decisions now live in wiki/decisions/."""
    return redirect("/decisions", code=301)


@app.route("/page/<folder>/<stem>")
def page_detail(folder, stem):
    """Detail page for a single content unit (any wiki page). Search results
    link here."""
    titles = title_index()
    if folder == "adr":
        # Former ADR URLs (/page/adr/0012-…) land on the decision record that
        # kept their number (DR-012-…), or on the list if it was re-filed.
        m = re.match(r"(\d{4})-(.+)$", stem)
        if m:
            new_stem = f"DR-{int(m.group(1)):03d}-{m.group(2)}"
            if (WIKI_DIR / "decisions" / f"{new_stem}.md").is_file():
                return redirect(_page_url("decisions", new_stem), code=301)
        return redirect("/decisions", code=301)

    # FRs have their own rich page (full text + hierarchy breakdown) under the
    # functional-requirements/ path; send any /page link there so the whole
    # hierarchy stays on one route.
    if folder == "functional-requirements":
        return redirect(f"/functional-requirements/{stem}", code=302)

    path = WIKI_DIR / folder / f"{stem}.md"
    page = _parse(path, folder) if path.is_file() else None
    if not page:
        abort(404)
    kind = FOLDER_LABELS.get(folder, folder)
    # drop the leading "# Title" heading from the body — shown in the page header
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)
    body_html = render_markdown(body, titles)
    # context pages carry the system-context diagram, projected live (DR-013)
    context_diagram = build_context_diagram() if folder == "context" else None
    context_flows = build_context_flows() if folder == "context" else None
    # glossary pages carry a focused ego-graph snippet above the definition (DR-023)
    ego_graph = build_glossary_ego_graph(stem) if folder == "glossary" else None
    trace = build_trace(stem, folder)
    whitebox = build_whitebox(stem) if folder == "building-blocks" else None
    sequence = build_sequence_diagram(stem) if folder == "runtime-scenarios" else None
    hints = (runtime_hints(stem) if folder == "runtime-scenarios"
             else deployment_hints(stem) if folder == "deployment-nodes" else [])
    deployment = build_deployment_diagram(stem) if folder == "deployment-nodes" else None
    ego_layers = None
    if ego_graph:
        c = ego_graph["layer_counts"]
        ego_layers = [{"key": k, "label": l} for k, l in
                      (("DM", "Data model"), ("STK", "Stakeholder"), ("GOAL", "Goals"),
                       ("BB", "Building block"))
                      if c.get(k)]
        for L in ego_layers:
            L["count"] = c[L["key"]]
    return render_template(
        "detail.html", kind=kind, id=page.id, title=page.title,
        status=page.status, created=str(page.meta.get("created", "")),
        updated=str(page.meta.get("updated", "")), tags=page.meta.get("tags") or [],
        body_html=body_html, **_section_crumb(folder),
        context_diagram=context_diagram, context_flows=context_flows,
        relations=build_relations_panel(stem, exclude=trace_stems(trace)),
        trace=trace, whitebox=whitebox,
        state=page_state(page) if folder in ARCH_FOLDERS else None,
        sequence=sequence, hints=hints, deployment=deployment,
        ego_graph=ego_graph, ego_layers=ego_layers,
        needs_mermaid=bool(context_diagram or whitebox or sequence or deployment) or "language-mermaid" in body_html,
        sources=provenance(page),
        issue=issue_fields(page, titles, link_index()) if folder == "issues" else None,
        page_issues=open_issues_for(stem),
        formats=format_labels(page.body),
    )


def _section_crumb(folder: str) -> dict:
    """The section level of a wiki page's path (FR-020): where the page
    belongs, not how the reader got there. A folder outside the sections
    gives no section level, so the path reads Home › page."""
    sec = catalog.section_for_folder(folder)
    return {"crumb": sec["title"], "crumb_href": catalog.section_href(sec)} if sec else {"crumb": None, "crumb_href": None}


@app.route("/source/<stem>")
def source_detail(stem):
    """Detail page for one raw/sources/ provenance record: what it is, where it
    came from, and which wiki pages it fed (`ingested-pages:`). Reached from a
    provenance chip on any sourced page; no standalone sources list exists yet,
    so its path is Home › source (FR-020)."""
    src = source_index().get(stem)
    if not src:
        abort(404)
    titles = title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", src.body, count=1)
    # frontmatter values are human-entered and never trusted: escape every one
    # before it lands in body_html, which the template renders with `| safe`.
    facts = [("Type", str(src.meta.get("source-type") or "—")),
             ("Origin", str(src.meta.get("origin") or "—")),
             ("Captured", str(src.meta.get("captured") or "—")),
             ("Checksum", str(src.meta.get("sha256") or "—")[:16])]
    facts_html = "".join(f"<dt>{k}</dt><dd>{escape(v)}</dd>" for k, v in facts)
    # each ref is escaped before render_wikilinks sees it — confirmed this does
    # not break [[…]] matching (brackets/pipes aren't HTML-special, so a clean
    # wikilink round-trips untouched; a hostile one comes out as inert entities
    # whether or not it resolves to a real page).
    ingested = ", ".join(render_wikilinks(str(escape(str(r))), titles, link_index()) for r in (src.meta.get("ingested-pages") or [])) or "—"
    body_html = f'<dl class="source-facts">{facts_html}<dt>Ingested pages</dt><dd>{ingested}</dd></dl>' + render_markdown(body, titles)
    return render_template("detail.html", kind="Source", id=src.id, title=src.title, status=src.status,
                           created=str(src.meta.get("created", "")), updated=str(src.meta.get("updated", "")),
                           tags=src.meta.get("tags") or [], body_html=body_html, crumb=None, crumb_href=None,
                           context_diagram=None, context_flows=None,
                           relations=None, ego_graph=None, ego_layers=None,
                           needs_mermaid=False, sources=None)


@app.route("/search.json")
def search_index():
    """The search index for the topbar's incremental search popup
    (static/search-popup.js); ranked client-side by static/search-rank.js,
    the same code the /search page uses."""
    return jsonify(build_search_index())


@app.route("/search")
def search_view():
    """Global search across all wiki content. Results render once and are
    filtered incrementally client-side; type facets allow browsing by content type."""
    index = build_search_index()
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
    for p in load_all_pages():
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


def _short_title(p: Page) -> str:
    """Concise label for diagram nodes / tile rows. `short_title:` frontmatter
    field wins; falls back to the full title. Defined per goal so the same label
    is used everywhere a compact form is needed."""
    return str(p.meta.get("short_title") or p.title).strip()


def _mermaid_goal_tree(vision: Page, objectives: list[Page]) -> str | None:
    """Project the Vision→Objectives tree from `parent:` edges (DR-018 style).
    Top-down, short-name nodes; clicking a goal jumps to its anchor below.
    Default `useMaxWidth: true` so the SVG fits the container at typical
    desktop widths (≥1000 px) without horizontal scrolling."""
    if not vision or not objectives:
        return None
    root = _clean_label(wiki_config()["system_name"], drop_parenthetical=False)
    lines = ["graph TD", f'  V["Vision {root}"]:::vision',
             f'  click V "/goals#{vision.id}"']
    for o in objectives:
        nid = _diagram_node_id(o.id)
        label = _clean_label(_short_title(o))
        lines.append(f'  V --> {nid}["{o.id}<br/>{label}"]:::goal')
        # absolute target so the same diagram works on /goals (in-page anchor)
        # and on /req42 (cross-page navigation to the matching goal card)
        lines.append(f'  click {nid} "/goals#{o.id}"')
    lines += [
        "  classDef vision fill:#2f6fb3,stroke:#7fc0ff,color:#ffffff,stroke-width:2px,font-weight:bold;",
        "  classDef goal fill:#d7dbe3,stroke:#9aa3b2,color:#15202e;",
    ]
    return "\n".join(lines)


# --- data model projection (DR-027) --------------------------------------
#
# Two carriers, one diagram. A `DM-` page is the carrier of record: identity,
# attributes, and a `relationships:` list in frontmatter, which is where the
# edges come from. Body prose is for humans; frontmatter is for the projection,
# the same split that makes the context diagram work (`flows:`, DR-026).
#
# A glossary term marked `stereotype: entity` (or `value-object`) is promoted
# into the diagram as a STUB: named, empty, annotated `<<term>>`. That is the
# pragmatic half. During a workshop nobody writes fifteen DM pages, but marking
# a term costs one line — and an unmodelled entity then shows up as visible work
# outstanding rather than as nothing at all. Write the DM page later and it
# supersedes the stub, so the concept is never drawn twice.

DM_MARKED_STEREOTYPES = {"entity", "value-object"}

# `kind:` -> (mermaid arrow, cardinalities are meaningful). Inheritance is the
# odd one out: mermaid wants `Base <|-- Derived`, i.e. the edge is emitted
# backwards from how the page states it, and a multiplicity on it is nonsense.
_DM_ARROWS = {
    "association": ("-->", True),
    "aggregation": ("o--", True),
    "composition": ("*--", True),
    "inheritance": ("<|--", False),
}


# German umlauts and ß have a conventional ASCII spelling; every other accent
# is dropped via NFKD below (é→e). Without this, the ASCII split treated "ü" as
# a word boundary and the glossary term "Durchführungsart" was drawn as
# "DurchfHrungsart" — legal mermaid, nonsense on a wall (atrium, 2026-10-14).
_DM_TRANSLIT = str.maketrans({
    "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
    "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ẞ": "Ss",
})


def _dm_ascii(label: str) -> str:
    """`label` with umlauts transliterated and remaining diacritics stripped."""
    s = label.translate(_DM_TRANSLIT)
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def _dm_class_name(label: str, taken: set) -> str:
    """A mermaid-safe class name that still reads like the entity. Collisions
    are resolved rather than silently merged — two entities sharing a sanitised
    name would otherwise become one box."""
    # Capitalise each word BEFORE stripping separators, or "Piece for sale"
    # becomes "Pieceforsale" — legal mermaid, unreadable on a wall.
    words = re.split(r"[^A-Za-z0-9]+", _dm_ascii(_clean_label(label)))
    base = "".join(w[:1].upper() + w[1:] for w in words if w) or "Entity"
    if base[0].isdigit():
        base = "E" + base
    name, n = base, 2
    while name in taken:
        name, n = f"{base}{n}", n + 1
    taken.add(name)
    return name


@_request_cached
def data_model_nodes() -> list[dict]:
    """Every class in the model: DM pages first, then the glossary terms marked
    as data that no DM page has claimed yet.

    A DM page claims a term by linking it in `related:`, or by carrying the same
    title. Title matching is the forgiving half — during a workshop the term is
    written first and the DM page often forgets the back-link."""
    dm_pages = sorted(load_folder("data-models"), key=lambda p: p.id)

    claimed: set[str] = set()
    for p in dm_pages:
        claimed.add(p.title.strip().lower())
        for raw in (p.meta.get("related") or []):
            stem = _stem_of_link(raw)
            if stem:
                claimed.add(stem)

    nodes = [{
        "key": p.stem,
        "id": p.id,
        "label": p.title,
        "context": str(p.meta.get("bounded-context") or "").strip(),
        "stereotype": str(p.meta.get("stereotype") or "").strip().lower(),
        "attributes": _extract_dm_attribute_names(p),
        "stub": False,
        "url": f"/page/data-models/{p.stem}",
    } for p in dm_pages]

    for p in sorted(load_folder("glossary"), key=lambda p: p.id):
        stereotype = str(p.meta.get("stereotype") or "").strip().lower()
        if stereotype not in DM_MARKED_STEREOTYPES:
            continue                       # an ordinary term is not data
        if p.stem in claimed or p.title.strip().lower() in claimed:
            continue                       # a DM page already models this
        nodes.append({
            "key": p.stem,
            "id": p.id,
            "label": p.title,
            "context": str(p.meta.get("bounded-context") or "").strip(),
            "stereotype": stereotype,
            "attributes": [],
            "stub": True,
            "url": f"/page/glossary/{p.stem}",
        })
    return nodes


@_request_cached
def data_model_edges() -> list[dict]:
    """Relationships, read from `relationships:` frontmatter on DM pages. An
    entry pointing at a page that does not exist is dropped, not drawn as a
    dangling stub — a typo should leave a gap you notice, not a ghost class."""
    by_stem = {n["key"] for n in data_model_nodes()}
    out = []
    for p in sorted(load_folder("data-models"), key=lambda p: p.id):
        # A sum-type variant already names its sum type in `parent:` (DR-019).
        # Draw that as the inheritance it is, rather than make the author repeat
        # it as a relationship entry — one fact, one place.
        for raw in (p.meta.get("parent") or []):
            tgt = _stem_of_link(raw)
            if tgt and tgt in by_stem and tgt != p.stem:
                out.append({"source": p.stem, "target": tgt, "verb": "",
                            "cardinality": "", "kind": "inheritance"})
        for entry in (p.meta.get("relationships") or []):
            if not isinstance(entry, dict):
                continue
            tgt = _stem_of_link(entry.get("target"))
            if not tgt or tgt not in by_stem or tgt == p.stem:
                continue
            kind = str(entry.get("kind") or "association").strip().lower()
            out.append({
                "source": p.stem,
                "target": tgt,
                "verb": _clean_label(str(entry.get("verb") or "")),
                "cardinality": str(entry.get("cardinality") or "").strip(),
                "kind": kind if kind in _DM_ARROWS else "association",
            })
    return out


@_request_cached
def data_model_contexts() -> list[str]:
    """The bounded contexts present in the model, for the filter control."""
    return sorted({n["context"] for n in data_model_nodes() if n["context"]})


def build_data_model_full_diagram(context: str | None = None,
                                  focus: str | None = None) -> str | None:
    """Project a mermaid class diagram of the model (DR-027).

    `context` narrows to one bounded context; `focus` narrows to one entity and
    its direct neighbours, which is what makes this readable in a room — the
    context diagram's own regression was fourteen nodes drawn at once (DR-026)
    and this model will get larger than that.

    Returns None when nothing survives the filter. `data_model.html` guards on
    `entities`, not on this diagram, so None stays a valid answer.
    """
    nodes = data_model_nodes()
    edges = data_model_edges()
    if context:
        keep = {n["key"] for n in nodes if n["context"] == context}
    else:
        keep = {n["key"] for n in nodes}
    if focus:
        if focus not in keep:
            return None
        neighbours = {focus}
        for e in edges:
            if e["source"] == focus:
                neighbours.add(e["target"])
            elif e["target"] == focus:
                neighbours.add(e["source"])
        keep &= neighbours
    nodes = [n for n in nodes if n["key"] in keep]
    if not nodes:
        return None

    taken: set[str] = set()
    name_of = {n["key"]: _dm_class_name(n["label"], taken) for n in nodes}

    def _decl(n) -> str:
        # The identifier is ASCII; the box shows the page's real title via a
        # mermaid class label (`class Id["Title"]`) whenever the two differ, so
        # "Durchführungsart" is drawn as written, not as "Durchfuehrungsart".
        ident = name_of[n["key"]]
        label = _clean_label(n["label"]).replace('"', "'")
        return f'{ident}["{label}"]' if label != ident else ident

    lines = ["classDiagram"]
    for n in nodes:
        body = []
        if n["stub"]:
            body.append("    <<term>>")
        elif n["stereotype"] and n["stereotype"] != "entity":
            body.append(f"    <<{n['stereotype']}>>")
        body += [f"    +{a}" for a in n["attributes"]]
        if body:
            lines.append(f"  class {_decl(n)} {{")
            lines += ["  " + b for b in body]
            lines.append("  }")
        else:
            lines.append(f"  class {_decl(n)}")

    for e in edges:
        if e["source"] not in keep or e["target"] not in keep:
            continue
        arrow, carded = _DM_ARROWS[e["kind"]]
        src, dst = name_of[e["source"]], name_of[e["target"]]
        if e["kind"] == "inheritance":
            # mermaid draws `Base <|-- Derived`; the page says "Derived is-a Base"
            src, dst = dst, src
        # `cardinality:` describes the TARGET end only. Deriving a source
        # multiplicity from it looked tidier and was wrong: "0..*" would have
        # drawn a zero on the owning side, which means nothing.
        if carded and e["cardinality"]:
            line = f'  {src} {arrow} "{e["cardinality"]}" {dst}'
        else:
            line = f"  {src} {arrow} {dst}"
        if e["verb"]:
            line += f" : {e['verb']}"
        lines.append(line)

    return "\n".join(lines)


# Section/callout extractors for the /data-model catalog: each DM page is
# rendered as bold-led sections (**Purpose.**, **Attributes.**, **Relationships.**,
# **Invariants / rules.** …) plus 0..n `> [!note] X` callouts (Open points,
# deliberately omitted). Order from the file is preserved so the on-page detail
# reads the same as the markdown source.

_DM_SECTION_RE = re.compile(
    r"^\*\*(?P<label>[^*\n]+?)\.\*\*\s*\n?(?P<body>.*?)"
    r"(?=^\*\*[^*\n]+?\.\*\*|^>\s*\[!|^##\s|\Z)",
    re.DOTALL | re.MULTILINE,
)

_DM_NOTE_RE = re.compile(
    r"^>\s*\[!note\]\s*(?P<title>[^\n]+)\n(?P<body>(?:^>.*\n?)+)",
    re.MULTILINE,
)

_DM_ATTRIBUTES_BLOCK_RE = re.compile(
    r"\*\*Attributes\.\*\*\s*\n(?P<body>.+?)"
    r"(?=^\*\*[A-Za-z][^*\n]+?\.\*\*|^>\s*\[!|^##\s|\Z)",
    re.DOTALL | re.MULTILINE,
)
# Hyphens belong here. `minimum-sale-price` is an ordinary field name, and
# excluding it did not fail loudly — the attribute simply vanished from the
# table and from the class box, which is the "looks merely empty" failure this
# whole area keeps producing.
_DM_ATTR_BULLET_RE = re.compile(
    r"^\s*-\s+`(?P<name>[a-zA-Z][a-zA-Z0-9_-]*)`", re.MULTILINE,
)


def _extract_dm_attribute_names(page: Page) -> list[str]:
    """Just the attribute *names* from the `**Attributes.**` bullet list — used
    for the compact summary table at the top of /data-model; the per-entity
    cards below carry types, modality, and prose."""
    m = _DM_ATTRIBUTES_BLOCK_RE.search(page.body)
    if not m:
        return []
    return _DM_ATTR_BULLET_RE.findall(m.group("body"))


def _extract_dm_sections(page: Page, titles: dict[str, str]) -> list[tuple[str, str]]:
    """`(label, rendered-html)` pairs for every `**Label.**` section in a DM body,
    in source order. Bullets / inline code are preserved by routing the section
    body back through `render_markdown`."""
    out = []
    for m in _DM_SECTION_RE.finditer(page.body):
        label = m.group("label").strip()
        body = m.group("body").rstrip()
        out.append((label, render_markdown(body, titles)))
    return out


def _extract_dm_notes(page: Page, titles: dict[str, str]) -> list[dict]:
    """`> [!note] Title` callouts as `{title, html}` records. Quote markers
    (`> `) are stripped before the body is re-rendered as markdown."""
    out = []
    for m in _DM_NOTE_RE.finditer(page.body):
        title = m.group("title").strip()
        body_lines = m.group("body").splitlines()
        cleaned = "\n".join(re.sub(r"^>\s?", "", line) for line in body_lines).strip()
        out.append({"title": title, "html": render_markdown(cleaned, titles)})
    return out


def data_model_entities() -> list[dict]:
    """One record per data-model page with its sections + notes ready to render —
    the per-entity catalog rendered below the projection diagram on /data-model."""
    titles = title_index()
    pages = sorted(load_folder("data-models"), key=lambda p: p.id)
    out = []
    for p in pages:
        out.append({
            "id": p.id,
            "stem": p.stem,
            "title": p.title,
            "status": p.status,
            "stereotype": str(p.meta.get("stereotype") or "").strip(),
            "source_of_truth": str(p.meta.get("source-of-truth") or "").strip(),
            "attributes": _extract_dm_attribute_names(p),
            "sections": _extract_dm_sections(p, titles),
            "notes": _extract_dm_notes(p, titles),
        })
    return out


# Block 05 collapses the underlying entity pages (data-models/,
# activity-models/) into one row per *model type* — use cases moved to block 04
# (DR-011). Each row links to its own
# overview page; types with no content yet are skipped from the listing.
SUPPORTING_MODEL_TYPES = [
    {"folder": "data-models", "label": "Data model", "code": "DM", "href": "/data-model"},
    {"folder": "activity-models", "label": "Activity models", "code": "ACT", "href": None},
]


def _supporting_model_entries() -> list[dict]:
    """One row per *populated* supporting-model type, for block 05's sample
    list. Empty types are skipped (they re-appear once their first page is
    written)."""
    out = []
    for m in SUPPORTING_MODEL_TYPES:
        n = len(load_folder(m["folder"]))
        if n == 0:
            continue
        out.append({
            "id": m["code"],
            "title": m["label"],
            "type": f"{n} entries",
            "status": "",
            "relations": n,
            "href": m["href"],
        })
    return out


def _goal_matrix(data: dict) -> tuple[list[dict], list[dict]]:
    """proj-goal-coverage as (columns, rows) for /goals (FR-036).

    Columns are the epics and use cases: epics that serve a goal or break
    rule-fr-traces-to-goal (`nogoal`), then use cases, then the enabler epics
    as their own group. Rows are the objectives; a row without a mark is a
    `gap`, and its `note` says when features or stories serve it all the same.
    Columns and rows carry their status for the "Agreed only" filter."""
    enabler_ids = {fr.id for fr in data["enablers"]}
    untraced_ids = {fr.id for fr in data["untraced"]}
    epics = [fr for fr in data["frs"]
             if str(fr.meta.get("stereotype") or "").strip().lower() == "epic"]

    def col(p: Page) -> dict:
        return {"id": p.id, "title": p.title, "url": _page_url(p.folder, p.stem),
                "status": p.status, "enabler": p.id in enabler_ids,
                "nogoal": p.id in untraced_ids}

    cols = ([col(e) for e in epics if e.id not in enabler_ids]
            + [col(uc) for uc in data["ucs"]]
            + [col(e) for e in epics if e.id in enabler_ids])
    col_ids = {c["id"] for c in cols}

    def gap_note(serving: list[Page], agreed: bool) -> str:
        # the features and stories that serve a goal without a column
        kinds = [k for k in ("feature", "story") if any(
            p.id not in col_ids and str(p.meta.get("stereotype") or "").strip().lower() == k
            for p in serving)]
        a = "agreed " if agreed else ""
        if not kinds:
            return f"No {a}epic or use case yet"
        plural = {"feature": "features", "story": "stories"}
        return f"No {a}epic yet, served by " + " and ".join(a + plural[k] for k in kinds)

    rows = []
    for o in data["objectives"]:
        serving = data["coverage"].get(o.id, [])
        covered = {p.id for p in serving}
        cells = [c["id"] in covered for c in cols]
        rows.append({"id": o.id, "title": o.title, "url": _page_url(o.folder, o.stem),
                     "status": o.status, "cells": cells, "gap": not any(cells),
                     "note": gap_note(serving, False),
                     # for "Agreed only": counts accepted pages only
                     "note_accepted": gap_note([p for p in serving if p.status == "accepted"], True)})
    return cols, rows


@app.route("/goals")
def goals_view():
    """req42 Block 01 — Vision + Objectives. Three sections top-down:
    Mermaid tree, full-text cards (vision then objectives), goal-coverage matrix.
    Goal↔Epic edges are read from each FR's `goal:` field (DR-018)."""
    titles = title_index()
    links = link_index()       # vision/objective prose wikilinks become real links
    data = load_goals()
    vision, objectives = data["vision"], data["objectives"]
    # the flat, sortable list of every goal page (FR-021)
    goal_rows = [{"id": g.id, "title": g.title, "url": _page_url(g.folder, g.stem),
                  "stereotype": str(g.meta.get("stereotype") or "").strip().lower(),
                  "horizon": str(g.meta.get("horizon") or "").strip(), "status": g.status}
                 for g in ([vision] if vision else []) + objectives]
    if not vision:
        # Empty vault: no `stereotype: vision` page yet. Render the empty
        # state rather than a 404 — this route must work on workshop day one.
        return render_template(
            "goals.html",
            diagram=None,
            vision={
                "id": "", "title": "No vision yet", "stereotype": "Vision",
                "maturity": None, "beneficiary": [],
                "html": "<p>No vision yet — capture a GOAL- page with "
                        "<code>stereotype: vision</code>.</p>",
            },
            objectives=[],
            fr_cols=[],
            matrix_rows=[],
            needs_mermaid=False,
            goal_rows=goal_rows,
        )

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

    vision_card = {
        "id": vision.id,
        "title": vision.title,
        "url": _page_url(vision.folder, vision.stem),
        "stereotype": "Vision",
        "maturity": None,
        "beneficiary": _wikilink_list(vision.meta.get("beneficiary")),
        # Vision card shows the prose of the `## Vision` section — the
        # objectives list and impact block from the wiki page are projected
        # below as separate objective cards and the coverage matrix.
        "html": "".join(f"<p>{p}</p>" for p in _vision_paragraphs(vision, titles, links)),
    }

    def _inline(s) -> str:
        """Frontmatter strings may contain `[[wikilinks]]` — render them as
        real hyperlinks when the target resolves."""
        return render_wikilinks(str(s or "").strip(), titles, links)

    fr_cols, matrix_rows = _goal_matrix(data)

    objective_cards = []
    for o in objectives:
        objective_cards.append({
            "id": o.id,
            "title": o.title,
            "url": _page_url(o.folder, o.stem),
            "stereotype": "Goal",
            "purpose": extract_pam_bullet(o, "Purpose", titles, links),
            "advantage": extract_pam_bullet(o, "Advantage", titles, links),
            "metric": _inline(o.meta.get("metric")),
            "target": _inline(o.meta.get("target")),
            "baseline": _inline(o.meta.get("baseline")),
            "beneficiary": _wikilink_list(o.meta.get("beneficiary")),
            # every requirement that serves the goal, features and stories
            # too: a superset of its matrix marks, as text (FR-036)
            "epics": [{"id": p.id, "title": p.title, "url": _page_url(p.folder, p.stem)}
                      for p in data["coverage"].get(o.id, [])],
        })

    diagram = _mermaid_goal_tree(vision, objectives)
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


@app.route("/data-model")
def data_model_view():
    """req42 block 05 — Data model: the full class diagram of all DM entities
    (not yet implemented — see build_data_model_full_diagram()) plus the
    per-entity catalog below — every section + callout block from every DM
    page, so the full data-model documentation lives on one page."""
    contexts = data_model_contexts()
    context = request.args.get("context") or None
    if context not in contexts:
        context = None                     # an unknown filter shows everything
    nodes = data_model_nodes()
    focus = request.args.get("focus") or None
    if focus not in {n["key"] for n in nodes}:
        focus = None
    diagram = build_data_model_full_diagram(context=context, focus=focus)
    return render_template("data_model.html", diagram=diagram, **_section_crumb("data-models"),
                           entities=data_model_entities(), nodes=nodes,
                           contexts=contexts, context=context, focus=focus,
                           stubs=[n for n in nodes if n["stub"]],
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
    pages = [p for t in tiles for f in t["folders"] for p in load_folder(f)]
    return render_template("area.html", area=area, tiles=tiles, count=len(pages),
                           maturity=maturity(p.status for p in pages), needs_mermaid=False)


@app.route("/req42/functional-requirements")
def functional_requirements_view():
    """req42 block 04 — Functional Requirements as the Epic→Feature→Story hierarchy.
    A dedicated rich view for the `functional-requirements` slug (the other /req42/<slug> blocks
    use the generic list). Flask matches this static rule ahead of the dynamic
    /req42/<slug>. Doubles as the home `functional-requirements` tile's click-target."""
    hierarchy = build_fr_hierarchy()
    goals = load_goals()
    diagram = _mermaid_goal_epic_tree(goals, hierarchy)
    block = REQ42_BY_SLUG.get("functional-requirements")
    uc_kids = {u["id"]: u for u in hierarchy["use_cases"]}
    use_cases = [{
        "id": p.id, "title": p.title, "url": _page_url("use-cases", p.stem),
        "level": str(p.meta.get("level") or ""),
        "priority": str(p.meta.get("priority") or ""),
        "status": p.status,
        "goals": [{"id": _goal_id_from_ref(g), "anchor": f"/goals#{_goal_id_from_ref(g)}"}
                  for g in (p.meta.get("goal") or [])],
        "n_features": uc_kids.get(p.id, {}).get("n_features", 0),
        "n_stories": uc_kids.get(p.id, {}).get("n_stories", 0),
    } for p in goals["ucs"]]
    # the flat list under the hierarchy (FR-021): every requirement and use
    # case once, sortable by priority, release and order
    rows = []
    for p in sorted(load_folder("functional-requirements"), key=lambda q: q.id):
        rows.append({"id": p.id, "title": p.title, "url": f"/functional-requirements/{p.stem}",
                     "kind": _fr_stereotype(p), "priority": str(p.meta.get("priority") or "").strip(),
                     "release": str(p.meta.get("release") or "").strip(),
                     "order": str(p.meta.get("order") if p.meta.get("order") is not None else "").strip(),
                     "status": p.status})
    for p in goals["ucs"]:
        rows.append({"id": p.id, "title": p.title, "url": _page_url("use-cases", p.stem),
                     "kind": "use case", "priority": str(p.meta.get("priority") or "").strip(),
                     "release": "", "order": "", "status": p.status})
    return render_template(
        "functional-requirements.html", hierarchy=hierarchy, diagram=diagram,
        block=block, use_cases=use_cases, needs_mermaid=bool(diagram), rows=rows,
    )


@app.route("/req42/backlog")
def backlog_redirect():
    """The block's pre-2026 name. Permanent redirect so old links and
    bookmarks keep working; the block itself is /req42/functional-requirements."""
    return redirect("/req42/functional-requirements", code=301)

@app.route("/functional-requirements/<stem>")
def fr_view(stem):
    """Rich detail page for one functional requirement of any stereotype
    (epic/feature/story), mirroring the wiki/functional-requirements/ folder.
    Shows the FR's full text plus — for non-leaf FRs — its own Feature→Story
    breakdown (mermaid + cards). Every FR node in the hierarchy diagrams clicks
    here, so the whole hierarchy lives under one sprechenden path with a
    'Functional Requirements' breadcrumb (instead of the generic /page 'Search' crumb).
    404 if `stem` is not an FR page."""
    path = WIKI_DIR / "functional-requirements" / f"{stem}.md"
    page = _parse(path, "functional-requirements") if path.is_file() else None
    if not page:
        abort(404)
    titles = title_index()
    body = re.sub(r"^\s*#\s+.*(?:\n|$)", "", page.body, count=1)  # drop leading "# Title"
    body_html = render_markdown(body, titles)

    hierarchy = build_fr_hierarchy()
    node, kind = _fr_hierarchy_node(hierarchy, stem)
    fr = {
        "id": page.id, "title": page.title, "stem": stem,
        "stereotype": kind or _fr_stereotype(page) or "story",
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

    diagram = _mermaid_fr_subtree(node)
    trace = build_trace(stem, "functional-requirements")
    return render_template(
        "fr.html", fr=fr, body_html=body_html, diagram=diagram,
        ancestors=_fr_ancestors(stem),
        trace=trace,
        relations=build_relations_panel(stem, exclude=trace_stems(trace)),
        needs_mermaid=bool(diagram) or "language-mermaid" in body_html,
        sources=provenance(page),
        page_issues=open_issues_for(stem),
        formats=format_labels(page.body),
    )


_QR_SCENARIO = ("Source", "Stimulus", "Environment", "Response", "Measure")


def _qr_details(page: Page, titles: dict[str, str],
                links: dict[str, tuple[str, str]]) -> dict:
    """What a quality requirement needs on the block list besides its title:
    its Q42 dimensions (DR-003), the priority and its Q42 quality scenario, so
    the list reads without opening every page. Empty scenario parts are left out."""
    scenario = [(label, re.sub(r"\*(\S[^*]*?)\*", r"<em>\1</em>", html)) for label in _QR_SCENARIO
                if (html := extract_pam_bullet(page, label, titles, links))]
    dims = page.meta.get("dimensions") or []
    if isinstance(dims, str):
        dims = [dims]
    return {"dimensions": [str(d).strip() for d in dims if str(d).strip()],
            "priority": str(page.meta.get("priority") or "").strip(),
            "scenario": scenario}


@app.route("/req42/<slug>")
def req42_block_view(slug):
    """All entries of one req42 block, for blocks without their own rich view."""
    block = REQ42_BY_SLUG.get(slug)
    if not block:
        abort(404)
    titles, links = title_index(), link_index()
    rows = [
        {"id": p.id, "type": FOLDER_LABELS.get(p.folder, p.folder),
         "title": p.title, "url": _page_url(p.folder, p.stem),
         "status": p.status, "relations": len(p.link_targets()),
         **(_qr_details(p, titles, links) if p.folder == "quality-requirements" else {})}
        for p in _block_pages(block)
    ]
    # the Scope block (03) shows the same live-projected system-context diagram
    context_diagram = build_context_diagram() if slug == "scope" else None
    context_flows = build_context_flows() if slug == "scope" else None
    return render_template(
        "req42_block.html", block=block, rows=rows, total=len(rows),
        list_type=metamodel.type_for_folder(block["folders"][0]) if block["folders"] else "page",
        context_diagram=context_diagram, context_flows=context_flows,
        needs_mermaid=bool(context_diagram),
        maturity=maturity(r["status"] for r in rows),
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


# ---------------------------------------------------------------------------
# Server lifecycle: self-shutdown as soon as no browser is watching anymore.
# Multiple browsers (workshop clients) may watch at once, so presence is
# tracked per client (a random id each tab generates once, in base.html)
# rather than as a single "is anyone home" flag.
#
# Every open page sends a lightweight heartbeat (`POST /ping`) every few
# seconds, tagged with its client_id. As long as any client keeps pinging,
# the server keeps running; once the last one goes quiet, the watchdog shuts
# it down after a grace period — a closed browser window leaves no orphaned
# container behind. A page additionally reports via a pagehide beacon
# `POST /leaving` that it is going away: if it was just navigation, the next
# page's `/ping` (same client_id, carried via sessionStorage) immediately
# clears the signal; if the tab is really closed, that client is dropped
# after `_LEAVE_GRACE` (~5 s) instead of waiting out the full heartbeat grace
# period.
#
# Deliberately NO long-lived open connection (an earlier iteration used an
# SSE/events stream): that tied up a worker thread for a tab's entire
# lifetime, and clicking through subpages piled these up until the thread
# pool was exhausted and even /stop stopped being served. A /ping is instead
# an immediate request that holds no thread — the problem disappears
# entirely. The grace period is generous so a tab throttled in the background
# (browsers throttle timers to ~1x/min) stays alive; only a genuinely closed
# tab stops pinging altogether. A single worker keeps the state
# process-coherent (Dockerfile: --workers 1). See DR-022 and its addendum.
# ---------------------------------------------------------------------------


def _grace(env_name: str, default: float) -> float:
    """Grace period in seconds, overridable via env var (for tests/tuning)."""
    try:
        return float(os.environ.get(env_name, default))
    except (TypeError, ValueError):
        return default


# Shut down once no client has pinged for longer than this. Larger than the
# browser's background-tab throttling (~60 s), so a merely hidden tab does
# not falsely trigger a shutdown; only a genuinely closed tab drops out.
_HEARTBEAT_GRACE = _grace("DASH_HEARTBEAT_GRACE", 90.0)
# Grace period at startup, until the first heartbeat arrives (a slower first
# build / first render). If one never comes, the server shuts down afterwards
# instead of running on as an orphan.
_STARTUP_GRACE = _grace("DASH_STARTUP_GRACE", 90.0)
# Short grace period after a client's "tab is leaving" signal (`/leaving`,
# via a pagehide beacon) before dropping that client. On navigation the next
# page connects right away (`/ping` clears the signal); if none arrives (tab
# closed), the client is dropped after this — much faster than the heartbeat
# grace period.
_LEAVE_GRACE = _grace("DASH_LEAVE_GRACE", 5.0)
# How recently a client must have pinged to count as "connected" in the
# footer's live counter. Deliberately tighter than _HEARTBEAT_GRACE: the
# counter is a live-feeling UI nicety, not the shutdown trip wire, so it
# should not wait out the full 90 s tolerance built in for background-tab
# throttling.
_PRESENCE_WINDOW = _grace("DASH_PRESENCE_WINDOW", 30.0)

_lifecycle_lock = threading.Lock()
_clients: dict[str, float] = {}   # client_id -> monotonic time of last /ping
_leaving: dict[str, float] = {}   # client_id -> monotonic time /leaving arrived
_first_seen: dict[str, float] = {}   # client_id -> monotonic time of its first-ever /ping
_user_agents: dict[str, str] = {}    # client_id -> User-Agent header from its latest /ping
# Sticky identity for the whole dashboard session (= server lifetime): a
# client_id's name is fixed at its first /ping and never changes, and the
# facilitator role moves on only when its holder is gone — never back.
# Neither is cleared by `_forget_client`, so a tab that drops out and
# returns with the same client_id is still the same person.
_names: dict[str, str] = {}          # client_id -> name, fixed at first /ping
_facilitator: str | None = None      # client_id currently holding the role
_ever_connected = False
_shutting_down = False
_watchdog_started = False
_server_started = time.monotonic()


def _forget_client(cid):
    """Drop a client_id from every presence structure at once — called from
    the watchdog's two eviction paths so none of them can go out of sync."""
    _clients.pop(cid, None)
    _leaving.pop(cid, None)
    _first_seen.pop(cid, None)
    _user_agents.pop(cid, None)


def _facilitator_client_id():
    """The facilitator: the first client to connect ("Yoda"), and it keeps
    the role for as long as it is *currently connected*. No shared secret —
    just connection order. A reload/navigation keeps the same client_id
    (sessionStorage), so it doesn't cost the role.

    Sticky: the role is not recomputed per call. Only when its holder is
    no longer connected does it pass, once, to whoever is left with the
    earliest first_seen; it does not return when the old holder's tab
    reappears. Recomputing it on every call made the role (and with it the
    name "Yoda") flip back and forth between two tabs whenever the first
    one hovered around the presence window (reported 2026-10-28).

    "Currently connected" means within `_PRESENCE_WINDOW`, same bar as the
    footer counter and /who — not merely "not yet evicted by the 90s
    heartbeat grace" (`_clients`/`_first_seen` only drop an entry that late).
    Without this, a tab gone 40s ago could still hold the role for another
    50s, and everyone actually present would show as a plain client
    (nobody would pass the `cid == _facilitator_client_id()` check at all).
    Call under `_lifecycle_lock`."""
    global _facilitator
    now = time.monotonic()
    active = {cid: fs for cid, fs in _first_seen.items()
              if now - _clients.get(cid, 0) <= _PRESENCE_WINDOW}
    if _facilitator in active:
        return _facilitator
    _facilitator = min(active, key=active.get) if active else None
    return _facilitator


def _name_for(cid):
    """This client_id's name for the whole session, fixed on first call:
    "Yoda" for the very first facilitator, a random-looking nickname for
    everyone else. A client that later inherits the role keeps its own
    name. Call under `_lifecycle_lock`."""
    if cid not in _names:
        is_first = not _names and cid == _facilitator_client_id()
        _names[cid] = "Yoda" if is_first else _nickname(cid)
    return _names[cid]


def _shutdown(reason):
    """Cleanly shut down the server. Under gunicorn, the master (our parent)
    is terminated via SIGTERM, so all workers exit and the container's PID 1
    returns — with `restart: no` the container then stays down. Under the dev
    server we only terminate ourselves (NOT the parent — that is the shell)
    via SIGTERM: a SIGINT sent from a background thread to our own process is
    swallowed by the Werkzeug dev server (Werkzeug 3.x), whereas SIGTERM is
    reliably handled via the default signal action."""
    global _shutting_down
    with _lifecycle_lock:
        if _shutting_down:
            return
        _shutting_down = True
    app.logger.info("dashboard shutdown: %s", reason)

    def _terminate():
        time.sleep(0.4)  # let the HTTP response / beacon flush first
        if app.config.get("DEV_SERVER"):
            os.kill(os.getpid(), signal.SIGTERM)
            return
        try:
            os.kill(os.getppid(), signal.SIGTERM)  # gunicorn master
        except (ProcessLookupError, PermissionError):
            pass
        os.kill(os.getpid(), signal.SIGTERM)

    threading.Thread(target=_terminate, daemon=True).start()


def _watchdog():
    global _ever_connected
    while True:
        time.sleep(1.0)
        with _lifecycle_lock:
            if _shutting_down:
                return
            now = time.monotonic()
            # A client said goodbye and never pinged again: drop it (fast
            # path on tab close). A fresher ping after the goodbye cancels it
            # (was just in-page navigation).
            for cid, left_at in list(_leaving.items()):
                last = _clients.get(cid)
                if last is not None and last > left_at:
                    _leaving.pop(cid, None)
                elif now - left_at > _LEAVE_GRACE:
                    _forget_client(cid)
            # A client simply went stale (no goodbye, no more pings either).
            for cid, last in list(_clients.items()):
                if now - last > _HEARTBEAT_GRACE:
                    _forget_client(cid)
            anyone_left = bool(_clients)
            ever = _ever_connected
        if not ever:
            # Nobody has ever pinged -> startup grace period.
            if now - _server_started > _STARTUP_GRACE:
                _shutdown("no browser heartbeat within the startup grace period")
                return
        elif not anyone_left:
            _shutdown("no more browser heartbeat (all tabs closed)")
            return


def _ensure_watchdog():
    global _watchdog_started
    with _lifecycle_lock:
        if _watchdog_started:
            return
        _watchdog_started = True
    threading.Thread(target=_watchdog, daemon=True).start()


def _client_id(req) -> str:
    """The per-tab id a page sends with /ping and /leaving (generated once in
    base.html, kept in sessionStorage so it survives in-tab navigation but
    not a closed tab). Defaulted and length-capped so a missing or malformed
    body can't wedge the presence dict."""
    try:
        data = req.get_json(silent=True, force=True) or {}
    except Exception:
        data = {}
    cid = str(data.get("client_id") or "").strip()[:64]
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
    global _ever_connected
    _ensure_watchdog()
    cid = _client_id(request)
    ua = request.headers.get("User-Agent", "")[:200]
    with _lifecycle_lock:
        now = time.monotonic()
        if cid not in _clients:
            _first_seen[cid] = now
        _clients[cid] = now
        _user_agents[cid] = ua
        _leaving.pop(cid, None)
        _ever_connected = True
        is_facilitator = cid == _facilitator_client_id()
        nickname = _name_for(cid)
    return {"nickname": nickname, "is_facilitator": is_facilitator}


@app.route("/leaving", methods=["POST"])
def heartbeat_leaving():
    """Beacon sent when one page is left (pagehide: tab closed OR navigated).
    Marks that client_id as possibly-gone; if the user was only navigating,
    the next page's immediate `/ping` (same client_id) clears the signal
    again before it expires."""
    _ensure_watchdog()
    cid = _client_id(request)
    with _lifecycle_lock:
        _leaving[cid] = time.monotonic()
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
    with _lifecycle_lock:
        count = sum(1 for last in _clients.values()
                    if now - last <= _PRESENCE_WINDOW)
    return {"count": count}


_NICKNAME_ADJECTIVES = ["Curious", "Swift", "Quiet", "Bold", "Sunny", "Clever",
                         "Gentle", "Brisk", "Merry", "Wandering", "Sharp", "Calm"]
_NICKNAME_ANIMALS = ["Otter", "Falcon", "Fox", "Heron", "Lynx", "Puffin",
                      "Badger", "Wren", "Marten", "Ibex", "Hare", "Tern"]


def _nickname(client_id: str) -> str:
    """A stable, fun, non-identifying label for a client_id, for the "who's
    here" page — deterministic (the same tab always gets the same nickname
    across polls) but derived from nothing more than the random id the tab
    already generated itself, so there's no real identity behind it."""
    h = zlib.crc32(client_id.encode("utf-8"))
    adjective = _NICKNAME_ADJECTIVES[h % len(_NICKNAME_ADJECTIVES)]
    animal = _NICKNAME_ANIMALS[(h // len(_NICKNAME_ADJECTIVES)) % len(_NICKNAME_ANIMALS)]
    return f"{adjective} {animal}"


def _parse_user_agent(ua: str) -> tuple[str, str]:
    """Coarse browser/OS labels for the "who's here" page. Good enough for
    the handful of browsers a workshop room actually shows up with — not a
    real user-agent-parsing library, and doesn't need to be."""
    ua = ua or ""
    if "Edg/" in ua:
        browser = "Edge"
    elif "OPR/" in ua or "Opera" in ua:
        browser = "Opera"
    elif "Firefox/" in ua:
        browser = "Firefox"
    elif "CriOS" in ua or ("Chrome/" in ua and "Safari/" in ua):
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    else:
        browser = "a browser"

    if "iPhone" in ua or "iPad" in ua:
        os_name = "iOS"
    elif "Android" in ua:
        os_name = "Android"
    elif "Mac OS X" in ua:
        os_name = "macOS"
    elif "Windows" in ua:
        os_name = "Windows"
    elif "Linux" in ua:
        os_name = "Linux"
    else:
        os_name = ""
    return browser, os_name


@app.route("/presence/list")
def presence_list():
    """Per-client detail for the "who's here" page: a fun deterministic
    nickname, a coarse browser/OS, and how long they've been connected.
    Includes the facilitator, same as /presence/count, marked with
    `is_facilitator: true` so the page can mark the role. Shown to every
    viewer, not facilitator-gated — it's meant as a bit of a moment for
    everyone else, not an admin tool."""
    now = time.monotonic()
    with _lifecycle_lock:
        yoda = _facilitator_client_id()
        rows = []
        for cid, last in _clients.items():
            if now - last > _PRESENCE_WINDOW:
                continue
            browser, os_name = _parse_user_agent(_user_agents.get(cid, ""))
            rows.append({
                "nickname": _name_for(cid),
                "is_facilitator": cid == yoda,
                "browser": browser,
                "os": os_name,
                "connected_seconds": round(now - _first_seen.get(cid, last)),
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
    mtime) and the folder listings are re-globbed per request, so a fresh
    ingest's new, edited and deleted pages already show up on an ordinary
    browser refresh. Two things do not, and they are why the button exists —
    a rewrite that lands on the same mtime (a restored file, a checkout, a
    timestamp-preserving copy) stays a cache hit forever, and Jinja compiles
    each template once per worker, so an edited template otherwise needs the
    process restarted. Clearing both costs one re-parse of the vault, which
    is milliseconds at workshop scale.

    Open to every viewer, unlike the facilitator-only controls below: it
    reads the same read-only files any page render already reads, and the
    worst a stranger can do with it is make one render slower.

    POST-only on purpose. A GET would let a prefetch or a crawler flush the
    cache on someone else's behalf."""
    _PARSE_CACHE.clear()
    if app.jinja_env.cache is not None:
        app.jinja_env.cache.clear()
    return {"ok": True}


@app.route("/settings", methods=["GET"])
def settings_get():
    """The Configure dialog's data: the catalog grouped by area plus the
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
    """Facilitator-only: replace the hide list and rewrite dashboard.yaml.
    Same self-asserted client_id check as /disconnect-all — the facilitator is
    whoever connected first and is still here. Unknown IDs are a 400 and
    nothing is written; the dialog only ever sends catalog IDs, so a 400 here
    means a stale page or a hand-crafted request."""
    cid = _client_id(request)
    with _lifecycle_lock:
        if cid != _facilitator_client_id():
            abort(403)
    try:
        data = request.get_json(silent=True, force=True) or {}
    except Exception:
        data = {}
    valid, unknown = _validate_hidden(data.get("hidden"))
    if unknown or not isinstance(data.get("hidden"), list):
        return {"error": "unknown", "unknown": unknown}, 400
    write_dashboard_config(valid)
    if has_request_context():             # drop this request's memoised config
        g.get("_build_cache", {}).pop(("dashboard_config", ()), None)
    _PARSE_CACHE.clear()
    if app.jinja_env.cache is not None:
        app.jinja_env.cache.clear()
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
    shutting the server down outright (`_shutdown`, above). Everyone else's
    next /ping then fails, which the footer script turns into a plain
    "session ended" notice (base.html)."""
    cid = _client_id(request)
    with _lifecycle_lock:
        if cid != _facilitator_client_id():
            abort(403)
    _shutdown("disconnect-all requested by facilitator")
    return ("", 204)


# Start the watchdog on import (in the gunicorn worker or dev process), so the
# startup grace period also applies if no /ping ever arrives.
_ensure_watchdog()

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
    html = md.markdown(text.replace("{{DIAGRAM}}", img), extensions=["extra", "sane_lists"])
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
_MM_ROUTE_RE = re.compile(r"^(/\S*)")


def _mm_dr_link(ref: str, label: str = "") -> str:
    """A decision record a metamodel page cites, as a link to its page — only
    when the vault has a page with exactly that stem. The metamodel ships to
    every project, but meta's decisions do not (DR-034), and a project numbers
    its own from DR-001: a bare 'DR-013' there is a different decision. So a
    bare ID is never linked, and a full stem ('DR-013-data-flows-as-…') the
    vault lacks stays plain text instead of a link that 404s."""
    text = escape(label or ref)
    if ref in {p.stem for p in load_folder("decisions")}:
        return f'<a class="wl" href="{_page_url("decisions", ref)}">{text}</a>'
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
        if a := anchor_lookup().get(base.lower()):
            return (f'<a class="wl wl-anchor" href="#{a["id"]}" '
                    f'title="{escape(anchor_title(a))}">{escape(alias or a["name"])}</a>')
        if base in anchors:
            return f'<a class="wl" href="#{anchors[base]}">{escape(alias or base)}</a>'
        if _MM_DR_RE.match(base):
            return _mm_dr_link(base, alias)
        return f'<span class="mm-anchor">{escape(alias or base)}</span>'
    return WIKILINK_RE.sub(repl, text)


def _mm_html(text: str, anchors: dict[str, str]) -> str:
    """A metamodel page body (or a summary line) as HTML."""
    return md.markdown(_mm_wikilinks(_unwrap_prose(text or ""), anchors),
                       extensions=["extra", "sane_lists"])


def _mm_inline(text: str, anchors: dict[str, str]) -> str:
    """One line of markdown without the wrapping paragraph, for a table cell."""
    html = _mm_html(text, anchors).strip()
    if html.startswith("<p>") and html.endswith("</p>") and html.count("<p>") == 1:
        html = html[3:-4]
    return html


_MM_BODY_H1_RE = re.compile(r"^#\s+[^\n]*\n", re.MULTILINE)

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
        pages = load_sources()
        url = lambda p: f"/source/{p.stem}"             # noqa: E731
    else:
        name = Path(folder).name
        pages = load_folder(name)
        url = lambda p: _page_url(name, p.stem)         # noqa: E731
    if not pages:
        return {"count": 0}
    best = min(pages, key=lambda p: (_MM_EXAMPLE_RANK.get(p.status, 9), p.id))
    return {"count": len(pages), "id": best.id, "title": best.title, "url": url(best),
            "status": best.status, "stereotype": best.meta.get("stereotype") or ""}


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
    a = anchor_lookup().get(str(name).strip().lower())
    if not a:
        return {"name": str(name), "href": "", "title": ""}
    return {"name": a["name"], "href": f"#{a['id']}", "title": anchor_title(a)}


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

    alt = mm["altitude"]
    altitude = None
    if alt:
        altitude = {
            "rungs": alt.get("rungs") or [],
            "assignments": [{"type": _mm_type_label(a.get("type"), by_name),
                             "type_anchor": anchors.get(str(a.get("type")), ""),
                             "stereotype": a.get("stereotype") or "", "field": a.get("field") or "",
                             "rung": a.get("rung") or "", "status": a.get("status") or "",
                             "note": a.get("note") or ""} for a in alt.get("assignments") or []],
            "body_html": _mm_html(_MM_BODY_H1_RE.sub("", alt.get("_body") or "", count=1), anchors),
        }

    rules = []
    for ru in mm["rules"]:
        ap = ru.get("applies_to") or {}
        st = ap.get("stereotype")
        rules.append({
            "name": ru["name"], "anchor": f"rule-{ru['name']}",
            "applies_type": _mm_type_label(ap.get("type"), by_name),
            "applies_anchor": anchors.get(str(ap.get("type")), ""),
            "applies_stereotype": ", ".join(st) if isinstance(st, list) else (st or ""),
            "check": _mm_inline(str(ru.get("check") or ""), anchors),
            "confidence": ru.get("confidence") or "", "action": ru.get("action") or "",
            "source": ru.get("source") or "",
            "summary_html": _mm_inline(ru.get("_summary") or "", anchors),
        })

    graph = build_metamodel_graph(mm)
    n_in = sum(1 for b in mm["blocks"] if b.get("scope") == "in")
    return render_template(
        "metamodel.html", present=mm["present"], types=types, relations=relations,
        projections=projections, altitude=altitude, rules=rules, graph=graph,
        method_anchors=build_mm_anchors(mm, anchors),
        universal=graph["universal"], universal_fields=universal_fields,
        lifecycles=meta.get("lifecycles") or {}, constructs=meta.get("constructs") or [],
        field_kinds=meta.get("field_kinds") or [], version=meta.get("version") or "",
        frameworks=mm["frameworks"], n_blocks_in=n_in, n_blocks=len(mm["blocks"]),
        n_examples=sum(1 for t in types if t["example"]["count"]),
        decision_html=_mm_dr_link("DR-035-explicit-metamodel", "DR-035"),
    )


def _about_path() -> Path | None:
    try:
        data = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        data = {}
    return about_doc(data.get("about")) if isinstance(data, dict) else None


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
    html = md.markdown(path.read_text(encoding="utf-8"), extensions=["extra", "sane_lists"])
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
    return send_file(path)


if __name__ == "__main__":
    app.config["DEV_SERVER"] = True
    app.run(host="0.0.0.0", port=8000, threaded=True)
