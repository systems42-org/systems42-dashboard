"""Impossible dates and bytes that are not UTF-8, in every input (issue #176).

`created: 2026-13-01` matches YAML's date pattern, so PyYAML builds a date
from it and raises ValueError, which is no yaml.YAMLError. Bytes that are not
UTF-8 raise UnicodeDecodeError. Every request reads the wiki pages, wiki.yaml
and the metamodel, so either one used to be an error on every route. Now the
bad value costs only itself, and a log line names the file and the problem.

Run from the dashboard dir:
    .venv/bin/python tests/test_invalid_input.py
"""
import logging
import os
import shutil
import sys
import tempfile
from pathlib import Path

WIKI_FOLDERS = [
    "domain-terms", "goals", "stakeholders", "context", "external-interfaces",
    "activity-models", "functional-requirements",
    "quality-requirements", "constraints", "issues", "building-blocks", "decisions",
    "solution-strategy", "crosscutting-concepts", "runtime-scenarios", "deployment-nodes",
]

_system = Path(__file__).resolve().parents[3]
_repo = Path(tempfile.mkdtemp()) / "repo"
_wiki = _repo / "wiki"
for _f in WIKI_FOLDERS:
    (_wiki / _f).mkdir(parents=True)
_sources = _repo / "raw" / "sources"
_sources.mkdir(parents=True)
(_repo / "docs").mkdir()
_config = _repo / "_system" / "wiki.yaml"
_metamodel = _repo / "_system" / "metamodel"
shutil.copytree(_system / "metamodel", _metamodel)
shutil.copytree(_system / "anchors", _repo / "_system" / "anchors")


def _page(folder, stem, frontmatter, body="# T\n"):
    (_wiki / folder / f"{stem}.md").write_text(f"---\n{frontmatter}\n---\n{body}", encoding="utf-8")


# --- wiki ---------------------------------------------------------------------
_page("domain-terms", "DT-001-invalid-month",
      "id: DT-001\ntitle: Invalid month\nstatus: draft\ncreated: 2026-13-01\nupdated: 2026-01-02",
      "**Definition.** A term.\n")
_page("domain-terms", "DT-002-invalid-day",
      "id: DT-002\ntitle: Invalid day\nstatus: draft\ncreated: 2026-01-02\nupdated: 2026-02-30",
      "**Definition.** See [[DT-001-invalid-month]].\n")
_page("domain-terms", "DT-003-valid",
      "id: DT-003\ntitle: Valid term\nstatus: draft\ncreated: 2026-01-02\nupdated: 2026-01-03",
      "**Definition.** Links to [[DT-001-invalid-month]] and [[DT-002-invalid-day]].\n")
_page("decisions", "DR-001-invalid-decided",
      "id: DR-001\ntitle: Decided on no day\nkind: architecture\ndecided: 2026-02-30\ncreated: 2026-00-10")
_page("issues", "ISS-001-invalid-time",
      "id: ISS-001\ntitle: Invalid time\nstatus: open\ncreated: 2026-01-02T25:00:00Z\nupdated: 2026-13-01")
# values no constructor can build: the fields are ignored, as for malformed YAML
_page("goals", "GOAL-001-not-a-timestamp",
      "id: GOAL-001\ntitle: Tagged\nstereotype: vision\ncreated: !!timestamp never")
_page("constraints", "CON-001-not-an-int", "id: CON-001\ntitle: Not an int\npriority: !!int abc")
# bytes that are not UTF-8, in the frontmatter and in the body
(_wiki / "stakeholders" / "STK-001-latin1.md").write_bytes(
    b"---\nid: STK-001\ntitle: Gr\xfc\xdfe\ncreated: 2026-01-02\n---\nBody \xff.\n")
(_sources / "SRC-001-invalid-month.md").write_text(
    "---\nid: SRC-001\ntitle: Source\ntype: source\ncreated: 2026-13-01\n---\n# Source\n", encoding="utf-8")

# --- configuration --------------------------------------------------------------
_config.write_text("system_name: Dated\nstarted: 2026-13-01\n", encoding="utf-8")

# --- metamodel ------------------------------------------------------------------
_bad_type = _metamodel / "types" / "type-constraint.md"
_bad_type.write_bytes(_bad_type.read_bytes() + b"\nGr\xfc\xdfe\n")
_dated_type = _metamodel / "types" / "type-goal.md"
_dated_type.write_text(_dated_type.read_text(encoding="utf-8").replace("---\n", "---\nchecked: 2026-02-30\n", 1),
                       encoding="utf-8")
