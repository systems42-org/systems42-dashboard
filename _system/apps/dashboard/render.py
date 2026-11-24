"""From wiki text to safe HTML: the sanitizer, wikilinks and Markdown.

Owns the sanitizer, the scroll box around tables, the rendering of wikilinks,
the method-anchor links, the "follows" notes and code spans, callouts, the
unwrapping of hard-wrapped prose, render_markdown and the helpers that pull a
labelled paragraph or bullet from a page body.

May import `wiki`, `links` and `metamodel`, and the packages markdown, nh3
and markupsafe. No Flask import and no import of `app` here
(tests/test_module_imports.py).
"""
from __future__ import annotations

import re

import markdown as md
import nh3
from markupsafe import escape

import links as links_module  # link resolver and indexes. "links" is a parameter name here
import metamodel  # reader for _system/metamodel/ (DR-035)
import wiki  # paths, pages, parse cache and loaders


# --- rendering helpers -----------------------------------------------------
#
# Wiki text is not trusted markup. Pages are written by agents from sources in
# raw/ (emails, tickets, transcripts), and the dashboard is served to the whole
# room, so a `<script>` or `onerror=` that arrives with a source must never run
# in a viewer's browser. Every HTML fragment built from wiki content goes
# through sanitize_html() before a template renders it with `| safe`; a
# wikilink's label is escaped where it is built; plain-text frontmatter values
# are escaped outright (render_wikilinks_text).

# Allow-list on top of nh3's defaults: titles for abbr/footnotes and anchor
# links, and `text-align` only for the alignment the tables extension writes
# as inline style. Comments (the `<!-- levels: … -->` markers) are stripped,
# which they already were visually.
#
# `id` and `class` are allowed only with the values our own markup and
# Python-Markdown emit. The content sits in the page *before* the settings
# dialog and the footer, and the page scripts look elements up by id
# (getElementById returns the first match) and by class across the whole
# document (`.fbtn`, `.sresult`, `.layer-btn` …): a free `id="settings-dialog"`
# or `class="fbtn"` in a wiki page would take over the page's own controls.
_SANITIZE_ATTRIBUTES = {tag: set(attrs) for tag, attrs in nh3.ALLOWED_ATTRIBUTES.items()}
_SANITIZE_ATTRIBUTES["*"] = {"class", "id", "title"}
for _cell in ("th", "td"):
    _SANITIZE_ATTRIBUTES[_cell] = _SANITIZE_ATTRIBUTES.get(_cell, set()) | {"style"}
_SANITIZE_TAGS = set(nh3.ALLOWED_TAGS) | {"tfoot"}
# footnotes: fn:1, fnref:1, fnref2:1 (a second reference to the same note)
_CONTENT_ID_RE = re.compile(r"fn(?:ref\d*)?:[\w.-]+")
# wikilinks, term links and anchor links (render_wikilinks, /metamodel), fenced
# code incl. mermaid, footnotes, the scroll box around tables (wrap_tables)
_CONTENT_CLASS_RE = re.compile(r"wl|wl-anchor|wl-term|mm-anchor|language-[\w+-]+|footnote(?:-ref|-backref)?"
                               r"|table-scroll")


# Wiki content must not make a viewer's browser fetch from outside: a remote
# image or a `background: url(…)` is a beacon that tells its server who looks
# at the page, and the dashboard runs offline anyway. An image keeps its `src`
# only when it names a path of the dashboard itself. A style declaration that
# can load something (url(), image-set(), image(), or a CSS escape that could
# spell one of them) is dropped.
_URL_SCHEME_RE = re.compile(r"[a-z][a-z0-9+.-]*:", re.I)
_CSS_FETCH_RE = re.compile(r"url\s*\(|image-set|image\s*\(|\\", re.I)


def _local_url(value: str) -> bool:
    # a browser drops tabs and newlines inside a URL and reads "\" as "/"
    url = re.sub(r"[\t\n\r]", "", value).strip("".join(map(chr, range(33))))
    return not (_URL_SCHEME_RE.match(url) or "\\" in url or url.startswith("//"))


