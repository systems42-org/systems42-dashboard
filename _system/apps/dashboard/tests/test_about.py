"""The /about page: `about:` in wiki.yaml names a page under docs/; the hero
mark and a text link lead there, the files it links to under docs/ are served.
No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_about.py
"""
import os
import sys
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
(_tmp / "wiki").mkdir(); (_tmp / "sources").mkdir()
_docs = _tmp / "docs"
(_docs / "brand" / "svg").mkdir(parents=True)
(_docs / "brand" / "README.md").write_text(
    "# Brand\n\n![mark](svg/mark.svg) ![shared](../shared.svg) ![out](../../secret.md)\n\n"
    "[site](https://example.org) [top](#brand)\n", encoding="utf-8")
(_docs / "brand" / "svg" / "mark.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
(_docs / "shared.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>', encoding="utf-8")
(_tmp / "secret.md").write_text("# outside docs\n", encoding="utf-8")
# a symlink inside docs/ that points out of it
(_docs / "brand" / "leak.md").symlink_to(_tmp / "secret.md")
_cfg = _tmp / "wiki.yaml"
os.environ["WIKI_DIR"] = str(_tmp / "wiki")
os.environ["RAW_SOURCES_DIR"] = str(_tmp / "sources")
os.environ["DOCS_DIR"] = str(_docs)
os.environ["WIKI_CONFIG"] = str(_cfg)
os.environ["DASHBOARD_CONFIG"] = str(_tmp / "dashboard.yaml")
os.environ["DASH_STARTUP_GRACE"] = "3600"
os.environ["DASH_HEARTBEAT_GRACE"] = "3600"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import app  # noqa: E402

client = app.app.test_client()


def configure(extra: str) -> None:
    _cfg.write_text('system_name: "Demo"\n' + extra, encoding="utf-8")


def test_no_about_key_means_no_link_and_404():
    configure("")
    home = client.get("/").get_data(as_text=True)
    assert 'href="/about"' not in home and "hero-mark-link" not in home
    assert client.get("/about").status_code == 404


def test_about_renders_page_with_rewritten_relative_urls():
    configure("about: docs/brand/README.md\n")
    home = client.get("/").get_data(as_text=True)
    assert 'class="hero-mark-link" href="/about"' in home
    assert "About Demo →" in home
    r = client.get("/about")
    body = r.get_data(as_text=True)
    assert r.status_code == 200 and "<h1" in body and "Brand" in body
    assert 'src="/about/files/brand/svg/mark.svg"' in body
    assert 'href="https://example.org"' in body and 'href="#brand"' in body
    assert client.get("/about/files/brand/svg/mark.svg").status_code == 200


def test_parent_relative_urls_are_resolved_against_the_page():
    """`../shared.svg` left to the browser would become /about/shared.svg (404);
    it is resolved here instead. A URL leading out of docs/ is not rewritten."""
    configure("about: docs/brand/README.md\n")
    body = client.get("/about").get_data(as_text=True)
    assert 'src="/about/files/shared.svg"' in body, body
    assert client.get("/about/files/shared.svg").status_code == 200
    assert 'src="../../secret.md"' in body, body


def test_label_override():
    configure('about: docs/brand/README.md\nabout_label: "About the mark"\n')
    assert "About the mark →" in client.get("/").get_data(as_text=True)


def test_paths_outside_docs_are_refused():
    for bad in ("../secret.md", "docs/../secret.md", "docs/brand/svg/mark.svg", "docs/missing.md"):
        configure(f"about: {bad}\n")
        assert client.get("/about").status_code == 404, bad
        assert 'href="/about"' not in client.get("/").get_data(as_text=True), bad
    configure("about: docs/brand/README.md\n")
    assert client.get("/about/files/../../secret.md").status_code == 404
    assert client.get("/about/files/../secret.md").status_code == 404


def test_symlinks_out_of_docs_are_refused():
    """send_from_directory stops `..` but follows symlinks; the resolved path
    must still lie inside docs/."""
    configure("about: docs/brand/README.md\n")
    assert client.get("/about/files/brand/leak.md").status_code == 404
    configure("about: docs/brand/leak.md\n")
    assert client.get("/about").status_code == 404


def test_about_page_carries_no_brand_animation():
    """/about shows the project's own page as written; the intro animation, if
    a brand ships one, belongs to the home page only (static/brand/README.md)."""
    configure("about: docs/brand/README.md\n")
    about = client.get("/about").get_data(as_text=True)
    assert "intro.js" not in about and "<template" not in about


if __name__ == "__main__":
    test_no_about_key_means_no_link_and_404()
    test_about_renders_page_with_rewritten_relative_urls()
    test_parent_relative_urls_are_resolved_against_the_page()
    test_label_override()
    test_paths_outside_docs_are_refused()
    test_symlinks_out_of_docs_are_refused()
    test_about_page_carries_no_brand_animation()
    print("ok")
