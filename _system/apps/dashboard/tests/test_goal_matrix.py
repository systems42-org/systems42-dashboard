"""The goal coverage matrix on /goals shows Systems42's goal-coverage projection
(FR-036, proj-goal-coverage, rule-fr-traces-to-goal). No pytest.

Rows are goals, columns are epics and use cases. An enabler is an epic in lane
platform or display that names no goal. A backbone epic that names no goal breaks the rule and
stays in the main group, marked. A goal no column serves stands out. The
"Agreed only" filter of the goal list applies to the matrix too.

Run from the dashboard dir:
    .venv/bin/python tests/test_goal_matrix.py
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("goals", "functional-requirements", "use-cases"):
    (_wiki / _f).mkdir(parents=True)
(_tmp / "wiki.yaml").write_text("system_name: System X\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402


def _page(folder, stem, title, status, **fields):
    pid = "-".join(stem.split("-")[:2])
    extra = "".join(f"{k}: {v}\n" for k, v in fields.items())
    (_wiki / folder / f"{stem}.md").write_text(
        f"---\nid: {pid}\ntitle: {title}\nstatus: {status}\nsources: []\nrelated: []\n"
        f"{extra}---\n\n# {title}\n", encoding="utf-8")


_page("goals", "GOAL-001-vision", "The vision", "accepted", stereotype="vision")
_page("goals", "GOAL-002-served", "Served goal", "accepted", stereotype="objective")
_page("goals", "GOAL-003-unserved", "Unserved goal", "accepted", stereotype="objective")
_page("goals", "GOAL-004-draft", "Draft goal", "draft", stereotype="objective")

_FR = "functional-requirements"
_page(_FR, "FR-001-served-epic", "Served epic", "accepted",
      stereotype="epic", lane="backbone", parent="[]", goal='["[[GOAL-002-served]]"]')
_page(_FR, "FR-002-untraced-epic", "Untraced epic", "draft",
      stereotype="epic", lane="backbone", parent="[]", goal="[]")
_page(_FR, "FR-003-platform-epic", "Platform epic", "accepted",
      stereotype="epic", lane="platform", parent="[]", goal="[]")
_page(_FR, "FR-004-feature", "A feature", "accepted",
      stereotype="feature", lane="backbone", parent='["[[FR-001-served-epic]]"]',
      goal='["[[GOAL-002-served]]"]')
_page(_FR, "FR-005-display-epic", "Display epic", "draft",
      stereotype="epic", lane="display", parent="[]", goal="[]")
_page(_FR, "FR-006-draft-epic", "Draft epic", "draft",
      stereotype="epic", lane="backbone", parent="[]", goal='["[[GOAL-002-served]]"]')
# lane platform, but it names a goal: no enabler (rel-goal)
_page(_FR, "FR-007-platform-with-goal", "Platform epic with a goal", "draft",
      stereotype="epic", lane="platform", parent="[]", goal='["[[GOAL-004-draft]]"]')
_page("use-cases", "UC-001-borrow", "Borrow", "draft", goal='["[[GOAL-004-draft]]"]')

BODY = app.app.test_client().get("/goals").get_data(as_text=True)


def _matrix():
    m = re.search(r'<section class="goal-matrix"[^>]*>(.*?)</section>', BODY, re.S)
    assert m, "no matrix section"
    return m.group(1)


def _headers():
    return re.findall(r'<th class="gm-th[^"]*"[^>]*>.*?</th>', _matrix(), re.S)


def _rows():
    return dict(re.findall(r'<tr[^>]*data-goal="(GOAL-\d+)"[^>]*>(.*?)</tr>', _matrix(), re.S))


def test_rule_helper():
    data = app.load_goals()
    assert [p.id for p in data["enablers"]] == ["FR-003", "FR-005"], data["enablers"]
    assert [p.id for p in data["untraced"]] == ["FR-002"], data["untraced"]


def test_goal_epic_map_keeps_untraced_epics():
    # the map on the functional-requirements page: an untraced epic is no
    # enabler, but it must not drop off the map either
    dia = app._mermaid_goal_epic_tree(app.load_goals(), app.build_fr_hierarchy())
    enabler = re.search(r"ENABLER --> (\w+)", dia)
    assert 'NOGOAL["No goal"]' in dia, dia
    assert re.search(r"NOGOAL --> \w+\[\"FR-002", dia), dia
    assert not re.search(r"ENABLER --> \w+\[\"FR-002", dia), dia
    assert re.search(r"ENABLER --> \w+\[\"FR-003", dia), enabler


def test_columns_are_epics_and_use_cases_enablers_last():
    ids = [re.search(r">(FR-\d+|UC-\d+)<", h).group(1) for h in _headers()]
    assert ids == ["FR-001", "FR-002", "FR-006", "FR-007", "UC-001", "FR-003", "FR-005"], ids
    assert "Epic-0" not in _matrix()


def test_header_links_and_tooltip():
    h = _headers()[0]
    assert 'href="/functional-requirements/FR-001-served-epic"' in h, h
    assert 'data-tooltip="Served epic"' in h, h
    uc = next(x for x in _headers() if "UC-001" in x)
    assert 'href="/page/use-cases/UC-001-borrow"' in uc, uc


def test_enablers_by_lane():
    for h in _headers():
        enabler = "gm-enabler" in h.split(">")[0]
        assert enabler == ("FR-003" in h or "FR-005" in h), h


def test_untraced_epic_is_marked_not_an_enabler():
    h = next(x for x in _headers() if ">FR-002<" in x)
    assert "gm-enabler" not in h.split(">")[0], h
    assert "gm-nogoal" in h.split(">")[0] and "no goal" in h, h
    assert "no goal" in re.search(r'<p class="goal-matrix-legend">(.*?)</p>', BODY, re.S).group(1)


def test_goal_without_a_mark_stands_out():
    rows = _rows()
    assert "gm-dot" not in rows["GOAL-003"]
    head = re.search(r'<tr([^>]*)data-goal="GOAL-003"', _matrix()).group(1)
    assert "gm-gap" in head, head
    assert "No epic or use case yet" in rows["GOAL-003"]
    assert "No epic or use case yet" not in rows["GOAL-002"]
    assert "gm-gap" not in re.search(r'<tr([^>]*)data-goal="GOAL-002"', _matrix()).group(1)


def test_row_goal_links_its_page():
    assert 'href="/page/goals/GOAL-002-served"' in _rows()["GOAL-002"]


def test_marks_carry_status_for_the_filter():
    m = _matrix()
    assert re.search(r'<tr[^>]*data-goal="GOAL-004"[^>]*data-status="draft"', m), m
    h = next(x for x in _headers() if ">FR-006<" in x)
    assert 'data-status="draft"' in h, h
    # one status filter for the whole page: the matrix has its own buttons for
    # the same `?status=` parameter as the goal list
    assert 'data-list-status="accepted"' in m
    assert 'data-list-controls="goal"' in m


def test_drives_lists_match_the_marks():
    rows = _rows()
    cols = [re.search(r">(FR-\d+|UC-\d+)<", h).group(1) for h in _headers()]
    for gid, row in rows.items():
        cells = re.findall(r"<td\b[^>]*>(.*?)</td>", row, re.S)[1:]
        marked = [c for c, cell in zip(cols, cells) if "gm-dot" in cell]
        card = re.search(r'<section id="' + gid + r'" class="goal-card">(.*?)</section>', BODY, re.S).group(1)
        drives = re.findall(r'<a href="[^"]+">((?:FR|UC)-\d+) ', card)
        assert drives == marked, (gid, drives, marked)


def _node(body):
    js = (Path(__file__).resolve().parents[1] / "static" / "goal-matrix.js").read_text(encoding="utf-8")
    out = subprocess.run(["node", "-e", "var window = {};\n" + js + "\n" + body],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_agreed_only_hides_drafts_and_finds_new_gaps():
    if not shutil.which("node"):
        print("skip: no node")
        return
    cols = [{"status": "accepted"}, {"status": "draft"}]
    rows = [{"status": "accepted", "marks": [True, False]},
            {"status": "accepted", "marks": [False, True]},
            {"status": "draft", "marks": [True, True]}]
    call = "console.log(JSON.stringify(window.S42GoalMatrix.view(%s, %s, %s)));"
    every = _node(call % (json.dumps(rows), json.dumps(cols), json.dumps("all")))
    assert every == {"rows": [True, True, True], "cols": [True, True],
                     "gaps": [False, False, False]}, every
    agreed = _node(call % (json.dumps(rows), json.dumps(cols), json.dumps("accepted")))
    # the second goal is served only by a draft, so with drafts hidden it is a gap
    assert agreed == {"rows": [True, True, False], "cols": [True, False],
                      "gaps": [False, True, False]}, agreed


def test_goals_page_loads_the_matrix_script():
    assert "goal-matrix.js" in BODY


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