def _content_attribute(tag: str, attr: str, value: str) -> str | None:
    if attr == "id":
        return value if _CONTENT_ID_RE.fullmatch(value) else None
    if attr == "class":
        kept = [c for c in value.split() if _CONTENT_CLASS_RE.fullmatch(c)]
        return " ".join(kept) or None
    if attr == "src":
        return value if _local_url(value) else None
    if attr == "style":
        kept = [d for d in value.split(";") if d.strip() and not _CSS_FETCH_RE.search(d)]
        return ";".join(kept) or None
    return value


# The About page is the project's own documentation (docs/), laid out by hand:
# it may also place and colour boxes with inline styles. Property names only;
# CSS in a style attribute cannot run script.
_ABOUT_STYLES = {"text-align", "display", "gap", "flex", "flex-wrap", "align-items",
                 "justify-content", "background", "background-color", "color",
                 "padding", "margin", "border", "border-radius", "width", "max-width",
                 "height"}
_ABOUT_ATTRIBUTES = {tag: attrs | {"style"} for tag, attrs in _SANITIZE_ATTRIBUTES.items()}


def sanitize_html(html: str, about: bool = False) -> str:
    """Strip scripts, event handlers, `javascript:` URLs, every tag or
    attribute outside the allow-list, ids or classes the page's own
    markup could collide with, and anything that fetches from outside
    (a remote image, a style with `url()`), from an HTML fragment. `about` keeps the
    inline layout styles of the About page (_ABOUT_STYLES)."""
    return nh3.clean(html, tags=_SANITIZE_TAGS,
                     attributes=_ABOUT_ATTRIBUTES if about else _SANITIZE_ATTRIBUTES,
                     attribute_filter=_content_attribute,
                     filter_style_properties=_ABOUT_STYLES if about else {"text-align"},
                     link_rel=None)


_TABLE_OPEN_RE = re.compile(r"<table\b", re.I)
_TABLE_CLOSE_RE = re.compile(r"</table\s*>", re.I)


def wrap_tables(html: str) -> str:
    """Put every table of rendered markdown in a box that scrolls sideways on
    its own, so a wide table never makes the page scroll at 320 px (QR-001)."""
    html = _TABLE_OPEN_RE.sub('<div class="table-scroll"><table', html)
    return _TABLE_CLOSE_RE.sub("</table></div>", html)


def render_wikilinks(text: str, titles: dict[str, str],
                     links: dict[str, tuple[str, str]] | None = None) -> str:
    """Replace [[..]] with its alias (or resolved title). When `links` is given
    and the target resolves to a wiki page, a source record or a method anchor,
    emit a real hyperlink; otherwise (inline snippets, or an unresolved target)
    keep the styled-text span. A link to a domain term carries the term's
    definition as its title (FR-041).

    The label is escaped (a title is data, not markup); the text around the
    links is left as it is, because callers pass markdown here and sanitize
    the result (render_markdown) or escape it (render_wikilinks_text)."""
    def repl(m: re.Match) -> str:
        target, alias = m.group(1).strip(), m.group(2)
        base = target.split("/")[-1]
        label = escape(alias.strip() if alias else titles.get(base, base))
        if links is not None and (target.startswith("raw/") or base.startswith("SRC-")):
            # a source cited in the text leads to its record (FR-034)
            if src := links_module.source_index().get(base):
                return (f'<a class="wl" href="{escape("/source/" + src.stem)}">'
                        f'{escape(alias.strip() if alias else src.title)}</a>')
        elif links:
            dest = links_module.resolve_link(target, links)
            if dest:
                url = escape(links_module._page_url(*dest))
                if wiki._is(dest[0], "domain-term") and (definition := term_definition(dest[1])):
                    return (f'<a class="wl wl-term" href="{url}" '
                            f'title="{_title_attribute(definition)}">{label}</a>')
                return f'<a class="wl" href="{url}">{label}</a>'
        if links is not None and (a := anchor_lookup().get(base.lower())):
            return _anchor_link(a, str(escape(alias.strip() if alias else a["name"])))
        return f'<span class="wl">{label}</span>'
    return wiki.WIKILINK_RE.sub(repl, text)


