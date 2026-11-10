"""Plain-assert test: features and stories may refine a use case (rel-parent,
DR-011) — no pytest dependency.

    .venv/bin/python tests/test_fr_under_use_case.py

Copies the neutral fixture vault to a temp dir and adds one use case with a
goal, one story that names it as parent and carries no goal of its own, and
one use case without children. The shared fixture stays untouched, so the
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
(_VAULT / "use-cases").mkdir()
(_VAULT / "use-cases" / "UC-001-borrow-a-book.md").write_text("""---
id: UC-001
type: use-case
title: Borrow a Book
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [use-case]
primary-actor: "[[STK-001-librarian]]"
level: user-goal
priority: must
goal: ["[[GOAL-002-faster-lending]]"]
---

# Borrow a Book
""")
(_VAULT / "use-cases" / "UC-002-renew-a-loan.md").write_text("""---
id: UC-002
type: use-case
title: Renew a Loan
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [use-case]
level: user-goal
priority: could
goal: []
---

# Renew a Loan
""")
(_VAULT / "functional-requirements" / "FR-007-reserve-a-book.md").write_text("""---
id: FR-007
type: functional-requirement
title: Reserve a Book
status: draft
created: 2026-10-19
updated: 2026-10-19
sources: []
related: []
tags: [functional-requirement]
stereotype: story
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
os.environ["DASHBOARD_CONFIG"] = str(_FIXTURE.parent / "dashboard-absent.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402


def test_use_case_is_a_hierarchy_root():
    bl = app.build_fr_hierarchy()
    # the story under a use case is not an orphan
    assert bl["orphans"] == [], bl["orphans"]
    # only use cases with children appear as roots
    assert [u["id"] for u in bl["use_cases"]] == ["UC-001"], bl["use_cases"]
    uc = bl["use_cases"][0]
    assert [s["id"] for s in uc["direct_stories"]] == ["FR-007"], uc
    assert uc["n_stories"] == 1 and uc["n_features"] == 0, uc
    # totals count what the epics and use cases render
    assert bl["total_stories"] == sum(e["n_stories"] for e in bl["epics"] + bl["use_cases"])
    node, kind = app._fr_hierarchy_node(bl, "FR-007-reserve-a-book")
    assert kind == "story" and node["id"] == "FR-007", (node, kind)
    print("OK use case as root:", uc["id"], "->", [s["id"] for s in uc["direct_stories"]])


def test_ancestors_end_at_the_use_case():
    chain = app._fr_ancestors("FR-007-reserve-a-book")
    assert [a["id"] for a in chain] == ["UC-001"], chain
    assert chain[0]["url"].endswith("UC-001-borrow-a-book"), chain
    # an FR chain still links to FR pages
    assert all(a["url"].startswith("/functional-requirements/")
               for a in app._fr_ancestors("FR-003-scan-a-book"))
    print("OK ancestors:", [a["id"] for a in chain])


def test_story_inherits_the_use_case_goals():
    g = app.load_goals()
    assert "FR-007" in {p.id for p in g["coverage"]["GOAL-002"]}, g["coverage"]["GOAL-002"]
    assert "FR-007" not in {p.id for p in g["enablers"]}
    print("OK goal inherited from UC-001")


def test_use_case_page_shows_realized_by():
    trace = app.build_trace("UC-001-borrow-a-book", "use-cases")
    ids = [it["id"] for grp in trace["realized_by"] for it in grp["links"]]
    assert ids == ["FR-007"], trace["realized_by"]
    assert app.build_trace("UC-002-renew-a-loan", "use-cases")["realized_by"] == []
    print("OK realized by:", ids)


def test_pages_render():
    app.app.config["TESTING"] = True
    client = app.app.test_client()
    body = client.get("/req42/functional-requirements").get_data(as_text=True)
    assert "UC-001" in body and "1 story" in body, body[:400]
    assert "Orphaned requirements" not in body
    fr = client.get("/functional-requirements/FR-007-reserve-a-book")
    assert fr.status_code == 200
    assert "UC-001" in fr.get_data(as_text=True)
    print("OK pages render")


if __name__ == "__main__":
    test_use_case_is_a_hierarchy_root()
    test_ancestors_end_at_the_use_case()
    test_story_inherits_the_use_case_goals()
    test_use_case_page_shows_realized_by()
    test_pages_render()
    shutil.rmtree(_VAULT.parent, ignore_errors=True)
