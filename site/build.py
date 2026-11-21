#!/usr/bin/env python3
"""Build the static dashboard.systems42.org website and /demo/ showcase.

Outputs a ready-to-publish GitHub Pages directory containing:
  - /               Landing page (arc42-inspired header & footer)
  - /downloads/     Downloadable dashboard.sh + SHA-256, Docker/GHCR, uv wheel, changelog
  - /docs/          Configuration, branding, workshops, Getting Started & brand prompt
  - /imprint/       Imprint (Impressum) & Privacy (Datenschutz)
  - /demo/          Static interactive export of a Systems42 wiki using the real dashboard
  - /CNAME          dashboard.systems42.org
  - /.nojekyll      Disables Jekyll processing on GitHub Pages

Nothing in the source repository or demo wiki is modified.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import html as html_lib
import json
import os
import re
import shutil
import sys
from collections import deque
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import jinja2
import markdown as md
import yaml

DEMO_PREFIX = "/demo"

# Server-only routes that do not exist in a static snapshot.
SKIP_PREFIXES = (
    "/ping",
    "/leaving",
    "/presence",
    "/who",
    "/join",
    "/reload",
    "/settings",
    "/disconnect-all",
)

# File extensions served directly (not wrapped in <path>/index.html).
ASSET_EXTS = {
    ".css", ".js", ".json", ".svg", ".png", ".jpg", ".jpeg", ".gif",
    ".webp", ".ico", ".woff", ".woff2", ".ttf", ".html", ".pdf", ".txt", ".xml", ".sh",
}

SEED_ROUTES = [
    "/",
    "/method",
    "/changes",
    "/domain-terms",
    "/graph/domain-terms",
    "/entity-diagram",
    "/issues",
    "/stakeholders",
    "/decisions",
    "/goals",
    "/req42",
    "/arc42",
    "/commons",
    "/req42/functional-requirements",
    "/arc42/building-blocks",
    "/arc42/concepts",
    "/arc42/runtime",
    "/arc42/deployment",
    "/search",
    "/search.json",
    "/metamodel",
    "/help",
    "/about",
    "/brand/intro.html",
    "/brand/favicon.svg",
    "/brand/mark-dark.svg",
    "/brand/mark-light.svg",
]

DEMO_BANNER_CSS = """
<style id="s42-site-demo-style">
.s42-demo-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem 1rem;
  padding: 0.45rem 1rem;
  background: #0f172a;
  color: #e2e8f0;
  border-bottom: 1px solid #1e293b;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  font-size: 0.84rem;
  line-height: 1.4;
}
.s42-demo-bar a {
  color: #93c5fd;
  text-decoration: none;
  font-weight: 600;
}
.s42-demo-bar a:hover { color: #ffffff; text-decoration: underline; }
.s42-demo-bar-links {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.9rem;
}
.s42-demo-bar-tag {
  font-size: 0.78rem;
  color: #cbd5e1;
  background: #1e293b;
  padding: 0.14rem 0.55rem;
  border-radius: 999px;
}
</style>
"""


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def render_markdown(text: str) -> str:
    return md.markdown(
        text,
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
    )


def extract_recent_changelog(changelog_path: Path, max_releases: int = 5) -> str:
    """Return HTML for the Unreleased + latest N release sections of CHANGELOG.md."""
    if not changelog_path.is_file():
        return "<p>See GitHub Releases for the full changelog.</p>"
    lines = changelog_path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    sections = 0
    started = False
    for line in lines:
        if line.startswith("## "):
            if started and sections >= max_releases:
                break
            started = True
            sections += 1
        if started:
            out.append(line)
    return render_markdown("\n".join(out))


def is_asset_path(path: str) -> bool:
    if path.startswith("/static/"):
        return True
    suffix = Path(path).suffix.lower()
    return suffix in ASSET_EXTS


def demo_url(raw: str) -> str:
    """Rewrite a dashboard root-absolute URL to live under /demo/."""
    if not raw.startswith("/") or raw.startswith("//"):
        return raw
    if raw == DEMO_PREFIX or raw.startswith(DEMO_PREFIX + "/"):
        return raw
    parts = urlsplit(raw)
    path = parts.path or "/"
    if any(path == p or path.startswith(p + "/") for p in SKIP_PREFIXES):
        return raw
    if path == "/":
        new_path = DEMO_PREFIX + "/"
    elif is_asset_path(path):
        new_path = DEMO_PREFIX + path
    else:
        new_path = DEMO_PREFIX + path.rstrip("/") + "/"
    return urlunsplit((parts.scheme, parts.netloc, new_path, parts.query, parts.fragment))


def transform_demo_html(html: str, demo_name: str) -> str:
    """Convert a live dashboard HTML response into a self-contained /demo/ static page."""
    # 1. Remove LAN QR join widget on the home page.
    html = re.sub(
        r'\s*<a class="hero-join"[^>]*>.*?</a>',
        "",
        html,
        flags=re.S,
    )

    # 2. Remove settings.js script tag (server-only View dialog).
    html = re.sub(
        r'\s*<script src="[^"]*settings\.js[^"]*"[^>]*></script>',
        "",
        html,
    )

    # 3. Remove live-server-only menu items (View, Who's here, Reload, Disconnect all).
    html = re.sub(
        r'\s*<li><button[^>]*id="open-settings"[^>]*>.*?</button></li>',
        "",
        html,
    )
    html = re.sub(
        r'\s*<li><a[^>]*href="/who"[^>]*>.*?</a></li>',
        "",
        html,
    )
    html = re.sub(
        r'\s*<li><button[^>]*id="reload-data"[^>]*>.*?</button></li>',
        "",
        html,
    )
    html = re.sub(
        r'\s*<li><button[^>]*id="disconnect-all"[^>]*>.*?</button></li>',
        "",
        html,
    )

    # 4. Replace live presence badge with a static snapshot label.
    html = re.sub(
        r'<span class="presence" id="presence" hidden>.*?</span>\s*</span>',
        '<span class="presence" id="presence"><span class="presence-unit">Static demo · read-only</span></span>',
        html,
        flags=re.S,
    )

    # 5. Strip heartbeat/presence/reload IIFEs while keeping Cmd-K and Theme switch.
    cmd_k_snippet = """  (function () {
    var isMac = /Mac|iPhone|iPad/.test(navigator.platform || "");
    var box = document.getElementById("nav-search");
    if (box) box.placeholder = "Search  " + (isMac ? "\\u2318K" : "Ctrl K");
    document.addEventListener("keydown", function (e) {
      if ((e.key === "k" || e.key === "K") && (isMac ? e.metaKey : e.ctrlKey) && !e.altKey && !e.shiftKey) {
        if (box) { e.preventDefault(); box.focus(); box.select(); }
      }
    });
  })();
"""
    html = re.sub(
        r"// Lifecycle: a lightweight per-tab heartbeat.*?// Theme switch\.",
        lambda _: cmd_k_snippet + "\n  // Theme switch.",
        html,
        flags=re.S,
    )

    # 6. Rewrite HTML href/src/action root-absolute URLs to /demo/...
    def _attr_repl(m: re.Match) -> str:
        attr, quote, val = m.group(1), m.group(2), m.group(3)
        return f"{attr}={quote}{demo_url(val)}{quote}"

    html = re.sub(r'\b(href|src|action)=(["\'])(/[^"\']*)\2', _attr_repl, html)

    # 7. Rewrite embedded JSON "url": "/..." values (search index, Cytoscape graphs).
    def _json_url_repl(m: re.Match) -> str:
        prefix, val = m.group(1), m.group(2)
        return f'{prefix}"{demo_url(val)}"'

    html = re.sub(r'("url"\s*:\s*)"(/[^"]*)"', _json_url_repl, html)

    # 8. Rewrite brand intro JS string on the home page (with or without ?v=).
    html = html.replace('"/brand/intro.html', f'"{DEMO_PREFIX}/brand/intro.html')

    # 9. Rewrite Mermaid click directives: click ID "/path"
    def _mermaid_click_repl(m: re.Match) -> str:
        prefix, val = m.group(1), m.group(2)
        return f'{prefix}"{demo_url(val)}"'

    html = re.sub(r'(\bclick\s+[A-Za-z0-9_.-]+\s+)"(/[^"]*)"', _mermaid_click_repl, html)

    # 10. Inject top navigation bar back to dashboard.systems42.org (AFTER URL rewrite!).
    demo_bar = (
        '<div class="s42-demo-bar" role="region" aria-label="Public showcase navigation">'
        '<div class="s42-demo-bar-links">'
        '<a href="/">← dashboard.systems42.org</a>'
        '<a href="/docs/">Docs</a>'
        '<a href="/downloads/">Downloads</a>'
        '</div>'
        f'<span class="s42-demo-bar-tag">Interactive static demo · {html_lib.escape(demo_name)}</span>'
        '</div>'
    )
    if "</head>" in html:
        html = html.replace("</head>", DEMO_BANNER_CSS + "</head>", 1)
    if "<body>" in html:
        html = html.replace("<body>", "<body>\n" + demo_bar, 1)

    return html


def export_demo(repo_dir: Path, demo_wiki: Path, out_dir: Path) -> dict:
    """Crawl and export the real dashboard app for demo_wiki into out_dir/demo/."""
    dashboard_dir = repo_dir / "_system" / "apps" / "dashboard"
    os.environ["REPO_DIR"] = str(demo_wiki.resolve())
    sys.path.insert(0, str(dashboard_dir))

    import app as dash_app  # type: ignore  # imported after setting REPO_DIR

    cfg = dash_app.wiki_config()
    demo_name = cfg.get("system_name") or "Systems42 Demo"
    demo_tagline = cfg.get("tagline") or "Interactive Systems42 requirements and architecture wiki"

    demo_out = out_dir / "demo"
    demo_out.mkdir(parents=True, exist_ok=True)

    # Copy dashboard static assets and patch search-popup.js for /demo prefix.
    static_src = dashboard_dir / "static"
    static_dst = demo_out / "static"
    shutil.copytree(static_src, static_dst, dirs_exist_ok=True)

    popup_js = static_dst / "search-popup.js"
    if popup_js.is_file():
        js_text = popup_js.read_text(encoding="utf-8")
        js_text = js_text.replace('fetch("/search.json")', f'fetch("{DEMO_PREFIX}/search.json")')
        js_text = js_text.replace('"/search?q=', f'"{DEMO_PREFIX}/search/?q=')
        js_text = js_text.replace("'/search?q=", f"'{DEMO_PREFIX}/search/?q=")
        popup_js.write_text(js_text, encoding="utf-8")

    client = dash_app.app.test_client()
    queue: deque[str] = deque(SEED_ROUTES)
    seen: set[str] = set()
    exported_routes = 0
    wiki_page_count = 0

    def enqueue(raw_href: str) -> None:
        if not raw_href.startswith("/") or raw_href.startswith("//"):
            return
        if "&lt;" in raw_href or "<" in raw_href or "{" in raw_href:
            return
        parts = urlsplit(raw_href)
        path = parts.path or "/"
        if path.startswith("/static/"):
            return
        if any(path == p or path.startswith(p + "/") for p in SKIP_PREFIXES):
            return
        if path not in seen:
            queue.append(path)

    while queue:
        route = queue.popleft()
        if route in seen:
            continue
        seen.add(route)

        resp = client.get(route)
        if resp.status_code in (301, 302, 303, 307, 308):
            loc = resp.headers.get("Location", "")
            enqueue(loc)
            # Also emit a tiny HTML meta-refresh redirect at this route so links still work.
            target = demo_url(urlsplit(loc).path or "/")
            redir_html = (
                '<!doctype html><html lang="en"><head><meta charset="utf-8">'
                f'<meta http-equiv="refresh" content="0; url={target}">'
                f'<link rel="canonical" href="{target}">'
                f'<title>Redirecting…</title></head><body><a href="{target}">Continue</a></body></html>\n'
            )
            dest = demo_out / route.lstrip("/") / "index.html"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(redir_html, encoding="utf-8")
            continue

        if resp.status_code != 200:
            continue

        ctype = (resp.content_type or "").split(";")[0].strip().lower()
        data = resp.get_data()

        if route == "/search.json" or ctype == "application/json":
            payload = json.loads(data.decode("utf-8"))
            if isinstance(payload, dict) and isinstance(payload.get("records"), list):
                wiki_page_count = len(payload["records"])
                for rec in payload["records"]:
                    if isinstance(rec, dict) and isinstance(rec.get("url"), str):
                        enqueue(rec["url"])
                        rec["url"] = demo_url(rec["url"])
            dest = demo_out / route.lstrip("/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            continue

        if ctype == "text/html" and route != "/brand/intro.html":
            raw_html = data.decode("utf-8")
            # Discover additional links before rewriting.
            for m in re.finditer(r'(?:href|src)=["\'](/[^"\']*)["\']', raw_html):
                enqueue(m.group(1))
            for m in re.finditer(r'"url"\s*:\s*"(/[^"]*)"', raw_html):
                enqueue(m.group(1))

            fixed_html = transform_demo_html(raw_html, demo_name)
            if route == "/":
                dest = demo_out / "index.html"
            else:
                dest = demo_out / route.lstrip("/") / "index.html"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(fixed_html, encoding="utf-8")
            exported_routes += 1
        else:
            dest = demo_out / route.lstrip("/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)

    return {
        "name": demo_name,
        "tagline": demo_tagline,
        "pages": wiki_page_count,
        "routes": exported_routes,
    }


def verify_output(out_dir: Path) -> None:
    """Verify required outputs exist and internal links resolve inside out_dir."""
    required = [
        "CNAME",
        ".nojekyll",
        "index.html",
        "downloads/index.html",
        "downloads/dashboard.sh",
        "docs/index.html",
        "docs/getting-started/index.html",
        "imprint/index.html",
        "demo/index.html",
        "demo/search/index.html",
        "demo/search.json",
    ]
    missing = [rel for rel in required if not (out_dir / rel).is_file()]
    if missing:
        raise RuntimeError(f"Missing expected site outputs: {missing}")

    broken: list[tuple[str, str]] = []
    live_leaks: list[str] = []

    for html_file in sorted(out_dir.rglob("*.html")):
        rel = html_file.relative_to(out_dir).as_posix()
        text = html_file.read_text(encoding="utf-8", errors="ignore")
        if rel.startswith("demo/") and rel != "demo/brand/intro.html":
            if 'fetch("/ping"' in text or 'fetch("/presence/count"' in text:
                live_leaks.append(rel)
        for m in re.finditer(r'\b(?:href|src)=["\'](/[^"\']*)["\']', text):
            raw = m.group(1)
            if raw.startswith("//") or "&lt;" in raw or "<" in raw or "{" in raw:
                continue
            path = urlsplit(raw).path or "/"
            if path == "/":
                target_ok = (out_dir / "index.html").is_file()
            else:
                candidate = out_dir / path.lstrip("/")
                target_ok = candidate.is_file() or (candidate / "index.html").is_file()
            if not target_ok:
                broken.append((rel, raw))

    if live_leaks:
        raise RuntimeError(f"Live heartbeat script leaked into static demo pages: {live_leaks[:5]}")
    if broken:
        sample = "\n".join(f"  {src} -> {dst}" for src, dst in broken[:20])
        raise RuntimeError(f"Found {len(broken)} broken internal links:\n{sample}")


def build_site(repo_dir: Path, demo_wiki: Path, out_dir: Path) -> None:
    site_dir = repo_dir / "site"
    version = (repo_dir / "_system" / "apps" / "dashboard" / "VERSION").read_text(encoding="utf-8").strip()
    built_date = datetime.date.today().isoformat()

    if out_dir.exists():
        for child in out_dir.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Export the interactive /demo/ showcase first so we have live stats & metadata.
    demo_info = export_demo(repo_dir, demo_wiki, out_dir)

    # 2. Copy site static assets and brand marks.
    assets_dir = out_dir / "assets"
    assets_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(site_dir / "static" / "site.css", assets_dir / "site.css")
    brand_dir = repo_dir / "_system" / "apps" / "dashboard" / "brands" / "systems42"
    for name in ("favicon.svg", "mark-light.svg", "mark-dark.svg"):
        shutil.copy2(brand_dir / name, assets_dir / name)

    # 3. Copy downloadable launcher script and compute checksum.
    dl_dir = out_dir / "downloads"
    dl_dir.mkdir(parents=True, exist_ok=True)
    launcher_src = repo_dir / "dashboard.sh"
    shutil.copy2(launcher_src, dl_dir / "dashboard.sh")
    launcher_sha256 = sha256_file(launcher_src)

    # 4. Copy CNAME and write .nojekyll for GitHub Pages.
    shutil.copy2(site_dir / "CNAME", out_dir / "CNAME")
    (out_dir / ".nojekyll").write_text("", encoding="utf-8")

    # 5. Render site pages with Jinja2.
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(site_dir / "templates")),
        autoescape=jinja2.select_autoescape(["html"]),
    )
    common = {
        "version": version,
        "built_date": built_date,
        "demo_name": demo_info["name"],
        "demo_tagline": demo_info["tagline"],
        "demo_stats": {
            "pages": demo_info["pages"],
            "routes": demo_info["routes"],
        },
    }

    def write_page(template_name: str, dest_rel: str, **ctx) -> None:
        html = env.get_template(template_name).render(**common, **ctx)
        dest = out_dir / dest_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(html, encoding="utf-8")

    write_page("index.html", "index.html", active_nav="home")
    write_page(
        "downloads.html",
        "downloads/index.html",
        active_nav="downloads",
        launcher_sha256=launcher_sha256,
        changelog_html=extract_recent_changelog(repo_dir / "CHANGELOG.md"),
    )
    write_page("docs.html", "docs/index.html", active_nav="docs")
    write_page("imprint.html", "imprint/index.html", active_nav="imprint")

    # Render repository documentation pages into /docs/...
    gs_path = repo_dir / "docs" / "GETTING-STARTED.md"
    if gs_path.is_file():
        write_page(
            "doc_page.html",
            "docs/getting-started/index.html",
            active_nav="docs",
            doc_title="Getting Started",
            doc_lead="Capturing, grilling and inspecting requirements in a Systems42 wiki.",
            body_html=render_markdown(gs_path.read_text(encoding="utf-8")),
        )

    prompt_path = repo_dir / "docs" / "prompts" / "brand-mark-and-intro.md"
    if prompt_path.is_file():
        write_page(
            "doc_page.html",
            "docs/brand-prompt/index.html",
            active_nav="docs",
            doc_title="Brand Prompt Template",
            doc_lead="Generate dark/light marks, a favicon and an intro animation for your Systems42 wiki.",
            body_html=render_markdown(prompt_path.read_text(encoding="utf-8")),
        )

    verify_output(out_dir)
    print(
        f"✓ Built dashboard.systems42.org into {out_dir} "
        f"(v{version}, demo '{demo_info['name']}': {demo_info['pages']} wiki pages, {demo_info['routes']} HTML views)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the static dashboard.systems42.org site.")
    parser.add_argument("--repo", type=Path, required=True, help="Path to systems42-dashboard repository")
    parser.add_argument("--demo-wiki", type=Path, required=True, help="Path to Systems42 wiki to export under /demo/")
    parser.add_argument("--out", type=Path, required=True, help="Output directory for generated static site")
    args = parser.parse_args()
    build_site(args.repo.resolve(), args.demo_wiki.resolve(), args.out.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
