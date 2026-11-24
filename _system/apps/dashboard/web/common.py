"""What several route groups share.

Owns the static file URL with its cache buster, the sort presets of the
lists, the head and the section path of a detail page, the issue fields and
the issues that link to a page, and the address and QR code for joining.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import os
import re
import socket
from pathlib import Path
from urllib.parse import urlsplit

from flask import current_app, request, url_for

import catalog  # the section catalog (DR-033)
import links as links_module  # link resolver and indexes. "links" is a local name in many functions here
import wiki  # paths, pages, parse cache and loaders
import project.architecture  # decisions, building blocks, runtime, deployment, traces
import project.common  # what several projections share


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
        mtime = int((Path(current_app.static_folder) / filename).stat().st_mtime)
    except OSError:
        return url
    return f"{url}?v={mtime}"


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
