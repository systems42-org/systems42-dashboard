"""Requirements-Wiki Dashboard.

A small read-only Flask app that parses the Obsidian-style requirements wiki
(markdown + YAML frontmatter + [[wikilinks]]) live on each request and renders
it as a tiled dashboard. The wiki folder is mounted into the container; nothing
is ever written back.
"""
from __future__ import annotations

import mimetypes
import os
import secrets
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import Flask, g, has_request_context, render_template, request

import catalog  # the section catalog (DR-033)
import metamodel  # reader for _system/metamodel/ (DR-035)
import session  # presence, the Keyholder role, the view and the lifecycle
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders
import web.brand  # the brand's marks and intro, the about page and its files
import web.common  # what several route groups share
import web.help  # help, the method and the metamodel page
import web.pages  # home, areas, section lists, page and source detail, changes
import web.projections  # goals, requirements, terms, arc42 views, decisions, stakeholders, issues
import web.search_session  # search, join, presence, reload, the view and Disconnect all

# some slim base images lack a webp entry in their mime.types
mimetypes.add_type("image/webp", ".webp")

# Timezone for the "last refreshed" footer; honours the container's TZ env.
# Empty (not "UTC") when unset, so inject_refresh_time can fall back to the
# host's own local zone instead of forcing UTC.
DISPLAY_TZ = os.environ.get("TZ") or ""


def _build_cache() -> dict | None:
    """The builder cache of the current request (wiki._request_cached), or
    None outside a request."""
    return g.setdefault("_build_cache", {}) if has_request_context() else None


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


def inject_metamodel_version():
    """The repository's metamodel version against this release (FR-043), for
    the footer notice and the version section of /metamodel."""
    return {"metamodel_check": metamodel.version_check()}


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


def inject_nav():
    """`nav_items` for base.html: (href, label, current), hidden entries dropped."""
    if not has_request_context():
        return {"nav_items": [(h, l, False) for _, h, l in _nav_entries()]}
    area = catalog.area_for_path(request.path)
    return {"nav_items": [(h, l, _nav_current(k, h, request.path, area))
                          for k, h, l in _nav_entries() if not settings.is_hidden(k)]}


def not_found(_err):
    """A missing page keeps the header and footer, so the reader can go on
    from here (FR-013)."""
    return render_template("not_found.html"), 404


def create_app() -> Flask:
    """Build the Flask app: the hooks, the template context and the 404 page
    that apply to every route, the template globals, the route groups and the
    request cache. Two calls give two apps over the same module state (the
    settings, the session, the caches), which is fine while one process
    serves one wiki."""
    app = Flask(__name__)
    wiki.use_request_cache(_build_cache)

    app.before_request(read_sections)
    app.after_request(_page_policy)
    for processor in (inject_refresh_time, inject_identity, inject_metamodel_version,
                      inject_area, inject_nav):
        app.context_processor(processor)
    app.register_error_handler(404, not_found)

    app.jinja_env.globals["csp_nonce"] = csp_nonce
    app.jinja_env.globals["static_url"] = web.common.static_url
    app.jinja_env.globals["list_spec"] = web.common.list_spec
    # the folder a type's pages live in, for the hints that name it (CON-006)
    app.jinja_env.globals["type_folder"] = catalog.folder

    # The route groups, one blueprint each. None has a URL prefix.
    for group in (web.pages, web.projections, web.search_session, web.help, web.brand):
        app.register_blueprint(group.bp)
    return app


# The one app of this process: Gunicorn (`app:app`), the site export and the
# tests use it. Building it starts no thread and writes nothing.
app = create_app()


if __name__ == "__main__":
    session.start_lifecycle()
    app.run(host="0.0.0.0", port=8000, threaded=True)