_bad_anchor = _repo / "_system" / "anchors" / "zz-latin1.md"
_bad_anchor.write_bytes(b"---\ntype: anchor\ntitle: Gr\xfc\xdfe\n---\n# Gr\xfc\xdfe\n")
(_metamodel / "metamodel-version.md").write_bytes(b"---\nversion: \"0.1\"\nnote: Gr\xfc\xdfe\n---\n")

os.environ["REPO_DIR"] = str(_repo)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_config)
os.environ["RAW_SOURCES_DIR"] = str(_sources)
os.environ["DOCS_DIR"] = str(_repo / "docs")
os.environ["METAMODEL_DIR"] = str(_metamodel)
for _name in ("NOTATIONS_DIR", "ANCHORS_DIR"):
    os.environ.pop(_name, None)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py


class _Collect(logging.Handler):
    def __init__(self):
        super().__init__()
        self.lines: list[str] = []

    def emit(self, record):
        self.lines.append(record.getMessage())


_log = _Collect()
logging.getLogger("systems42.inputs").addHandler(_log)

import app  # noqa: E402
import settings  # noqa: E402
import wiki  # noqa: E402
import inputs  # noqa: E402
import links  # noqa: E402


def _get(path):
    resp = app.app.test_client().get(path, follow_redirects=True)
    return resp.status_code, resp.get_data(as_text=True)


def _all_routes():
    plain = sorted(str(r) for r in app.app.url_map.iter_rules()
                   if "GET" in r.methods and "<" not in str(r)
                   # /about: this wiki.yaml names no about page, so 404 is right
                   and str(r) not in ("/presence/count", "/presence/list", "/brand/intro.html", "/about"))
    pages = [links._page_url(p.parent.name, p.stem) for p in sorted(_wiki.glob("*/*.md"))]
    return plain + pages + ["/source/SRC-001-invalid-month"]


def _assert_every_route_answers(what):
    failed = []
    for path in _all_routes():
        status, _ = _get(path)
        if status != 200:
            failed.append(f"{path} -> {status}")
    assert not failed, f"{what}:\n" + "\n".join(failed)
    resp = app.app.test_client().post("/ping", json={"client_id": "t"})
    assert resp.status_code == 200, f"{what}: the heartbeat answers {resp.status_code}"


def _logged(path, *words):
    """The log lines that name `path` and hold every one of `words`."""
    return [line for line in _log.lines if str(path) in line and all(w in line for w in words)]


def test_no_route_breaks():
    _assert_every_route_answers("invalid dates and encodings in wiki, configuration and metamodel")


def test_an_invalid_date_costs_the_page_nothing_else():
    month = wiki._parse(_wiki / "domain-terms" / "DT-001-invalid-month.md", "domain-terms")
    assert month.id == "DT-001" and month.title == "Invalid month" and month.status == "draft"
    assert month.meta["created"] == "2026-13-01", "the invalid date is not kept as written"
    assert str(month.meta["updated"]) == "2026-01-02", "the valid date beside it is lost"
    day = wiki._parse(_wiki / "domain-terms" / "DT-002-invalid-day.md", "domain-terms")
    assert day.title == "Invalid day" and day.meta["updated"] == "2026-02-30"
    status, body = _get("/page/domain-terms/DT-003-valid")
    assert status == 200
    assert 'href="/page/domain-terms/DT-001-invalid-month"' in body, "the link to the bad page is lost"
    _, listing = _get("/domain-terms")
    for title in ("Invalid month", "Invalid day", "Valid term"):
        assert title in listing, f"{title!r} is missing from the term list"
    status, body = _get("/search.json")
    assert status == 200 and "Invalid month" in body


def test_an_invalid_date_is_shown_as_written_not_as_a_date():
    _, body = _get("/page/domain-terms/DT-001-invalid-month")
    assert "2026-13-01" in body


