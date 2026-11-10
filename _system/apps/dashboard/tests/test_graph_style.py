"""Term-network readability contract (DR-023, 2026-10-12 amendment): the shared
graph module styles nodes from the page's theme tokens — card fill, ink text, a
thick type-coloured frame — instead of a hard-wired dark palette, and re-styles
when the theme toggles. No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_graph_style.py
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JS = (ROOT / "static" / "glossary-graph.js").read_text(encoding="utf-8")
CSS = (ROOT / "static" / "style.css").read_text(encoding="utf-8")
GRAPH = (ROOT / "templates" / "graph.html").read_text(encoding="utf-8")
DETAIL = (ROOT / "templates" / "detail.html").read_text(encoding="utf-8")

TYPE_TOKENS = ["--layer-glo-ink", "--layer-dm-ink", "--layer-stk-ink",
               "--layer-eif-ink", "--layer-goal-ink", "--layer-rest-ink"]


def test_module_parses():
    node = shutil.which("node")
    if not node:
        print("  (node not found — syntax check skipped)")
        return
    subprocess.run([node, "--check", str(ROOT / "static" / "glossary-graph.js")], check=True)


def test_nodes_are_framed_boxes_on_theme_tokens():
    assert "'text-outline-width': 0" in JS, "labels inside opaque boxes need no halo"
    assert "'shape': 'round-rectangle'" in JS and "'shape': 'diamond'" not in JS and "'shape': 'hexagon'" not in JS
    for tok in ("--card", "--ink", "--ink-dim", "--accent", "--font-text", *TYPE_TOKENS):
        assert f"token('{tok}'" in JS, tok
    assert re.search(r"'background-color': t\.card", JS), "fill is the card colour, not a type colour"
    assert "MutationObserver" in JS and "data-theme" in JS, "must re-style on theme toggle"
    assert "document.fonts" in JS and "AQ_GLOSSARY_GRAPH.ready(" in GRAPH, \
        "label boxes are measured after the web font has loaded"


def test_neighbour_labels_are_id_plus_clipped_title_with_tooltip():
    assert "TITLE_CLIP" in JS and ("\\u2026" in JS or "\u2026" in JS)
    assert "graph-tip" in JS and "renderedBoundingBox" in JS
    assert ".graph-tip {" in CSS


def test_type_tokens_exist_in_both_themes_and_drive_legend_and_buttons():
    dark = CSS[CSS.index(":root {"):CSS.index(':root[data-theme="light"]')]
    light = CSS[CSS.index(':root[data-theme="light"]'):CSS.index("* { box-sizing")]
    for tok in TYPE_TOKENS:
        assert f"{tok}:" in dark and f"{tok}:" in light, tok
    legend = CSS[CSS.index(".lg-dot {"):CSS.index(".graph-tip {")]
    assert "background: var(--card)" in legend, "legend swatches are frames like the nodes"
    for t in ("GLO", "DM", "STK", "EIF", "GOAL", "REST"):
        assert f".lg-{t} {{ border-color: var(--layer-{t.lower()}-ink)" in legend, t
    assert not re.search(r"\.layer-(DM|STK|EIF|GOAL|REST)\s*\{[^}]*#[0-9a-f]{6}", CSS), \
        "layer buttons take their colour from the tokens"


def test_both_views_use_the_shared_style_and_attach():
    assert "AQ_GLOSSARY_GRAPH.style()" in GRAPH and "AQ_GLOSSARY_GRAPH.attach(" in GRAPH
    assert "AQ_GLOSSARY_GRAPH.STYLE" not in GRAPH
    assert "mountEgo(" in DETAIL and "attach(cy, opts.container)" in JS
    assert "(italic)" in GRAPH and "(dashed)" in GRAPH, "legend explains state as frame style"


if __name__ == "__main__":
    test_module_parses()
    test_nodes_are_framed_boxes_on_theme_tokens()
    test_neighbour_labels_are_id_plus_clipped_title_with_tooltip()
    test_type_tokens_exist_in_both_themes_and_drive_legend_and_buttons()
    test_both_views_use_the_shared_style_and_attach()
    print("OK: term-network style follows the theme tokens")
