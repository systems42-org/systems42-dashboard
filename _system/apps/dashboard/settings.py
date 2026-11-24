"""The settings of one dashboard: `_system/wiki.yaml`, the brand and the view.

Owns `wiki_config()` and its warnings, the about page and the files under
`docs/` (DOCS_DIR), the brand folders and their files, the path of `help.md`,
and what the view hides (`dashboard_config()`, `is_hidden()`, the visible
areas and sections).
A problem in wiki.yaml is logged once per process on the logger
`systems42.settings`.

May import `wiki`, `catalog`, `metamodel`, `inputs` and `session`. No Flask
import and no import of `app` here (tests/test_module_imports.py).
"""
from __future__ import annotations

import logging
import os
import zlib
from pathlib import Path

import catalog  # the section catalog (DR-033)
import session  # presence, the Keyholder role, the view and the lifecycle
import wiki  # paths, pages, parse cache and loaders

log = logging.getLogger("systems42.settings")


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


DEFAULT_SYSTEM_NAME = "Requirements Wiki"

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
        log.warning(message)


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


def _brand_checksum(path: Path | None) -> str:
    try:
        return f"{zlib.crc32(path.read_bytes()):08x}"
    except (OSError, AttributeError):
        return ""


HELP_PATH = Path(__file__).resolve().parent / "help.md"
