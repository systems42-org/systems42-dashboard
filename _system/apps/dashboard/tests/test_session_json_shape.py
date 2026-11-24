"""The session endpoints answer 400 to a JSON body that is not an object.

/ping, /leaving, /settings and /disconnect-all read `client_id` (and
`hidden`) from a JSON object. An array, string, number or boolean used to
reach `.get()` and raise AttributeError (HTTP 500, issue #184). Now each of
them gets the same 400 and the session state stays as it was. No body, an
unreadable body and `null` still count as an empty object.

Run from the dashboard dir:
    .venv/bin/python tests/test_session_json_shape.py
"""
import json
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
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py

import app  # noqa: E402
import settings  # noqa: E402
import session  # noqa: E402

ROUTES = ["/ping", "/leaving", "/settings", "/disconnect-all"]
# Truthy and falsy values of every JSON type that is not an object. The falsy
# ones used to pass as an empty object through `or {}`.
NOT_OBJECTS = ['["x"]', "[]", '"x"', '""', "7", "0", "1.5", "true", "false"]
NOT_AN_OBJECT = {"error": "not-an-object"}

_shutdowns = []
session._shutdown = _shutdowns.append  # never signal the test process


def _reset():
    with session._lifecycle_lock:
        session._clients.clear()
        session._leaving.clear()
        session._first_seen.clear()
        session._user_agents.clear()
        session._names.clear()
        session._facilitator = None
        session._ever_connected = False
    session.set_view([])
    del _shutdowns[:]


def _state():
    with session._lifecycle_lock:
        return (dict(session._clients), dict(session._leaving), dict(session._first_seen),
                dict(session._user_agents), dict(session._names), session._facilitator,
                session._ever_connected, list(settings.dashboard_config()["hidden"]), list(_shutdowns))


def _post(client, route, body):
    return client.post(route, data=body, content_type="application/json")


def test_a_body_that_is_not_an_object_is_a_400_on_every_route():
    _reset()
    client = app.app.test_client()
    for route in ROUTES:
        for body in NOT_OBJECTS:
            resp = _post(client, route, body)
            assert resp.status_code == 400, (route, body, resp.status_code)
            assert resp.get_json() == NOT_AN_OBJECT, (route, body, resp.data)


def test_a_rejected_body_changes_no_session_state():
    # "anon" is the facilitator here: the worst case, because a body read as
    # an empty object would act with the facilitator's rights.
    _reset()
    client = app.app.test_client()
    assert client.post("/ping").get_json()["is_facilitator"] is True
    session.set_view(["C6"])
    before = _state()
    for route in ROUTES:
        for body in NOT_OBJECTS:
            assert _post(client, route, body).status_code == 400
            assert _state() == before, (route, body)
    assert settings.dashboard_config()["hidden"] == ["C6"]   # /settings saved nothing
    assert _shutdowns == []              # /disconnect-all stopped nothing


def test_a_rejected_first_request_does_not_count_as_a_connected_page():
    _reset()
    client = app.app.test_client()
    for body in NOT_OBJECTS:
        _post(client, "/ping", body)
    with session._lifecycle_lock:
        assert session._clients == {} and session._ever_connected is False


def test_no_body_an_unreadable_body_and_null_still_mean_an_empty_object():
    for body in [None, "", "{not json", "null"]:
        _reset()
        client = app.app.test_client()
        resp = client.post("/ping") if body is None else _post(client, "/ping", body)
        assert resp.status_code == 200, (body, resp.status_code)
        assert resp.get_json() == {"nickname": "Yoda", "is_facilitator": True}
        with session._lifecycle_lock:
            assert list(session._clients) == ["anon"]
        resp = client.post("/leaving") if body is None else _post(client, "/leaving", body)
        assert resp.status_code == 204, (body, resp.status_code)
        with session._lifecycle_lock:
            assert list(session._leaving) == ["anon"]
        # "anon" holds the role, `hidden` is missing: the documented 400.
        resp = client.post("/settings") if body is None else _post(client, "/settings", body)
        assert resp.status_code == 400, (body, resp.status_code)
        assert resp.get_json() == {"error": "unknown", "unknown": []}
        resp = (client.post("/disconnect-all") if body is None
                else _post(client, "/disconnect-all", body))
        assert resp.status_code == 204, (body, resp.status_code)
        assert _shutdowns == ["disconnect-all requested by facilitator"]


def test_valid_objects_still_work():
    _reset()
    client = app.app.test_client()
    yoda = json.dumps({"client_id": "yoda"})
    luke = json.dumps({"client_id": "luke"})
    assert _post(client, "/ping", yoda).get_json() == {
        "nickname": "Yoda", "is_facilitator": True}
    assert _post(client, "/ping", luke).get_json()["is_facilitator"] is False

    assert _post(client, "/leaving", luke).status_code == 204
    with session._lifecycle_lock:
        assert list(session._leaving) == ["luke"]

    body = json.dumps({"client_id": "luke", "hidden": ["C6"]})
    assert _post(client, "/settings", body).status_code == 403
    assert settings.dashboard_config()["hidden"] == []
    body = json.dumps({"client_id": "yoda", "hidden": ["C6"]})
    resp = _post(client, "/settings", body)
    assert resp.status_code == 200
    assert resp.get_json() == {"ok": True, "hidden": ["C6"]}
    assert settings.dashboard_config()["hidden"] == ["C6"]

    assert _post(client, "/disconnect-all", luke).status_code == 403
    assert _shutdowns == []
    assert _post(client, "/disconnect-all", yoda).status_code == 204
    assert _shutdowns == ["disconnect-all requested by facilitator"]


if __name__ == "__main__":
    test_a_body_that_is_not_an_object_is_a_400_on_every_route()
    test_a_rejected_body_changes_no_session_state()
    test_a_rejected_first_request_does_not_count_as_a_connected_page()
    test_no_body_an_unreadable_body_and_null_still_mean_an_empty_object()
    test_valid_objects_still_work()
    print("all session JSON shape tests passed")
