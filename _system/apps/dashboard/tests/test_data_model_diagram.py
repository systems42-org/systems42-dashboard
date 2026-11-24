"""The entity diagram (R4) — a projection, like every other diagram here.

A domain term with `stereotype: entity | value-object | sum-type` is a class.
It holds identity, `attributes:` and a `relationships:` list in frontmatter,
which is where the edges come from. Body prose is for humans, frontmatter is
for the projection, exactly as `flows:` works for the context diagram (DR-026).
A term without such a stereotype stays out of the model.

Run from the dashboard dir:
    .venv/bin/python tests/test_data_model_diagram.py
"""
import os
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues",
]

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
(_tmp / "wiki.yaml").write_text("system_name: System X\n", encoding="utf-8")
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import project.terms  # noqa: E402

_DT = _wiki / "domain-terms"


def _dt(num, title, context, attributes=(), relationships=(), stereotype="entity", parent=()):
    front = [
        "---", f"id: DT-{num}", "type: domain-term", f"title: {title}",
        "status: draft", "created: 2026-09-09", "updated: 2026-09-09",
        "sources: []", "related: []", "tags: [domain-term]", "aliases: []",
        f"bounded-context: {context}", f"parent: [{', '.join(parent)}]",
    ]
    if stereotype:
        front += [f"stereotype: {stereotype}", "source-of-truth: System X"]
    front += ["attributes:"] + [f"  - {{name: {a}, type: text}}" for a in attributes]
    front += ["relationships:"] + [f"  - {{ {r} }}" for r in relationships]
    front += ["---", "", f"# {title}", "", "**Definition.** A thing.", ""]
    _DT.joinpath(f"DT-{num}-{title.lower().replace(' ', '-')}.md").write_text(
        "\n".join(front), encoding="utf-8")


# Catalog context: Artwork owns Lots, and inherits from Asset.
_dt("001", "Artwork", "Catalog", attributes=["id", "title"], relationships=[
    "label: contains, to: \"[[DT-002-lot]]\", multiplicity: 1..*, kind: composition",
    "label: is a, to: \"[[DT-004-asset]]\", kind: generalization",
    "label: dangles, to: \"[[DT-999-nowhere]]\", kind: association",
])
_dt("002", "Lot", "Catalog", attributes=["id", "lot-number"])
_dt("004", "Asset", "Catalog", attributes=["id"])
# a second bounded context, so the filter has something to exclude
_dt("003", "Payment", "Billing", attributes=["amount"])
# a sum-type variant: `parent:` alone must draw the inheritance (DR-019)
_dt("005", "Sold Artwork", "Catalog", parent=['"[[DT-001-artwork]]"'])
# no stereotype -> not in the model
_dt("006", "Tour", "Catalog", stereotype=None)
# a German title: the ASCII identifier must not swallow the umlaut
_dt("007", "Durchführungsart", "Catalog", stereotype="value-object")


def _diagram(**kw):
    d = project.terms.build_data_model_full_diagram(**kw)
    assert d, f"no diagram projected for {kw or 'the whole model'}"
    return d


def test_a_structured_term_becomes_a_class_with_its_attributes():
    d = _diagram()
    assert "classDiagram" in d, d
    assert "class Artwork" in d, d
    assert "+id" in d and "+title" in d, d


def test_a_multi_word_entity_keeps_its_word_boundaries():
    """"Sold Artwork" must read as SoldArtwork, not Soldartwork. Both are legal
    mermaid; only one is legible on a projector."""
    assert "class SoldArtwork" in _diagram(), _diagram()


def test_a_hyphenated_attribute_name_survives():
    """`lot-number` is an ordinary field name. Dropping it was silent — the
    attribute just stopped existing in the box and in the table."""
    assert "+lot-number" in _diagram(), _diagram()


def test_a_value_object_is_marked_with_its_stereotype():
    assert "<<value-object>>" in _diagram(), _diagram()


def test_an_umlaut_survives_as_label_and_is_transliterated_in_the_identifier():
    """Splitting on [^A-Za-z0-9] treated "ü" as a word boundary, so the box read
    "DurchfHrungsart". The identifier now uses the conventional ASCII spelling
    and the box carries the real title as a mermaid class label."""
    d = _diagram()
    assert 'class Durchfuehrungsart["Durchführungsart"]' in d, d
    assert "DurchfHrungsart" not in d, d


def test_a_multi_word_title_is_labelled_with_its_wording():
    """`SoldArtwork` is the identifier; the wall should read "Sold Artwork"."""
    assert 'class SoldArtwork["Sold Artwork"]' in _diagram(), _diagram()


def test_an_ascii_single_word_title_needs_no_label():
    d = _diagram()
    assert "class Artwork {" in d, d
    assert 'Artwork["Artwork"]' not in d, "a label that repeats the identifier is noise"


def test_a_term_without_stereotype_stays_out_of_the_model():
    """The terminology is not the data model. Only a structured term is drawn."""
    assert "Tour" not in _diagram()


def test_relationships_carry_verb_cardinality_and_kind():
    """`multiplicity:` applies at the TARGET end, and only there —
    inventing a source multiplicity from it puts a meaningless "0" on the
    owning side of any `0..*`."""
    d = _diagram()
    assert any('Artwork *-- "1..*" Lot : contains' in l for l in d.splitlines()), d


def test_a_parent_link_draws_inheritance_without_repeating_it():
    """A variant names its sum type in `parent:` and nowhere else. Making the
    author restate that as a relationship entry would be one fact in two
    places, and the two would drift."""
    assert any("Artwork <|-- SoldArtwork" in l for l in _diagram().splitlines()), _diagram()


def test_inheritance_points_from_the_base_class():
    """`A is-a B` draws `B <|-- A`, which is the direction mermaid expects."""
    assert any("Asset <|-- Artwork" in l for l in _diagram().splitlines())


def test_a_relationship_to_a_missing_page_is_dropped():
    assert "DT-999" not in _diagram() and "nowhere" not in _diagram().lower()


def test_the_bounded_context_filter_narrows_the_diagram():
    d = _diagram(context="Billing")
    assert "class Payment" in d, d
    assert "Artwork" not in d, "another context's entities must not leak in"


def test_focus_keeps_one_entity_and_its_direct_neighbours():
    d = _diagram(focus="DT-001-artwork")
    assert "class Artwork" in d and "class Lot" in d and "class Asset" in d, d
    assert "Payment" not in d, "focus is one hop, not the whole vault"


def test_a_filter_that_matches_nothing_projects_nothing():
    """The view guards on entities, not on the diagram, so None is a valid
    answer and must stay one (see build_data_model_full_diagram's contract)."""
    assert project.terms.build_data_model_full_diagram(context="No Such Context") is None


def test_the_contexts_are_listed_for_the_filter_ui():
    assert project.terms.data_model_contexts() == ["Billing", "Catalog"], project.terms.data_model_contexts()


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn()
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
    if failed:
        sys.exit(1)
    print(f"ok — {len(fns)} checks")
