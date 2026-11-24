"""The term page shows kind, aliases, attributes and relationships (FR-039), and
the term list shows the kind and filters by it (FR-038). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_term_fields.py
"""
import html as html_lib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

TERMS = {
    "DT-001-training": '''title: Training
status: accepted
stereotype: entity
aliases: [Course, "Class <b>"]
attributes:
- {name: training_id, type: string, multiplicity: "1", identifier: true}
- {name: price, type: Money, multiplicity: "0..1"}
- {name: seats, type: integer, multiplicity: 1}
relationships:
- {to: "[[DT-002-session]]", label: schedules, kind: composition, multiplicity: "0..*"}
- {to: "[[DT-004-offer|Offer]]", kind: generalization, multiplicity: "5"}
- {to: "[[DT-003-review]]", label: gets, multiplicity: "0..1"}
- {to: "[[DT-099-ghost]]", label: haunts, kind: aggregation, multiplicity: "2"}
''',
    "DT-002-session": "title: Session\nstatus: draft\nstereotype: value-object\n",
    "DT-003-review": "title: Review\nstatus: accepted\n",
    "DT-004-offer": "title: Offer\nstatus: draft\nstereotype: Sum-Type\n",
    "DT-005-note": "title: Note\nstatus: draft\nstereotype: gadget\naliases: [Memo]\n",
}


def _text(fragment):
    """The visible text of an HTML fragment, whitespace collapsed."""
    return " ".join(html_lib.unescape(re.sub(r"<[^>]+>", " ", fragment)).split())


def _rows(page, section_id):
    """The body rows of the table in <section id=...>, each a list of cell HTML."""
    m = re.search(r'<section[^>]*id="%s".*?</section>' % section_id, page, re.S)
    assert m, f"no section {section_id}"
    body = m.group(0).split("<tbody>", 1)[1]
    return [re.findall(r"<td[^>]*>(.*?)</td>", row, re.S) for row in re.findall(r"<tr[^>]*>(.*?)</tr>", body, re.S)]


def _fields(page):
    """{label: dd HTML} of the term fields under the page head."""
    m = re.search(r'<dl class="issue-fields" id="term-fields">(.*?)</dl>', page, re.S)
    return dict(re.findall(r"<dt>(.*?)</dt>\s*<dd>(.*?)</dd>", m.group(1), re.S)) if m else {}


