"""Branding is configuration: `brand:`, `intro:` and `dashboard_version:` in
wiki.yaml. No pytest.

`brand:` names an example brand shipped in brands/ (systems42, atrium) or a
folder relative to the wiki repository root (REPO_DIR). Missing means
systems42. A folder outside the root, missing or incomplete falls back to
systems42 with a log warning, never a 500. The folder is only read.

Run from the dashboard dir:
    .venv/bin/python tests/test_brand_config.py
"""
from __future__ import annotations

import logging
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_repo = _tmp / "repo"
(_repo / "wiki").mkdir(parents=True)
(_repo / "sources").mkdir()
_cfg = _tmp / "wiki.yaml"
os.environ["WIKI_DIR"] = str(_repo / "wiki")
os.environ["RAW_SOURCES_DIR"] = str(_repo / "sources")
os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_CONFIG"] = str(_cfg)
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

_HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_HERE))

import app  # noqa: E402

client = app.app.test_client()
BRANDS = _HERE / "brands"
MARKS = ("mark-dark.svg", "mark-light.svg", "favicon.svg")


class _Records(logging.Handler):
    def __init__(self):
        super().__init__(logging.WARNING)
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


LOG = _Records()
app.app.logger.addHandler(LOG)


def configure(extra: str = "") -> None:
    _cfg.write_text('system_name: "Demo"\n' + extra, encoding="utf-8")


def make_brand(folder: Path, files=MARKS, intro: str | None = None) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for name in files:
        (folder / name).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><!-- {folder.name} {name} --></svg>',
            encoding="utf-8")
    if intro is not None:
        (folder / "intro.html").write_text(intro, encoding="utf-8")


def served(name: str) -> str:
    resp = client.get(f"/brand/{name}")
    assert resp.status_code == 200, (name, resp.status_code)
    assert resp.mimetype == "image/svg+xml", resp.mimetype
    return resp.get_data(as_text=True)


def home() -> str:
    resp = client.get("/")
    assert resp.status_code == 200, resp.status_code
    return resp.get_data(as_text=True)


def test_missing_brand_key_means_systems42():
    configure()
    for name in MARKS:
        assert served(name) == (BRANDS / "systems42" / name).read_text(encoding="utf-8"), name
    page = home()
    assert 'rel="icon" type="image/svg+xml" href="/brand/favicon.svg?v=' in page
    assert 'src="/brand/mark-dark.svg?v=' in page and 'src="/brand/mark-light.svg?v=' in page
    assert 'id="brand-intro"' in page


def test_example_brand_atrium_is_one_key_away():
    configure("brand: atrium\n")
    for name in MARKS:
        assert served(name) == (BRANDS / "atrium" / name).read_text(encoding="utf-8"), name
    page = home()
    assert 'id="atrium-splash"' in page and 'id="brand-intro"' not in page
    assert page.index('id="atrium-splash"') < page.index('class="hero"')
    sub = client.get("/glossary").get_data(as_text=True)
    assert 'id="atrium-splash"' not in sub
    assert 'src="/brand/mark-dark.svg?v=' in sub            # top bar


def test_switching_brand_is_read_live_and_changes_the_mark_url():
    configure("brand: systems42\n")
    first = home()
    configure("brand: atrium\n")
    second = home()
    url = lambda page: page.split('src="/brand/mark-dark.svg?v=', 1)[1].split('"', 1)[0]
    assert url(first) != url(second), "the cache buster must change with the brand"


def test_folder_brand_from_the_wiki_repository():
    make_brand(_repo / "brand", intro='<div id="own-intro" hidden></div>')
    configure("brand: brand/\n")
    assert "brand mark-dark.svg" in served("mark-dark.svg")
    assert "brand favicon.svg" in served("favicon.svg")
    page = home()
    assert 'id="own-intro"' in page and 'id="brand-intro"' not in page
    assert page.index('id="own-intro"') < page.index('class="hero"')


def test_folder_brand_without_intro_has_none():
    make_brand(_repo / "plain")
    configure("brand: plain\n")
    page = home()
    assert "brand-intro" not in page and "splash" not in page
    assert "plain mark-light.svg" in served("mark-light.svg")


