"""The wiki as files: paths, pages, the parse cache and the loaders.

Owns the repository paths (REPO_DIR, WIKI_DIR, SOURCES_DIR, CONFIG_PATH), the
Page class, parsing and containment, the parse cache, the folder loaders, the
reading of `_system/wiki.yaml` and the per-request memo decorator. Other
modules read these as `wiki.NAME` at call time, because tests reassign them.

May import `inputs`, `metamodel` and `catalog`. No Flask import and no import
of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import functools
import os
import re
import threading
from dataclasses import dataclass, field
from pathlib import Path

import yaml

import catalog  # the section catalog (DR-033)
import inputs  # readers for files the dashboard does not write

# Root of the wiki repository (FR-042, CON-005). The launcher mounts it
# read-only at /repo and the image sets REPO_DIR; a local run takes the
# repository this file sits in. Every folder below is found from here by
# convention. A folder's own variable (WIKI_DIR, DOCS_DIR, ...) still wins,
# which is how the tests point the app at their fixtures.
_env_repo = os.environ.get("REPO_DIR")
REPO_DIR = Path(_env_repo) if _env_repo else Path(__file__).resolve().parents[3]


# The cache of the current request, or None outside one. The web application
# registers the provider (use_request_cache), so this module needs no Flask.
_request_cache = lambda: None


def use_request_cache(provider) -> None:
    """Register the function that returns the current request's cache dict,
    or None outside a request."""
    global _request_cache
    _request_cache = provider


def _request_cached(func):
    """Memoize a builder for the current request (keyed by name + args). The
    cached objects are treated as read-only by every caller, so sharing the same
    reference across calls within a request is safe."""
    @functools.wraps(func)
    def wrapper(*args):
        cache = _request_cache()
        if cache is None:
            return func(*args)
        key = (func.__name__, args)
        if key not in cache:
            cache[key] = func(*args)
        return cache[key]
    return wrapper


# Root of the wiki layer, read-only.
_env_wiki = os.environ.get("WIKI_DIR")
WIKI_DIR = Path(_env_wiki) if _env_wiki else REPO_DIR / "wiki"

# Provenance records (raw/sources/, Source type, DR-006). Only ever read.
_env_src = os.environ.get("RAW_SOURCES_DIR")
SOURCES_DIR = Path(_env_src) if _env_src else REPO_DIR / "raw" / "sources"

# Project identity. Everything the original demo vault hardcoded (page title,
# footer, hero, goal-tree root, context-diagram centre) reads from here so a
# fresh vault can be renamed in one place. Read per call, never cached: during
# a workshop the group fills this in live and just refreshes the page.
_env_cfg = os.environ.get("WIKI_CONFIG")
CONFIG_PATH = Path(_env_cfg) if _env_cfg else REPO_DIR / "_system" / "wiki.yaml"


def _config_data() -> dict:
    """wiki.yaml as a mapping. {} when the file is missing, is not UTF-8 or
    is not a YAML mapping: `inputs` logs the last two."""
    try:
        text = inputs.read_text(CONFIG_PATH)
    except OSError:
        return {}
    data = inputs.load_yaml(CONFIG_PATH, text) if text is not None else None
    return data if isinstance(data, dict) else {}


def _inside(root: Path, path: Path) -> bool:
    return path == root or root in path.parents


# [[target]] | [[target|alias]] | [[target#heading]] | [[path/target|alias]]
WIKILINK_RE = re.compile(r"\[\[([^\]\|#]+)(?:#[^\]\|]+)?(?:\|([^\]]+))?\]\]")
FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)


@dataclass
class Page:
    stem: str                       # filename without .md, e.g. DT-006-kind
    meta: dict                      # parsed frontmatter
    body: str                       # markdown body (frontmatter stripped)
    folder: str                     # owning wiki subfolder, e.g. domain-terms
    # Last-modified time of the source file. Last field, and defaulted, so every
    # existing positional/keyword construction keeps working. Feeds the home
    # page's "Latest changes" tile — see recent_changes().
    mtime: float = 0.0
    # link_targets() memo. A parsed Page is shared through _PARSE_CACHE and
    # replaced, never edited, when its file changes, so the memo cannot go stale.
    _targets: frozenset[str] | None = field(default=None, init=False, repr=False, compare=False)

    @property
    def id(self) -> str:
        # a blank `id:` (a draft still being written) falls back to the file
        # name, so sorting and linking never meet None
        return str(self.meta.get("id") or self.stem)

    @property
    def title(self) -> str:
        # a blank `title:` (YAML null) falls back to the file name like a
        # missing one; a number or date is shown as written
        t = self.meta.get("title")
        return str(t) if t not in (None, "") else self.stem

    @property
    def status(self) -> str:
        return str(self.meta.get("status") or "")

    @property
    def aliases(self) -> list[str]:
        return [str(x) for x in self.as_list("aliases") if x]

    def as_list(self, field: str) -> list:
        """A list-valued frontmatter field as a list, whatever was written:
        blank → [], a single value → [value] (`tags: draft` is one tag, and
        `parent: 7` must not crash an iteration)."""
        v = self.meta.get(field)
        if v is None or v == "":
            return []
        return v if isinstance(v, list) else [v]

    def link_targets(self) -> frozenset[str]:
        """Distinct wiki pages this page points to (frontmatter + body),
        excluding self-references and raw/ source provenance links. Computed
        once per Page: the relations panel asks every page in the wiki."""
        if self._targets is not None:
            return self._targets
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
        self._targets = frozenset(targets)
        return self._targets


# --- caching ----------------------------------------------------------------
#
# The wiki is parsed live on every request and was, before caching, re-read and
# re-parsed dozens of times per page (every `render_markdown` rebuilt the whole
# link index from disk). Two complementary layers fix that without ever serving
# stale content:
#
#   Tier 1  _parse() is memoized by (path, mtime_ns, size). A file is re-read only
#           when it changes on disk, so editing a page and refreshing the browser still
#           shows the new text — but repeated reads (within a request and across
#           requests) collapse to a dict lookup. The cache lives for the worker's
#           lifetime; each gunicorn worker warms its own.
#
#   Tier 2  the aggregate builders (load_folder / load_all_pages / title_index /
#           link_index / load_decisions) are memoized for the duration of ONE request
#           via flask.g, so the tree is walked once per request instead of once
#           per markdown block rendered. Outside a request context they run
#           uncached (keeps build_* helpers usable standalone, e.g. for ISS-010).

# (path -> ((mtime_ns, size), parsed Page or None)), like metamodel._CACHE. The
# size catches a same-mtime rewrite whose length changed. Folder is
# deterministic from the path (always path.parent.name at every call site), so
# the path alone is the key.
_PARSE_CACHE: dict[Path, tuple[tuple[int, int], "Page | None"]] = {}
# gunicorn serves requests on several threads (Dockerfile, `--threads 4`). The
# lock covers each read, write and sweep of _PARSE_CACHE. Parsing runs outside
# it: two threads parsing the same file waste a parse, nothing worse.
_PARSE_LOCK = threading.Lock()


def _forget(path: Path) -> None:
    """Drop a file's cache entry: it is gone, unreadable or no longer served."""
    with _PARSE_LOCK:
        _PARSE_CACHE.pop(path, None)


