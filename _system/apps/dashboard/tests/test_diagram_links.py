"""Every node of a diagram is also a text link on the same page (QR-001). No pytest.

On a phone a diagram node is hard to hit, and a screen reader cannot open it
at all. Each page below draws a diagram and must link every page the diagram
shows somewhere outside the picture: /graph/domain-terms, /arc42/deployment,
/page/deployment-nodes/*, /req42/functional-requirements, /req42/scope.

The checks read the diagram as the browser gets it (the mermaid source, the
term network's JSON) and look for the links in the rest of the HTML, so they
do not depend on how the list is built.

The vault is tests/fixtures/arc42-views/wiki plus terms, goals, an epic and
two context neighbours.

Run from the dashboard dir:
    .venv/bin/python tests/test_diagram_links.py
"""
import html as html_lib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
shutil.copytree(HERE / "tests" / "fixtures" / "arc42-views" / "wiki", _wiki)
(_tmp / "wiki.yaml").write_text("system_name: Credentials\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"


def _page(folder, name, front, body=""):
    (_wiki / folder).mkdir(parents=True, exist_ok=True)
    lines = ["---", *front, "sources: []", "created: 2026-11-19", "updated: 2026-11-19",
             "---", "", f"# {name}", "", body]
    (_wiki / folder / f"{name}.md").write_text("\n".join(lines), encoding="utf-8")


_page("domain-terms", "DT-001-account", ["id: DT-001", "type: domain-term", "title: Account",
      "status: draft", "tags: [domain-term]", 'related: ["[[DT-002-password]]", "[[STK-001-member]]"]'])
_page("domain-terms", "DT-002-password", ["id: DT-002", "type: domain-term", "title: Password",
      "status: draft", "tags: [domain-term]", "related: []"])
_page("goals", "GOAL-001-self-service", ["id: GOAL-001", "type: goal", "title: Self service",
      "status: draft", "tags: [goal]", "related: []", "stereotype: vision", "parent: []"])
_page("goals", "GOAL-002-fewer-calls", ["id: GOAL-002", "type: goal", "title: Fewer calls",
      "status: draft", "tags: [goal]", "related: []", "stereotype: objective",
      'parent: ["[[GOAL-001-self-service]]"]', "metric: help desk calls"])
_page("functional-requirements", "FR-001-reset", ["id: FR-001", "type: functional-requirement",
      "title: Reset on your own", "status: draft", "tags: [functional-requirement]", "related: []",
      "notation: agile", "level: epic", "parent: []", "priority: Must",
      'goal: ["[[GOAL-002-fewer-calls]]"]'])
_page("external-interfaces", "EIF-002-directory", ["id: EIF-002", "type: external-interface",
      "title: Directory", "status: draft", "tags: [external-interface]", "related: []",
      "partner: Company directory", "tier: supply",
      "flows:", "  - { data: staff records, direction: inbound, label: staff }"])
_page("stakeholders", "STK-002-help-desk", ["id: STK-002", "type: stakeholder", "title: Help desk",
      "status: draft", "tags: [stakeholder]", "related: []", "provides: [unlock requests]",
      "receives: [audit log]", "nature: person"])

sys.path.insert(0, str(HERE))  # import app.py

import app  # noqa: E402
import wiki  # noqa: E402
import project.architecture  # noqa: E402

client = app.app.test_client()
_ID_RE = re.compile(r"\b[A-Z]+-\d+\b")


def _get(path):
    resp = client.get(path)
    assert resp.status_code == 200, f"{path} answered {resp.status_code}"
    return resp.get_data(as_text=True)


def _split(page):
    """(the diagram sources, the anchors outside them as (href, text))."""
    diagrams = re.findall(r'<pre class="mermaid">(.*?)</pre>', page, re.S)
    data = re.findall(r'<script id="graph-data" type="application/json">(.*?)</script>', page, re.S)
    rest = re.sub(r'<pre class="mermaid">.*?</pre>|<script\b.*?</script>', "", page, flags=re.S)
    anchors = [(html_lib.unescape(h), re.sub(r"<[^>]+>", "", t))
               for h, t in re.findall(r'<a\b[^>]*\bhref="([^"]+)"[^>]*>(.*?)</a>', rest, re.S)]
    return [html_lib.unescape(d) for d in diagrams] + data, anchors


def _assert_ids_linked(path):
    diagrams, anchors = _split(_get(path))
    assert diagrams, f"{path} draws no diagram. Did the fixture lose its data?"
    ids = set(_ID_RE.findall("\n".join(diagrams)))
    assert ids, f"{path}: no page IDs in the diagram"
    missing = sorted(i for i in ids if not any(i in text for _, text in anchors))
    assert not missing, f"{path}: drawn but not linked as text: {missing}"
    return ids


def test_deployment_view_links_every_node():
    ids = _assert_ids_linked("/arc42/deployment")
    assert {"DN-002", "BB-004"} <= ids, ids   # a node and a block it hosts


def test_deployment_node_pages_link_every_node():
    for p in wiki.load_folder("deployment-nodes"):
        if project.architecture.build_deployment_diagram(p.stem):
            _assert_ids_linked(f"/page/deployment-nodes/{p.stem}")


def test_goal_map_links_goals_and_epics():
    ids = _assert_ids_linked("/req42/functional-requirements")
    assert {"GOAL-002", "FR-001"} <= ids, ids
    _, anchors = _split(_get("/req42/functional-requirements"))
    assert ("/goals#GOAL-002", "GOAL-002 Fewer calls") in [(h, " ".join(t.split())) for h, t in anchors]


def test_context_diagram_links_every_neighbour():
    diagrams, anchors = _split(_get("/req42/scope"))
    assert any("Directory" in d and "Help desk" in d for d in diagrams), diagrams
    hrefs = {h for h, _ in anchors}
    for url in ("/page/external-interfaces/EIF-002-directory", "/page/stakeholders/STK-002-help-desk"):
        assert url in hrefs, f"/req42/scope: {url} is drawn but not linked as text"


def test_term_network_links_every_node():
    page = _get("/graph/domain-terms")
    diagrams, anchors = _split(page)
    nodes = json.loads(diagrams[-1])["nodes"]
    hrefs = {h for h, _ in anchors}
    missing = [n["data"]["url"] for n in nodes if n["data"]["url"] not in hrefs]
    assert not missing, f"term network nodes without a text link: {missing}"
    assert "All terms (2)" in page and "/page/stakeholders/STK-001-member" in hrefs, \
        "the terms and the pages the Expand buttons add are not both listed"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
    print(f"OK: {len(fns)} diagram pages link every node as text")
