"""Issue lookups stay cheap with many issues. No pytest.

Every page view lists the issues that link to the page (FR-027), and each issue
checks its values against the metamodel. The metamodel files are parsed once
and then only again when one changes, so a page view with 200 issues reads no
metamodel YAML and answers well under a second.

Run from the dashboard dir:
    .venv/bin/python tests/test_issue_perf.py
"""
import os
import sys
import tempfile
import time
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
for _f in ("issues", "stakeholders"):
    (_wiki / _f).mkdir(parents=True)
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

N = 200
(_wiki / "stakeholders" / "STK-001-team.md").write_text(
    "---\nid: STK-001\ntype: stakeholder\ntitle: Team\nstatus: draft\nrelated: []\n---\n\n# Team\n",
    encoding="utf-8")
for n in range(1, N + 1):
    (_wiki / "issues" / f"ISS-{n:03d}-frage.md").write_text(
        f"---\nid: ISS-{n:03d}\ntype: issue\ntitle: Frage {n}\nstatus: open\nsources: []\n"
        f'related: ["[[STK-001-team]]"]\ntags: []\nseverity: minor\nkind: question\n'
        f"category: content\nowner:\n---\n\n# Frage {n}\n", encoding="utf-8")

import app  # noqa: E402
import metamodel  # noqa: E402

client = app.app.test_client()


def _count_metamodel_parses(fn):
    calls = [0]
    real = metamodel.yaml.safe_load

    def counting(*a, **kw):
        calls[0] += 1
        return real(*a, **kw)
    metamodel.yaml.safe_load = counting
    try:
        fn()
    finally:
        metamodel.yaml.safe_load = real
    return calls[0]


def test_warm_page_view_reads_no_metamodel_yaml():
    client.get("/page/stakeholders/STK-001-team")        # warm up both caches
    for path in ("/page/stakeholders/STK-001-team", "/issues"):
        n = _count_metamodel_parses(lambda: client.get(path))
        assert n == 0, (path, n)


def test_page_view_with_200_issues_is_fast():
    client.get("/issues")
    for path in ("/page/stakeholders/STK-001-team", "/issues", "/issues?status=open&owner=none"):
        t = time.perf_counter()
        resp = client.get(path)
        took = time.perf_counter() - t
        assert resp.status_code == 200, path
        assert took < 1.5, (path, round(took, 2))
    assert len(app.open_issues_for("STK-001-team")) == N


def test_a_changed_metamodel_file_is_read_again():
    page = metamodel.METAMODEL_DIR / "types" / "type-issue.md"
    before = metamodel.field_values("issue", "severity")
    st = page.stat()
    os.utime(page, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000))
    try:
        n = _count_metamodel_parses(lambda: metamodel.field_values("issue", "severity"))
        assert n >= 1, n
        assert metamodel.field_values("issue", "severity") == before
    finally:
        os.utime(page, ns=(st.st_atime_ns, st.st_mtime_ns))


if __name__ == "__main__":
    test_warm_page_view_reads_no_metamodel_yaml()
    test_page_view_with_200_issues_is_fast()
    test_a_changed_metamodel_file_is_read_again()
    print("OK: issue perf")
