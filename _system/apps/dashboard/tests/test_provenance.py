"""Provenance chips and the /source view — every page's `sources:` wikilinks
resolve to a raw/sources/ record; unsourced pages surface that honestly too.
No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_provenance.py
"""
import os
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
_src = _tmp / "sources"
_src.mkdir()
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_src)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))

import app  # noqa: E402
import wiki  # noqa: E402
import project.common  # noqa: E402

(_src / "SRC-001-brief.md").write_text("""---
id: SRC-001
type: source
title: Project brief
status: ingested
created: 2026-09-06
updated: 2026-09-06
tags: [source]
source-type: document
origin: raw/ingested/brief.md
captured: 2026-09-06
sha256: n/a
ingested-pages: ["[[DT-001-tour]]"]
---

# Project brief

The one-page brief the sponsor sent.
""", encoding="utf-8")
(_wiki / "domain-terms" / "DT-001-tour.md").write_text("""---
id: DT-001
type: domain-term
title: Tour
status: draft
created: 2026-09-06
updated: 2026-09-06
sources: ["[[raw/sources/SRC-001-brief]]"]
related: []
tags: [domain-term]
---

# Tour

**Definition.** A travelling exhibition.
""", encoding="utf-8")
(_wiki / "domain-terms" / "DT-002-show.md").write_text("""---
id: DT-002
type: domain-term
title: Show
status: draft
created: 2026-09-06
updated: 2026-09-06
sources: []
related: []
tags: [domain-term]
---

# Show

**Definition.** One stop of a tour.
""", encoding="utf-8")
# A bare string (not a YAML list) for `sources:` — malformed frontmatter that
# still names exactly one real source; provenance() must treat it as a
# one-element list rather than iterating its characters.
(_wiki / "domain-terms" / "DT-003-single.md").write_text("""---
id: DT-003
type: domain-term
title: Single
status: draft
created: 2026-09-06
updated: 2026-09-06
sources: "[[raw/sources/SRC-001-brief]]"
related: []
tags: [domain-term]
---

# Single

**Definition.** A page with a bare-string `sources:` field.
""", encoding="utf-8")
# A hostile provenance record: source-type/origin carry HTML that must come
# out escaped, not live, on the /source/<stem> facts table.
(_src / "SRC-002-hostile.md").write_text("""---
id: SRC-002
type: source
title: Hostile record
status: ingested
created: 2026-09-06
updated: 2026-09-06
tags: [source]
source-type: "<img src=x onerror=alert(1)>"
origin: "raw/<b>x</b>.md"
captured: 2026-09-06
sha256: n/a
ingested-pages: []
---

# Hostile record

Frontmatter with HTML in it.
""", encoding="utf-8")


def test_provenance_resolves_source_records():
    wiki._PARSE_CACHE.clear()
    page = wiki._parse(_wiki / "domain-terms" / "DT-001-tour.md", "domain-terms")
    rows = project.common.provenance(page)
    assert rows == [{"id": "SRC-001", "title": "Project brief", "stem": "SRC-001-brief", "type": "document",
                     "origin": "raw/ingested/brief.md", "captured": "2026-09-06", "url": "/source/SRC-001-brief"}], rows


def test_chips_on_detail_pages():
    wiki._PARSE_CACHE.clear()
    c = app.app.test_client()
    sourced = c.get("/page/domain-terms/DT-001-tour").get_data(as_text=True)
    assert 'class="chip chip-src"' in sourced and "SRC-001" in sourced
    unsourced = c.get("/page/domain-terms/DT-002-show").get_data(as_text=True)
    assert "chip-unsourced" in unsourced


def test_source_page_renders_and_links_back():
    wiki._PARSE_CACHE.clear()
    body = app.app.test_client().get("/source/SRC-001-brief").get_data(as_text=True)
    assert "Project brief" in body and "raw/ingested/brief.md" in body
    assert "/page/domain-terms/DT-001-tour" in body        # ingested-pages resolved
    assert app.app.test_client().get("/source/SRC-999-nope").status_code == 404


def test_source_page_escapes_hostile_frontmatter():
    wiki._PARSE_CACHE.clear()
    resp = app.app.test_client().get("/source/SRC-002-hostile")
    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "&lt;img" in body
    assert "<img src=x" not in body


def test_unresolved_and_empty_source_refs():
    """A `sources:` entry with no record behind it must still produce a chip
    (dashed, url=None) rather than vanish; a None/blank entry must produce
    nothing at all rather than an empty chip."""
    wiki._PARSE_CACHE.clear()
    page = wiki._parse(_wiki / "domain-terms" / "DT-001-tour.md", "domain-terms")
    page.meta["sources"] = ["[[raw/sources/SRC-404-ghost]]", None, "", "   "]
    rows = project.common.provenance(page)
    assert len(rows) == 1, rows
    assert rows[0]["id"] == "SRC-404-ghost" and rows[0]["url"] is None, rows


def test_provenance_accepts_bare_string_sources():
    wiki._PARSE_CACHE.clear()
    page = wiki._parse(_wiki / "domain-terms" / "DT-003-single.md", "domain-terms")
    rows = project.common.provenance(page)
    assert len(rows) == 1, rows
    assert rows[0]["url"] == "/source/SRC-001-brief", rows


if __name__ == "__main__":
    test_provenance_resolves_source_records()
    test_chips_on_detail_pages()
    test_source_page_renders_and_links_back()
    test_source_page_escapes_hostile_frontmatter()
    test_provenance_accepts_bare_string_sources()
    test_unresolved_and_empty_source_refs()
    print("OK: provenance")
