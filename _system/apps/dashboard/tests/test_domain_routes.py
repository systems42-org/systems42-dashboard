"""Old model URLs preserve their filters through one permanent redirect."""
import os
from pathlib import Path
import sys
import tempfile


HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures/wiki"

with tempfile.TemporaryDirectory() as temp:
    os.environ.update(
        WIKI_DIR=str(FIXTURE),
        DASHBOARD_CONFIG=str(Path(temp) / "dashboard.yaml"),
        DASH_STARTUP_GRACE="3600",
        DASH_HEARTBEAT_GRACE="3600",
    )
    sys.path.insert(0, str(HERE.parent))
    import app

    client = app.app.test_client()
    for old, new in (
        ("/glossary", "/domain-terms"),
        ("/graph/glossary", "/graph/domain-terms"),
        ("/data-model", "/entity-diagram"),
    ):
        for query in ("", "?edges=structured", "?context=Sales%20%26%20Orders&focus=DT-001-order",
                      "?x=1&x=2&empty="):
            response = client.get(old + query)
            assert response.status_code == 301, (old, response.status_code)
            assert response.headers["Location"] == new + query
            canonical = client.get(response.headers["Location"])
            assert canonical.status_code == 200, new
            assert "Location" not in canonical.headers

    for route in ("/", "/commons", "/domain-terms", "/graph/domain-terms",
                  "/entity-diagram", "/req42/models"):
        body = client.get(route).get_data(as_text=True)
        for old in ("/glossary", "/graph/glossary", "/data-model"):
            assert f'href="{old}"' not in body and f'href="{old}?' not in body, route

print("domain routes: passed")
