"""Parity test: Python reference dashboard vs Go dashboard (issue #80, FR-055).

Starts both implementations against every wiki fixture under tests/fixtures/
and this repository's own wiki, asks both for every route (including every
page of every type and JSON endpoints), normalises what may differ (whitespace,
attribute order, footer timestamp, per-request tokens), and reports the first
difference per route.

Routes not ported yet live in UNPORTED_ROUTES (grouped by phase). That list
shrinks with every phase; the Go implementation is done when it is empty.

No pytest dependency; uses Python stdlib only. Exits 77 (skip) when neither
`go` nor `GO_DASHBOARD_BIN` is available (matching tests/test_uv_start.py).

Run from the dashboard dir:
    uv run --no-project --python 3.12 --with-requirements requirements.txt python tests/test_parity.py
"""
from __future__ import annotations

import html
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
REPO = HERE.parents[2]
FIXTURES_DIR = HERE / "tests" / "fixtures"

# Fixture directories that hold helper data rather than a wiki.
NON_WIKI_FIXTURES = {"notations"}

# Routes not ported to Go yet, grouped by the phase in issue #80 that ports
# them. Exact paths live in UNPORTED_EXACT; prefixes in UNPORTED_PREFIXES.
# When a phase lands, remove its entries here so CI enforces parity on them.
UNPORTED_EXACT: dict[str, str] = {}

UNPORTED_PREFIXES: tuple[tuple[str, str], ...] = ()

# Static assets verified for exact byte parity in Phase 0.
STATIC_SAMPLE_ROUTES = (
    "/static/style.css",
    "/static/settings.js",
    "/static/search-rank.js",
    "/static/search-popup.js",
    "/static/list-view.js",
    "/static/python-logo.svg",
    "/static/go-logo.svg",
)

# Fixed routes exercised on every wiki.
FIXED_ROUTES = (
    "/",
    "/req42",
    "/arc42",
    "/commons",
    "/req42/scope",
    "/req42/models",
    "/req42/quality",
    "/req42/constraints",
    "/req42/functional-requirements",
    "/req42/building-blocks",
    "/goals",
    "/entity-diagram",
    "/entity-diagram?focus=DT-002-order",
    "/graph/domain-terms",
    "/graph/domain-terms?edges=related",
    "/graph/domain-terms?edges=structured",
    "/arc42/strategy",
    "/arc42/building-blocks",
    "/arc42/deployment",
    "/arc42/runtime",
    "/arc42/concepts",
    "/section/C6",
    "/metamodel",
    "/method",
    "/changes",
    "/issues",
    "/issues?status=open",
    "/issues?status=closed",
    "/issues?section=c1",
    "/issues?owner=none",
    "/stakeholders",
    "/decisions",
    "/domain-terms",
    "/search",
    "/search.json",
    "/join",
    "/who",
    "/help",
    "/about",
    "/about/files/guide/mark.svg",
    "/settings",
    "/presence/count",
    "/presence/list",
    "/brand/mark-dark.svg",
    "/brand/mark-light.svg",
    "/brand/favicon.svg",
    "/brand/intro.html",
    "/brand/intro.html?theme=light",
    "/__parity_not_found__",
    *STATIC_SAMPLE_ROUTES,
    *UNPORTED_EXACT.keys(),
)

_REFRESHED_RE = re.compile(r"Data last refreshed:\s*\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}h")
_STATIC_VER_RE = re.compile(r"(/static/[^\"'\s?]+)\?v=[^\"'\s&]+")
_CSP_NONCE_RE = re.compile(r"'nonce-[^']+'")
_VOID_TAGS = frozenset({
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
})
_RAW_TEXT_TAGS = frozenset({"pre", "code", "script", "style"})


def is_unported(route: str) -> str | None:
    """Return the phase label if route is not yet ported, else None."""
    path_only = route.split("?", 1)[0]
    if path_only in UNPORTED_EXACT:
        return UNPORTED_EXACT[path_only]
    for prefix, phase in UNPORTED_PREFIXES:
        if path_only.startswith(prefix):
            return phase
    return None


