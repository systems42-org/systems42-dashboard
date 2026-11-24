"""The brand and the about page: files of the wiki repository, served as they
are.

Owns the routes of the active brand's marks and its intro, the about page
and the files it links to, and the policy that keeps such a file inert.
Which folder and which page these are is decided in `settings.py`.

May import Flask and every module below `web/`, never `app`
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import quote, unquote

import markdown as md
from flask import Blueprint, abort, current_app, make_response, render_template, request, send_file

import render  # sanitizer, wikilinks and Markdown
import settings  # wiki.yaml, the brand, the about page and what the view hides
import wiki  # paths, pages, parse cache and loaders

bp = Blueprint("brand", __name__)


# A file the dashboard serves as it is (a brand mark, a file under docs/) is
# shown from the dashboard's own origin. Opened directly, an SVG or HTML file
# with a script in it would run with the dashboard's rights; sandboxed and
# without script it is only a picture.
_FILE_CSP = "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox"


def _inert_file(resp):
    resp.headers["Content-Security-Policy"] = _FILE_CSP
    resp.headers["X-Content-Type-Options"] = "nosniff"
    return resp


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
        css = (Path(current_app.static_folder) / "style.css").read_text(encoding="utf-8")
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


@bp.route("/brand/intro.html")
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


@bp.route("/brand/<name>")
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


@bp.route("/about")
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


@bp.route("/about/files/<path:name>")
def about_file(name):
    """Files the about page links to (images, SVGs) — inside docs/ only."""
    if _about_path() is None:
        abort(404)
    path = settings.docs_file(name)
    if path is None:
        abort(404)
    return _inert_file(send_file(path))
