"""The glossary and data-model URLs of the old schema are gone (DR-039)."""
import os
from pathlib import Path
import sys
import tempfile


HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures/wiki"

with tempfile.TemporaryDirectory() as temp:
    os.environ.update(
        WIKI_DIR=str(FIXTURE),
        DASH_STARTUP_GRACE="3600",
        DASH_HEARTBEAT_GRACE="3600",
    )
    sys.path.insert(0, str(HERE.parent))
    import app

    client = app.app.test_client()
    for old in ("/glossary", "/graph/glossary", "/data-model"):
        response = client.get(old)
        assert response.status_code == 404, (old, response.status_code)

    for route in ("/", "/commons", "/domain-terms", "/graph/domain-terms",
                  "/entity-diagram", "/req42/models"):
        body = client.get(route).get_data(as_text=True)
        for old in ("/glossary", "/graph/glossary", "/data-model"):
            assert f'href="{old}"' not in body and f'href="{old}?' not in body, route

print("domain routes: passed")
