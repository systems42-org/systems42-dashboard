"""The Quality block (/req42/quality) lists each quality requirement with its
Q42 dimensions, priority and quality scenario, and links its title to the page — the
generic block list used to show the bare, unlinked title only. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_quality_block.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_qr = _tmp / "wiki" / "quality-requirements"
_qr.mkdir(parents=True); (_tmp / "sources").mkdir()
(_qr / "QR-001-fast-filter.md").write_text("""---
id: QR-001
type: quality-requirement
title: "Filterwechsel ohne Verzögerung"
status: draft
dimensions: [efficient, usable]
priority: should
---

# Filterwechsel ohne Verzögerung

**Scenario (Q42 quality scenario).**
- **Source.** Besucher:in
- **Stimulus.** ändert einen Filter
- **Environment.** *Normalbetrieb*
- **Response.** atrium aktualisiert die Trefferliste
- **Measure.** höchstens 300 ms

**Applies to.** Training-Finder
""", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

client = app.app.test_client()


def test_quality_rows_carry_link_dimensions_priority_and_scenario():
    body = client.get("/req42/quality").get_data(as_text=True)
    assert 'href="/page/quality-requirements/QR-001-fast-filter"' in body
    assert ">efficient<" in body and ">usable<" in body and ">should<" in body
    for part in ("Stimulus", "ändert einen Filter", "Response", "Normalbetrieb"):
        assert part in body, part
    assert "<em>Normalbetrieb</em>" in body
    assert '<dd class="qr-measure">höchstens 300 ms</dd>' in body
    # the next bold lead after the scenario is not swallowed into Measure
    assert "Applies to" not in body


if __name__ == "__main__":
    test_quality_rows_carry_link_dimensions_priority_and_scenario()
    print("ok")
