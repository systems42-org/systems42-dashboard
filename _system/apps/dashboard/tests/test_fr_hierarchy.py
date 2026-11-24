"""Plain-assert test for build_fr_hierarchy() — no pytest dependency.

Run from the dashboard dir inside a venv that has the app's requirements:
    python3 -m venv .venv
    .venv/bin/pip install -q -r requirements.txt
    .venv/bin/python tests/test_fr_hierarchy.py

WIKI_DIR points at tests/fixtures/wiki, a small neutral vault, so the suite is
independent of whatever content this starter is filled with.
"""
import os
import shutil
import sys
import tempfile
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import render  # noqa: E402
import links as links_module  # noqa: E402
import wiki as wiki_module  # noqa: E402
import project.requirements  # noqa: E402


def test_build_fr_hierarchy_counts_and_shape():
    bl = project.requirements.build_fr_hierarchy()

    # --- internal-consistency invariants (hold for any valid vault) ---
    assert bl["total_epics"] == len(bl["epics"]), \
        (bl["total_epics"], len(bl["epics"]))
    roots = bl["epics"] + bl["use_cases"]
    assert sum(e["n_features"] for e in roots) == bl["total_features"], \
        (sum(e["n_features"] for e in roots), bl["total_features"])
    assert sum(e["n_stories"] for e in roots) == bl["total_stories"], \
        (sum(e["n_stories"] for e in roots), bl["total_stories"])
    assert bl["orphans"] == [], bl["orphans"]

    by_id = {e["id"]: e for e in bl["epics"]}

    # --- stable structure (FR IDs are stable and never reused) ---
    # FR-001 is the fixture's fully broken-down epic: 1 feature, 2+1 = 3 stories.
    fr001 = by_id["FR-001"]
    feat_ids = [f["id"] for f in fr001["features"]]
    assert feat_ids == ["FR-002"], feat_ids
    assert fr001["n_features"] == 1, fr001["n_features"]
    assert fr001["n_stories"] == 3, fr001["n_stories"]

    # Story order within a feature is driven by the `order` frontmatter, not by
    # ID, so assert membership (as sets) rather than sequence.
    feat_by_id = {f["id"]: f for f in fr001["features"]}
    fr002_stories = {s["id"] for s in feat_by_id["FR-002"]["stories"]}
    assert fr002_stories == {"FR-003", "FR-004"}, fr002_stories

    # FR-001 also has a story hung straight off the epic; more may be added
    # later, so assert SUPERSET (>=) rather than equality.
    fr001_direct = {s["id"] for s in fr001["direct_stories"]}
    assert fr001_direct >= {"FR-005"}, fr001_direct

    # at least one leaf epic with no children at all (also the fixture's
    # explicit Enabler epic: goal: [])
    fr006 = by_id["FR-006"]
    assert fr006["n_features"] == 0, fr006["n_features"]
    assert fr006["n_stories"] == 0, fr006["n_stories"]
    assert fr006["features"] == [], fr006["features"]

    print("OK build_fr_hierarchy:", bl["total_epics"], "epics",
          bl["total_features"], "features", bl["total_stories"], "stories")


def test_goal_epic_diagram_string():
    bl = project.requirements.build_fr_hierarchy()
    dia = project.requirements._mermaid_goal_epic_tree(app.load_goals(), bl)
    assert dia is not None
    assert dia.startswith("graph TD"), dia[:40]
    # objectives present and clickable to their goal cards on /goals
    assert "GOAL-002" in dia and "/goals#GOAL-002" in dia
    # epics present and clickable to their FR page under the new folder route
    assert "FR-001" in dia and "/functional-requirements/" in dia
    # enabler epics (goal: []) stay reachable under the Platform node, whose
    # label must be English — it was the last German string in the dashboard,
    # rendered as a labelled mermaid box on /req42/functional-requirements (CON-005).
    assert "ENABLER" in dia and "FR-006" in dia
    assert 'ENABLER["Platform / Enabler"]' in dia, dia
    # two levels only — no story IDs leak into the overview map
    assert "FR-003" not in dia
    print("OK goal-epic diagram:", dia.count("-->"), "edges")


