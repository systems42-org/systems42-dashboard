"""The goal coverage matrix stays inside its card. With many FR columns the
table scrolls inside the card, the goal column stays put, and the page itself
never scrolls sideways (QR-001). The lead names no decision record that this
wiki does not have. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_goal_matrix_fits.py
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
CSS = (HERE / "static" / "style.css").read_text(encoding="utf-8")
TPL = (HERE / "templates" / "goals.html").read_text(encoding="utf-8")


def _rule(selector):
    m = re.search(re.escape(selector) + r"\s*\{([^}]*)\}", CSS)
    assert m, selector
    return m.group(1)


def test_card_scrolls_its_table():
    card = _rule(".goal-matrix-card")
    assert re.search(r"overflow-x:\s*auto", card), card
    assert "overflow: visible" not in card, card


def test_goal_column_stays_put():
    assert "position: sticky" in _rule(".goal-matrix-card tbody td.gm-row-head")
    assert "position: sticky" in _rule(".goal-matrix-card thead th.gm-corner")


def test_goal_column_leaves_room_on_a_phone():
    # 16rem of a 320 px screen left one column in view: the goal column
    # shrinks with the viewport, so several columns stay visible beside it
    corner = _rule(".goal-matrix-card thead th.gm-corner")
    assert re.search(r"min-width:\s*min\(16rem,\s*\d+vw\)", corner), corner
    # and a goal ID does not break at its hyphen in the narrower column
    assert "white-space: nowrap" in _rule(".goal-matrix-card tbody td.gm-row-head code")


def test_lead_names_no_foreign_decision():
    lead = re.search(r'<section class="goal-matrix">(.*?)<div class="goal-matrix-card">', TPL, re.S).group(1)
    assert "DR-018" not in lead and "DR-011" not in lead, lead


def test_goal_titles_use_page_ink():
    assert "color: inherit" in _rule(".goal-card-head h2 a")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
