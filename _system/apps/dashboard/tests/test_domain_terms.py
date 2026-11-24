"""Domain terms carry both the terminology and the model structure (DR-039)."""
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
aliases: [Course]
attributes: [{name: training_id, type: string, identifier: true}, {name: order date}, {name: "cost {net}"}]
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
    os.environ.update(WIKI_DIR=str(wiki), DASH_STARTUP_GRACE="3600")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import app
    import project.terms

    with app.app.test_client() as client:
        graph = project.terms.build_glossary_graph()
        assert {n["data"]["id"] for n in graph["nodes"]} == {
            "DT-001-training", "DT-002-session", "DT-003-review"
        }
        assert {e["data"]["kind"] for e in graph["edges"]} == {"related", "composition"}
        assert {e["data"]["kind"] for e in project.terms.build_glossary_graph("structured")["edges"]} == {"composition"}
        assert {e["data"]["kind"] for e in project.terms.build_glossary_graph("related")["edges"]} == {"related"}
        diagram = project.terms.build_data_model_full_diagram()
        assert 'Training *-- "0..*" Session : schedules' in diagram and "+training_id" in diagram
        assert "+order date" in diagram
        assert "+cost #123;net#125;" in diagram
        summary = client.get("/entity-diagram").get_data(as_text=True)
        assert "<code>order date</code>" in summary and "<code>cost {net}</code>" in summary
        # an alias focuses the term it names
        html = client.get("/entity-diagram?focus=Course").get_data(as_text=True)
        assert "and its direct neighbours" in html
        assert "Training" in html.split("<figcaption>", 1)[1].split("</figcaption>", 1)[0]
        assert "Review" not in diagram
        for url, expected in (
            ("/domain-terms", "/page/domain-terms/DT-003-review"),
            ("/graph/domain-terms?edges=structured", "Structured relationships"),
            ("/entity-diagram", "/graph/domain-terms"),
            ("/req42/models", "classDiagram"),
            ("/page/domain-terms/DT-001-training", "Meaning of DT-001-training."),
        ):
            response = client.get(url)
            assert response.status_code == 200 and expected in response.get_data(as_text=True), url
print("domain terms: passed")