def test_fr_subtree_diagram_string():
    bl = project.requirements.build_fr_hierarchy()
    # epic root: features + a nested story, all clicking to their own FR page
    fr001 = next(e for e in bl["epics"] if e["id"] == "FR-001")
    dia = project.requirements._mermaid_fr_subtree(fr001)
    assert dia is not None and dia.startswith("graph TD"), (dia or "")[:40]
    assert "FR-001" in dia and "FR-002" in dia and "FR-003" in dia
    assert "/functional-requirements/FR-003-scan-a-book" in dia
    assert "/page/functional-requirements/" not in dia  # no links to the old route

    # feature root: just its stories
    fr002 = next(f for f in fr001["features"] if f["id"] == "FR-002")
    fdia = project.requirements._mermaid_fr_subtree(fr002)
    assert fdia is not None and "FR-002" in fdia and "FR-003" in fdia, fdia

    # leaf (childless epic, or a story) yields no diagram
    fr006 = next(e for e in bl["epics"] if e["id"] == "FR-006")
    assert project.requirements._mermaid_fr_subtree(fr006) is None
    story = fr001["features"][0]["stories"][0]
    assert project.requirements._mermaid_fr_subtree(story) is None
    print("OK fr-subtree diagram:", dia.count("-->"), "edges")


def test_fr_ancestors():
    # FR-003 (story) -> FR-002 (feature) -> FR-001 (epic), root first
    chain = [a["id"] for a in project.requirements._fr_ancestors("FR-003-scan-a-book")]
    assert chain == ["FR-001", "FR-002"], chain
    # an epic has no ancestors
    assert project.requirements._fr_ancestors("FR-001-lending") == []
    print("OK fr ancestors:", chain)


def test_fr_route_redirect_and_404():
    app.app.config["TESTING"] = True
    client = app.app.test_client()
    bl = project.requirements.build_fr_hierarchy()
    epic_stem = next(e["stem"] for e in bl["epics"] if e["id"] == "FR-001")
    story_stem = next(
        s["stem"] for e in bl["epics"] for f in e["features"] for s in f["stories"]
    )

    # epic page: full text + breakdown + Functional-Requirements breadcrumb (not "Search")
    resp = client.get(f"/functional-requirements/{epic_stem}")
    assert resp.status_code == 200, resp.status_code
    body = resp.get_data(as_text=True)
    assert "Functional Requirements" in body and "Breakdown" in body
    assert "FR-002" in body                       # a child feature listed

    # story page: a leaf still resolves (full text, no breakdown diagram)
    assert client.get(f"/functional-requirements/{story_stem}").status_code == 200

    # the old /page route 302-redirects FRs to the new path
    r = client.get(f"/page/functional-requirements/{epic_stem}")
    assert r.status_code == 302, r.status_code
    assert r.headers["Location"].endswith(f"/functional-requirements/{epic_stem}")

    # unknown stem -> 404
    assert client.get("/functional-requirements/FR-999-does-not-exist").status_code == 404
    print("OK fr route + redirect + 404")


def test_body_wikilinks_become_hyperlinks():
    titles, links = links_module.title_index(), links_module.link_index()

    # a stakeholder wikilink with an alias -> real anchor to its /page route
    html = render.render_wikilinks("As [[STK-001-librarian|the librarian]] …", titles, links)
    assert '<a class="wl" href="/page/stakeholders/STK-001-librarian">the librarian</a>' in html, html

    # an FR target resolves to the rich FR route, not /page
    html2 = render.render_wikilinks("see [[FR-001-lending]]", titles, links)
    assert 'href="/functional-requirements/FR-001-lending"' in html2, html2

    # provenance and unresolved targets stay non-link spans
    assert '<span class="wl">' in render.render_wikilinks("[[raw/sources/SRC-001-x|Q]]", titles, links)
    assert '<span class="wl">' in render.render_wikilinks("[[Totally-Unknown]]", titles, links)

    # inline-snippet callers pass no link index -> nothing becomes a link
    assert "<a " not in render.render_wikilinks("[[STK-001-librarian|X]]", titles, None)
    print("OK wikilinks -> hyperlinks")


def test_old_backlog_route_is_gone():
    """/req42/backlog was the block's pre-2026 name; it no longer redirects."""
    client = app.app.test_client()
    assert client.get("/req42/backlog").status_code == 404
    assert client.get("/req42/functional-requirements").status_code == 200


