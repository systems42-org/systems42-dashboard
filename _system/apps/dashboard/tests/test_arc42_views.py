"""arc42 Deployment View (A3), Runtime View (A4), Crosscutting Concepts (A5) and
the `state: current | target` field on architecture pages — no pytest dependency.

Run from the dashboard dir:
    .venv/bin/python tests/test_arc42_views.py

WIKI_DIR points at tests/fixtures/arc42-views/wiki, a vault of its own: the
iSAQB-like "lost credentials" landscape with current and target nodes, a
parent cycle among nodes, a dangling runtime participant and a step that
contradicts `uses:`.
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "arc42-views" / "wiki"
os.environ["WIKI_DIR"] = str(_FIXTURE)
os.environ["DASHBOARD_CONFIG"] = str(_FIXTURE.parent / "dashboard-absent.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _page(folder, stem):
    return next(p for p in app.load_folder(folder) if p.stem == stem)


def _ids(groups):
    return {g["type"]: [l["id"] for l in g["links"]] for g in groups}


# --- state, supersession, inverse panels --------------------------------------

def test_state_default_target():
    assert app.page_state(_page("building-blocks", "BB-001-portal")) == "target"
    assert app.page_state(_page("building-blocks", "BB-003-console")) == "current"


def test_state_unknown_is_target():
    assert app.page_state(_page("building-blocks", "BB-002-identity")) == "target"   # state: ist


def test_superseded_both_ways():
    old = app.build_trace("DN-003-ldap", "deployment-nodes")
    new = app.build_trace("DN-004-keycloak", "deployment-nodes")
    assert _ids(old["replaced_by"]) == {"DN": ["DN-004"]}, old["replaced_by"]
    assert _ids(new["replaces"]) == {"DN": ["DN-003"]}, new["replaces"]
    assert old["replaces"] == [] and new["replaced_by"] == []


def test_inverses_on_block():
    t = app.build_trace("BB-004-account", "building-blocks")
    assert _ids(t["governed_by"]) == {"CC": ["CC-001"]}, t["governed_by"]
    assert _ids(t["deployed_on"]) == {"DN": ["DN-002"]}, t["deployed_on"]
    assert _ids(t["takes_part_in"]) == {"RS": ["RS-001"]}, t["takes_part_in"]


def test_forward_panels_on_concept_and_node():
    assert _ids(app.build_trace("CC-001-identity", "concepts")["applies_to"]) == {
        "BB": ["BB-004"], "DN": ["DN-002"]}
    assert _ids(app.build_trace("DN-002-app-server", "deployment-nodes")["hosts"]) == {
        "BB": ["BB-003", "BB-004"]}
    assert _ids(app.build_trace("DN-002-app-server", "deployment-nodes")["governed_by"]) == {"CC": ["CC-001"]}
    assert _ids(app.build_trace("CC-001-identity", "concepts")["shaped_by"]) == {"DR": ["DR-001"]}


def test_addressed_by_includes_arch():
    assert _ids(app.build_addressed_by("QR-001-secure-login")) == {"CC": ["CC-001"], "DN": ["DN-003"]}
    assert _ids(app.build_addressed_by("UC-001-reset-credentials")) == {"RS": ["RS-001", "RS-002"]}
    assert _ids(app.build_trace("ACT-001-self-service", "activity-models")["addressed_by"]) == {"RS": ["RS-001"]}


# --- runtime scenarios (A4) ---------------------------------------------------

def _participants(mm):
    """[(id, keyword, label)] in declaration order."""
    out = []
    for line in mm.splitlines():
        parts = line.strip().split(" ", 3)
        if parts[0] in ("actor", "participant"):
            out.append((parts[1], parts[0], parts[3]))
    return out


def _arrow(mm, a, b):
    """The message line from the participant labelled a to the one labelled b."""
    ids = {label: nid for nid, _, label in _participants(mm)}
    return next(l.strip() for l in mm.splitlines() if l.strip().startswith(f"{ids[a]}->>{ids[b]}:"))


def test_sequence_participants_in_order():
    mm = app.build_sequence_diagram("RS-001-reset-credentials")
    assert mm.startswith("sequenceDiagram"), mm
    assert [l for _, _, l in _participants(mm)] == [
        "Mitglied", "BB-003 · Mitgliederkonsole", "BB-004 · Kontodienst", "Mailversand",
        "BB-002 · Identität", "BB-005 · Passwortspeicher", "BB-999-ghost"], mm
    assert _participants(mm)[0][1] == "actor", mm


def test_sequence_messages():
    mm = app.build_sequence_diagram("RS-001-reset-credentials")
    assert mm.count("->>") == 6, mm
    assert _arrow(mm, "Mitglied", "BB-003 · Mitgliederkonsole").endswith(": Passwort vergessen"), mm
    eif = dict((l, n) for n, _, l in _participants(mm))["Mailversand"]
    assert f"Note over {eif}: nach 5 Minuten ungültig" in mm, mm


def test_sequence_dangling_participant():
    mm = app.build_sequence_diagram("RS-001-reset-credentials")
    assert _arrow(mm, "BB-004 · Kontodienst", "BB-999-ghost").endswith(": Protokoll"), mm


def test_sequence_escapes_message():
    mm = app.build_sequence_diagram("RS-001-reset-credentials")
    line = next(l for l in mm.splitlines() if "Reset-Link" in l)
    assert ";" not in line.replace("#59;", "").replace("#35;", ""), line
    assert "#59;" in line, line


def test_sequence_hash_escaped_once():
    mm = app.build_sequence_diagram("RS-003-edge-cases")
    line = next(l for l in mm.splitlines() if "Ticket" in l)
    assert "Ticket #35;5 öffnen" in line and "#35#" not in line, line


def test_sequence_participant_ids_are_safe_and_distinct():
    mm = app.build_sequence_diagram("RS-003-edge-cases")
    lls = _participants(mm)
    assert all(nid.startswith("L") and nid[1:].isdigit() for nid, _, _ in lls), lls
    labels = [l for _, _, l in lls]
    assert labels == ["Box", "BB-003 · Mitgliederkonsole", "BB-003", "Web Browser", "Web-Browser",
                      "Über", "Äöü", "?", "TCP/IP Gateway"], labels
    assert len({nid for nid, _, _ in lls}) == len(lls)


def test_unquoted_wikilinks_resolve():
    # `to: [[BB-003-console]]` without quotes is a nested YAML list
    hints = app.runtime_hints("RS-003-edge-cases")
    assert not any("BB-003-console" in h for h in hints), hints
    assert _ids(app.build_trace("BB-003-console", "building-blocks")["takes_part_in"]) == {"RS": ["RS-001", "RS-003"]}
    assert 'DN001 -- "HTTPS" --> DN003' in app.build_deployment_diagram()


def test_sequence_none_without_steps():
    assert app.build_sequence_diagram("RS-002-reset-credentials-new") is None


def test_runtime_hint_missing_uses():
    hints = app.runtime_hints("RS-001-reset-credentials")
    assert "BB-002 → BB-004: no uses: edge" in hints, hints
    assert not any(h.startswith("BB-003 → BB-004") for h in hints), hints
    assert "BB-999-ghost: no such page" in hints, hints


def test_runtime_hint_ancestor_uses_counts():
    # BB-003's parent BB-001 uses BB-002, the parent of BB-005
    hints = app.runtime_hints("RS-001-reset-credentials")
    assert not any(h.startswith("BB-003 → BB-005") for h in hints), hints
    assert len(hints) == 2, hints


# --- deployment view (A3) ----------------------------------------------------

def _subgraph(mm, nid):
    """The lines of one subgraph, up to its matching `end`."""
    lines = mm.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(f"subgraph {nid}["))
    depth, out = 0, []
    for l in lines[start:]:
        if l.strip().startswith("subgraph "):
            depth += 1
        elif l.strip() == "end":
            depth -= 1
        out.append(l)
        if depth == 0:
            return "\n".join(out)
    raise AssertionError(f"unclosed subgraph {nid}")


def test_deployment_nesting():
    mm = app.build_deployment_diagram()
    assert mm.startswith("flowchart"), mm
    assert "subgraph DN002[" in _subgraph(mm, "DN001"), mm


def test_deployment_hosts_blocks():
    mm = app.build_deployment_diagram()
    inner = _subgraph(mm, "DN002")
    assert "BB-004 · Kontodienst" in inner and "BB-003 · Mitgliederkonsole" in inner, inner
    assert "BB-005 · Passwortspeicher" in _subgraph(mm, "DN003"), mm


def test_deployment_protocol_label():
    mm = app.build_deployment_diagram()
    assert 'DN002 -- "LDAPS · nur lesend" --> DN003' in mm, mm
    assert 'DN002 -- "OIDC" --> DN004' in mm, mm              # existing → planned is drawn
    assert 'DN002 -- "SMTP" --> EIF001' in mm and 'EIF001["Mailversand"]' in mm, mm


def test_deployment_survives_parent_cycle():
    ids = [n["id"] for n in _flat(app.build_node_tree())]
    assert sorted(ids) == ["DN-001", "DN-002", "DN-003", "DN-004", "DN-005", "DN-006", "DN-007", "DN-008"], ids
    mm = app.build_deployment_diagram()
    assert "DN006" in mm and "DN007" in mm, mm


def test_deployment_escapes_protocol():
    tgt = app.build_deployment_diagram()
    line = next(l for l in tgt.splitlines() if "DN004 --" in l)
    label = line.split(" -- ", 1)[1].rsplit(" -->", 1)[0]
    assert label.startswith('"') and label.endswith('"') and '"' not in label[1:-1], line
    assert ";" not in label.replace("#59;", "").replace("#35;", ""), line
    assert "v2 #35;1" in label and "#35#" not in label, line


def test_node_subtree():
    mm = app.build_deployment_diagram("DN-001-isaqb-cloud")
    assert "DN002" in mm and "DN003" in mm and "DN004" not in mm, mm
    assert app.build_deployment_diagram("DN-005-new-platform") is not None


def test_a2_split_by_state():
    code, body = _get("/arc42/building-blocks")
    assert code == 200 and body.count('class="mermaid"') == 1, body.count('class="mermaid"')
    assert 'state-badge state-outdated' in body and 'state-badge state-target' in body
    assert "grey: outdated or deprecated" in body
    whole = app.build_whitebox("BB-001-portal")               # its parts are current
    assert "  style " not in whole, whole                   # its parts are all existing
    allbb = app.build_whitebox(None)
    assert "style BB001 stroke-dasharray" in allbb and "style BB006 fill:#eceef2" in allbb, allbb
    assert "· outdated" in allbb, allbb
    assert 'BB006 -. "replaced by" .-> BB001' in allbb, allbb


def test_deployment_one_diagram_for_everything():
    mm = app.build_deployment_diagram()
    for nid in ("DN001", "DN002", "DN003", "DN004", "DN005", "DN008"):
        assert nid in mm, nid
    assert "style DN004 stroke-dasharray" in mm and "style DN008 stroke-dasharray" in mm, mm   # target, planned
    assert "style DN007 fill:#eceef2" in mm, mm                                                # outdated
    assert 'DN003 -. "replaced by" .-> DN004' in mm, mm
    assert not re.search(r"style DN00[123] ", mm), mm                                         # current
    for sfx in ("· being replaced", "· planned", "· target", "· outdated"):
        assert sfx in mm, sfx
    code, body = _get("/arc42/deployment")
    assert code == 200 and body.count('class="mermaid"') == 1, body.count('class="mermaid"')
    assert "dashed: planned or target" in body and "grey: outdated or deprecated" in body


def test_four_states():
    assert [app.page_state(_page("deployment-nodes", s)) for s in
            ("DN-007-loop-b", "DN-002-app-server", "DN-008-keycloak-host", "DN-004-keycloak")] == [
        "outdated", "current", "planned", "target"]


def test_decision_replaced_by_panels():
    old = app.build_trace("DR-002-ldap-login", "decisions")
    new = app.build_trace("DR-001-sso", "decisions")
    assert _ids(old["replaced_by"]) == {"DR": ["DR-001"]}, old
    assert _ids(new["replaces"]) == {"DR": ["DR-002"]}, new
    code, body = _get("/page/decisions/DR-001-sso")
    assert code == 200 and "Replaces" in body and "DR-002" in body


def test_subtree_marks_planned_inside_existing():
    mm = app.build_deployment_diagram("DN-001-isaqb-cloud")
    assert "style DN008 stroke-dasharray" in mm, mm
    assert "style DN001 " not in mm and "style DN002 " not in mm, mm


def test_single_lifecycle_draws_plain():
    tmp = Path(tempfile.mkdtemp()) / "wiki"
    shutil.copytree(_FIXTURE, tmp)
    for f in tmp.glob("deployment-nodes/*.md"):
        if f.stem not in ("DN-001-isaqb-cloud", "DN-002-app-server"):
            f.unlink()
    saved = app.WIKI_DIR
    app.WIKI_DIR = tmp
    try:
        app._PARSE_CACHE.clear()
        mm = app.build_deployment_diagram()
        assert "stroke-dasharray" not in mm and "· planned" not in mm, mm
    finally:
        app.WIKI_DIR = saved
        app._PARSE_CACHE.clear()
        shutil.rmtree(tmp.parent)


def test_malformed_steps_warn():
    hints = app.runtime_hints("RS-003-edge-cases")
    assert "step 5: not a {from, to, message} entry, not drawn" in hints, hints
    assert "step 6: from: is empty" in hints, hints
    assert not any(h.startswith("?") for h in hints), hints


def test_free_text_keeps_slash():
    mm = app.build_sequence_diagram("RS-003-edge-cases")
    assert "as TCP/IP Gateway" in mm, mm
    assert "TCP/IP Gateway: no such page" in app.runtime_hints("RS-003-edge-cases")
    # a path to a real page still resolves
    by_stem = {q.stem: q for q in app.load_all_pages()}
    assert app._endpoint("wiki/building-blocks/BB-003-console", by_stem)[0] == "BB-003-console"


def test_concept_category_ignores_case():
    code, body = _get("/arc42/concepts")
    ops = body[body.index("Operations"):]
    assert "CC-002" in ops, ops[:300]
    unc = body[body.index("Uncategorised"):]
    assert "CC-003" in unc and "Unknown category: Sicherheit" in unc, unc[:500]


def test_deployment_hints_name_what_is_not_drawn():
    h = app.deployment_hints("DN-002-app-server")
    assert "DN-002 connects entry 3: not a {to, protocol} entry, not drawn" in h, h
    assert "DN-002 connects DN-999-ghost: no such page" in h, h
    assert not any("other state" in x for x in h), h
    assert "DN-005 hosts STK-001-member: not a building block, not drawn" in app.deployment_hints("DN-005-new-platform")
    every = app.deployment_hints()
    assert set(h) <= set(every) and len(every) == 3, every
    code, body = _get("/arc42/deployment")
    assert "DN-002 connects DN-999-ghost: no such page" in body
    code, body = _get("/page/deployment-nodes/DN-002-app-server")
    assert "DN-002 connects DN-999-ghost: no such page" in body


def _flat(nodes):
    for n in nodes:
        yield n
        yield from _flat(n["children"])


# --- routes ------------------------------------------------------------------

def _get(url):
    r = app.app.test_client().get(url)
    return r.status_code, r.get_data(as_text=True)


def test_detail_panels_and_state_badge():
    code, body = _get("/page/building-blocks/BB-004-account")
    assert code == 200
    for heading in ("Governed by", "Deployed on", "Takes part in"):
        assert heading in body, heading
    assert 'class="state-badge state-current"' in body
    code, body = _get("/page/deployment-nodes/DN-003-ldap")
    assert code == 200 and "Replaced by" in body and "DN-004" in body
    code, body = _get("/page/deployment-nodes/DN-004-keycloak")
    assert "Replaces" in body and 'state-badge state-target' in body
    code, body = _get("/page/quality-requirements/QR-001-secure-login")
    assert "Addressed by" in body and "CC-001" in body
    code, body = _get("/page/use-cases/UC-001-reset-credentials")
    assert "state-badge" not in body                    # requirements carry no state


def test_concepts_view():
    code, body = _get("/arc42/concepts")
    assert code == 200
    sec = body[body.index("Safety &amp; security"):]
    assert "CC-001" in sec and "BB-004" in sec and "DN-002" in sec, sec[:400]
    ops = body[body.index("Operations"):]
    assert "CC-002" in ops and "whole system" in ops
    assert "CC-003" in body[body.index("Uncategorised"):]
    assert 'state-badge state-current' in body


def test_runtime_view():
    code, body = _get("/arc42/runtime")
    assert code == 200
    assert "RS-001" in body and "RS-002" in body and "UC-001" in body
    assert body.index("RS-001") < body.index("RS-002")
    assert 'state-badge state-current' in body and 'state-badge state-target' in body


def test_deployment_view():
    code, body = _get("/arc42/deployment")
    assert code == 200
    assert body.count('class="mermaid"') == 1, body.count('class="mermaid"')
    assert "DN-006" in body and "DN-007" in body          # node list survives the cycle


def test_runtime_detail_has_sequence_and_hints():
    code, body = _get("/page/runtime-scenarios/RS-001-reset-credentials")
    assert code == 200 and "sequenceDiagram" in body
    assert "BB-002 → BB-004: no uses: edge" in body and "BB-999-ghost: no such page" in body
    code, body = _get("/page/runtime-scenarios/RS-002-reset-credentials-new")
    assert code == 200 and "sequenceDiagram" not in body and "Replaces" in body


def test_node_detail_has_subtree():
    code, body = _get("/page/deployment-nodes/DN-001-isaqb-cloud")
    assert code == 200 and "flowchart" in body and "DN002" in body
    assert "vendor/mermaid.min.js" in body


if __name__ == "__main__":
    test_state_default_target()
    test_state_unknown_is_target()
    test_superseded_both_ways()
    test_inverses_on_block()
    test_forward_panels_on_concept_and_node()
    test_addressed_by_includes_arch()
    test_detail_panels_and_state_badge()
    test_sequence_participants_in_order()
    test_sequence_messages()
    test_sequence_dangling_participant()
    test_sequence_escapes_message()
    test_sequence_hash_escaped_once()
    test_sequence_participant_ids_are_safe_and_distinct()
    test_unquoted_wikilinks_resolve()
    test_sequence_none_without_steps()
    test_runtime_hint_missing_uses()
    test_runtime_hint_ancestor_uses_counts()
    test_deployment_nesting()
    test_deployment_hosts_blocks()
    test_deployment_protocol_label()
    test_deployment_survives_parent_cycle()
    test_deployment_escapes_protocol()
    test_node_subtree()
    test_a2_split_by_state()
    test_concepts_view()
    test_runtime_view()
    test_deployment_view()
    test_deployment_one_diagram_for_everything()
    test_four_states()
    test_decision_replaced_by_panels()
    test_subtree_marks_planned_inside_existing()
    test_single_lifecycle_draws_plain()
    test_malformed_steps_warn()
    test_free_text_keeps_slash()
    test_concept_category_ignores_case()
    test_deployment_hints_name_what_is_not_drawn()
    test_runtime_detail_has_sequence_and_hints()
    test_node_detail_has_subtree()
    print("OK: arc42 views")
