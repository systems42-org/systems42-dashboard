"""`create_app()` builds the Flask app (issue #185). No pytest.

The routes are blueprints in `web/`. What applies to every route (the request
hooks, the template context, the 404 page) is registered on the app, not on a
blueprint, and no blueprint moves a URL. `app.app` is the one app Gunicorn,
the site export and the tests use. A second call gives a second app over the
same module state.

Run from the dashboard dir:
    .venv/bin/python tests/test_app_factory.py
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
(_tmp / "wiki").mkdir()
(_tmp / "sources").mkdir()
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import flask  # noqa: E402

import app  # noqa: E402


def _rules(a) -> list[tuple[str, str, tuple]]:
    return sorted((r.rule, r.endpoint, tuple(sorted(r.methods))) for r in a.url_map.iter_rules())


def test_app_app_is_the_flask_app():
    assert isinstance(app.app, flask.Flask)
    assert app.app.name == "app", app.app.name


def test_every_route_but_static_is_in_a_blueprint_without_a_prefix():
    for rule in app.app.url_map.iter_rules():
        if rule.endpoint == "static":
            assert rule.rule == "/static/<path:filename>", rule.rule
            continue
        assert "." in rule.endpoint, f"{rule.rule} is registered on the app itself"
    assert set(app.app.blueprints) == {"pages", "projections", "search_session", "help", "brand"}
    for bp in app.app.blueprints.values():
        assert bp.url_prefix is None and bp.subdomain is None, bp.name
        assert bp.static_folder is None and bp.template_folder is None, bp.name


def test_hooks_context_and_the_404_page_are_on_the_app():
    """Registered for every route (the key None), never for one blueprint."""
    a = app.app
    assert a.before_request_funcs == {None: [app.read_sections]}, a.before_request_funcs
    assert a.after_request_funcs == {None: [app._page_policy]}, a.after_request_funcs
    # Flask itself adds its default processor (g, request) per blueprint
    ours = {key: [f for f in funcs if not f.__module__.startswith("flask.")]
            for key, funcs in a.template_context_processors.items()}
    assert ours.pop(None) == [app.inject_refresh_time, app.inject_identity,
                              app.inject_metamodel_version, app.inject_area, app.inject_nav], ours
    assert not any(ours.values()), ours
    assert list(a.error_handler_spec[None][404].values()) == [app.not_found]
    assert not any(spec for key, spec in a.error_handler_spec.items() if key is not None)
    for name in ("csp_nonce", "static_url", "list_spec", "type_folder"):
        assert name in a.jinja_env.globals, name


def test_a_second_call_gives_a_second_app_with_the_same_routes():
    other = app.create_app()
    assert other is not app.app
    assert _rules(other) == _rules(app.app)
    for a in (app.app, other):
        client = a.test_client()
        home = client.get("/")
        assert home.status_code == 200, home.status_code
        assert "nonce-" in home.headers["Content-Security-Policy"]
        missing = client.get("/no-such-page")
        assert missing.status_code == 404 and b"<nav" in missing.data, missing.status_code


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