def render_wikilinks_text(text: str, titles: dict[str, str],
                          links: dict[str, tuple[str, str]] | None = None) -> str:
    """render_wikilinks for a plain-text value (a frontmatter string): the
    text between the links is escaped too, so `<b>` shows as written."""
    parts, pos = [], 0
    for m in wiki.WIKILINK_RE.finditer(text):
        parts.append(str(escape(text[pos:m.start()])))
        parts.append(render_wikilinks(m.group(0), titles, links))
        pos = m.end()
    parts.append(str(escape(text[pos:])))
    return "".join(parts)


# --- method anchors (FR-035) -------------------------------------------------
#
# `[[MADR]]` names a method anchor, not a wiki page. It leads to the anchor's
# entry on /metamodel, with the short definition as the link's title, so a
# reader learns what the page follows without leaving it.

@wiki._request_cached
def anchor_lookup() -> dict[str, dict]:
    """Lower-cased anchor title, alias and file name → the anchor."""
    return metamodel.anchor_index(metamodel.method_anchors())


# `[text](url)` too: a link inside the `title=""` of an anchor link would be
# turned into an <a> by Markdown and break the attribute open
_PLAIN_MD_RE = re.compile(r"\*\*([^*]+)\*\*|`([^`]+)`|<(https?://[^>]+)>|\[([^\]]+)\]\([^)\s]+\)")


def anchor_title(a: dict) -> str:
    """An anchor's definition as plain text, for a `title` attribute."""
    text = wiki.WIKILINK_RE.sub(lambda m: (m.group(2) or m.group(1)).strip(), a.get("definition") or "")
    return _PLAIN_MD_RE.sub(lambda m: m.group(1) or m.group(2) or m.group(3) or m.group(4), text)


# --- term definitions (FR-041) -----------------------------------------------
#
# A link to a domain term carries the term's definition as its `title`, so a
# reader meets it where the term is used. static/term-definition.js shows the
# title in place on hover, focus and tap. Without script the browser's own
# tooltip shows it.

# longest definition a link carries, in characters, the ellipsis included
TERM_DEFINITION_MAX = 300
# characters Markdown reads as markup. A title is written into Markdown text
# before Markdown runs, and a backtick or bracket in it could pair with one in
# the text around the link and break the attribute open.
_TITLE_MARKUP = {ord(c): f"&#{ord(c)};" for c in "`[]\\*_"}


def _title_attribute(text: str) -> str:
    """`text` escaped for a `title` attribute in Markdown text."""
    return str(escape(text)).translate(_TITLE_MARKUP)