def test_wiki_diagnostics_name_file_and_problem():
    assert _logged(_wiki / "domain-terms" / "DT-001-invalid-month.md", "2026-13-01", "not a valid date")
    assert _logged(_wiki / "domain-terms" / "DT-002-invalid-day.md", "2026-02-30", "not a valid date")
    assert _logged(_wiki / "issues" / "ISS-001-invalid-time.md", "2026-01-02T25:00:00Z")
    assert _logged(_wiki / "issues" / "ISS-001-invalid-time.md", "2026-13-01")
    assert _logged(_wiki / "decisions" / "DR-001-invalid-decided.md", "2026-02-30", "2026-00-10")
    assert _logged(_sources / "SRC-001-invalid-month.md", "2026-13-01")
    assert _logged(_wiki / "stakeholders" / "STK-001-latin1.md", "not valid UTF-8")
    assert not [line for line in _log.lines if "DT-003-valid" in line], "a valid page was reported"


def test_a_value_no_type_accepts_drops_the_fields_and_says_so():
    path = _wiki / "constraints" / "CON-001-not-an-int.md"
    page = wiki._parse(path, "constraints")
    assert page.meta == {} and page.title == "CON-001-not-an-int"
    assert _logged(path, "fields ignored", "abc")
    path = _wiki / "goals" / "GOAL-001-not-a-timestamp.md"
    assert wiki._parse(path, "goals").meta == {}
    assert _logged(path, "fields ignored")


def test_a_problem_is_logged_once_and_again_after_it_changed():
    path = _wiki / "domain-terms" / "DT-001-invalid-month.md"
    before = len(_logged(path))
    for _ in range(3):
        _get("/domain-terms")
    assert len(_logged(path)) == before, "the same problem is logged on every request"
    assert inputs.load_yaml(path, "created: 2026-13-01") == {"created": "2026-13-01"}
    assert len(_logged(path)) == before, "the same problem is logged twice"
    assert inputs.load_yaml(path, "created: 2026-01-01") is not None
    inputs.load_yaml(path, "created: 2026-13-01")
    assert len(_logged(path)) == before + 1, "a problem that came back is not logged again"


def test_metamodel_survives_and_reports():
    import metamodel
    assert _logged(_bad_type, "not valid UTF-8", "file ignored")
    assert metamodel._read(_bad_type) is None, "a file that is not UTF-8 is presented as a metamodel page"
    dated = metamodel._read(_dated_type)
    assert dated is not None and dated["checked"] == "2026-02-30", "one bad date cost the type its page"
    assert _logged(_dated_type, "2026-02-30", "not a valid date")
    assert _logged(_bad_anchor, "not valid UTF-8")
    assert _logged(_metamodel / "metamodel-version.md", "not valid UTF-8")
    check = metamodel.version_check()
    assert (check["file"], check["version"], check["state"]) == ("metamodel-version.md", "", "missing"), check
    status, body = _get("/metamodel")
    assert status == 200 and "Goal" in body


def test_configuration_survives_and_reports():
    # an invalid date beside the name: the name still counts
    assert settings.wiki_config()["system_name"] == "Dated"
    assert _logged(_config, "2026-13-01", "not a valid date")
    # bytes that are not UTF-8: the defaults, as for a malformed file
    _config.write_bytes(b"system_name: Gr\xfc\xdfe\n")
    cfg = settings.wiki_config()
    assert cfg["system_name"] == settings.DEFAULT_SYSTEM_NAME and cfg["system_name_set"] is False
    assert _logged(_config, "not valid UTF-8", "file ignored")
    _assert_every_route_answers("wiki.yaml that is not UTF-8")
    # a value no constructor can build
    _config.write_text("system_name: Typed\ndashboard_version: !!float x\n", encoding="utf-8")
    assert settings.wiki_config()["system_name"] == settings.DEFAULT_SYSTEM_NAME
    assert _logged(_config, "fields ignored")
    _assert_every_route_answers("wiki.yaml with a value no type accepts")
    _config.write_text("system_name: Dated\n", encoding="utf-8")
    assert settings.wiki_config()["system_name"] == "Dated"


if __name__ == "__main__":
    test_no_route_breaks()
    test_an_invalid_date_costs_the_page_nothing_else()
    test_an_invalid_date_is_shown_as_written_not_as_a_date()
    test_wiki_diagnostics_name_file_and_problem()
    test_a_value_no_type_accepts_drops_the_fields_and_says_so()
    test_a_problem_is_logged_once_and_again_after_it_changed()
    test_metamodel_survives_and_reports()
    test_configuration_survives_and_reports()
    print("OK: invalid dates and encodings cost one value or one file, and are logged")