class _Normalizer(HTMLParser):
    """Canonicalizes HTML into a flat token list so parity ignores whitespace,
    attribute order, footer timestamp, CSP nonces, static ?v= tokens, and QR
    SVG path encodings while catching every structural or text change."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.tokens: list[str] = []
        self._raw_depth = 0
        self._in_qr_svg = False
        self._in_stack_badge = False

    def _norm_attr(self, tag: str, name: str, val: str | None) -> tuple[str, str]:
        name = name.lower()
        if val is None:
            return (name, "")
        val = html.unescape(val)
        if name == "nonce" and val:
            return (name, "<NONCE>")
        if name in ("href", "src"):
            val = _STATIC_VER_RE.sub(r"\1?v=<V>", val)
        if name == "data-sort-orders" and val:
            try:
                val = json.dumps(json.loads(val), sort_keys=True, separators=(",", ":"))
            except ValueError:
                pass
        if self._in_stack_badge:
            if name == "title":
                return (name, "<STACK_TITLE>")
            if tag == "img" and name in ("src", "class", "width", "height"):
                return (name, f"<STACK_{name.upper()}>")
        if self._in_qr_svg:
            if tag == "svg" and name == "viewbox":
                return (name, "<QR_VIEWBOX>")
            if tag == "path" and name == "d":
                assert val.strip(), "QR SVG <path> has empty d attribute"
                return (name, "<QR_PATH>")
        return (name, val)

    def _format_tag(self, tag: str, attrs: list[tuple[str, str | None]]) -> str:
        tag = tag.lower()
        attr_map = dict((k.lower(), v or "") for k, v in attrs)
        if tag == "svg" and "segno" in attr_map.get("class", "").split():
            self._in_qr_svg = True
        if tag == "span" and "stack-badge" in attr_map.get("class", "").split():
            self._in_stack_badge = True
        norm = sorted(self._norm_attr(tag, k, v) for k, v in attrs)
        parts = [tag]
        for k, v in norm:
            parts.append(f'{k}="{v}"' if v != "" else k)
        return "<" + " ".join(parts) + ">"

    def handle_decl(self, decl: str) -> None:
        self.tokens.append(f"<!{decl.strip().lower()}>")

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        t = tag.lower()
        if self._in_stack_badge:
            return
        self.tokens.append(self._format_tag(t, attrs))
        if self._in_stack_badge:
            self.tokens.append("TEXT:<STACK_BADGE>")
        if t in _RAW_TEXT_TAGS:
            self._raw_depth += 1

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        t = tag.lower()
        if self._in_stack_badge:
            return
        self.tokens.append(self._format_tag(t, attrs))
        if t not in _VOID_TAGS:
            self.tokens.append(f"</{t}>")
            if t == "svg" and self._in_qr_svg:
                self._in_qr_svg = False

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if t in _VOID_TAGS:
            return
        if t in _RAW_TEXT_TAGS and self._raw_depth > 0:
            self._raw_depth -= 1
        if t == "svg" and self._in_qr_svg:
            self._in_qr_svg = False
        if t == "span" and self._in_stack_badge:
            self._in_stack_badge = False
            self.tokens.append(f"</{t}>")
            return
        if self._in_stack_badge:
            return
        self.tokens.append(f"</{t}>")

    def handle_data(self, data: str) -> None:
        self._emit_text(data)

    def handle_entityref(self, name: str) -> None:
        self._emit_text(html.unescape(f"&{name};"))

    def handle_charref(self, name: str) -> None:
        self._emit_text(html.unescape(f"&#{name};"))

    def _emit_text(self, text: str) -> None:
        if self._in_stack_badge:
            return
        if self._raw_depth > 0:
            text = text.replace("\r\n", "\n")
            if self.tokens and self.tokens[-1].startswith("TEXT:"):
                self.tokens[-1] += text
            elif text.strip():
                self.tokens.append("TEXT:" + text)
            return
        # Merge adjacent text/entity tokens before collapsing whitespace.
        if self.tokens and self.tokens[-1].startswith("TEXT:"):
            self.tokens[-1] += text
        else:
            self.tokens.append("TEXT:" + text)

    def finalize(self) -> list[str]:
        out: list[str] = []
        raw_depth = 0
        for tok in self.tokens:
            if tok.startswith("<") and not tok.startswith("</") and not tok.startswith("<!"):
                tag = tok[1:].split(" ", 1)[0].rstrip(">")
                if tag in _RAW_TEXT_TAGS:
                    raw_depth += 1
                out.append(tok)
            elif tok.startswith("</"):
                tag = tok[2:-1]
                if tag in _RAW_TEXT_TAGS and raw_depth > 0:
                    raw_depth -= 1
                out.append(tok)
            elif tok.startswith("TEXT:"):
                body = tok[5:]
                if raw_depth > 0:
                    body = body.strip()
                    if body:
                        if out and out[-1].startswith("<script ") and 'type="application/json"' in out[-1]:
                            try:
                                parsed = json.loads(body)
                                # Python's build_glossary_ego_graph iterates a set for nodes.
                                if 'id="ego-data"' in out[-1] and isinstance(parsed, dict) and isinstance(parsed.get("nodes"), list):
                                    parsed["nodes"] = sorted(parsed["nodes"], key=lambda n: n.get("data", {}).get("id", ""))
                                body = json.dumps(parsed, sort_keys=True, separators=(",", ":"))
                            except ValueError:
                                pass
                        out.append("RAW:" + body)
                else:
                    body = _REFRESHED_RE.sub("Data last refreshed: <REFRESHED_AT>", body)
                    body = re.sub(r"\s+", " ", body).strip()
                    if body:
                        out.append("TEXT:" + body)
            else:
                out.append(tok)
        return out


def normalize_html(doc: str) -> list[str]:
    p = _Normalizer()
    p.feed(doc)
    p.close()
    return p.finalize()


def first_token_diff(py_tokens: list[str], go_tokens: list[str]) -> str | None:
    """Return a concise description of the first differing token, or None."""
    n = min(len(py_tokens), len(go_tokens))
    for i in range(n):
        if py_tokens[i] != go_tokens[i]:
            lo = max(0, i - 2)
            ctx = " | ".join(py_tokens[lo:i])
            return (
                f"first difference at token #{i}\n"
                f"    before: {ctx}\n"
                f"    python: {py_tokens[i]!r}\n"
                f"    go:     {go_tokens[i]!r}"
            )
    if len(py_tokens) != len(go_tokens):
        extra_side = "python" if len(py_tokens) > len(go_tokens) else "go"
        extra_tok = (py_tokens if len(py_tokens) > len(go_tokens) else go_tokens)[n]
        return (
            f"first difference at token #{n} (length python={len(py_tokens)}, go={len(go_tokens)})\n"
            f"    extra in {extra_side}: {extra_tok!r}"
        )
    return None


def first_json_diff(py_val: object, go_val: object, path: str = "$") -> str | None:
    if type(py_val) is not type(go_val):
        return f"first JSON difference at {path}: python={py_val!r} ({type(py_val).__name__}), go={go_val!r} ({type(go_val).__name__})"
    if isinstance(py_val, dict):
        keys = sorted(set(py_val.keys()) | set(go_val.keys()))
        for k in keys:
            if k not in py_val:
                return f"first JSON difference at {path}.{k}: missing in python, go={go_val[k]!r}"
            if k not in go_val:
                return f"first JSON difference at {path}.{k}: python={py_val[k]!r}, missing in go"
            diff = first_json_diff(py_val[k], go_val[k], f"{path}.{k}")
            if diff:
                return diff
        return None
    if isinstance(py_val, list):
        for i in range(min(len(py_val), len(go_val))):
            diff = first_json_diff(py_val[i], go_val[i], f"{path}[{i}]")
            if diff:
                return diff
        if len(py_val) != len(go_val):
            return f"first JSON difference at {path}: list length python={len(py_val)}, go={len(go_val)}"
        return None
    if py_val != go_val:
        return f"first JSON difference at {path}: python={py_val!r}, go={go_val!r}"
    return None


def _test_normalizer() -> None:
    # Identical despite whitespace, attribute order, nonce, timestamp, static ?v=, QR path
    a = (
        '<!DOCTYPE html><html lang="en"><head>'
        '<link href="/static/style.css?v=12345" rel="stylesheet">'
        '<script nonce="aaa111">x=1;</script></head><body>'
        '<span class="hero-qr"><svg class="segno" viewBox="0 0 100 100">'
        '<path class="qrline" stroke="currentColor" transform="scale(4)" d="M1 1h5"/></svg></span>'
        '<footer>Data last refreshed: 2026-11-21 15:00:01h</footer></body></html>'
    )
    b = (
        '<!doctype html>\n<html lang="en">\n<head>\n'
        '  <link rel="stylesheet" href="/static/style.css?v=deadbeef">\n'
        '  <script nonce="zzz999">x=1;</script>\n</head>\n<body>\n'
        '  <span class="hero-qr"><svg viewBox="0 0 108 108" class="segno">'
        '<path transform="scale(4)" stroke="currentColor" class="qrline" d="M2 2h3"></path></svg></span>\n'
        '  <footer>Data last refreshed:   2026-11-21 15:00:09h</footer>\n</body>\n</html>'
    )
    assert first_token_diff(normalize_html(a), normalize_html(b)) is None, (normalize_html(a), normalize_html(b))

    # Must catch real differences (text, href, missing element, brand checksum)
    c = b.replace("15:00:09h</footer>", "15:00:09h<span>extra</span></footer>")
    diff = first_token_diff(normalize_html(a), normalize_html(c))
    assert diff is not None and "<span>" in diff, diff

    d1 = '<img src="/brand/mark-dark.svg?v=11111111">'
    d2 = '<img src="/brand/mark-dark.svg?v=22222222">'
    assert first_token_diff(normalize_html(d1), normalize_html(d2)) is not None, "brand checksum diff must fail"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _build_go_binary(tmp: Path) -> Path:
    prebuilt = os.environ.get("GO_DASHBOARD_BIN", "").strip()
    if prebuilt:
        p = Path(prebuilt)
        assert p.is_file(), f"GO_DASHBOARD_BIN does not exist: {p}"
        return p
    out = tmp / "systems42-dashboard"
    env = {**os.environ, "CGO_ENABLED": "0"}
    res = subprocess.run(
        ["go", "build", "-o", str(out), "./cmd/systems42-dashboard"],
        cwd=str(HERE), env=env, capture_output=True, text=True,
    )
    assert res.returncode == 0, f"go build failed:\n{res.stderr}"
    return out


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect())


def _fetch(url: str) -> tuple[int, dict[str, str], bytes]:
    req = urllib.request.Request(url, method="GET")
    try:
        with _OPENER.open(req, timeout=5) as resp:
            headers = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, headers, resp.read()
    except urllib.error.HTTPError as err:
        headers = {k.lower(): v for k, v in err.headers.items()}
        return err.code, headers, err.read()


def _wait_ready(proc: subprocess.Popen, port: int, name: str) -> None:
    deadline = time.time() + 15.0
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(f"{name} exited early (rc={proc.returncode}):\n{out}")
        try:
            _fetch(f"http://127.0.0.1:{port}/")
            return
        except OSError:
            time.sleep(0.05)
    out = proc.stdout.read() if (proc.poll() is not None and proc.stdout) else ""
    raise RuntimeError(f"{name} did not become ready on port {port}\n{out}")


def _stop_proc(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)


def _discover_wikis(tmp: Path) -> list[tuple[str, dict[str, str], Path, Path]]:
    """Return (label, env_overrides, wiki_dir, raw_sources_dir) for every
    fixture wiki under tests/fixtures/, a synthetic notices/intro-off wiki,
    and this repository's own wiki."""
    wikis: list[tuple[str, dict[str, str], Path, Path]] = []

    for entry in sorted(FIXTURES_DIR.iterdir()):
        if not entry.is_dir() or entry.name in NON_WIKI_FIXTURES:
            continue
        wiki_dir = entry / "wiki" if (entry / "wiki").is_dir() else entry
        cfg = entry / "wiki.yaml" if (entry / "wiki.yaml").is_file() else entry / "_system" / "wiki.yaml"
        mm = entry / "_system" / "metamodel" if (entry / "_system" / "metamodel").is_dir() else REPO / "_system" / "metamodel"
        sources = entry / "raw" / "sources"
        docs = entry / "docs"
        env = {
            "REPO_DIR": str(entry),
            "WIKI_DIR": str(wiki_dir),
            "WIKI_CONFIG": str(cfg),
            "RAW_SOURCES_DIR": str(sources),
            "DOCS_DIR": str(docs),
            "METAMODEL_DIR": str(mm),
            "ANCHORS_DIR": str(mm.parent / "anchors"),
        }
        wikis.append((f"fixture:{entry.name}", env, wiki_dir, sources))

    # Synthetic edge-case wiki: unnamed vault, version mismatch notice,
    # unsupported metamodel version notice, intro: off (404 on /brand/intro.html).
    edge = tmp / "edge-wiki"
    (edge / "wiki").mkdir(parents=True)
    (edge / "raw" / "sources").mkdir(parents=True)
    shutil.copytree(REPO / "_system" / "metamodel", edge / "_system" / "metamodel")
    shutil.copytree(REPO / "_system" / "anchors", edge / "_system" / "anchors")
    (edge / "docs" / "guide").mkdir(parents=True)
    (edge / "docs" / "guide" / "mark.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"></svg>', encoding="utf-8")
    (edge / "docs" / "guide" / "about.md").write_text('# About Edge\n\n<div style="color:red;background:url(https://evil.example/x)">Hello</div>\n\n![Mark](mark.svg)\n', encoding="utf-8")
    (edge / "_system" / "metamodel" / "metamodel-version.md").write_text("---\nversion: 0.2\n---\n", encoding="utf-8")
    (edge / "_system" / "wiki.yaml").write_text('dashboard_version: "0.1.0"\nintro: off\nabout: docs/guide/about.md\n', encoding="utf-8")
    wikis.append((
        "synthetic:notices",
        {"REPO_DIR": str(edge)},
        edge / "wiki",
        edge / "raw" / "sources",
    ))

    # This repository's own wiki (uses REPO_DIR only, exercising full layout + CON-005 preflight).
    wikis.append((
        "repo:self",
        {"REPO_DIR": str(REPO)},
        REPO / "wiki",
        REPO / "raw" / "sources",
    ))
    return wikis


def _discover_routes(wiki_dir: Path, sources_dir: Path) -> list[str]:
    routes = list(FIXED_ROUTES)
    if wiki_dir.is_dir():
        for folder in sorted(wiki_dir.iterdir()):
            if not folder.is_dir():
                continue
            for md in sorted(folder.glob("*.md")):
                if folder.name == "functional-requirements":
                    routes.append(f"/functional-requirements/{md.stem}")
                else:
                    routes.append(f"/page/{folder.name}/{md.stem}")
    if sources_dir.is_dir():
        for md in sorted(sources_dir.glob("*.md")):
            routes.append(f"/source/{md.stem}")
    # Preserve order while deduplicating.
    return list(dict.fromkeys(routes))


def _compare_route(label: str, route: str, py_port: int, go_port: int) -> str | None:
    py_status, py_hdrs, py_body = _fetch(f"http://127.0.0.1:{py_port}{route}")
    go_status, go_hdrs, go_body = _fetch(f"http://127.0.0.1:{go_port}{route}")

    if py_status != go_status:
        return f"[{label}] {route}: status python={py_status}, go={go_status}"

    py_ct = py_hdrs.get("content-type", "").split(";", 1)[0].strip().lower()
    go_ct = go_hdrs.get("content-type", "").split(";", 1)[0].strip().lower()
    if py_ct != go_ct:
        return f"[{label}] {route}: content-type python={py_ct!r}, go={go_ct!r}"

    if py_ct == "text/html":
        # Verify CSP and framing policy match once per-request nonces are normalised.
        py_csp = _CSP_NONCE_RE.sub("'nonce-<NONCE>'", py_hdrs.get("content-security-policy", ""))
        go_csp = _CSP_NONCE_RE.sub("'nonce-<NONCE>'", go_hdrs.get("content-security-policy", ""))
        if py_csp != go_csp:
            return f"[{label}] {route}: CSP mismatch\n    python: {py_csp!r}\n    go:     {go_csp!r}"
        py_xfo = py_hdrs.get("x-frame-options", "")
        go_xfo = go_hdrs.get("x-frame-options", "")
        if py_xfo != go_xfo:
            return f"[{label}] {route}: X-Frame-Options mismatch python={py_xfo!r}, go={go_xfo!r}"
        if 300 <= py_status < 400:
            py_loc = py_hdrs.get("location", "")
            go_loc = go_hdrs.get("location", "")
            if py_loc != go_loc:
                return f"[{label}] {route}: Location mismatch python={py_loc!r}, go={go_loc!r}"
            return None
        py_text = py_body.decode("utf-8", errors="replace")
        go_text = go_body.decode("utf-8", errors="replace")
        if 'class="stack-badge"' in py_text:
            if "python-logo.svg" not in py_text or "Built with Python + Flask" not in py_text:
                return f"[{label}] {route}: python response missing Python stack badge"
            if "go-logo.svg" not in go_text or "Built with Go" not in go_text:
                return f"[{label}] {route}: go response missing Go stack badge"
        diff = first_token_diff(
            normalize_html(py_text),
            normalize_html(go_text),
        )
        if diff:
            return f"[{label}] {route}: {diff}"
        return None

    if py_ct == "application/json":
        diff = first_json_diff(json.loads(py_body), json.loads(go_body))
        if diff:
            return f"[{label}] {route}: {diff}"
        return None

    if py_body != go_body:
        return f"[{label}] {route}: binary/text mismatch (python={len(py_body)} bytes, go={len(go_body)} bytes)"
    return None


# The session endpoints and the bodies both dashboards must reject alike: every
# JSON type that is not an object (issue #184). A rejected body changes no
# state, so these requests cannot disturb the route checks.
SESSION_ROUTES = ["/ping", "/leaving", "/settings", "/disconnect-all"]
NOT_JSON_OBJECTS = ['["x"]', "[]", '"x"', '""', "7", "0", "1.5", "true", "false"]


def _post(url: str, body: str) -> tuple[int, str, bytes]:
    req = urllib.request.Request(
        url, data=body.encode("utf-8"), method="POST",
        headers={"Content-Type": "application/json"})
    try:
        with _OPENER.open(req, timeout=5) as resp:
            return resp.status, resp.headers.get("Content-Type", ""), resp.read()
    except urllib.error.HTTPError as err:
        return err.code, err.headers.get("Content-Type", ""), err.read()


def _compare_session_body(label: str, route: str, body: str,
                          py_port: int, go_port: int) -> str | None:
    py_status, py_ct, py_body = _post(f"http://127.0.0.1:{py_port}{route}", body)
    go_status, go_ct, go_body = _post(f"http://127.0.0.1:{go_port}{route}", body)
    where = f"[{label}] POST {route} {body}"
    if (py_status, go_status) != (400, 400):
        return f"{where}: status python={py_status}, go={go_status}, want 400"
    if "application/json" not in py_ct or "application/json" not in go_ct:
        return f"{where}: content-type python={py_ct!r}, go={go_ct!r}"
    diff = first_json_diff(json.loads(py_body), json.loads(go_body))
    return f"{where}: {diff}" if diff else None


def _start_python(port: int, env_overrides: dict[str, str]) -> subprocess.Popen:
    env = {k: v for k, v in os.environ.items() if k not in (
        "REPO_DIR", "WIKI_DIR", "WIKI_CONFIG", "RAW_SOURCES_DIR",
        "DOCS_DIR", "METAMODEL_DIR", "NOTATIONS_DIR", "ANCHORS_DIR",
    )}
    env.update(env_overrides)
    env.update({
        "TZ": "UTC",
        "DASH_PUBLIC_URL": "http://127.0.0.1:8080",
        "DASH_STARTUP_GRACE": "3600",
        "DASH_HEARTBEAT_GRACE": "3600",
        "PYTHONPATH": str(HERE),
    })
    runner = (
        "from werkzeug.serving import make_server; "
        "import app; "
        f"srv = make_server('127.0.0.1', {port}, app.app, threaded=True); "
        "srv.serve_forever()"
    )
    return subprocess.Popen(
        [sys.executable, "-c", runner],
        cwd=str(HERE), env=env, start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def _start_go(binary: Path, port: int, env_overrides: dict[str, str]) -> subprocess.Popen:
    env = {k: v for k, v in os.environ.items() if k not in (
        "REPO_DIR", "WIKI_DIR", "WIKI_CONFIG", "RAW_SOURCES_DIR",
        "DOCS_DIR", "METAMODEL_DIR", "NOTATIONS_DIR", "ANCHORS_DIR",
    )}
    env.update(env_overrides)
    env.update({
        "TZ": "UTC",
        "DASH_PUBLIC_URL": "http://127.0.0.1:8080",
        "DASH_STARTUP_GRACE": "3600",
        "DASH_HEARTBEAT_GRACE": "3600",
        "DASH_HOST": "127.0.0.1",
        "DASH_PORT": str(port),
    })
    return subprocess.Popen(
        [str(binary)],
        cwd=str(HERE), env=env, start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def main() -> int:
    _test_normalizer()

    if not os.environ.get("GO_DASHBOARD_BIN") and not shutil.which("go"):
        print("SKIP: go is not installed and GO_DASHBOARD_BIN is unset")
        return 77

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        binary = _build_go_binary(tmp_path)
        wikis = _discover_wikis(tmp_path)
        assert len(wikis) >= 2, f"expected fixtures + repo wiki, got {[w[0] for w in wikis]}"

        checked = 0
        unported = 0
        failures: list[str] = []

        for label, env_overrides, wiki_dir, sources_dir in wikis:
            routes = _discover_routes(wiki_dir, sources_dir)
            py_port = _free_port()
            go_port = _free_port()
            py_proc = _start_python(py_port, env_overrides)
            go_proc = _start_go(binary, go_port, env_overrides)
            try:
                _wait_ready(py_proc, py_port, f"python({label})")
                _wait_ready(go_proc, go_port, f"go({label})")
                for route in routes:
                    if is_unported(route) is not None:
                        unported += 1
                        continue
                    checked += 1
                    err = _compare_route(label, route, py_port, go_port)
                    if err:
                        failures.append(err)
                for route in SESSION_ROUTES:
                    for body in NOT_JSON_OBJECTS:
                        checked += 1
                        err = _compare_session_body(label, route, body, py_port, go_port)
                        if err:
                            failures.append(err)
                if label == "fixture:search-wiki" and shutil.which("node"):
                    se_env = dict(os.environ)
                    se_env["DASH_SEARCH_URL"] = f"http://127.0.0.1:{go_port}"
                    se = subprocess.run(
                        [sys.executable, str(HERE / "tests" / "test_search_examples.py")],
                        cwd=str(HERE), env=se_env, capture_output=True, text=True,
                    )
                    if se.returncode != 0:
                        failures.append(f"[go:{label}] test_search_examples.py failed:\n{se.stdout}{se.stderr}")
            finally:
                _stop_proc(py_proc)
                _stop_proc(go_proc)

        if failures:
            for f in failures:
                print(f"✗ {f}", file=sys.stderr)
            print(
                f"FAIL: {len(failures)} parity failure(s) out of {checked} checked routes "
                f"across {len(wikis)} wikis ({unported} unported).",
                file=sys.stderr,
            )
            return 1

        print(
            f"OK: parity ({checked} route checks passed across {len(wikis)} wikis; "
            f"{unported} unported route checks remaining across {len(UNPORTED_EXACT)} exact + "
            f"{len(UNPORTED_PREFIXES)} prefix entries)."
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
