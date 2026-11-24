"""One resolver for every link (issue #178).

The body text resolved `[[GOAL-002]]` through the link index (file name or
ID), while the goal coverage, the relations panel and the typed link fields
(`goal:`, `parent:`, `drivers:`, `realizes:`, `uses:`, `steps:`) compared the
written name with file names only. So the same link opened its page in the
text and was missing from the projections. Two pages linking each other also
had no "Linked from", because backlinks left out the pages a page links to
(FR-034: every linking page shows there).

Run from the dashboard dir:
    .venv/bin/python tests/test_link_resolver.py
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

# The pages are the fixture tests/fixtures/link-spellings, so test_parity.py
# compares the same cases in the Go implementation. Here they are copied into
# a temporary wiki.
_system = Path(__file__).resolve().parents[3]
_fixture = Path(__file__).resolve().parent / "fixtures" / "link-spellings"
_repo = Path(tempfile.mkdtemp()) / "repo"
_wiki = _repo / "wiki"
shutil.copytree(_fixture / "wiki", _wiki)
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(exist_ok=True)
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
(_repo / "docs").mkdir()
_config = _repo / "_system" / "wiki.yaml"
shutil.copytree(_system / "metamodel", _repo / "_system" / "metamodel")
shutil.copytree(_system / "anchors", _repo / "_system" / "anchors")
shutil.copy(_fixture / "wiki.yaml", _config)

GOAL = "GOAL-002-shorter-waiting-times"      # the file name is longer than the ID
# every spelling the body text resolves, each on a requirement of its own, in
# `goal:` and in the text
SPELLINGS = {
    "FR-001-stem": f"[[{GOAL}]]",
    "FR-002-id": "[[GOAL-002]]",
    "FR-003-alias": "[[GOAL-002|waiting times]]",
    "FR-004-heading": "[[GOAL-002#Metric]]",
    "FR-005-path": f"[[goals/{GOAL}]]",
    "FR-006-all": "[[wiki/goals/GOAL-002#Metric|waiting times]]",
}
# The other pages:
#   FR-007-twice       the goal twice, in two spellings (counted once)
#   FR-008-unresolved  a goal that does not exist
#   FR-009-child       a feature whose `parent:` is an ID alone
#   DT-001-alpha       links DT-002 by ID alone, and itself in both spellings
#   DT-002-beta        links DT-001 back
#   DT-003-gamma       links DT-001 in two spellings and a page that does not exist
#   BB-001, BB-002, RS-001  `drivers:`, `uses:`, `parent:`, `realizes:` and
#                      `steps:` by ID alone

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
import wiki  # noqa: E402
import links  # noqa: E402

client = app.app.test_client()


def _get(url):
    r = client.get(url)
    assert r.status_code == 200, (url, r.status_code)
    return r.get_data(as_text=True)


def _ids(groups):
    return sorted(it["id"] for g in groups for it in g["links"])


def _panel(html, heading):
    """IDs listed under one heading of the relations panel of a rendered page."""
    m = re.search(rf'<h2 class="rel-h">{heading}</h2>(.*?)</section>', html, re.S)
    return sorted(re.findall(r"<code>([^<]+)</code>", m.group(1))) if m else []


def test_fixture_holds_the_spellings():
    for stem, link in SPELLINGS.items():
        text = (_wiki / "functional-requirements" / f"{stem}.md").read_text(encoding="utf-8")
        assert text.count(link) == 2, (stem, link)


def test_resolver_accepts_every_spelling_the_body_accepts():
    with app.app.test_request_context("/"):
        index = links.page_index()
        for link in SPELLINGS.values():
            page = links.resolve_link(link, index)
            assert page is not None and page.stem == GOAL, link
        # the name alone, as a typed field may hold it
        assert links.resolve_link("GOAL-002", index).stem == GOAL
        assert links.resolve_link(GOAL, index).stem == GOAL
        for missing in ("[[GOAL-099]]", "[[goal-002]]", "", None, "[[]]"):
            assert links.resolve_link(missing, index) is None, missing
        # the index the body text uses gives the same page
        for link in SPELLINGS.values():
            assert links.resolve_link(link, links.link_index()) == ("goals", GOAL), link
    print("OK: one resolver, every spelling")


def test_body_links_open_the_goal():
    for stem in SPELLINGS:
        html = _get(f"/functional-requirements/{stem}")
        assert f'href="/page/goals/{GOAL}"' in html, stem
    assert "/page/goals/GOAL-099" not in _get("/functional-requirements/FR-008-unresolved")
    print("OK: every spelling is a working link in the text")


def test_coverage_is_the_same_for_every_spelling():
    with app.app.test_request_context("/"):
        data = app.load_goals()
        by_stem = {p.stem: p for p in wiki.load_folder("functional-requirements")}
        for stem in SPELLINGS:
            assert links.links_of(by_stem[stem], "goal") == [GOAL], stem
        assert links.links_of(by_stem["FR-007-twice"], "goal") == [GOAL]
        assert links.links_of(by_stem["FR-008-unresolved"], "goal") == []
    serving = [p.id for p in data["coverage"]["GOAL-002"]]
    assert serving == ["FR-001", "FR-002", "FR-003", "FR-004", "FR-005", "FR-006", "FR-007"], serving
    assert data["coverage"]["GOAL-003"] == []
    # the epic whose goal does not exist breaks the rule, no other epic does
    assert [p.id for p in data["untraced"] if app._fr_level(p) == "epic"] == ["FR-008"], data["untraced"]

    html = _get("/goals")
    rows = {goal: bool(gap) for gap, goal in re.findall(r'<tr( class="gm-gap")? data-goal="(GOAL-\d+)"', html)}
    assert rows == {"GOAL-002": False, "GOAL-003": True}, rows
    print("OK: coverage shows the goal for every spelling, once per requirement")


def test_relations_are_the_same_for_every_spelling():
    panels = {}
    for stem in list(SPELLINGS) + ["FR-007-twice"]:
        html = _get(f"/functional-requirements/{stem}")
        panels[stem] = _panel(html, "Links to")
    assert all(p == ["GOAL-002"] for p in panels.values()), panels
    assert _panel(_get("/functional-requirements/FR-008-unresolved"), "Links to") == []
    linked_from = _panel(_get(f"/page/goals/{GOAL}"), "Linked from")
    assert linked_from == ["FR-001", "FR-002", "FR-003", "FR-004", "FR-005", "FR-006", "FR-007"], linked_from
    print("OK: relations are identical for every spelling")


def test_id_only_reciprocal_self_and_duplicate_links():
    alpha = _get("/page/domain-terms/DT-001-alpha")
    beta = _get("/page/domain-terms/DT-002-beta")
    gamma = _get("/page/domain-terms/DT-003-gamma")
    # an ID-only link is an outbound link, a self-link is none
    assert _panel(alpha, "Links to") == ["DT-002"], _panel(alpha, "Links to")
    # two pages linking each other show each other in both panels (FR-034)
    assert _panel(alpha, "Linked from") == ["DT-002", "DT-003"], _panel(alpha, "Linked from")
    assert _panel(beta, "Links to") == ["DT-001"]
    assert _panel(beta, "Linked from") == ["DT-001"], _panel(beta, "Linked from")
    # one target in two spellings is one link, a missing target is none
    assert _panel(gamma, "Links to") == ["DT-001"], _panel(gamma, "Links to")
    assert _panel(gamma, "Linked from") == []

    with app.app.test_request_context("/"):
        rel = app.build_relations_panel("DT-001-alpha")
        assert _ids(rel["outbound"]) == ["DT-002"] and _ids(rel["inbound"]) == ["DT-002", "DT-003"]
    # the relations count of the term list counts a page once
    rows = re.findall(r'href="/page/domain-terms/(DT-\d+)[^"]*".*?<span class="rel-pill">(\d+)</span>',
                      _get("/domain-terms"), re.S)
    counts = {k: int(v) for k, v in rows}
    assert counts == {"DT-001": 1, "DT-002": 1, "DT-003": 2}, counts
    print("OK: ID-only, reciprocal, self and duplicate links")


def test_typed_fields_follow_an_id_only_link():
    with app.app.test_request_context("/"):
        # parent: the feature sits under its epic, it is no orphan
        tree = app.build_fr_hierarchy()
        assert tree["orphans"] == [], tree["orphans"]
        epic = next(e for e in tree["epics"] if e["id"] == "FR-002")
        assert [f["id"] for f in epic["features"]] == ["FR-009"], epic
        assert [a["id"] for a in app._fr_ancestors("FR-009-child")] == ["FR-002"]
        # drivers, realizes, uses, parent and steps of the architecture pages
        assert _ids(app.build_drivers("BB-001-core")) == ["FR-001"]
        assert _ids(app.build_addressed_by("FR-001-stem")) == ["BB-001"]
        assert _ids(app.build_realized_by("FR-001-stem")) == ["RS-001"]
        blocks = {p.stem: p for p in wiki.load_folder("building-blocks")}
        assert links.links_of(blocks["BB-001-core"], "uses") == ["BB-003-store"]
        top = app.build_bb_tree()
        assert [n["stem"] for n in top] == ["BB-001-core", "BB-003-store"], top
        assert [c["stem"] for c in top[0]["children"]] == ["BB-002-part"], top[0]
        scenario = next(iter(wiki.load_folder("runtime-scenarios")))
        steps = app.steps_of(scenario)
        assert (steps[0]["from_stem"], steps[0]["to_stem"]) == ("BB-001-core", "BB-003-store"), steps
    print("OK: parent, drivers, realizes, uses and steps follow an ID-only link")


if __name__ == "__main__":
    test_fixture_holds_the_spellings()
    test_resolver_accepts_every_spelling_the_body_accepts()
    test_body_links_open_the_goal()
    test_coverage_is_the_same_for_every_spelling()
    test_relations_are_the_same_for_every_spelling()
    test_id_only_reciprocal_self_and_duplicate_links()
    test_typed_fields_follow_an_id_only_link()
    print("all link-resolver tests passed")
