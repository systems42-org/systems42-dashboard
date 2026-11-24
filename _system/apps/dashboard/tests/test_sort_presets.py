"""Sort presets live in the dashboard, not in the metamodel (FR-021, CON-006). No pytest.

The presets are web.common.SORT_PRESETS; the metamodel declares none.

Run from the dashboard dir:
    .venv/bin/python tests/test_sort_presets.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
(_tmp / "wiki").mkdir()
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402
import web.common  # noqa: E402
import metamodel  # noqa: E402


def test_presets_per_type():
    want = {
        "functional-requirement": [{"label": "Priority › release › order", "keys": ["priority", "release", "order"]}],
        "issue": [{"label": "Status › severity", "keys": ["status", "severity"]}],
        "decision-record": [{"label": "Newest first", "keys": ["decided"]}],
        "domain-term": [{"label": "A to Z", "keys": ["title"]}],
        "stakeholder": [{"label": "Influence › interest", "keys": ["influence", "interest"]}],
        "quality-requirement": [{"label": "Priority", "keys": ["priority"]}],
    }
    for name, orders in want.items():
        assert web.common.sort_presets(name) == orders, (name, web.common.sort_presets(name))
    assert web.common.sort_presets("constraint") == []
    assert web.common.sort_presets("no-such-type") == []


def test_no_type_page_declares_sort_orders():
    # CON-006: the metamodel knows nothing about how the dashboard sorts
    for p in sorted(metamodel.METAMODEL_DIR.glob("types/*.md")):
        assert "sort_orders:" not in p.read_text(encoding="utf-8"), p.name
    assert "sort_orders" not in (metamodel.METAMODEL_DIR / "meta-metamodel.md").read_text(encoding="utf-8")


def test_a_preset_cannot_be_changed_through_its_result():
    web.common.sort_presets("issue")[0]["keys"].append("x")
    assert web.common.SORT_PRESETS["issue"][0]["keys"] == ["status", "severity"]


def test_domain_terms_list_takes_the_domain_term_type():
    # the metamodel's type for wiki/domain-terms/ (meta DR-039)
    assert metamodel.type_for_folder("domain-terms") == "domain-term"
    tpl = (Path(app.__file__).parent / "templates" / "glossary.html").read_text(encoding="utf-8")
    assert 'list_spec("domain-term")' in tpl
    assert web.common.list_spec("domain-term")["orders"] == [{"label": "A to Z", "keys": ["title"]}]


if __name__ == "__main__":
    test_presets_per_type()
    test_no_type_page_declares_sort_orders()
    test_a_preset_cannot_be_changed_through_its_result()
    test_domain_terms_list_takes_the_domain_term_type()
    print("ALL PASSED")