def test_unplaced_requirements_stay_visible():
    """A page the Agile projection cannot place (other notation, no notation)
    is listed, never silently dropped."""
    extra = [
        wiki_module.Page("UC-009-find", {"id": "UC-009", "title": "Find", "notation": "use-case",
                                 "level": "sea"}, "", "functional-requirements"),
        wiki_module.Page("FR-090-unplaced", {"id": "FR-090", "title": "No notation"},
                 "", "functional-requirements"),
        wiki_module.Page("FR-091-ears", {"id": "FR-091", "title": "Shall", "notation": "ears",
                                 "level": "requirement"}, "", "functional-requirements"),
    ]
    real = wiki_module.load_folder
    wiki_module.load_folder = lambda folder: real(folder) + (extra if folder == "functional-requirements" else [])
    try:
        bl = project.requirements.build_fr_hierarchy()
        body = app.app.test_client().get("/req42/functional-requirements").get_data(as_text=True)
    finally:
        wiki_module.load_folder = real
    other = {o["id"]: o for o in bl["other_notations"]}
    assert set(other) == {"UC-009", "FR-090", "FR-091"}, other
    assert other["FR-090"]["notation"] == "", other["FR-090"]
    assert "FR-090" not in {e["id"] for e in bl["epics"]}
    section = body[body.index("Outside the Agile hierarchy"):]
    assert "no notation · no level" in section and "ears · requirement" in section, section[:800]
    print("OK unplaced requirements listed:", sorted(other))


def test_features_and_stories_may_refine_a_use_case():
    """DR-038 amendment: an Agile feature or story may name a sea- or fish-level
    use case as parent. The use case becomes a root beside the epics, its page
    shows what realizes it, and the children are no orphans. A kite-level use
    case takes no Agile children, so a story under one stays an orphan, and
    neither does an epic: an epic naming a use case stays an epic root. Goal
    inheritance reads the same edge: a feature with goal: [] serves the goals
    of a sea- or fish-level parent use case, never those of a kite."""
    goal = 'goal: ["[[GOAL-002-faster-lending]]"]\n'
    pages = {
        "UC-010-borrow": "notation: use-case\nlevel: sea\n" + goal,
        "FR-091-scan": "notation: agile\nlevel: story\nparent: [\"[[UC-010-borrow]]\"]\n",
        "FR-092-renew": "notation: agile\nlevel: feature\nparent: [\"[[UC-010-borrow]]\"]\n",
        "FR-093-renew-online": "notation: agile\nlevel: story\nparent: [\"[[FR-092-renew]]\"]\n",
        "UC-011-run-library": "notation: use-case\nlevel: kite\n" + goal,
        "FR-094-under-kite": "notation: agile\nlevel: story\nparent: [\"[[UC-011-run-library]]\"]\n",
        "FR-097-feature-under-kite": "notation: agile\nlevel: feature\nlane: backbone\ngoal: []\n"
                                     "parent: [\"[[UC-011-run-library]]\"]\n",
        "UC-012-reserve": "notation: use-case\nlevel: sea\n",
        "UC-013-pick-shelf": "notation: use-case\nlevel: fish\n" + goal,
        "FR-095-scan-shelf": "notation: agile\nlevel: feature\nlane: backbone\ngoal: []\n"
                             "parent: [\"[[UC-013-pick-shelf]]\"]\n",
        "FR-096-epic-under-uc": "notation: agile\nlevel: epic\nparent: [\"[[UC-010-borrow]]\"]\n",
    }
    with tempfile.TemporaryDirectory() as tmp:
        wiki = Path(tmp) / "wiki"
        shutil.copytree(_FIXTURE, wiki)
        for stem, meta in pages.items():
            (wiki / "functional-requirements" / f"{stem}.md").write_text(
                f"---\nid: {stem[:6]}\ntype: functional-requirement\ntitle: {stem[7:]}\n"
                f"status: draft\n{meta}---\n\n# {stem[7:]}\n", encoding="utf-8")
        saved, wiki_module.WIKI_DIR = wiki_module.WIKI_DIR, wiki
        try:
            bl = project.requirements.build_fr_hierarchy()
            node, level = project.requirements._fr_hierarchy_node(bl, "UC-010-borrow")
            client = app.app.test_client()
            uc_page = client.get("/functional-requirements/UC-010-borrow").get_data(as_text=True)
            overview = client.get("/req42/functional-requirements").get_data(as_text=True)
            crumbs = [a["id"] for a in project.requirements._fr_ancestors("FR-093-renew-online")]
            goals = app.load_goals()
        finally:
            wiki_module.WIKI_DIR = saved

    ucs = {u["id"]: u for u in bl["use_cases"]}
    assert set(ucs) == {"UC-010", "UC-013"}, ucs
    # fish level: a root like sea
    assert [f["id"] for f in ucs["UC-013"]["features"]] == ["FR-095"], ucs["UC-013"]
    assert project.requirements._fr_hierarchy_node(bl, "UC-013-pick-shelf")[1] == "fish"
    # an epic under a use case is still an epic root, not part of its breakdown
    assert "FR-096" in {e["id"] for e in bl["epics"]}, bl["epics"]
    assert project.requirements._fr_hierarchy_node(bl, "FR-096-epic-under-uc")[1] == "epic"
    uc = ucs["UC-010"]
    assert [f["id"] for f in uc["features"]] == ["FR-092"], uc["features"]
    assert [s["id"] for s in uc["features"][0]["stories"]] == ["FR-093"], uc["features"]
    assert [s["id"] for s in uc["direct_stories"]] == ["FR-091"], uc["direct_stories"]
    assert (uc["n_features"], uc["n_stories"]) == (1, 2), uc
    assert {o["id"] for o in bl["orphans"]} == {"FR-094", "FR-097"}, bl["orphans"]
    # goal inheritance agrees with the story map
    served = {p.id for p in goals["coverage"]["GOAL-002"]}
    assert "FR-095" in served and "FR-097" not in served, served
    untraced = {p.id for p in goals["untraced"]}
    assert "FR-097" in untraced and "FR-095" not in untraced, untraced
    other = {o["id"] for o in bl["other_notations"]}
    assert "UC-010" not in other and {"UC-011", "UC-012"} <= other, other
    assert "UC-010" not in {e["id"] for e in bl["epics"]}
    assert node is uc and level == "sea", (node, level)
    assert "Refined by" in uc_page and "FR-091" in uc_page and "FR-093" in uc_page
    assert "Use cases refined by features and stories" in overview and "UC-010" in overview
    assert "UC-010" in crumbs, crumbs
    print("OK use case refined by Agile children")


