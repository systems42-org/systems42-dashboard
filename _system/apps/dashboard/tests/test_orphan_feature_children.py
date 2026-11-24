"""Plain-assert test: the requirement hierarchy loses no requirement (#179).

    .venv/bin/python tests/test_orphan_feature_children.py

A throwaway vault holds the parent edges the story map cannot place under an
epic or a use case: a feature without a parent and its story, a child of a
deprecated epic, cycles, self-parents and children of a page that takes no
such child. Every live requirement must show exactly once: under a root,
under "Orphaned requirements" or under "Outside the Agile hierarchy".
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

_VAULT = Path(tempfile.mkdtemp(prefix="fr-orphans-")) / "wiki"
_FR = _VAULT / "functional-requirements"
_FR.mkdir(parents=True)


def _page(stem, level, parent="", notation="agile", status="draft"):
    fid = "-".join(stem.split("-")[:2])
    title = stem.split("-", 2)[2].replace("-", " ").capitalize()
    refs = ", ".join(f'"[[{p}]]"' for p in parent.split()) if parent else ""
    (_FR / f"{stem}.md").write_text(f"""---
id: {fid}
type: functional-requirement
title: {title}
status: {status}
notation: {notation}
level: {level}
parent: [{refs}]
priority: Must
---

# {title}
""")


# a regular chain
_page("FR-001-lending", "epic")
_page("FR-002-checkout", "feature", "FR-001-lending")
_page("FR-003-scan-a-book", "story", "FR-002-checkout")
# the reported case: a feature without a parent, and its story
_page("FR-010-notify", "feature")
_page("FR-011-send-a-reminder", "story", "FR-010-notify")
# a feature of a deprecated epic, and its story
_page("FR-020-retired-epic", "epic", status="deprecated")
_page("FR-021-reports", "feature", "FR-020-retired-epic")
_page("FR-022-monthly-report", "story", "FR-021-reports")
# an epic whose parent does not exist stays a root with its chain
_page("FR-030-search", "epic", "FR-999-missing")
_page("FR-031-filters", "feature", "FR-030-search")
_page("FR-032-filter-by-author", "story", "FR-031-filters")
# a two-page cycle of features with a story, and one of stories
_page("FR-040-ping", "feature", "FR-041-pong")
_page("FR-041-pong", "feature", "FR-040-ping")
_page("FR-042-rally", "story", "FR-040-ping")
_page("FR-043-chicken", "story", "FR-044-egg")
_page("FR-044-egg", "story", "FR-043-chicken")
# self-parents at every level
_page("FR-050-own-feature", "feature", "FR-050-own-feature")
_page("FR-051-own-story", "story", "FR-051-own-story")
_page("FR-052-own-epic", "epic", "FR-052-own-epic")
# a two-page cycle of epics
_page("FR-060-yin", "epic", "FR-061-yang")
_page("FR-061-yang", "epic", "FR-060-yin")
# parents that take no such child
_page("FR-070-story-of-a-story", "story", "FR-003-scan-a-book")
_page("FR-071-feature-of-a-feature", "feature", "FR-002-checkout")
_page("FR-072-its-story", "story", "FR-071-feature-of-a-feature")
_page("FR-073-feature-of-a-story", "feature", "FR-003-scan-a-book")
_page("UC-001-summary", "kite", notation="use-case")
_page("FR-074-story-of-a-kite", "story", "UC-001-summary")
# a use case that roots a feature and its story, and one without children
_page("UC-002-borrow", "sea", notation="use-case")
_page("FR-080-reserve", "feature", "UC-002-borrow")
_page("FR-081-reserve-online", "story", "FR-080-reserve")
_page("UC-003-renew", "fish", notation="use-case")
# an unknown level
_page("FR-090-odd-level", "saga")

os.environ["WIKI_DIR"] = str(_VAULT)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402
import project.requirements  # noqa: E402

LIVE = sorted(p.stem for p in _FR.glob("*.md") if p.stem != "FR-020-retired-epic")


def _shown(bl):
    """(stem, level) of every node the hierarchy holds, one entry per place."""
    out = []
    for root in bl["epics"] + bl["use_cases"]:
        out.append((root["stem"], root["level"]))
        for f in root["features"]:
            out.append((f["stem"], "feature"))
            out += [(s["stem"], "story") for s in f["stories"]]
        out += [(s["stem"], "story") for s in root["direct_stories"]]
    for o in bl["orphans"]:
        out.append((o["stem"], o["level"]))
        out += [(s["stem"], "story") for s in o.get("stories") or []]
    out += [(o["stem"], o["level"]) for o in bl["other_notations"]]
    return out


def test_every_live_requirement_shows_exactly_once():
    bl = project.requirements.build_fr_hierarchy()
    shown = _shown(bl)
    stems = sorted(s for s, _ in shown)
    assert stems == LIVE, (sorted(set(LIVE) - set(stems)),
                           sorted(s for s in set(stems) if stems.count(s) > 1))
    assert "FR-020-retired-epic" not in stems
    print("OK every live requirement shows once:", len(stems))


def test_orphans_keep_their_stories():
    bl = project.requirements.build_fr_hierarchy()
    orphans = {o["id"]: o for o in bl["orphans"]}
    assert sorted(orphans) == ["FR-010", "FR-021", "FR-040", "FR-041", "FR-043", "FR-044",
                               "FR-050", "FR-051", "FR-070", "FR-071", "FR-073", "FR-074"], sorted(orphans)

    def stories(fid):
        return [s["id"] for s in orphans[fid].get("stories") or []]

    assert stories("FR-010") == ["FR-011"]   # no parent
    assert stories("FR-021") == ["FR-022"]   # deprecated parent
    assert stories("FR-040") == ["FR-042"]   # in a cycle
    assert stories("FR-071") == ["FR-072"]   # under a feature
    assert stories("FR-041") == [] and stories("FR-050") == [] and stories("FR-073") == []
    # roots keep their chains: a dangling, cyclic or self parent on an epic changes nothing
    epics = {e["id"]: e for e in bl["epics"]}
    assert sorted(epics) == ["FR-001", "FR-030", "FR-052", "FR-060", "FR-061"], sorted(epics)
    assert [(f["id"], [s["id"] for s in f["stories"]]) for f in epics["FR-030"]["features"]] \
        == [("FR-031", ["FR-032"])]
    assert [u["id"] for u in bl["use_cases"]] == ["UC-002"]
    assert sorted(o["id"] for o in bl["other_notations"]) == ["FR-090", "UC-001", "UC-003"]
    print("OK orphans keep their stories")


def test_counters_equal_what_is_shown():
    bl = project.requirements.build_fr_hierarchy()
    shown = _shown(bl)
    n_feat = sum(1 for _, lvl in shown if lvl == "feature")
    n_story = sum(1 for _, lvl in shown if lvl == "story")
    assert (bl["total_epics"], bl["total_features"], bl["total_stories"]) == (5, n_feat, n_story), bl
    # ten live Agile features and twelve live Agile stories are in the vault
    assert (n_feat, n_story) == (10, 12), (n_feat, n_story)
    for root in bl["epics"] + bl["use_cases"]:
        assert root["n_features"] == len(root["features"]), root
        assert root["n_stories"] == len(root["direct_stories"]) + sum(
            len(f["stories"]) for f in root["features"]), root
    print("OK counters:", bl["total_epics"], bl["total_features"], bl["total_stories"])


def test_hierarchy_page_lists_orphans_with_their_stories():
    r = app.app.test_client().get("/req42/functional-requirements")
    assert r.status_code == 200
    html = r.get_data(as_text=True)
    section = html.split('class="fr-card fr-orphans"')[1].split("</section>")[0]
    ids = re.findall(r'<code class="ml-id">(FR-\d+)</code>', section)
    assert sorted(ids) == ["FR-010", "FR-011", "FR-021", "FR-022", "FR-040", "FR-041", "FR-042",
                           "FR-043", "FR-044", "FR-050", "FR-051", "FR-070", "FR-071", "FR-072",
                           "FR-073", "FR-074"], ids
    # the story sits in the list nested in its feature's item
    item = section.split('<code class="ml-id">FR-010</code>')[1].split('<code class="ml-id">FR-021</code>')[0]
    assert '<ul class="fr-stories">' in item and "/functional-requirements/FR-011-send-a-reminder" in item, item
    print("OK hierarchy page: orphans section lists", len(ids), "requirements")


def test_detail_page_of_an_orphan_feature_lists_its_story():
    client = app.app.test_client()
    for stem, story in (("FR-010-notify", "FR-011-send-a-reminder"),
                        ("FR-021-reports", "FR-022-monthly-report"),
                        ("FR-040-ping", "FR-042-rally"),
                        ("FR-071-feature-of-a-feature", "FR-072-its-story")):
        node, kind = project.requirements._fr_hierarchy_node(project.requirements.build_fr_hierarchy(), stem)
        assert kind == "feature" and [s["stem"] for s in node["stories"]] == [story], (stem, node)
        r = client.get(f"/functional-requirements/{stem}")
        assert r.status_code == 200, stem
        html = r.get_data(as_text=True)
        breakdown = html.split('class="fr-breakdown"')[1].split("</section>")[0]
        assert f'href="/functional-requirements/{story}"' in breakdown, (stem, breakdown)
        assert '<span class="fr-counter">1 story</span>' in html, stem
        # the detail diagram draws the story as a child of the feature
        diagram = html.split('<pre class="mermaid">')[1].split("</pre>")[0]
        fid, sid = stem[:6].replace("-", ""), story[:6].replace("-", "")
        assert f"{fid} --&gt; {sid}[" in diagram or f"{fid} --> {sid}[" in diagram, (stem, diagram)
    print("OK detail pages of orphan features list their stories")


def test_every_detail_page_renders():
    client = app.app.test_client()
    for stem in LIVE + ["FR-020-retired-epic"]:
        r = client.get(f"/functional-requirements/{stem}")
        assert r.status_code == 200, (stem, r.status_code)
        assert f'<code class="detail-id">{stem[:6]}</code>' in r.get_data(as_text=True), stem
    print("OK every detail page renders:", len(LIVE) + 1)


if __name__ == "__main__":
    test_every_live_requirement_shows_exactly_once()
    test_orphans_keep_their_stories()
    test_counters_equal_what_is_shown()
    test_hierarchy_page_lists_orphans_with_their_stories()
    test_detail_page_of_an_orphan_feature_lists_its_story()
    test_every_detail_page_renders()
    shutil.rmtree(_VAULT.parent, ignore_errors=True)
    print("all orphan-hierarchy tests passed")