@wiki._request_cached
def term_definition(stem: str) -> str:
    """The definition of the domain term with this file name as plain text:
    its **Definition.** paragraph, links and Markdown reduced to their text,
    cut at a word after TERM_DEFINITION_MAX characters. "" for a term without
    one and for a page of another type. Read once per request and term,
    however many links name the term."""
    page = links_module.page_index().get(stem)
    if page is None or not wiki._is(page.folder, "domain-term"):
        return ""
    titles = links_module.title_index()

    def link_text(m: re.Match) -> str:
        base = m.group(1).strip().split("/")[-1]
        return (m.group(2) or titles.get(base, base)).strip()

    text = wiki.WIKILINK_RE.sub(link_text, labeled_text(page, "Definition"))
    text = _PLAIN_MD_RE.sub(lambda m: m.group(1) or m.group(2) or m.group(3) or m.group(4), text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > TERM_DEFINITION_MAX:
        cut = text[:TERM_DEFINITION_MAX - 1]
        if " " in cut:
            cut = cut[:cut.rindex(" ")]
        text = cut.rstrip(" ,;:.") + "…"
    return text


def anchor_url(a: dict) -> str:
    return f"/metamodel#{a['id']}"


def _anchor_link(a: dict, label: str) -> str:
    return (f'<a class="wl wl-anchor" href="{anchor_url(a)}" '
            f'title="{escape(anchor_title(a))}">{label}</a>')


# A page's note that it follows a standard, a quote line of its own that
# starts with a lowercase "follows": "> follows [[MADR]]", "> follows [[arc42]]
# (section 5, black box)". More than 3 spaces before the ">" is indented code.
_FOLLOWS_RE = re.compile(r"^ {0,3}>[ \t]*follows[ \t]+(\S.*?)[ \t]*$")
_FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
# an inline code span: a run of backticks closed by a run of the same length,
# within one paragraph. A backslash before the opening run escapes it.
_CODE_SPAN_RE = re.compile(r"(?<![`\\])(`+)(?!`)((?:[^\n]|\n(?![ \t]*\n))+?)(?<!`)\1(?!`)")
# a note without a link names its format in a few words, not a sentence
_FOLLOWS_PLAIN_MAX_WORDS = 6


def _fenced_lines(lines: list[str]) -> list[bool]:
    """For each line, whether it belongs to fenced code (``` or ~~~), the
    fence lines included. A fence closes on a fence of the same character at
    least as long as the opening one. An unclosed fence runs to the end."""
    out = []
    fence = ""
    for line in lines:
        f = _FENCE_RE.match(line)
        if fence:
            if f and f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence):
                fence = ""
            out.append(True)
        elif f:
            fence = f.group(1)
            out.append(True)
        else:
            out.append(False)
    return out


def outside_code(text: str, sub) -> str:
    """Apply `sub` to the markdown outside fenced code and inline code spans,
    so a wikilink quoted as code stays literal text."""
    lines = text.split("\n")
    fenced = _fenced_lines(lines)
    blocks: list[tuple[bool, list[str]]] = []
    for line, f in zip(lines, fenced):
        if blocks and blocks[-1][0] == f:
            blocks[-1][1].append(line)
        else:
            blocks.append((f, [line]))
    out = []
    for f, block_lines in blocks:
        block = "\n".join(block_lines)
        if f:
            out.append(block)
            continue
        parts, pos = [], 0
        for m in _CODE_SPAN_RE.finditer(block):
            parts += [sub(block[pos:m.start()]), m.group(0)]
            pos = m.end()
        parts.append(sub(block[pos:]))
        out.append("".join(parts))
    return "\n".join(out)


def _follows_notes(body: str) -> list[tuple[int, str]]:
    """(line number, text after "follows") of every "follows" note, outside
    fenced code. The one test both the page (drop_follows, format_labels) and
    search (search_plain) use, so both leave out exactly the same lines."""
    out = []
    lines = body.split("\n")
    for i, (line, fenced) in enumerate(zip(lines, _fenced_lines(lines))):
        if fenced:
            continue
        m = _FOLLOWS_RE.match(line)
        if not m:
            continue
        text = m.group(1)
        if not wiki.WIKILINK_RE.search(text) and (len(text.split()) > _FOLLOWS_PLAIN_MAX_WORDS
                                              or re.search(r"[.!?;:]", text)):
            continue                         # an ordinary sentence in a quote
        out.append((i, text))
    return out


def drop_follows(body: str) -> str:
    """The body without its "follows" notes, each line removed with its line
    break, so a callout around it stays whole. They show as labels in the
    page head (format_labels), never as a box before the content."""
    drop = {i for i, _ in _follows_notes(body)}
    if not drop:
        return body
    return "\n".join(line for i, line in enumerate(body.split("\n")) if i not in drop)


