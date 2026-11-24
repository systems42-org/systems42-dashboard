"""A framework block without `title:` shows its ID wherever a block's name
shows: in the section navigation and on `/metamodel` (issue 205). With a
title both show the title. A block without an ID and a block entry that is
plain text are left out, and no route fails. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_block_without_title.py
"""
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
REPO = Path(__file__).resolve().parents[4]

_repo = Path(tempfile.mkdtemp())
(_repo / "wiki" / "activity-models").mkdir(parents=True)
(_repo / "raw" / "sources").mkdir(parents=True)
(_repo / "_system").mkdir()
(_repo / "_system" / "wiki.yaml").write_text('system_name: "Demo"\n', encoding="utf-8")
_mm = _repo / "_system" / "metamodel"
shutil.copytree(REPO / "_system" / "metamodel", _mm)
shutil.copytree(REPO / "_system" / "anchors", _repo / "_system" / "anchors")
(_repo / "wiki" / "activity-models" / "ACT-001-order.md").write_text(
    "---\nid: ACT-001\ntype: activity-model\ntitle: Order\nstatus: draft\nrelated: []\n---\n\n# Order\n",
    encoding="utf-8")

# R4 is the block the type activity-model names (`block: R4`).
_FW = _mm / "frameworks" / "fw-req42.md"
_R4 = re.compile(r"^  - \{id: R4,.*\}\n", re.MULTILINE)
_ORIGINAL = _FW.read_text(encoding="utf-8")
assert _R4.search(_ORIGINAL), "fw-req42.md declares no block R4"
assert "block: R4\n" in (_mm / "types" / "type-activity-model.md").read_text(encoding="utf-8")


def _declare(r4: str) -> None:
    """Write the framework with `r4` as its block R4, followed by a block
    without an ID and a block entry that is plain text."""
    _FW.write_text(_R4.sub(lambda m: f"  - {r4}\n"
                           '  - {number: "98", title: "Block without an ID", types: [], scope: in}\n'
                           "  - a block that is plain text\n", _ORIGINAL, count=1), encoding="utf-8")


_declare("{id: R4, types: [activity-model], scope: in}")

os.environ["REPO_DIR"] = str(_repo)
for _k in ("WIKI_DIR", "WIKI_CONFIG", "RAW_SOURCES_DIR", "DOCS_DIR", "METAMODEL_DIR", "ANCHORS_DIR",
           "NOTATIONS_DIR"):
    os.environ.pop(_k, None)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(HERE))

import app  # noqa: E402
import catalog  # noqa: E402
import metamodel  # noqa: E402

client = app.app.test_client()


def _get(route: str) -> str:
    r = client.get(route)
    assert r.status_code == 200, (route, r.status_code)
    return r.get_data(as_text=True)


def _tile_title(html: str) -> str:
    """The name on the tile of section R4, the entry in the section navigation."""
    m = re.search(r'<a id="tile-r4".*?<h2 class="tile-title">(.*?)</h2>', html, re.DOTALL)
    assert m, "no tile for section R4"
    return m.group(1).strip()


def _graph_labels(html: str) -> dict[str, str]:
    """Block node id -> label, from the graph data `/metamodel` embeds."""
    m = re.search(r'<script[^>]*id="mm-graph-data"[^>]*>(.*?)</script>', html, re.DOTALL)
    assert m, "no graph data on /metamodel"
    return {n["data"]["id"]: n["data"]["label"] for n in json.loads(m.group(1))["nodes"]
            if n["data"].get("is_block")}


def _shown(name: str) -> None:
    """`name` is what every view shows for block R4."""
    assert metamodel.block_title({"id": "R4", "title": name if name != "R4" else None}) == name
    section = next(s for s in catalog.build(metamodel.blocks()) if s["id"] == "R4")
    assert section["title"] == name, section
    loaded = next(b for b in metamodel.load()["blocks"] if b["id"] == "R4")
    assert loaded["title"] == name, loaded

    assert _tile_title(_get("/req42")) == name, _tile_title(_get("/req42"))
    assert f"<h1 class=\"page-h1\"><span class=\"req42-num\">R4</span> {name} " in _get("/req42/models")

    page = _get("/metamodel")
    assert ('<span class="mm-block-chip">R4</span> '
            f'<span class="mm-block-title">{name}</span>') in page, name
    assert _graph_labels(page)["block:R4"] == f"R4 · {name}", _graph_labels(page)


def test_a_block_without_a_title_shows_its_id():
    _shown("R4")


def test_blocks_without_an_id_or_as_plain_text_are_left_out():
    loaded = metamodel.load()["blocks"]
    assert all(isinstance(b, dict) and b["id"] for b in loaded), loaded
    assert sorted(b["id"] for b in loaded) == sorted(b["id"] for b in metamodel.blocks())
    for route in ("/", "/req42", "/arc42", "/commons", "/metamodel", "/req42/models",
                  "/page/activity-models/ACT-001-order"):
        assert "Block without an ID" not in _get(route), route
    # the count on /metamodel is of the blocks that are shown
    n_in = sum(1 for b in loaded if b.get("scope") == "in")
    assert f"{n_in} of {len(loaded)} blocks are captured" in _get("/metamodel")


def test_a_title_shows_in_both_views():
    _declare('{id: R4, title: "Helper Models", types: [activity-model], scope: in}')
    _shown("Helper Models")


if __name__ == "__main__":
    test_a_block_without_a_title_shows_its_id()
    test_blocks_without_an_id_or_as_plain_text_are_left_out()
    test_a_title_shows_in_both_views()
    print("ok: a block without a title shows its ID in the navigation and on /metamodel")
