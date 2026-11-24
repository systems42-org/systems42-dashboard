"""Created date, updated date and tags in the head of a requirement page
(issue #183, FR-034).

The requirement view built its own record for fr.html and left the three
values out, so they showed on every page type but this one. Both views now
take them from `web.common.page_head()` and render them with the `page_meta` macro.

Run from the dashboard dir:
    .venv/bin/python tests/test_fr_page_head.py
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues", "building-blocks", "decisions",
    "solution-strategy", "crosscutting-concepts", "runtime-scenarios", "deployment-nodes",
]

_system = Path(__file__).resolve().parents[3]
_repo = Path(tempfile.mkdtemp()) / "repo"
_wiki = _repo / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
(_repo / "docs").mkdir()
_config = _repo / "_system" / "wiki.yaml"
_config.parent.mkdir(parents=True, exist_ok=True)
_config.write_text("system_name: Page head\n", encoding="utf-8")
shutil.copytree(_system / "metamodel", _repo / "_system" / "metamodel")
shutil.copytree(_system / "anchors", _repo / "_system" / "anchors")


def _page(folder, stem, frontmatter, body="# T\n\nText.\n"):
    (_wiki / folder / f"{stem}.md").write_text(f"---\n{frontmatter}\n---\n{body}", encoding="utf-8")


HOSTILE = '<script>alert(1)</script>'
HOSTILE_ATTR = '"><img src=x onerror=alert(2)>'

_page("functional-requirements", "FR-001-agile",
      "id: FR-001\ntitle: Agile story\nstatus: draft\nnotation: agile\nlevel: story\n"
      "created: 2026-03-04\nupdated: 2026-05-06\ntags: [zebra-tag, second-tag]")
_page("functional-requirements", "UC-001-use-case",
      "id: UC-001\ntitle: A use case\nstatus: draft\nnotation: use-case\nlevel: user-goal\n"
      "created: 2026-07-08\nupdated: 2026-09-10\ntags: [uc-tag]")
_page("functional-requirements", "FR-002-bare",
      "id: FR-002\ntitle: Bare\nstatus: draft\nnotation: agile\nlevel: story")
_page("functional-requirements", "FR-003-blank",
      "id: FR-003\ntitle: Blank\nstatus: draft\nnotation: agile\nlevel: story\ncreated:\nupdated:\ntags:")
_page("functional-requirements", "FR-004-hostile",
      "id: FR-004\ntitle: Hostile\nstatus: draft\nnotation: agile\nlevel: story\n"
      f"created: 2026-01-02\ntags:\n  - '{HOSTILE}'\n  - '{HOSTILE_ATTR}'")
# one tag written as a scalar, an impossible date (arrives as written, PR 186)
_page("functional-requirements", "FR-005-odd",
      "id: FR-005\ntitle: Odd\nstatus: draft\nnotation: agile\nlevel: story\n"
      "created: 2026-13-01\ntags: lonely")
# only an updated date
_page("functional-requirements", "FR-006-updated-only",
      "id: FR-006\ntitle: Updated only\nstatus: draft\nnotation: agile\nlevel: story\nupdated: 2026-11-12")
# the same values on a generic page, to compare the markup
_page("constraints", "CON-001-generic",
      "id: CON-001\ntitle: Generic\nstatus: draft\n"
      f"created: 2026-03-04\nupdated: 2026-05-06\ntags:\n  - zebra-tag\n  - '{HOSTILE}'\n  - '{HOSTILE_ATTR}'")
_page("functional-requirements", "FR-007-like-generic",
      "id: FR-007\ntitle: Like generic\nstatus: draft\nnotation: agile\nlevel: story\n"
      f"created: 2026-03-04\nupdated: 2026-05-06\ntags:\n  - zebra-tag\n  - '{HOSTILE}'\n  - '{HOSTILE_ATTR}'")
_page("constraints", "CON-002-bare", "id: CON-002\ntitle: Bare\nstatus: draft")

os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_config)
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_repo / "docs")
os.environ["METAMODEL_DIR"] = str(_repo / "_system" / "metamodel")
for _name in ("NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_name, None)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import web.common  # noqa: E402
import wiki  # noqa: E402

_META = re.compile(r'<p class="detail-meta">.*?</p>', re.S)


def _get(path):
    resp = app.app.test_client().get(path, follow_redirects=True)
    assert resp.status_code == 200, (path, resp.status_code)
    return resp.get_data(as_text=True)


def _meta(html):
    """The page-head line, whitespace between tags removed."""
    found = _META.findall(html)
    assert len(found) <= 1, found
    return re.sub(r">\s+<", "><", found[0]) if found else None


def test_agile_requirement_shows_dates_and_tags():
    html = _get("/functional-requirements/FR-001-agile")
    assert _meta(html) == ('<p class="detail-meta"><span>created 2026-03-04</span>'
                           '<span>· updated 2026-05-06</span>'
                           '<span>· <span class="tag-chip">zebra-tag</span>'
                           '<span class="tag-chip">second-tag</span></span></p>'), _meta(html)
    # the generic address of a requirement leads to the same page
    assert _meta(_get("/page/functional-requirements/FR-001-agile")) == _meta(html)


def test_use_case_shows_dates_and_tags():
    html = _get("/functional-requirements/UC-001-use-case")
    assert "use-case" in html
    assert _meta(html) == ('<p class="detail-meta"><span>created 2026-07-08</span>'
                           '<span>· updated 2026-09-10</span>'
                           '<span>· <span class="tag-chip">uc-tag</span></span></p>'), _meta(html)


def test_missing_values_show_nothing():
    for stem in ("FR-002-bare", "FR-003-blank"):
        html = _get(f"/functional-requirements/{stem}")
        assert "detail-meta" not in html, stem
        assert "tag-chip" not in html, stem
        assert "created" not in html and "updated" not in html, stem
        assert "None" not in html, stem
    # a generic page with none of the three has no empty line either
    assert "detail-meta" not in _get("/page/constraints/CON-002-bare")


def test_one_missing_value_leaves_the_others():
    html = _get("/functional-requirements/FR-006-updated-only")
    assert _meta(html) == '<p class="detail-meta"><span>· updated 2026-11-12</span></p>', _meta(html)
    html = _get("/functional-requirements/FR-005-odd")
    assert _meta(html) == ('<p class="detail-meta"><span>created 2026-13-01</span>'
                           '<span>· <span class="tag-chip">lonely</span></span></p>'), _meta(html)


def test_hostile_tags_come_out_escaped():
    html = _get("/functional-requirements/FR-004-hostile")
    assert HOSTILE not in html
    assert "<img src=x" not in html
    meta = _meta(html)
    assert '<span class="tag-chip">&lt;script&gt;alert(1)&lt;/script&gt;</span>' in meta, meta
    assert '<span class="tag-chip">&#34;&gt;&lt;img src=x onerror=alert(2)&gt;</span>' in meta, meta
    assert "<script>alert" not in meta and "<img" not in meta


def test_markup_matches_the_generic_page():
    generic = _meta(_get("/page/constraints/CON-001-generic"))
    requirement = _meta(_get("/functional-requirements/FR-007-like-generic"))
    assert generic and generic == requirement, (generic, requirement)


def test_one_builder_for_both_views():
    page = next(p for p in wiki.load_folder("functional-requirements") if p.stem == "FR-005-odd")
    assert web.common.page_head(page) == {"created": "2026-13-01", "updated": "", "tags": ["lonely"]}
    templates = Path(app.app.root_path) / "templates"
    for name in ("detail.html", "fr.html"):
        text = (templates / name).read_text(encoding="utf-8")
        assert "page_meta(created, updated, tags)" in text, name
        assert "detail-meta" not in text, name


if __name__ == "__main__":
    for _name, _fn in sorted(globals().items()):
        if _name.startswith("test_") and callable(_fn):
            _fn()
            print(f"ok {_name}")
    print("✓ requirement page head")
