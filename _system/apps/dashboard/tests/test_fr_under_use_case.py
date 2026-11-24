"""Plain-assert test: Agile features and stories may refine a use case
(rel-parent, DR-038 amendment) — no pytest dependency.

    .venv/bin/python tests/test_fr_under_use_case.py

Copies the neutral fixture vault to a temp dir and adds one use case (the
use-case notation, level sea) with a goal, one story that names it as parent
and carries no goal of its own, and one use case without children. Use cases
live in wiki/functional-requirements/ like every other requirement. The shared fixture stays untouched, so the
counts other suites assert on do not move.
"""
import os
import shutil
import sys
import tempfile
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
_VAULT = Path(tempfile.mkdtemp(prefix="fr-uc-")) / "wiki"
shutil.copytree(_FIXTURE, _VAULT)
_FR = _VAULT / "functional-requirements"
(_FR / "UC-001-borrow-a-book.md").write_text("""---
id: UC-001
type: functional-requirement
title: Borrow a Book
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [functional-requirement]
notation: use-case
level: sea
primary-actor: "[[STK-001-librarian]]"
scope-building-block:
priority: Must
goal: ["[[GOAL-002-faster-lending]]"]
---

# Borrow a Book
""")
(_FR / "UC-002-renew-a-loan.md").write_text("""---
id: UC-002
type: functional-requirement
title: Renew a Loan
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [functional-requirement]
notation: use-case
level: sea
priority: Could
goal: []
---

# Renew a Loan
""")
(_FR / "FR-007-reserve-a-book.md").write_text("""---
id: FR-007
type: functional-requirement
title: Reserve a Book
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [functional-requirement]
notation: agile
level: story
parent: ["[[UC-001-borrow-a-book]]"]
priority: Could
release: unscheduled
lane: display
order: 1
goal: []
---

# Reserve a Book
""")

os.environ["WIKI_DIR"] = str(_VAULT)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402
import project.requirements  # noqa: E402


def test_use_case_is_a_hierarchy_root():
    bl = project.requirements.build_fr_hierarchy()
    # the story under a use case is not an orphan
    assert bl["orphans"] == [], bl["orphans"]
    # only use cases with children appear as roots
    assert [u["id"] for u in bl["use_cases"]] == ["UC-001"], bl["use_cases"]
    uc = bl["use_cases"][0]
    assert [s["id"] for s in uc["direct_stories"]] == ["FR-007"], uc
    assert uc["n_stories"] == 1 and uc["n_features"] == 0, uc
    # totals count what the epics and use cases render
    assert bl["total_stories"] == sum(e["n_stories"] for e in bl["epics"] + bl["use_cases"])
    node, kind = project.requirements._fr_hierarchy_node(bl, "FR-007-reserve-a-book")
    assert kind == "story" and node["id"] == "FR-007", (node, kind)
    node, kind = project.requirements._fr_hierarchy_node(bl, "UC-001-borrow-a-book")
    assert kind == "sea" and node is uc, (node, kind)
    # the use case without children is listed outside the story map
    other = {o["id"]: o for o in bl["other_notations"]}
    assert set(other) == {"UC-002"}, other
    assert (other["UC-002"]["notation"], other["UC-002"]["level"]) == ("use-case", "sea")
    print("OK use case as root:", uc["id"], "->", [s["id"] for s in uc["direct_stories"]])


def test_ancestors_end_at_the_use_case():
    chain = project.requirements._fr_ancestors("FR-007-reserve-a-book")
    assert [a["id"] for a in chain] == ["UC-001"], chain
    assert chain[0]["url"] == "/functional-requirements/UC-001-borrow-a-book", chain
    # an FR chain still links to FR pages
    assert all(a["url"].startswith("/functional-requirements/")
               for a in project.requirements._fr_ancestors("FR-003-scan-a-book"))
    print("OK ancestors:", [a["id"] for a in chain])


def test_story_inherits_the_use_case_goals():
    g = app.load_goals()
    assert "FR-007" in {p.id for p in g["coverage"]["GOAL-002"]}, g["coverage"]["GOAL-002"]
    assert "FR-007" not in {p.id for p in g["enablers"]}
    print("OK goal inherited from UC-001")


def test_use_case_page_shows_refined_by():
    client = app.app.test_client()
    r = client.get("/functional-requirements/UC-001-borrow-a-book")
    assert r.status_code == 200
    body = r.get_data(as_text=True)
    head = body[body.index("Refined by"):]
    assert "FR-007" in head and "Direct on use case" in head, head[:600]
    assert "use-case · Sea" in body
    body = client.get("/functional-requirements/UC-002-renew-a-loan").get_data(as_text=True)
    assert "Refined by" not in body
    print("OK refined by: FR-007")


def test_use_case_counts_as_a_column_and_serves_its_goal():
    g = app.load_goals()
    assert [u.id for u in g["ucs"]] == ["UC-001", "UC-002"], g["ucs"]
    assert "UC-001" in {p.id for p in g["coverage"]["GOAL-002"]}
    # a use case with goal: [] is untraced, never an enabler
    assert "UC-002" not in {p.id for p in g["enablers"] + g["untraced"]}
    body = app.app.test_client().get("/goals").get_data(as_text=True)
    assert 'href="/functional-requirements/UC-001-borrow-a-book"' in body
    print("OK use case column")


def test_pages_render():
    app.app.config["TESTING"] = True
    client = app.app.test_client()
    body = client.get("/req42/functional-requirements").get_data(as_text=True)
    assert "UC-001" in body and "1 story" in body, body[:400]
    assert "Use cases refined by features and stories" in body
    assert "Outside the Agile hierarchy" in body and "UC-002" in body
    assert "Orphaned requirements" not in body
    fr = client.get("/functional-requirements/FR-007-reserve-a-book")
    assert fr.status_code == 200
    assert "UC-001" in fr.get_data(as_text=True)
    print("OK pages render")


if __name__ == "__main__":
    test_use_case_is_a_hierarchy_root()
    test_ancestors_end_at_the_use_case()
    test_story_inherits_the_use_case_goals()
    test_use_case_page_shows_refined_by()
    test_use_case_counts_as_a_column_and_serves_its_goal()
    test_pages_render()
    shutil.rmtree(_VAULT.parent, ignore_errors=True)
