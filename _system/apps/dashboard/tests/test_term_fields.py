"""The term page shows kind, aliases, attributes and relationships (FR-039), and
the term list shows the kind and filters by it (FR-038). No pytest.

Run from the dashboard dir:
    .venv/bin/python tests/test_term_fields.py
"""
import html as html_lib
import os
from pathlib import Path
import re
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
        assert _list_rows(page) == {
            "DT-001": ("entity", "entity", "accepted"),
            "DT-002": ("value-object", "value-object", "draft"),
            "DT-003": ("", "", "accepted"),
            "DT-004": ("sum-type", "sum-type", "draft"),
            "DT-005": ("", "", "draft"),
        }
        assert 'data-key="kind"' in page, "the kind column sorts"
        options = re.findall(r'<option value="([^"]*)"( selected)?>([^<]*)</option>',
                             page.split('<select name="kind">', 1)[1].split("</select>", 1)[0])
        assert options == [("", " selected", "All"), ("entity", "", "entity"), ("value-object", "", "value-object"),
                           ("sum-type", "", "sum-type"), ("none", "", "No kind")], options

        def shown(query):
            return set(_list_rows(get("/domain-terms" + query)))

        assert shown("?kind=entity") == {"DT-001"}
        assert shown("?kind=value-object") == {"DT-002"}
        assert shown("?kind=sum-type") == {"DT-004"}
        assert shown("?kind=none") == {"DT-003", "DT-005"}
        assert shown("?kind=gadget") == {"DT-001", "DT-002", "DT-003", "DT-004", "DT-005"}, "an unknown kind is ignored"

        page = get("/domain-terms?kind=none")
        assert '<option value="none" selected>No kind</option>' in page
        assert "Showing 2 of 5 terms" in page and "5 terms</span>" in page

        # with the status filter: the server leaves the rows of the kind, and the
        # list layer (static/list-view.js) hides those whose data-status is not accepted
        page = get("/domain-terms?kind=none&status=accepted&sort=title:desc")
        rows = _list_rows(page)
        assert set(rows) == {"DT-003", "DT-005"}
        assert {i for i, r in rows.items() if r[2] == "accepted"} == {"DT-003"}
        assert "data-list-status" in page, "the status filter stays on the filtered list"
        # without script, Apply keeps status and sort
        form = page.split('<form class="issue-filters"', 1)[1].split("</form>", 1)[0]
        assert '<input type="hidden" name="status" value="accepted">' in form
        assert '<input type="hidden" name="sort" value="title:desc">' in form
        script = (Path(app.app.static_folder) / "list-view.js").read_text(encoding="utf-8")
        assert "new URLSearchParams(location.search)" in script, "the list layer keeps the other address parameters"

        # a kind with no term: the table stays, with a hint
        (terms / "DT-002-session.md").unlink()
        page = get("/domain-terms?kind=value-object")
        assert _list_rows(page) == {} and "No terms match this filter." in page
        assert "No agreed pages in this list." not in page

print("term fields: passed")
