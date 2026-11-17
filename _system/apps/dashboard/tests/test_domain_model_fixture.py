"""The example opened for visual inspection also renders in both model views."""
import os
from pathlib import Path
import shutil
import sys
import tempfile


HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "domain-model"

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    shutil.copytree(FIXTURE, root / "example")
    example = root / "example"
    os.environ.update(
        WIKI_DIR=str(example / "wiki"),
        WIKI_CONFIG=str(example / "wiki.yaml"),
        REPO_DIR=str(example),
        RAW_SOURCES_DIR=str(example / "raw/sources"),
        DOCS_DIR=str(example / "docs"),
        DASHBOARD_CONFIG=str(root / "dashboard.yaml"),
        DASH_STARTUP_GRACE="3600",
        DASH_HEARTBEAT_GRACE="3600",
    )
    sys.path.insert(0, str(HERE.parent))
    import app

    with app.app.test_request_context():
        diagram = app.build_data_model_full_diagram()
        assert 'Customer --> "0..*" Order : places' in diagram
        assert 'Order *-- "1..*" OrderLine : contains' in diagram
        assert "+customer_id" in diagram and "+quantity" in diagram
        assert "ReviewPolicy" not in diagram
        graph = app.build_glossary_graph()
        assert len(graph["nodes"]) == 4 and len(graph["edges"]) == 3
        assert len(app.build_glossary_graph("related")["edges"]) == 1
        assert len(app.build_glossary_graph("structured")["edges"]) == 2

    with app.app.test_client() as client:
        for route in ("/glossary", "/graph/glossary", "/data-model", "/req42/models"):
            response = client.get(route)
            assert response.status_code == 200, route
            assert "Order" in response.get_data(as_text=True), route
        for file in (example / "wiki/domain-terms").glob("*.md"):
            assert client.get(f"/page/domain-terms/{file.stem}").status_code == 200

print("domain model fixture: passed")
