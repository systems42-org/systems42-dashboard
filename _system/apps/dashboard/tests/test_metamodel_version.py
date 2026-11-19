"""The metamodel version check (FR-043): the release supports a set of
metamodel versions, reads the version the repository declares, and shows a
footer notice with a link to /metamodel#version when it is outside the set
or missing. It never refuses to render. No pytest dependency.

Run from the dashboard dir:
    .venv/bin/python tests/test_metamodel_version.py

Each case works on its own copy of the real metamodel in a temporary folder
(metamodel.METAMODEL_DIR), so the rest of the page renders as usual.
"""
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

_HERE = Path(__file__).resolve().parent
os.environ["WIKI_DIR"] = str(_HERE / "fixtures" / "wiki")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(_HERE.parent))

import app  # noqa: E402
import metamodel  # noqa: E402

_REAL = metamodel.METAMODEL_DIR
client = app.app.test_client()


def use_metamodel(version_line: str | None = "version: 0.1", version_file: str | None = None) -> Path:
    """A copy of the real metamodel with `version:` in meta-metamodel.md
    replaced by `version_line` (None drops it), and `version_file` as the
    text of metamodel-version.md (None: no such file)."""
    tmp = Path(tempfile.mkdtemp()) / "metamodel"
    shutil.copytree(_REAL, tmp)
    mmm = tmp / "meta-metamodel.md"
    text = mmm.read_text(encoding="utf-8")
    text = re.sub(r"^version:.*\n", "" if version_line is None else version_line + "\n",
                  text, count=1, flags=re.MULTILINE)
    mmm.write_text(text, encoding="utf-8")
    if version_file is not None:
        (tmp / "metamodel-version.md").write_text(version_file, encoding="utf-8")
    metamodel.METAMODEL_DIR = tmp
    return tmp


def get(path: str) -> str:
    r = client.get(path)
    assert r.status_code == 200, (path, r.status_code)
    return r.get_data(as_text=True)


def notice(page: str) -> str:
    """The footer notice's text, or "" when the page has none."""
    if 'class="metamodel-mismatch"' not in page:
        return ""
    return page.split('class="metamodel-mismatch">', 1)[1].split("</div>", 1)[0]


def version_section(page: str) -> str:
    return page.split('id="version"', 1)[1].split("</section>", 1)[0]


def test_release_supports_exactly_0_1():
    assert metamodel.SUPPORTED_VERSIONS == ("0.1",)


def test_supported_version_shows_no_notice():
    use_metamodel("version: 0.1")
    check = metamodel.version_check()
    assert check == {"version": "0.1", "file": "meta-metamodel.md",
                     "supported": ["0.1"], "state": "supported"}, check
    assert notice(get("/")) == ""
    section = version_section(get("/metamodel"))
    assert "<code>0.1</code>, from <code>_system/metamodel/meta-metamodel.md</code>" in section, section
    assert f"Dashboard {app.DASHBOARD_VERSION} supports" in section, section
    assert "To fix it" not in section


def test_version_outside_the_set_shows_a_notice_on_every_page():
    use_metamodel("version: 0.3")
    assert metamodel.version_check()["state"] == "unsupported"
    for path in ("/", "/domain-terms", "/metamodel", "/help"):
        line = notice(get(path))
        assert "version 0.3" in line and "supports 0.1" in line, (path, line)
        assert app.DASHBOARD_VERSION in line, (path, line)
        assert 'href="/metamodel#version"' in line, (path, line)


def test_metamodel_page_names_both_versions_and_the_next_step():
    use_metamodel("version: 0.3")
    section = version_section(get("/metamodel"))
    assert "<code>0.3</code>" in section and "<code>0.1</code>" in section, section
    assert f"Dashboard {app.DASHBOARD_VERSION} does not support metamodel version 0.3" in section, section
    assert "dashboard_version:" in section and "_system/metamodel/" in section, section


def test_missing_version_has_its_own_wording():
    use_metamodel(None)
    check = metamodel.version_check()
    assert check["state"] == "missing" and check["version"] == "" and check["file"] == "meta-metamodel.md", check
    line = notice(get("/"))
    assert "declares no version" in line and "supports 0.1" in line, line
    assert "version 0." not in line, line           # not the wording for a version outside the set
    section = version_section(get("/metamodel"))
    assert "has no <code>version:</code>" in section and "declares no version" in section, section


def test_no_metamodel_at_all_still_renders():
    metamodel.METAMODEL_DIR = Path(tempfile.mkdtemp()) / "missing"
    check = metamodel.version_check()
    assert check["state"] == "missing" and check["file"] == "", check
    assert "declares no version" in notice(get("/"))
    assert "neither <code>_system/metamodel/metamodel-version.md</code>" in version_section(get("/metamodel"))


def test_metamodel_version_file_takes_precedence():
    # the dedicated file has no `type: metamodel` (meta issue #39, point 2)
    use_metamodel("version: 0.1", "---\nversion: 0.2\n---\n\n# Metamodel version\n")
    check = metamodel.version_check()
    assert check["version"] == "0.2" and check["file"] == "metamodel-version.md", check
    assert check["state"] == "unsupported"
    assert "version 0.2" in notice(get("/"))
    use_metamodel("version: 0.9", '---\nversion: "0.1"\n---\n')
    assert metamodel.version_check()["state"] == "supported"
    # once the file exists it is the place: no fallback to meta-metamodel.md
    use_metamodel("version: 0.1", "---\ntitle: Metamodel version\n---\n")
    check = metamodel.version_check()
    assert check["state"] == "missing" and check["file"] == "metamodel-version.md", check


def test_version_is_read_as_text():
    use_metamodel("version: 0.10")                  # YAML would read the number 0.1
    check = metamodel.version_check()
    assert check["version"] == "0.10" and check["state"] == "unsupported", check


if __name__ == "__main__":
    try:
        test_release_supports_exactly_0_1()
        test_supported_version_shows_no_notice()
        test_version_outside_the_set_shows_a_notice_on_every_page()
        test_metamodel_page_names_both_versions_and_the_next_step()
        test_missing_version_has_its_own_wording()
        test_no_metamodel_at_all_still_renders()
        test_metamodel_version_file_takes_precedence()
        test_version_is_read_as_text()
    finally:
        metamodel.METAMODEL_DIR = _REAL
    print("OK: metamodel version check")