def format_labels(body: str) -> list[dict]:
    """The "follows" notes of a page as head labels, one per standard named,
    deduplicated: `label`, `url` and `title` (empty for a standard that is no
    anchor) and `note`, the rest of the line such as "section 5, black box"."""
    titles, links = links_module.title_index(), links_module.link_index()
    out: list[dict] = []
    seen: set[str] = set()
    for _, line in _follows_notes(body):
        note = wiki.WIKILINK_RE.sub("", line).strip(" ,;.").strip()
        note = re.sub(r"^\((.*)\)$", r"\1", note).strip()
        found = []
        for wm in wiki.WIKILINK_RE.finditer(line):
            base = wm.group(1).strip().split("/")[-1]
            a = anchor_lookup().get(base.lower())
            if a:
                found.append({"label": a["name"], "url": anchor_url(a), "title": anchor_title(a)})
            elif base in links:
                found.append({"label": titles.get(base, base), "url": links_module._page_url(*links[base]), "title": ""})
            else:
                found.append({"label": (wm.group(2) or base).strip(), "url": "", "title": ""})
        if not found:
            found, note = [{"label": re.sub(r"^the\s+", "", line, flags=re.I), "url": "", "title": ""}], ""
        for i, f in enumerate(found):
            if f["label"].lower() in seen:
                continue
            seen.add(f["label"].lower())
            out.append({**f, "note": note if i == 0 else ""})
    return out


# `[ \t]*`, not `\s*`, after the marker: `\s` would cross the line break and
# take the callout's first text line as its title (`> [!note]` alone on a line)
CALLOUT_RE = re.compile(r"^>[ \t]*\[!(\w+)\][ \t]*(.*)$", re.MULTILINE)

# Lines that START a markdown block. A prose line that follows one of these
# is left for Markdown's own lazy-continuation rules; a prose line that
# follows another prose line is a hard wrap in the source file and is joined.
_BLOCK_START_RE = re.compile(r"^(\s*([-*+]|\d+[.)])\s|\s*#|\s*>|\s*\||\s*```|\s*~~~|\s{4,}\S|\t|\s*<)")
_LIST_START_RE = re.compile(r"^\s*([-*+]|\d+[.)])\s")
# A GFM table separator row: "---|---", "|---|:---:|", "| --- | --- |". Must
# contain at least one "|" — a bare "---" is a thematic break, not a table.
_TABLE_SEP_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")


def _unwrap_prose(body: str) -> str:
    """Join hard-wrapped prose lines into one line per paragraph, and give a
    list that follows a prose line the blank line Python-Markdown needs.
    Agents write wiki pages wrapped at ~80 columns; rendering those wraps as
    <br> (the old `nl2br` extension) produced ragged paragraphs. Fenced code,
    explicit two-space line breaks, lists, quotes, tables and headings are
    passed through untouched. A wrapped *list item* (a plain continuation
    line right after a `- `/`1. ` line) is tracked via `in_list` so it stays
    a lazy continuation of that item — dedented, but without inserting the
    blank line that would turn a tight list into a loose one.

    Tables are recognised by their separator row (`---|---`, `|:---:|…|`),
    not by the mere presence of a "|" — ordinary prose containing a spaced
    pipe (e.g. a wikilink alias `[[FEAT-001|Feature | With Pipe]]`) must
    still be joined. A separator row pulls in the header line right above it
    and every following non-blank row containing "|" as table lines."""
    lines = body.split("\n")

    table_lines: set[int] = set()
    for i, line in enumerate(lines):
        if "|" in line and _TABLE_SEP_RE.match(line):
            table_lines.add(i)
            if i > 0 and "|" in lines[i - 1]:
                table_lines.add(i - 1)
            j = i + 1
            while j < len(lines) and lines[j].strip() and "|" in lines[j]:
                table_lines.add(j)
                j += 1

    fenced = _fenced_lines(lines)
    out: list[str] = []
    in_list = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if fenced[idx]:
            in_list = False
            out.append(line)
            continue
        if not stripped:
            in_list = False
            out.append(line)
            continue

        is_list_start = bool(_LIST_START_RE.match(line))
        is_block_start = (is_list_start or _BLOCK_START_RE.match(line)
                           or idx in table_lines)

        if in_list and not is_block_start:
            # lazy continuation of the current list item — dedent it, stay in the list
            out.append(line.lstrip())
            continue

        prev = out[-1] if out else ""
        prev_is_prose = (bool(prev.strip()) and not _BLOCK_START_RE.match(prev)
                          and (idx - 1) not in table_lines and not in_list)

        if is_block_start:
            if prev_is_prose and is_list_start:
                out.append("")            # prose → list needs a separating blank line
            out.append(line)
            in_list = is_list_start
            continue

        if prev_is_prose and not prev.endswith("  "):
            out[-1] = prev.rstrip() + " " + stripped
        else:
            out.append(line)
    return "\n".join(out)