def _list_rows(page):
    """{id: (kind attribute, kind cell text, status)} of the term list."""
    body = page.split('<tbody id="glossary-body">', 1)[1].split("</tbody>", 1)[0]
    out = {}
    for attrs, row in re.findall(r"<tr([^>]*)>(.*?)</tr>", body, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
        out[_text(cells[0])] = (re.search(r'data-kind="([^"]*)"', attrs).group(1), _text(cells[2]),
                                re.search(r'data-status="([^"]*)"', attrs).group(1))
    return out


with tempfile.TemporaryDirectory() as temp:
    wiki = Path(temp) / "wiki"
    terms = wiki / "domain-terms"
    terms.mkdir(parents=True)
    for name, fields in TERMS.items():
        (terms / f"{name}.md").write_text(
            f"---\nid: {name[:6]}\ntype: domain-term\n{fields}---\n\n"
            f"**Definition.** Meaning of {name}.\n", encoding="utf-8")
    os.environ.update(WIKI_DIR=str(wiki), DASH_STARTUP_GRACE="3600")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import app

    with app.app.test_client() as client:
        def get(url):
            response = client.get(url)
            assert response.status_code == 200, url
            return response.get_data(as_text=True)

        # --- the term page (FR-039) ---
        page = get("/page/domain-terms/DT-001-training")
        assert "Meaning of DT-001-training." in page
        fields = _fields(page)
        assert _text(fields["Kind"]) == "entity"
        assert _text(fields["Aliases"]) == "Course, Class <b>"
        assert "<b>" not in fields["Aliases"], "an alias is text, not markup"

        attributes = _rows(page, "term-attributes")
        assert [[_text(c) for c in row] for row in attributes] == [
            ["training_id identifier", "string", "1"],
            ["price", "Money", "0..1"],
            ["seats", "integer", "1"],
        ]

        relationships = _rows(page, "term-relationships")
        assert [[_text(c) for c in row] for row in relationships] == [
            ["composition", "schedules", "DT-002 Session", "0..*"],
            # a generalization has no multiplicity, as in the entity diagram
            ["generalization", "", "DT-004 Offer", ""],
            # no `kind:` is an association, as in the entity diagram
            ["association", "gets", "DT-003 Review", "0..1"],
            ["aggregation", "haunts", "DT-099-ghost", "2"],
        ]
        targets = [re.findall(r'href="([^"]*)"', row[2]) for row in relationships]
        assert targets == [["/page/domain-terms/DT-002-session"], ["/page/domain-terms/DT-004-offer"],
                           ["/page/domain-terms/DT-003-review"], []], targets
        for (url,) in targets[:3]:
            get(url)                                   # the links work

        # a value object without attributes or relationships: the kind, no empty sections
        page = get("/page/domain-terms/DT-002-session")
        assert _text(_fields(page)["Kind"]) == "value-object" and "Aliases" not in _fields(page)
        assert "term-attributes" not in page and "term-relationships" not in page
        assert _text(_fields(get("/page/domain-terms/DT-004-offer"))["Kind"]) == "sum-type"

        # a plain term: no kind, no structure sections
        page = get("/page/domain-terms/DT-003-review")
        assert "Meaning of DT-003-review." in page
        assert "term-fields" not in page and "term-attributes" not in page and "term-relationships" not in page
        # a stereotype the metamodel does not know is no kind. The aliases still show
        page = get("/page/domain-terms/DT-005-note")
        assert list(_fields(page)) == ["Aliases"] and _text(_fields(page)["Aliases"]) == "Memo"
        assert "gadget" not in page

        # --- the term list (FR-038) ---
        page = get("/domain-terms")
        every = {
            "DT-001": ("entity", "entity", "accepted"),
            "DT-002": ("value-object", "value-object", "draft"),
            "DT-003": ("", "", "accepted"),
            "DT-004": ("sum-type", "sum-type", "draft"),
            "DT-005": ("", "", "draft"),
        }
        assert _list_rows(page) == every
        assert 'data-key="kind"' in page, "the kind column sorts"
        picker = page.split("<select data-list-kind>", 1)[1].split("</select>", 1)[0]
        options = re.findall(r'<option value="([^"]*)">([^<]*)</option>', picker)
        assert options == [("", "All"), ("entity", "entity"), ("value-object", "value-object"),
                           ("sum-type", "sum-type"), ("none", "No kind")], options
        assert "No terms match these filters." in page
        # the filter runs in the browser: the server sends every term whatever the
        # address says, and the page holds no form and no script of its own
        for query in ("?kind=entity", "?kind=none&status=accepted&sort=title:desc", "?kind=gadget"):
            assert _list_rows(get("/domain-terms" + query)) == every, query
        content = page.split('<h1 class="page-h1">', 1)[1].split("</table>", 1)[0]
        assert "<form" not in content and "<script" not in content

        # --- the kind filter, run on this page's rows by static/list-view.js under node ---
        body = page.split('<tbody id="glossary-body">', 1)[1].split("</tbody>", 1)[0]
        rows = []
        for attrs, row in re.findall(r"<tr([^>]*)>(.*?)</tr>", body, re.S):
            cells = re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
            rows.append({"status": re.search(r'data-status="([^"]*)"', attrs).group(1),
                         "kind": re.search(r'data-kind="([^"]*)"', attrs).group(1),
                         "cells": [_text(cells[0]), _text(cells[1]), _text(cells[2])]})

        def run(search="", actions=(), picker=True):
            spec = {"search": search, "rows": rows, "kinds": [value for value, _ in options] if picker else [],
                    "columns": [{"key": "id"}, {"key": "title"}, {"key": "kind"}], "actions": list(actions)}
            out = subprocess.run(["node", str(Path(__file__).with_name("list_harness.js"))],
                                 input=json.dumps(spec), capture_output=True, text=True, check=True).stdout
            return json.loads(out)

        if not shutil.which("node"):
            print("skip: node not installed, the kind filter did not run")
        else:
            by_title = ["DT-005", "DT-004", "DT-003", "DT-002", "DT-001"]     # Note, Offer, Review, Session, Training
            out = run()
            assert sorted(out["shown"]) == sorted(every) and out["search"] == "" and out["kind"] == ""
            # one kind, picked on the page: the rows, and the address a reload shows them with
            for kind, ids in (("entity", ["DT-001"]), ("value-object", ["DT-002"]), ("sum-type", ["DT-004"]),
                              ("none", ["DT-005", "DT-003"])):
                picked = run(actions=[{"kind": kind}])
                assert picked["shown"] == ids and picked["search"] == "?kind=" + kind, (kind, picked)
                opened = run("?kind=" + kind)
                assert opened["shown"] == ids and opened["kind"] == kind, (kind, opened)
            # back to All takes the kind out of the address
            out = run("?kind=entity", [{"kind": ""}])
            assert sorted(out["shown"]) == sorted(every) and out["search"] == ""
            # an unknown kind shows every term
            out = run("?kind=gadget")
            assert sorted(out["shown"]) == sorted(every) and out["kind"] == ""
            # kind and status
            out = run("?kind=none&status=accepted")
            assert out["shown"] == ["DT-003"] and out["search"] == "?kind=none&status=accepted", out
            out = run("?status=accepted", [{"kind": "entity"}])
            assert out["shown"] == ["DT-001"] and out["search"] == "?status=accepted&kind=entity", out
            out = run("?kind=none", [{"status": "accepted"}, {"status": "all"}])
            assert out["shown"] == ["DT-005", "DT-003"] and out["search"] == "?kind=none", out
            assert out["events"][-2:] == [{"status": "accepted", "kind": "none"}, {"status": "all", "kind": "none"}]
            # a kind with no agreed term: the hint shows
            out = run("?kind=sum-type&status=accepted")
            assert out["shown"] == [] and out["emptyHint"] is True, out
            assert run("?kind=sum-type")["emptyHint"] is False
            # kind and sort
            out = run("?kind=none&sort=title:desc")
            assert out["shown"] == ["DT-003", "DT-005"] and out["search"] == "?kind=none&sort=title:desc", out
            out = run("?kind=none", [{"sort": "id"}])
            assert out["shown"] == ["DT-003", "DT-005"] and out["search"] == "?kind=none&sort=id:asc", out
            out = run("?sort=title:asc", [{"sort": "kind"}])
            assert out["shown"][:3] == ["DT-001", "DT-004", "DT-002"], out       # a term without a kind sorts last
            out = run("?sort=title:asc")
            assert out["shown"] == by_title, out
            # a list without a kind picker ignores ?kind= and leaves it alone
            out = run("?kind=entity&status=accepted", picker=False)
            assert out["shown"] == ["DT-003", "DT-001"] and out["search"] == "?kind=entity&status=accepted", out

print("term fields: passed")