def _forget_missing(folder: Path, present: list[Path]) -> None:
    """Drop the entries of files in `folder` that are no longer listed there.
    A deleted page is never globbed again, so _parse() never sees it."""
    keep = set(present)
    with _PARSE_LOCK:
        for path in [p for p in _PARSE_CACHE if p.parent == folder and p not in keep]:
            del _PARSE_CACHE[path]


def _resolves_inside(root: Path, path: Path) -> bool:
    """True when `path`, every symlink on the way resolved, is `root` or below
    it. A symlink in the wiki that points elsewhere in the wiki is fine; one
    that leads out of it (a committed `x.md -> /etc/…`, a linked folder) is
    not read: the dashboard serves the wiki, not what a link names."""
    try:
        return _inside(root.resolve(), path.resolve(strict=True))
    except (OSError, RuntimeError):            # missing, or a symlink loop
        return False


def _page_root(path: Path) -> Path:
    """The folder a page must stay inside: raw/sources/ for a provenance
    record, the wiki for everything else."""
    return SOURCES_DIR if _inside(SOURCES_DIR.absolute(), path.absolute()) else WIKI_DIR


def _parse(path: Path, folder: str) -> Page | None:
    # checked before the cache: a symlink retargeted out of the wiki must not
    # keep serving the page it pointed to before
    if not _resolves_inside(_page_root(path), path):
        _forget(path)
        return None
    try:
        st = path.stat()
    except OSError:
        _forget(path)
        return None
    stamp = (st.st_mtime_ns, st.st_size)
    with _PARSE_LOCK:
        cached = _PARSE_CACHE.get(path)
    if cached is not None and cached[0] == stamp:
        return cached[1]
    # One broken file must never take the whole dashboard down: every page
    # render walks the full vault (title/link indexes), so an exception here
    # is a 500 everywhere. Bytes that are not UTF-8 show as U+FFFD, and a
    # date that is none stays text: `inputs` logs both. A file that vanished
    # between stat and read is simply skipped (not cached).
    try:
        text = inputs.read_text(path, replace=True)
    except OSError:
        _forget(path)
        return None
    m = FRONTMATTER_RE.match(text)
    if not m:
        page = None
    else:
        meta = inputs.load_yaml(path, m.group(1))
        if not isinstance(meta, dict):
            meta = {}                         # `--- just a string ---` or a list: no fields
        page = Page(stem=path.stem, meta=meta, body=m.group(2), folder=folder,
                    mtime=st.st_mtime)
    with _PARSE_LOCK:
        _PARSE_CACHE[path] = (stamp, page)
    return page


@_request_cached
def load_folder(folder: str) -> list[Page]:
    d = WIKI_DIR / folder
    paths = sorted(d.glob("*.md")) if d.is_dir() and _resolves_inside(WIKI_DIR, d) else []
    _forget_missing(d, paths)
    pages = [_parse(p, folder) for p in paths]
    return [p for p in pages if p is not None]


def load_type(type_name: str) -> list[Page]:
    """The pages of one type, from the folder the repository's metamodel
    declares for it (CON-006)."""
    folder = catalog.folder(type_name)
    return load_folder(folder) if folder else []


def _is(folder: str, *type_names: str) -> bool:
    """Whether `wiki/<folder>` holds the pages of one of the named types."""
    return catalog.type_of(folder) in type_names


@_request_cached
def load_sources() -> list[Page]:
    """Provenance records from raw/sources/ — counted on the home page's status
    strip so the room can see how much material the wiki actually rests on.
    Not a wiki folder: it lives outside WIKI_DIR and is never rendered."""
    paths = sorted(SOURCES_DIR.glob("*.md")) if SOURCES_DIR.is_dir() else []
    _forget_missing(SOURCES_DIR, paths)
    pages = [_parse(p, "sources") for p in paths]
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
