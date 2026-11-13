# Requirements-Wiki Dashboard

A dashboard over the `wiki/` layer, read-only
as far as the wiki goes. It parses the markdown pages live on each request —
nothing in the wiki is ever written back; the one file it writes is its own
settings file (see Configure) — and renders them as tiles.

## Run

From the repository root:

```sh
./dashboard.sh          # build + start in Docker, opens http://localhost:8080
./dashboard.sh down     # stop
./dashboard.sh logs     # follow logs
./dashboard.sh rebuild  # clean rebuild
./dashboard.sh local    # no Docker: run Flask directly on http://localhost:8000
./dashboard.sh clean    # remove what can be rebuilt: container, image, .venv, caches
```

`clean` (also `make clean`) never touches `wiki/`, `raw/`, `docs/`, `sandbox/`,
the settings files or `harvest-*.patch`. Without a reachable Docker it says so,
leaves the container and image in place and still removes the local files.

The Docker path needs no local Python install — everything runs in the
container. `local` is the escape hatch for machines where Docker will not
start: it builds a `.venv/` here on first run (~20 s) and serves the same app.

The `wiki/` folder is bind-mounted read-only at `/wiki`, so the dashboard always
reflects the current state of the vault; just refresh the browser after editing.
(The only read-write mount is the dashboard's own settings file; see Configure.)
Every page footer shows the data-refresh timestamp (page load time, `%Y-%m-%d`,
in `TZ` if set, else the host's local zone).

The dashboard shuts itself down a few seconds after the last browser tab is
closed (DR-022), so it never lingers as an orphan process or container. The
footer shows a live client count; the ≡ menu opens the "Who's here?" page (a fun
nickname per tab, no real names). Whoever connects first is "Yoda" — listed
and counted like everyone else, but marked as facilitator and the only
one who sees the "Disconnect all" menu entry, which ends the session for
everyone; if their tab disappears, the role passes once to whoever's left with
the next-earliest connection and does not come back. Names are sticky for the
whole session: a tab keeps the name it got first, even when it inherits the
role or drops out and returns.

## Join code

The hero on the home page carries a QR code plus its plain-text address —
scan it (or type it) to open the dashboard on your own device. `/join`
renders the same code full-size for projecting, linked from "Who's here?".
The address defaults to the host's LAN IP (`dashboard.sh`'s `lan_ip()`,
port 8080 in Docker / 8000 for `local`); set `DASH_PUBLIC_URL` to override it
when the room has DNS or a tunnel, e.g. `DASH_PUBLIC_URL=http://name.local:8080
./dashboard.sh`. The QR is generated offline (`segno`, pure Python, no
network at runtime) and rendered inline as SVG so it follows the theme.

## Navigation

Every page carries the same topbar: the vault name (back to the home page;
omitted on the home page itself, where the hero already shows mark and name),
a five-entry nav (Requirements · Architecture · Domain Terms · Decisions · Issues) with the
current entry marked, a search box and the ≡ menu. Pressing <kbd>⌘K</kbd>
(<kbd>Ctrl K</kbd> elsewhere) anywhere focuses the search box; submitting it
lands on `/search`, the full-text view. The nav carries content only: the
two peaks, then Domain Terms, Decisions and Issues from Commons. Every label
comes from `catalog.py`, so a section has one name everywhere (FR-017).
Breadcrumbs under the bar read `Home › Area › Section › Page`, following
where a page belongs (FR-020). Pages outside the sections read `Home › Page`.

A 3 px bar under the topbar carries the area colour (green Requirements, blue
Architecture, red organisation) on pages of an area; home, help and
search have none. The ≡ menu holds Configure · Theme · Who's here · Help ·
Reload · Disconnect all. The footer holds formalities only: "Read-only
dashboard for Systems42 LLM wiki" (linked to the help section on the LLM
wiki), the live dot with the client count, the refresh time, Metamodel, Help, the
dashboard's own release (`VERSION`) and the Python mark. When `dashboard_version:`
in `wiki.yaml` names another release, one more line says so. Quote the value
(`dashboard_version: "1.10.0"`): unquoted, YAML reads `1.10` as the number 1.1,
and the dashboard logs a warning. The dot pulses while the server answers and stops, grey, when the
connection is lost.

## Visual identity