def test_parent_written_as_a_number_or_a_single_link():
    """`parent:` is a list, but a page may hold a number or one bare link
    (Page.as_list): a number names no parent, a single link is that parent,
    in the story map, the breadcrumb and goal inheritance alike."""
    pages = {
        "UC-080-lend": 'notation: use-case\nlevel: sea\ngoal: ["[[GOAL-002-faster-lending]]"]\n',
        "FR-081-number": "notation: agile\nlevel: story\nparent: 7\n",
        "FR-082-single-link": 'notation: agile\nlevel: feature\nlane: backbone\ngoal: []\n'
                              'parent: "[[UC-080-lend]]"\n',
        "FR-083-under-feature": 'notation: agile\nlevel: story\nparent: "[[FR-082-single-link]]"\n',
    }
    with tempfile.TemporaryDirectory() as tmp:
        wiki = Path(tmp) / "wiki"
        shutil.copytree(_FIXTURE, wiki)
        for stem, meta in pages.items():
            (wiki / "functional-requirements" / f"{stem}.md").write_text(
                f"---\nid: {stem[:6]}\ntype: functional-requirement\ntitle: {stem[7:]}\n"
                f"status: draft\n{meta}---\n\n# {stem[7:]}\n", encoding="utf-8")
        saved, wiki_module.WIKI_DIR = wiki_module.WIKI_DIR, wiki
        try:
            bl = project.requirements.build_fr_hierarchy()
            client = app.app.test_client()
            codes = {s: client.get(f"/functional-requirements/{s}").status_code for s in pages}
            overview = client.get("/req42/functional-requirements").status_code
            crumbs = {s: [a["id"] for a in project.requirements._fr_ancestors(s)] for s in pages}
            goals = app.load_goals()
        finally:
            wiki_module.WIKI_DIR = saved
    assert set(codes.values()) == {200} and overview == 200, (codes, overview)
    assert "FR-081" in {o["id"] for o in bl["orphans"]}, bl["orphans"]
    assert crumbs["FR-081-number"] == [], crumbs
    uc = {u["id"]: u for u in bl["use_cases"]}["UC-080"]
    assert [f["id"] for f in uc["features"]] == ["FR-082"], uc
    assert [s["id"] for s in uc["features"][0]["stories"]] == ["FR-083"], uc
    assert crumbs["FR-083-under-feature"] == ["UC-080", "FR-082"], crumbs
    assert project.requirements._fr_first_parent(wiki_module.Page("x", {"parent": 7}, "", "functional-requirements")) == "7"
    assert "FR-082" in {p.id for p in goals["coverage"]["GOAL-002"]}
    print("OK parent as a number or a single link")


if __name__ == "__main__":
    test_build_fr_hierarchy_counts_and_shape()
    test_parent_written_as_a_number_or_a_single_link()
    test_unplaced_requirements_stay_visible()
    test_features_and_stories_may_refine_a_use_case()
    test_goal_epic_diagram_string()
    test_fr_subtree_diagram_string()
    test_fr_ancestors()
    test_fr_route_redirect_and_404()
    test_body_wikilinks_become_hyperlinks()
    test_old_backlog_route_is_gone()
    print("ALL PASSED")
