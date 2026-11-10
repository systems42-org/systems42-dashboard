"""The vision card on /goals shows the whole vision and links to the pages. No pytest.

The regression this guards: the card showed only the first paragraph under
`## Vision`. A vision page that opens with a note such as
"> follows the Geoffrey Moore format" showed that note and nothing else, so the
vision could not be read. Nothing on /goals linked to the goal pages, and the
Vision node of the goal tree could not be clicked.

Run from the dashboard dir:
    .venv/bin/python tests/test_vision_card.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
(_wiki / "goals").mkdir(parents=True)
(_tmp / "wiki.yaml").write_text("system_name: System X\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402

(_wiki / "goals" / "GOAL-001-vision.md").write_text("""---
id: GOAL-001
type: goal
title: Trusted answers
status: draft
stereotype: vision
parent: []
---

# Trusted answers

## Vision

> follows the Geoffrey Moore format

For **everyone** who has a question, **System X** is a **view** that gives the answer.

Anyone with a question finds the answer faster than by asking a colleague.

**Objectives.** See the `parent:` backlinks.

## Impact

- **Served by:** projected.
""", encoding="utf-8")

(_wiki / "goals" / "GOAL-002-objective.md").write_text("""---
id: GOAL-002
type: goal
title: Answers without asking
status: draft
stereotype: objective
parent: ["[[GOAL-001-vision]]"]
---

# Answers without asking

- **Purpose.** Readers find answers.
""", encoding="utf-8")

_client = app.app.test_client()


def _goals_html() -> str:
    resp = _client.get("/goals")
    assert resp.status_code == 200
    return resp.get_data(as_text=True)


def test_the_vision_card_shows_every_paragraph_of_the_vision():
    html = _goals_html()
    assert "gives the answer" in html, "the Moore sentence is missing"
    assert "faster than by asking a colleague" in html, "the narrative paragraph is missing"


def test_the_vision_card_skips_notes_and_the_objectives_pointer():
    html = _goals_html()
    assert "follows the Geoffrey Moore format" not in html
    assert "See the `parent:` backlinks" not in html and "parent:</code> backlinks" not in html


def test_goal_cards_link_to_their_pages():
    html = _goals_html()
    assert 'href="/page/goals/GOAL-001-vision"' in html, "the vision card has no link to its page"
    assert 'href="/page/goals/GOAL-002-objective"' in html, "an objective card has no link to its page"


def test_the_vision_node_of_the_goal_tree_is_clickable():
    data = app.load_goals()
    tree = app._mermaid_goal_tree(data["vision"], data["objectives"])
    assert 'click V "/goals#GOAL-001"' in tree


if __name__ == "__main__":
    test_the_vision_card_shows_every_paragraph_of_the_vision()
    test_the_vision_card_skips_notes_and_the_objectives_pointer()
    test_goal_cards_link_to_their_pages()
    test_the_vision_node_of_the_goal_tree_is_clickable()
    print("test_vision_card: OK")