Flat panels with hairline borders and one border radius — no gradients, no
glow, no drop-shadow hover lift, no emoji anywhere (DR-025). Text, headings
and numbers use the vendored variable font **Bricolage Grotesque**; IDs, code
and eyebrows use vendored **JetBrains Mono** — both offline (OFL-licensed
woff2 under `static/vendor/fonts/`, see that folder's README), replacing
system fonts. A maturity bar (draft → review → accepted → deprecated) sits
under every tile count and list-page heading; issue statuses map onto
the same four steps. Counts are always spelled out in words ("3 stories · 1
feature", "4 links"), never bare letters or glyphs, via the single `plural()`
macro in `templates/_macros.html`.

The mark, the favicon and an optional intro animation on the home page are the
only product-specific look. They form a brand, and a wiki picks one in
`_system/wiki.yaml`: `brand: systems42` (the default) or `brand: atrium` names an
example brand shipped in `brands/`, `brand: brand/` names a folder of the wiki
repository. `intro: off` hides the intro. Switching is one changed key and a
reload. The dashboard only reads a wiki's brand folder and serves its marks at
`/brand/<file>`. A folder outside the repository, missing or without all three
marks falls back to `systems42` with a log warning, as does a `brand:` that is
not text (`brand: on`). Marks are served with a one-year cache while the URL's
`?v=` matches the file's checksum. A brand's `intro.html` and marks run in every
viewer's browser, so review them like code. `brands/README.md` states
what a brand must contain and what its intro must do.

## Home, areas and tiles

The section structure follows the Systems42 sections diagram and lives in one
place, `catalog.py`: three areas, eighteen sections (DR-033).

The home page (`/`) opens with the vault name and its tagline. Below it come two
peaks, **Requirements** and **Architecture**, and between them the *valley*:
vault status, latest changes, open issues and links to the decisions and to
Help. **Commons** runs full-width underneath. Each peak links to its area page.

The area pages `/req42`, `/arc42` and `/commons` show one tile per section,
rendered by `templates/_tile.html`. A tile carries the section ID, its title,
a count or short list of its pages and links to the section route. Sections
hidden in `_system/dashboard.yaml` drop off the tiles; a hidden area loses its
colour bar but its page still renders. A section's scope is `in` (captured in
wiki folders), `out` (deliberately not captured, an inactive tile) or `planned`
(arc42, no wiki folders yet; "not captured yet").

| ID | Area | Tile shows | Route |
|----|------|------------|-------|
| **R1** Vision & Goals | Requirements | the vision claim line and the objectives with covering epic/use-case counts | `/goals` |
| **R2** Resources & Staff | Requirements | out of scope, inactive tile | — |
| **R3** Functional Requirements | Requirements | all functional requirements (FR pages + use cases), broken down by epic/feature/story/use case, a per-epic breakdown and the use cases | `/req42/functional-requirements` |
| **R4** Supporting Models | Requirements | activity-model and data-model page counts | `/req42/models` |
| **R5** Team Structure | Requirements | out of scope, inactive tile | — |
| **R6** Roadmap | Requirements | out of scope, inactive tile | — |
| **A1** Solution Strategy | Architecture | planned, "not captured yet" | — |
| **A2** Building Block View | Architecture | planned | — |
| **A3** Deployment View | Architecture | planned | — |
| **A4** Runtime View | Architecture | planned | — |
| **A5** Crosscutting Concepts | Architecture | planned | — |
| **C1** Quality Requirements | Commons | scenario count and list | `/req42/quality` |
| **C2** Constraints | Commons | constraint count and list | `/req42/constraints` |
| **C3** Scope & Context | Commons | external interfaces; system boundary and context diagram | `/req42/scope` |
| **C4** Stakeholders | Commons | persona count and list; profile, influence, interest | `/stakeholders` |
| **C5** Domain Terms | Commons | term count and a per-term relation list; term network at `/graph/glossary` | `/glossary` |
| **C6** Issues | Commons | open issues, most severe first; filterable All / Open / Closed | `/issues` |
| **C7** Decisions | Commons | decision records (`wiki/decisions/`, MADR); filterable by kind architecture / business / undefined, expands the full text of a row | `/decisions` |

The sections diagram on `/help` still draws A6 Architecture Decisions; the
dashboard shows them as C7, together with business decisions (FR-009, DR-034).
`/adrs` and `/page/adr/<stem>` redirect to `/decisions` and to the decision
record that kept the ADR's number. A project spawned with `make new` starts
with an empty list. Section routes are unchanged from before the
restructure; `/req42` changed meaning from reading-order overview to the
Requirements area page.

Every tile that has no content yet renders a shared empty state naming the next
step, rather than a placeholder — a fresh vault is the normal day-one state.

The in-tile lists show ~4–5 rows and scroll for the rest. The relation count is
the number of distinct other wiki pages a page links to (frontmatter `related:`
plus body `[[wikilinks]]`), excluding self-references and `raw/` provenance
links. An issue counts as **closed** when its status is `resolved` or `wontfix`.
"Latest changes" and "last change" read the files' modification times, so a
freshly regenerated vault shows up on the next page refresh. The status strip's
source count comes from `raw/sources/` (`RAW_SOURCES_DIR`, mounted read-only at
`/sources` in Docker); it is the only folder outside `wiki/`
the dashboard reads.

## Configure

The ≡ menu's Configure dialog (`static/settings.js`, `GET`/`POST /settings`)
lists every area and section with a checkbox; unchecked ones form the hide list
in `_system/dashboard.yaml`, for example `hidden: [R2, R5, R6]`. Everyone can
open the dialog; only the facilitator ("Yoda") can save. The file is
hand-editable, an unknown entry is a warning rather than an error, and a
missing file hides nothing. It is the only file the dashboard writes, rewritten
in place through a read-write bind mount of that one file; `dashboard.sh` and
`make new` create it, `make sync` leaves it alone. Hidden sections keep their
routes and search hits. `POST /settings` rejects unknown IDs with 400 and
writes nothing. `wiki.yaml` stays project identity only.

Hand edits made with an editor that saves via temp-file-and-rename may not
reach the running container (the single-file bind mount keeps the old inode);
restart with `./dashboard.sh down && ./dashboard.sh`. Hand-written comments in
the file are replaced by the standard header on the next Configure save.

## Help

`/help` renders `help.md` together with the Systems42 sections diagram
(`static/systems42-sections.svg`, shown as an image so it works offline). It
explains how to read the dashboard and the area model; it is linked from the
≡ menu and the valley on the home page.

## About page

`/about` shows one page of the project's own documentation, for example a brand
guide explaining the system's name and mark. It exists only while `about:` in
`_system/wiki.yaml` names a markdown file under `docs/`
(`about: docs/brand/README.md`); then the hero mark becomes a link to it and a
text link appears under the tagline. `about_label:` sets the link text and page
title (default "About <system_name>"). Relative image and link URLs in the page,
`../` included, are resolved against its folder and served as
`/about/files/<path under docs/>`. Paths are resolved before they are checked,
so neither `..` nor a symlink reaches a file outside `docs/` (404). `docs/` is
mounted read-only at `/docs` (`DOCS_DIR`).

## Metamodel page

`/metamodel` (≡ menu, footer, linked from `/help`) explains the wiki's
metamodel (DR-035) from `_system/metamodel/`, read live by `metamodel.py`:
the content types as a cytoscape network grouped by section with every
declared relation as a labelled arrow (`static/metamodel-graph.js`, same
visual language as the term network), then tables — types with definition,
fields, stereotypes and a live example page of the vault; relations with
direction, cardinality and whether the reverse side is stored; projections
with the fields they read and the route that renders them; the granularity
scale with its open assignments; the rules; and the meta-meta language
(constructs, universal fields, lifecycles). Metamodel wikilinks resolve to
in-page anchors, decision-record links to `/decisions`, method anchors to
chips. The folder is mounted read-only at `/metamodel` in the container
(`METAMODEL_DIR`).

## Diagrams (mermaid)

The **system-context diagram** is not stored — it is *projected live* from the
wiki edges (DR-013): `build_context_diagram()` reads each external interface's
`flows:` and each stakeholder's `provides:`/`receives:` and emits a mermaid
flowchart (centre = the system, blue box; systems and organizations = light-grey
boxes; human roles = actor symbol 👤). Stakeholders are merged into shared
nodes, hidden, or shaped (person vs. organization) via their `context_role` /
`nature` frontmatter (DR-014). It is embedded on the context detail page
(`/page/context/…`) and on the req42 Scope page (`/req42/scope`).

The **goal tree** (vision → objectives) and the **goal/epic map** on
`/req42/functional-requirements` are projections in the same style, built from the goal pages'
`stereotype:`/`parent:` fields and each FR's `goal:` field (DR-016, DR-018).

mermaid.js is **vendored for offline use** at `static/vendor/mermaid.min.js` (no
CDN at runtime; see that folder's README for versions and licenses) and loaded
via `templates/_mermaid.html`. The same loader renders any fenced ` ```mermaid `
block in a page body, so extra diagrams can go straight into the markdown. The
glossary term network at `/graph/glossary` uses the vendored cytoscape bundle
plus `static/glossary-graph.js`.

## Provenance

Every wiki page's frontmatter `sources:` list is resolved and rendered as
chips right under the page header (`provenance_chips()` in
`templates/_provenance.html`) — one chip per source, linking to `/source/<stem>`,
or a dashed "unresolved" chip if the record is missing; a page with no
`sources:` at all shows an amber "unsourced" chip instead. `/source/<stem>`
renders one `raw/sources/` provenance record (type, origin, captured date,
checksum) plus the wiki pages it fed (`ingested-pages:`, resolved to real
links). The records themselves come from `raw/sources/` (`RAW_SOURCES_DIR`,
mounted read-only at `/sources` in Docker) — the same folder the home page's
status-strip source count already reads.

## Layout

```
_system/apps/dashboard/
  app.py             Flask app + wiki parser + all diagram projections
  catalog.py         the three areas and eighteen sections (labels, folders, routes, colours)
  metamodel.py       reader for _system/metamodel/ (the /metamodel page, ADR-0008)
  help.md            source of the /help page
  templates/         base, index, _empty (shared empty state), _macros (plural()),
                     _maturity (maturity bar/legend), _mermaid (loader),
                     _provenance (sources chips), glossary, graph, stakeholders,
                     issues, decisions, search, detail, goals, functional_requirements, fr, data_model,
                     req42_block, _tile (section tile), area (area pages), help, metamodel, join, who
  static/style.css   dashboard styling
  static/glossary-graph.js   the cytoscape term network
  static/list-view.js        the shared list layer: a th[data-sort] sorts by its
                             cells' data-sort-value (else their text), a
                             table[data-list] adds sort orders, "agreed only" and
                             keeps both in the address (?sort=, ?status=)
  static/metamodel-graph.js  the cytoscape metamodel network on /metamodel
  static/settings.js   the Configure dialog
  static/systems42-sections.svg   the sections diagram shown on /help
  static/systems42-logo.svg, systems42-favicon.png   the Systems42 mark
  brands/            the example brands systems42 and atrium (marks, favicon,
                     intro.html) and the brand contract (README.md)
  VERSION            the dashboard's own release, shown in the footer
  static/vendor/     vendored mermaid + cytoscape + fonts (offline, no CDN)
  tests/             plain-assert test scripts (no pytest) + a fixture vault
  Dockerfile         python:3.12-slim + gunicorn
  compose.yaml       service def, mounts ${WIKI_DIR}:/wiki:ro,
                     ${SOURCES_DIR}:/sources:ro, ${DOCS_DIR}:/docs:ro, ${REPO_DIR}:/repo:ro
                     (for a wiki's own brand folder), and the one read-write settings
                     mount ${DASHBOARD_CONFIG}:/config/dashboard.yaml
```

## Tests

Plain Python scripts with bare `assert`s — no pytest, no runner. From this
directory, inside the venv `./dashboard.sh local` builds:

```sh
for t in tests/test_*.py; do .venv/bin/python "$t" || echo "FAILED: $t"; done
```

Each script also runs on its own, which is what you want while working on one:

```sh
.venv/bin/python tests/test_reload.py
```

The `|| echo` is not decoration. A `for` loop reports only its last iteration's
status, so without it a test failing in the middle scrolls past and the shell
still exits 0.

They cover the empty vault (every route must render on day one), a populated
fixture vault, the functional-requirements hierarchy and goal projections, the glossary graphs, the
context diagram projection (one line per neighbour, short labels, `tier:` bands,
and deprecated interfaces drawn nowhere), the data-model class diagram (DM pages
plus marked glossary terms as `<<term>>` stubs, context and focus filters),
`wiki_config()`, the `/about` page and its path guard, the decision records in
`wiki/decisions/` and the old ADR redirects, presence and the "Yoda" facilitator, the light/dark theme
contract, the `/reload` control (server-side caches cleared, `static_url`
versioning), the copy contract (client wording with correct plurals, no glyph
abbreviations, DR-025 is indexed), and two contracts that would otherwise
drift in silence — `_templates/` against `app.py`'s parser, and the skills the
workflows name against the ones vendored under `.agents/skills/`. The
three-area restructure is pinned by `test_catalog.py` (every wiki folder
belongs to exactly one section), `test_dashboard_config.py` (the hide list and
its in-place write), `test_areas.py`, `test_area_chrome.py` (breadcrumbs,
colour bar), `test_menu.py`, `test_help.py` and `test_home_layout.py`.
`test_config_isolation.py` keeps every script that imports `app` on its own
`DASHBOARD_CONFIG`, so a project's hide list never reaches the tests.
The metamodel is pinned twice: `test_metamodel_lint.py` runs
`_system/scripts/metamodel-lint.py` (templates, folders, anchors and the
catalog must agree with `_system/metamodel/`), and `test_metamodel_page.py`
checks the `/metamodel` page (loader, graph as a pure projection, every type a
row with an anchor and a colour token, wikilink resolution, live examples).

## Obsidian

Hidden automatically: `_system/` is in `.obsidian/app.json` →
`userIgnoreFilters`, and `"showUnsupportedFiles": false` keeps the non-markdown
code files out of the file explorer. No extra configuration needed.
