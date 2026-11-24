"""The parse caches under load (issue #68). No pytest.

  * link_targets() dumps a page's frontmatter once, not once per call: the
    relations panel asks every page in the wiki on every detail view.
  * title_index() knows the pages load_all_pages() knows, and no others: a
    nested `wiki/x/y/z.md` is in neither.
  * A deleted page leaves _PARSE_CACHE on the next load, and a deleted anchor
    leaves the metamodel's anchor cache.
  * Threads parsing the same vault at once get the same pages and leave one
    entry per file.

Run from the dashboard dir:
    .venv/bin/python tests/test_cache_hardening.py
"""
import os
import sys
import tempfile
import threading
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
_wiki = _tmp / "wiki"
_anchors = _tmp / "anchors"
for _f in ("domain-terms", "stakeholders", "issues"):
    (_wiki / _f).mkdir(parents=True)
_anchors.mkdir()
os.environ["WIKI_DIR"] = str(_wiki)
os.environ["ANCHORS_DIR"] = str(_anchors)
os.environ["WIKI_CONFIG"] = str(_tmp / "wiki.yaml")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
# without a browser heartbeat the watchdog SIGTERMs this process (DR-022)
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # import app.py


def _page(folder, stem, title, body=""):
    path = _wiki / folder / f"{stem}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"---\nid: {stem.split('-')[0]}-{stem.split('-')[1]}\ntype: x\ntitle: {title}\n"
        f"status: draft\nrelated: []\n---\n\n{body}\n",
        encoding="utf-8")
    return path


for _i in range(1, 6):
    _page("domain-terms", f"DT-00{_i}-term-{_i}", f"Term {_i}", "See [[STK-001-owner]].")
_page("stakeholders", "STK-001-owner", "Owner", "Defines [[DT-001-term-1]].")
# nested one level too deep, and at the wiki root: not wiki pages
_page("domain-terms/deeper", "DT-900-nested", "Nested")
(_wiki / "README.md").write_text("---\ntitle: Root readme\n---\n", encoding="utf-8")

(_anchors / "MADR.md").write_text(
    "---\ntype: anchor\ntitle: MADR\naliases: []\napplies-to: []\n---\n\n# MADR\n\n"
    "Markdown decision records.\n", encoding="utf-8")
(_anchors / "PAM.md").write_text(
    "---\ntype: anchor\ntitle: PAM\naliases: []\napplies-to: []\n---\n\n# PAM\n\n"
    "Purpose, activity, metric.\n", encoding="utf-8")

import app  # noqa: E402
import wiki  # noqa: E402
import links  # noqa: E402
import metamodel  # noqa: E402

client = app.app.test_client()


def test_link_targets_dump_once_per_page():
    wiki._PARSE_CACHE.clear()
    calls = []
    real = wiki.yaml.safe_dump

    def counting(*a, **kw):
        calls.append(1)
        return real(*a, **kw)

    wiki.yaml.safe_dump = counting
    try:
        assert client.get("/page/stakeholders/STK-001-owner").status_code == 200
        first = len(calls)
        pages = wiki.load_all_pages()
        assert 0 < first <= len(pages), (first, len(pages))
        for p in pages:
            assert p.link_targets() == p.link_targets()
        # the Pages live on in _PARSE_CACHE, so the next request dumps nothing
        assert client.get("/page/stakeholders/STK-001-owner").status_code == 200
        assert len(calls) == len(pages), (len(calls), len(pages))
    finally:
        wiki.yaml.safe_dump = real
    owner = next(p for p in wiki.load_all_pages() if p.stem == "STK-001-owner")
    assert owner.link_targets() == {"DT-001-term-1"}


def test_an_edited_page_gets_fresh_link_targets():
    wiki._PARSE_CACHE.clear()
    path = _wiki / "stakeholders" / "STK-002-editor.md"
    _page("stakeholders", "STK-002-editor", "Editor", "Uses [[DT-002-term-2]].")
    page = wiki._parse(path, "stakeholders")
    assert page.link_targets() == {"DT-002-term-2"}
    _page("stakeholders", "STK-002-editor", "Editor", "Uses [[DT-003-term-3]].")
    st = path.stat()
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000_000))
    assert wiki._parse(path, "stakeholders").link_targets() == {"DT-003-term-3"}
    path.unlink()


def test_title_index_knows_what_load_all_pages_knows():
    with app.app.test_request_context("/"):
        stems = {p.stem for p in wiki.load_all_pages()}
        titles = links.title_index()
    assert set(titles) == stems, (set(titles) ^ stems)
    assert "DT-900-nested" not in titles and "README" not in titles
    assert titles["DT-001-term-1"] == "Term 1"


def test_a_deleted_page_leaves_the_cache():
    path = _page("domain-terms", "DT-050-doomed", "Doomed")
    wiki.load_folder("domain-terms")
    assert path in wiki._PARSE_CACHE
    path.unlink()
    assert "DT-050-doomed" not in {p.stem for p in wiki.load_folder("domain-terms")}
    assert path not in wiki._PARSE_CACHE
    # the other pages of the folder stay cached
    assert _wiki / "domain-terms" / "DT-001-term-1.md" in wiki._PARSE_CACHE


def test_parse_of_a_vanished_file_drops_its_entry():
    path = _page("domain-terms", "DT-051-gone", "Gone")
    assert wiki._parse(path, "domain-terms") is not None
    path.unlink()
    assert wiki._parse(path, "domain-terms") is None
    assert path not in wiki._PARSE_CACHE


def test_a_deleted_anchor_leaves_the_anchor_cache():
    doomed = _anchors / "PAM.md"
    assert {a["name"] for a in metamodel.method_anchors()} == {"MADR", "PAM"}
    assert doomed in metamodel._ANCHOR_CACHE
    doomed.unlink()
    assert {a["name"] for a in metamodel.method_anchors()} == {"MADR"}
    assert doomed not in metamodel._ANCHOR_CACHE


def test_threads_parsing_at_once_agree():
    for i in range(40):
        _page("issues", f"ISS-{100 + i}-load", f"Load {i}", "About [[DT-001-term-1]].")
    wiki._PARSE_CACHE.clear()
    errors, results = [], []
    start = threading.Barrier(8)

    def work():
        try:
            start.wait()
            for _ in range(20):
                pages = wiki.load_all_pages()
                results.append(sorted((p.stem, p.title, tuple(sorted(p.link_targets())))
                                      for p in pages))
                metamodel.method_anchors()
        except Exception as e:  # noqa: BLE001 - any failure fails the test
            errors.append(e)

    threads = [threading.Thread(target=work) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert not errors, errors
    assert all(r == results[0] for r in results)
    files = {p for p in _wiki.glob("*/*.md")}
    assert set(wiki._PARSE_CACHE) == files, set(wiki._PARSE_CACHE) ^ files


if __name__ == "__main__":
    test_link_targets_dump_once_per_page()
    test_an_edited_page_gets_fresh_link_targets()
    test_title_index_knows_what_load_all_pages_knows()
    test_a_deleted_page_leaves_the_cache()
    test_parse_of_a_vanished_file_drops_its_entry()
    test_a_deleted_anchor_leaves_the_anchor_cache()
    test_threads_parsing_at_once_agree()
    print("all cache hardening tests passed")