def render_markdown(body: str, titles: dict[str, str]) -> str:
    # a "follows" note is a head label, never a box in the text (FR-035)
    body = drop_follows(body)
    # unwrap hard-wrapped prose first — before wikilinks turn a leading
    # [[...]] into an <a>, which would otherwise look like an HTML block start
    body = _unwrap_prose(body)
    # full-text bodies get real hyperlinks; inline-snippet helpers keep spans
    # a wikilink quoted as code stays as written
    links = links_module.link_index()
    body = outside_code(body, lambda t: render_wikilinks(t, titles, links))
    # turn Obsidian callouts `> [!type] title` into a bold label line
    body = CALLOUT_RE.sub(lambda m: f"> **{m.group(2) or m.group(1).title()}**", body)
    return sanitize_html(wrap_tables(md.markdown(body, extensions=["extra", "sane_lists"])))


def labeled_text(page: wiki.Page, label: str) -> str:
    """The paragraph introduced by a bold lead like **Definition.** or
    **Snapshot.** as written, on one line."""
    rx = re.compile(r"\*\*" + re.escape(label) + r"\.\*\*\s*(.+?)(?=\n\s*\n|\n\s*\*\*|$)", re.DOTALL)
    m = rx.search(page.body)
    raw = m.group(1).strip() if m else ""
    return re.sub(r"\s+", " ", raw)


def extract_labeled(page: wiki.Page, label: str, titles: dict[str, str],
                    links: dict[str, tuple[str, str]] | None = None) -> str:
    """Pull the paragraph introduced by a bold lead like **Definition.** or
    **Snapshot.**, collapse whitespace, and render its wikilinks. Pass `links`
    (a link index) to turn resolvable targets into real hyperlinks instead of
    styled-text spans."""
    return sanitize_html(render_wikilinks(labeled_text(page, label), titles, links))


_PAM_BULLET_RE = re.compile(
    r"^[ \t]*-\s+\*\*(?P<label>[A-Za-z]+)\.\*\*\s+"
    r"(?P<body>.+?)(?=\n[ \t]*-\s+\*\*|\n##\s|\n\s*\n|\Z)",
    re.DOTALL | re.MULTILINE,
)


def extract_pam_bullet(page: wiki.Page, label: str, titles: dict[str, str],
                       links: dict[str, tuple[str, str]] | None = None) -> str:
    """Pull a bullet-style PAM field (`- **Purpose.** …`) from a goal body.
    Bullets can wrap onto continuation lines; stops at the next sibling bullet,
    a new heading, or a blank line. Pass `links` to emit real hyperlinks."""
    for m in _PAM_BULLET_RE.finditer(page.body):
        if m.group("label").lower() == label.lower():
            raw = re.sub(r"\s+", " ", m.group("body")).strip()
            return sanitize_html(render_wikilinks(raw, titles, links))
    return ""


_INLINE_MD_RE = re.compile(r"\*\*(?P<b>[^*]+)\*\*|`(?P<c>[^`]+)`|\*(?P<i>[^*]+)\*")


def _strip_inline_markdown(text: str) -> str:
    """Titles are read as raw text, not rendered, so `**bold**` and
    `` `code` `` would reach the /decisions list with their asterisks and
    backticks on screen. Titles are plain text there."""
    return _INLINE_MD_RE.sub(lambda m: m.group("b") or m.group("c") or m.group("i"),
                             text).strip()
