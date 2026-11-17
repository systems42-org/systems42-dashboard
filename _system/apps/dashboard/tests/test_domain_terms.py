"""A migrated vault uses one set of pages for terminology and model structure."""
import os
from pathlib import Path
import sys
import tempfile


with tempfile.TemporaryDirectory() as temp:
    wiki = Path(temp) / "wiki"
    terms = wiki / "domain-terms"
    terms.mkdir(parents=True)
    for name, fields in {
        "DT-001-training": '''title: Training
stereotype: entity
attributes: [{name: training_id, type: string, identifier: true}]
relationships:
- {to: "[[DT-002-session]]", label: schedules, kind: composition, multiplicity: "0..*"}
related: ["[[DT-003-review]]"]
''',
        "DT-002-session": "title: Session\nstereotype: value-object\n",
        "DT-003-review": "title: Review\n",
    }.items():
        (terms / f"{name}.md").write_text(
            f"---\nid: {name[:6]}\ntype: domain-term\nstatus: draft\n"
            f"{fields}---\n\n**Definition.** Meaning of {name}.\n", encoding="utf-8"
        )
    os.environ.update(WIKI_DIR=str(wiki), DASH_STARTUP_GRACE="3600",
                      DASHBOARD_CONFIG=str(Path(temp) / "dashboard.yaml"))
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import app

    with app.app.test_client() as client:
        graph = app.build_glossary_graph()
        assert {n["data"]["id"] for n in graph["nodes"]} == {
            "DT-001-training", "DT-002-session", "DT-003-review"
        }
        assert {e["data"]["kind"] for e in graph["edges"]} == {"related", "composition"}
        assert {e["data"]["kind"] for e in app.build_glossary_graph("structured")["edges"]} == {"composition"}
        assert {e["data"]["kind"] for e in app.build_glossary_graph("related")["edges"]} == {"related"}
        diagram = app.build_data_model_full_diagram()
        assert 'Training *-- "0..*" Session : schedules' in diagram and "+training_id" in diagram
        assert "Review" not in diagram and "<<term>>" not in diagram
        for url, expected in (
            ("/domain-terms", "/page/domain-terms/DT-003-review"),
            ("/graph/domain-terms?edges=structured", "Structured relationships"),
            ("/entity-diagram", "/graph/domain-terms"),
            ("/req42/models", "classDiagram"),
            ("/page/domain-terms/DT-001-training", "Meaning of DT-001-training."),
        ):
            response = client.get(url)
            assert response.status_code == 200 and expected in response.get_data(as_text=True), url
    glossary = wiki / "glossary"
    models = wiki / "data-models"
    glossary.mkdir()
    models.mkdir()
    (glossary / "GLO-004-policy.md").write_text(
        "---\nid: GLO-004\ntitle: Policy\nstereotype: entity\n---\n", encoding="utf-8"
    )
    (models / "DM-005-legacy.md").write_text(
        '---\nid: DM-005\ntitle: Legacy\nstereotype: entity\n'
        'relationships: [{target: "[[GLO-004-policy]]", kind: association, cardinality: "1..n"}]\n---\n',
        encoding="utf-8"
    )
    with app.app.test_request_context("/req42"):
        tile = app.build_section_tile(app.catalog.SECTION_BY_ID["R4"])
        assert tile["count"] == 3
        assert next(row for row in tile["rows"] if row["title"] == "Entity diagram")["pages"] == 3
        assert 'Legacy --> "1..n" Policy' in app.build_data_model_full_diagram()
    with app.app.test_client() as client:
        commons = client.get("/commons").get_data(as_text=True)
        assert "shared by both peaks · 4 pages" in commons
        requirements = client.get("/req42").get_data(as_text=True)
        assert "goals, needs, constraints · 1 page" in requirements
print("domain terms: passed")