def test_folder_brand_is_never_written():
    make_brand(_repo / "ro", intro="<div hidden></div>")
    before = {p.name: (p.stat().st_mtime_ns, p.stat().st_size) for p in (_repo / "ro").iterdir()}
    configure("brand: ro\n")
    home(); served("favicon.svg"); client.get("/glossary")
    after = {p.name: (p.stat().st_mtime_ns, p.stat().st_size) for p in (_repo / "ro").iterdir()}
    assert before == after


def _falls_back(value: str) -> None:
    LOG.messages.clear()
    configure(f"brand: {value}\n")
    page = home()
    assert served("mark-dark.svg") == (BRANDS / "systems42" / "mark-dark.svg").read_text(encoding="utf-8"), value
    assert 'id="brand-intro"' in page, value
    assert any("brand" in m and "systems42" in m for m in LOG.messages), (value, LOG.messages)


def test_path_outside_the_repository_is_refused():
    make_brand(_tmp / "outside")
    _falls_back("../outside")
    _falls_back(str(_tmp / "outside"))


def test_symlink_out_of_the_repository_is_refused():
    make_brand(_tmp / "elsewhere")
    (_repo / "linked").symlink_to(_tmp / "elsewhere")
    _falls_back("linked")


def test_missing_folder_falls_back():
    _falls_back("no-such-folder/")


def test_incomplete_folder_falls_back():
    make_brand(_repo / "half", files=("mark-dark.svg", "mark-light.svg"))
    _falls_back("half/")


def test_only_the_marks_are_served():
    make_brand(_repo / "brand", intro="<div hidden></div>")
    configure("brand: brand/\n")
    for bad in ("intro.html", "README.md", "..%2Fwiki.yaml", "nope.svg"):
        assert client.get(f"/brand/{bad}").status_code == 404, bad


def test_intro_off_hides_every_intro():
    make_brand(_repo / "brand", intro='<div id="own-intro" hidden></div>')
    markers = {"systems42": 'id="brand-intro"', "atrium": 'id="atrium-splash"', "brand/": 'id="own-intro"'}
    for brand, own in markers.items():
        for off in ("off", '"off"', "false", "no"):
            configure(f"brand: {brand}\nintro: {off}\n")
            page = home()
            for marker in markers.values():
                assert marker not in page, (brand, off, marker)
        configure(f"brand: {brand}\nintro: on\n")
        assert own in home(), brand


def test_footer_shows_the_dashboard_version():
    own = (_HERE / "VERSION").read_text(encoding="utf-8").strip()
    assert own == app.DASHBOARD_VERSION
    configure()
    page = home()
    assert f"Dashboard {own}" in page
    assert "version-mismatch" not in page


def test_matching_dashboard_version_says_nothing_more():
    configure(f'dashboard_version: "{app.DASHBOARD_VERSION}"\n')
    assert "version-mismatch" not in home()


def test_other_dashboard_version_is_named_in_one_line():
    configure('dashboard_version: "1.4.0"\n')
    page = home()
    assert 'class="version-mismatch"' in page
    line = page.split('class="version-mismatch"', 1)[1].split("</", 1)[0]
    assert "1.4.0" in line and app.DASHBOARD_VERSION in line, line
    assert "version-mismatch" in client.get("/glossary").get_data(as_text=True)


def test_wiki_config_reports_the_three_keys():
    configure()
    cfg = app.wiki_config()
    assert cfg["brand"] == "systems42" and cfg["intro"] is True and cfg["dashboard_version"] == ""
    configure("brand: atrium\nintro: off\ndashboard_version: 0.9\n")
    cfg = app.wiki_config()
    assert cfg["brand"] == "atrium" and cfg["intro"] is False and cfg["dashboard_version"] == "0.9"


if __name__ == "__main__":
    test_missing_brand_key_means_systems42()
    test_example_brand_atrium_is_one_key_away()
    test_switching_brand_is_read_live_and_changes_the_mark_url()
    test_folder_brand_from_the_wiki_repository()
    test_folder_brand_without_intro_has_none()
    test_folder_brand_is_never_written()
    test_path_outside_the_repository_is_refused()
    test_symlink_out_of_the_repository_is_refused()
    test_missing_folder_falls_back()
    test_incomplete_folder_falls_back()
    test_only_the_marks_are_served()
    test_intro_off_hides_every_intro()
    test_footer_shows_the_dashboard_version()
    test_matching_dashboard_version_says_nothing_more()
    test_other_dashboard_version_is_named_in_one_line()
    test_wiki_config_reports_the_three_keys()
    print("OK: brand configuration")
