# Requirements-Wiki Dashboard

A dashboard over the `wiki/` layer, read-only
as far as the wiki goes. It parses the markdown pages live on each request —
nothing in the repository is ever written — and renders them as tiles.

## Run

From the repository root:

```sh
./dashboard.sh          # start the release this wiki names, opens http://localhost:8080
./dashboard.sh down     # stop
./dashboard.sh logs     # follow logs
./dashboard.sh update   # name the newest release in _system/wiki.yaml
./dashboard.sh clean    # remove what can be rebuilt: container, caches
```

`dashboard.sh` is the launcher (FR-042), the only dashboard code a wiki holds.
It reads `dashboard_version:` from `_system/wiki.yaml` and starts the image
`ghcr.io/systems42-org/dashboard:<version>`, pulling it on the first start.
`update` asks GitHub for the newest release and writes that one line. A wiki
that names no release is told to run `update`.

**Without Docker.** `./dashboard.sh uv` (also `make uv`) starts the same
release with [uv](https://docs.astral.sh/uv/), for machines where Docker
cannot run, such as a virtual machine (FR-054). uv is then the one thing to
install. It fetches Python 3.12 and the release's wheel from the GitHub
release, and a release fetched once starts without network. The dashboard
runs in the foreground at the same address: Ctrl+C stops it, and so does
closing the last browser tab. `DASH_WHEEL` names a wheel file or address to
run instead, for a machine without network. Releases up to 0.12.0 have no
wheel. With `dashboard_version: local` it runs the code in this repository.

**One mount.** The launcher mounts the repository read-only at `/repo`. The
dashboard writes nothing there (see View). The image sets `REPO_DIR=/repo`, and the dashboard finds
`wiki/`, `raw/sources/`, `docs/`, `_system/metamodel/`, `_system/anchors/` and
`_system/wiki.yaml` below it. So the dashboard always shows the current state
of the wiki: refresh the browser after editing.

**Systems42 wikis only** (CON-005). Before it starts, the dashboard checks
that the repository holds `wiki/`, `raw/`, `_system/wiki.yaml`,
`_system/metamodel/` and `_system/anchors/` (`preflight.py`). If one is
missing, it names it and stops, and the launcher shows that message.

`clean` (also `make clean`) never touches `wiki/`, `raw/`, `docs/`, `sandbox/`,
the settings files or `harvest-*.patch`. It leaves a pulled release image in
place, because other wikis on the machine may use it. Without a reachable
Docker it says so and still removes the local files.

### In this repository

This repository holds the dashboard code, so it names `dashboard_version:
local`: the launcher builds the image from `_system/apps/dashboard/` at every
start. The launcher hands every command it does not know to `dev.sh` here:

```sh
./dashboard.sh rebuild  # build the local image from scratch, then start
./dashboard.sh local    # no Docker: run Flask directly on http://localhost:8000
./dashboard.sh test     # run the test scripts in Docker (also `make test`)
```

`local` is the older way to run without Docker and promises nothing. Use
`./dashboard.sh uv` instead, which runs the server of the image. `local`
builds a `.venv/` here on first run (~20 s), installs the requirements again
whenever `requirements.txt` has changed, and serves the same app until you
press Ctrl+C. It refuses to start while something already answers on port 8000.

### Releases

A release takes three steps, all from `main`:

1. `make version V=1.2.3` raises `VERSION` and names the release in
   `CHANGELOG.md`, on a branch `release-1.2.3`, and opens a pull request.
   Without `V` it says which version is next.
2. Merge that pull request.
3. `make publish` sets the tag `v1.2.3` and pushes it. It first brings `main`
   up to date, and it refuses when the release exists already, is lower than
   the newest one, is missing in `CHANGELOG.md`, or the tests fail. Each
   refusal says what to do next.

A git tag `vX.Y.Z` that matches `VERSION` runs `.github/workflows/release.yml`:
the tests, then an image for amd64 and arm64 under
`ghcr.io/systems42-org/dashboard:X.Y.Z` and `:latest`, then a GitHub release,
which is what `update` asks for (DR-004, FR-030). The release carries the
wheel `systems42_dashboard-X.Y.Z-py3-none-any.whl`, built from
`pyproject.toml` (DR-007). The wheel holds the files the `Dockerfile` copies:
a file added to one must be added to the other, and `tests/test_uv_start.py`
fails when they differ.

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
comes from `catalog.py`, which reads the section titles from the metamodel,
so a section has one name everywhere (FR-017, FR-044).
Breadcrumbs under the bar read `Home › Area › Section › Page`, following
where a page belongs (FR-020). Pages outside the sections read `Home › Page`.

A 3 px bar under the topbar carries the area colour (green Requirements, blue
Architecture, red organisation) on pages of an area; home, help and
search have none. The ≡ menu holds View · Theme · Who's here · Help ·
Reload · Disconnect all. The footer holds formalities only: "Read-only
dashboard for Systems42 LLM wiki" (linked to the help section on the LLM
wiki), the live dot with the client count, the refresh time, Method, Metamodel, Help, the
dashboard's own release (`VERSION`) and the Python mark. When `dashboard_version:`
in `wiki.yaml` names another release, one more line says so. When the
repository's metamodel version is not one this release supports
(`SUPPORTED_VERSIONS` in `metamodel.py`), or declares none, another line says
so and links to the version section of `/metamodel` (FR-043). Quote the value
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
`_system/wiki.yaml`: `brand: systems42` (the default) names the
brand shipped in `brands/`, `brand: brand/` names a folder of the wiki
repository. `intro: off` hides the intro. Switching is one changed key and a
reload. The dashboard only reads a wiki's brand folder and serves its marks at
`/brand/<file>`. A folder outside the repository, missing or without all three
marks falls back to `systems42` with a log warning, as does a `brand:` that is
not text (`brand: on`). Marks are served with a one-year cache while the URL's
`?v=` matches the file's checksum. A brand's `intro.html` never becomes part of a
page: the home page shows it in a sandboxed frame, where its script has none
of the dashboard's rights. `brands/README.md` states what a brand must
contain and what its intro must do.

Every HTML page carries a Content Security Policy. Script runs only from the
dashboard's own files and from the inline blocks of its templates, which carry
a nonce: write an inline script in a template as
`<script nonce="{{ csp_nonce() }}">`, or it will not run. Pages load nothing
from outside the dashboard. Wiki content keeps an image only when its `src` is
a path of the dashboard, and no style that loads something (`url()`).

## Home, areas and tiles

The section structure follows the Systems42 sections diagram (DR-033).
`catalog.py` holds the three areas and reads the sections from the framework
blocks in `_system/metamodel/frameworks/` of the repository (FR-044): id,
title, folders (from each listed type's `folder:`), scope and note. A
section's area is the `area:` of its framework file. The dashboard adds the
routes and colours of the sections it knows. A section it does not know gets
the generic list at `/section/<id>`, a generic tile and its area's colours.

The home page (`/`) opens with the vault name and the first sentence of the
vision, the goal page with `stereotype: vision`. Without a vision it shows the
tagline (FR-018). Below it come two
peaks, **Requirements** and **Architecture**, and between them the *valley*:
vault status, latest changes, open issues and links to the decisions and to
Help. **Commons** runs full-width underneath. Each peak links to its area page.
Each area tile lists its sections with the count their section tile shows.

The area pages `/req42`, `/arc42` and `/commons` show one tile per section,
rendered by `templates/_tile.html`. A tile carries the section ID, its title,
a count, the maturity bar and the open-issue flag, and links to the section
route. It names no pages (FR-019). Sections
hidden in the view drop off the tiles; a hidden area loses its
colour bar but its page still renders. A section's scope is `in` (captured in
wiki folders), `out` (deliberately not captured, an inactive tile) or `planned`
(arc42, no wiki folders yet; "not captured yet").

| ID | Area | Tile shows | Route |
|----|------|------------|-------|
| **R1** Vision & Goals | Requirements | goal count, the vision and its objectives | `/goals` |
| **R2** Resources & Staff | Requirements | out of scope, inactive tile | — |
| **R3** Functional Requirements | Requirements | count of all functional requirements of every notation (DR-038) | `/req42/functional-requirements` |
| **R4** Supporting Models | Requirements | count of model pages: activity models and the entity diagram | `/req42/models` |
| **R5** Team Structure | Requirements | out of scope, inactive tile | — |
| **R6** Roadmap | Requirements | out of scope, inactive tile | — |
| **A1** Solution Strategy | Architecture | planned, "not captured yet" | — |
| **A2** Building Block View | Architecture | planned | — |
| **A3** Deployment View | Architecture | planned | — |
| **A4** Runtime View | Architecture | planned | — |
| **A5** Crosscutting Concepts | Architecture | planned | — |
| **C1** Quality Requirements | Commons | scenario count | `/req42/quality` |
| **C2** Constraints | Commons | constraint count | `/req42/constraints` |
| **C3** Scope & Context | Commons | external interface count | `/req42/scope` |
| **C4** Stakeholders | Commons | persona count | `/stakeholders` |
| **C5** Domain Terms | Commons | term count, links to the table and to the term network at `/graph/domain-terms` | `/domain-terms` |
| **C6** Issues | Commons | count of all issues, the open ones as the flag (link to `/issues?status=open`) | `/issues` |
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

The relation count is
the number of distinct other wiki pages a page links to (frontmatter `related:`
plus body `[[wikilinks]]`), excluding self-references and `raw/` provenance
links. An issue counts as **closed** when its status is `resolved` or `wontfix`.
"Latest changes" and "last change" read the files' modification times, so a
freshly regenerated vault shows up on the next page refresh. The status strip's
source count comes from `raw/sources/`.

## View

The ≡ menu's View dialog (`static/settings.js`, `GET`/`POST /settings`) lists
every area and section with a checkbox; unchecked ones form the hide list of
this session (FR-046). Everyone can open the dialog; only the facilitator
("Yoda") can save. The view lives in the running dashboard only: no file holds
it, and after a restart everything shows again. Hidden sections keep their
routes and search hits. `POST /settings` rejects unknown IDs with 400 and
changes nothing. `wiki.yaml` stays project identity only.

Releases up to 0.11.4 saved the view in `_system/dashboard.yaml`. This release
ignores the file. The launcher still mounts it where a wiki has one, so an
older release keeps working. A wiki that runs this release or a newer one can
delete it.

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
so neither `..` nor a symlink reaches a file outside `docs/` (404).

## Method page

`/method` (footer) explains the three loops capture, inspect and clarify on one
screen (FR-011). While `ISS-002-define-the-clarify-loop` is open, the clarify
part says it is being defined and links that issue.

## Metamodel page

`/metamodel` (≡ menu, footer, linked from `/help`) explains the wiki's
metamodel (DR-035) from `_system/metamodel/`, read live by `metamodel.py`:
the content types as a cytoscape network grouped by section with every
declared relation as a labelled arrow (`static/metamodel-graph.js`, same
visual language as the term network), then tables — types with definition,
fields, stereotypes and a live example page of the vault; relations with
direction, cardinality and whether the reverse side is stored; projections
with the fields they read and the route that renders them; the requirement
notations (DR-038) with their levels, extra fields and level-marked page
sections, read from `_system/metamodel/notations/` and a project's own
`_system/notations/`, the `default_notation:` of `wiki.yaml` first; the rules; and the meta-meta language
(constructs, universal fields, lifecycles). Metamodel wikilinks resolve to
in-page anchors, decision-record links to `/decisions`, method anchors to
chips. It is the metamodel of the repository the dashboard runs on
(`_system/metamodel/`).

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
glossary term network at `/graph/domain-terms` uses the vendored cytoscape bundle
plus `static/glossary-graph.js`.

## Provenance

Every wiki page's frontmatter `sources:` list is resolved and rendered as
chips right under the page header (`provenance_chips()` in
`templates/_provenance.html`) — one chip per source, linking to `/source/<stem>`,
or a dashed "unresolved" chip if the record is missing; a page with no
`sources:` at all shows an amber "unsourced" chip instead. `/source/<stem>`
renders one `raw/sources/` provenance record (type, origin, captured date,
checksum) plus the wiki pages it fed (`ingested-pages:`, resolved to real
links). The records themselves come from `raw/sources/`, the same folder the home page's
status-strip source count already reads.

## Layout

```
_system/apps/dashboard/
  app.py             Flask app + wiki parser + all diagram projections
  catalog.py         the three areas, and the sections from the metamodel with routes and colours
  metamodel.py       reader for _system/metamodel/ (the /metamodel page, ADR-0008)
  help.md            source of the /help page
  templates/         base, index, _empty (shared empty state), _macros (plural()),
                     _maturity (maturity bar/legend), _mermaid (loader),
                     _provenance (sources chips), glossary, graph, stakeholders,
                     issues, decisions, search, detail, goals, functional_requirements, fr, data_model,
                     req42_block, _tile (section tile), area (area pages), help, method, metamodel, join, who
  static/style.css   dashboard styling
  static/glossary-graph.js   the cytoscape term network
  static/list-view.js        the shared list layer: a th[data-sort] sorts by its
                             cells' data-sort-value (else their text), a
                             table[data-list] adds sort orders, "agreed only" and
                             keeps both in the address (?sort=, ?status=)
  static/metamodel-graph.js  the cytoscape metamodel network on /metamodel
  static/settings.js   the View dialog
  static/systems42-sections.svg   the sections diagram shown on /help
  static/systems42-logo.svg, systems42-favicon.png   the Systems42 mark
  brands/            the shipped brand systems42 (marks, favicon, intro.html)
                     and the brand contract (README.md)
  VERSION            the dashboard's own release, shown in the footer
  static/vendor/     vendored mermaid + cytoscape + fonts (offline, no CDN)
  tests/             plain-assert test scripts (no pytest) + a fixture vault
  Dockerfile         python:3.12-slim + gunicorn, and a `test` stage for `make test`
  preflight.py       the check that the repository is a Systems42 wiki (CON-005)
  gunicorn.conf.py   runs that check before the app is loaded
  dev.sh             rebuild, local and test, reached through ../../../dashboard.sh
```

## Tests

For visual inspection of domain terms, relationships and multiplicities, open
the [order model fixture](tests/fixtures/domain-model/README.md). Its README
includes the startup command and the expected diagrams.

Plain Python scripts with bare `assert`s, no pytest. From the repository root:

```sh
make test
```

It runs every script in Docker and lists the ones that failed, with their
output. It exits 1 if any failed. The scripts run in the `test` stage of the
`Dockerfile`: the Python and the libraries of the shipped image, plus `make`,
`node` and Playwright with Chromium, which some scripts call. The repository is mounted read-only and
copied inside the container, so a test cannot change a file on the host. The
first run needs network to build the stage.

While working on one script, run it in the venv `./dashboard.sh local` builds,
from this directory:

```sh
.venv/bin/python tests/test_reload.py
```

`sh tests/run-all.sh .venv/bin/python` runs all of them there. Without `node`
on the machine, the scripts that need it skip their JavaScript checks.

One test needs a browser: `tests/test_mermaid_browser.py` starts the dashboard
on a throwaway vault and checks in headless Chromium that the vendored mermaid
actually draws the context diagram, the entity diagram and fenced
```` ```mermaid ```` blocks, survives the theme re-render, logs no JavaScript
errors, and is the version `static/vendor/README.md` names. Run it after every
mermaid update. `make test` runs it. Its dependencies stay out of the shipped
image. To run it in the venv, install them there:

```sh
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m playwright install chromium
```

Without them it prints `SKIP` and exits 77. `run-all.sh` counts a script that
exits 77 as skipped, not passed, and names it in the summary.

pytest can run one script (`pytest tests/test_reload.py`), but not the whole
folder: each script points the app at its own throwaway vault before
`import app`, so in one shared process only the first one counts.
`tests/conftest.py` stops such a run with this hint.

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
belongs to exactly one section), `test_sections_from_metamodel.py` (a renamed
and an added section show without a code change, FR-044), `test_view.py` (the view, its lifetime
and the success metric of FR-046), `test_areas.py`, `test_area_chrome.py` (breadcrumbs,
colour bar), `test_menu.py`, `test_help.py` and `test_home_layout.py`.
The metamodel is pinned twice: `test_metamodel_lint.py` runs
`_system/scripts/metamodel-lint.py` (templates, folders and anchors must
agree with `_system/metamodel/`, with no dashboard code present), and `test_metamodel_page.py`
checks the `/metamodel` page (loader, graph as a pure projection, every type a
row with an anchor and a colour token, wikilink resolution, live examples).

## Go implementation (Phase 0)

A second implementation of the dashboard in Go lives in this folder next to the
Python reference (FR-055, DR-007, issue #80). Both share `static/`,
`templates/`, `brands/`, `help.md` and `VERSION` without copies (`assets.go`
embeds them with `go:embed`). `Dockerfile` and `pyproject.toml` name their
files one by one, so Go files stay out of the container image and the wheel.

Build and run without cgo from this directory:

```sh
CGO_ENABLED=0 go build ./cmd/systems42-dashboard
./systems42-dashboard --version
./systems42-dashboard /path/to/systems42-wiki
```

Run the Go unit tests and the Python vs Go parity test:

```sh
go test -race ./...
uv run --no-project --python 3.12 --with-requirements requirements.txt python tests/test_parity.py
```

`tests/test_parity.py` starts both implementations on every wiki under
`tests/fixtures/`, a synthetic notices wiki and this repository's own wiki,
then compares status codes, CSP and framing headers, normalised HTML, JSON and
static bytes. Routes not ported yet sit in `UNPORTED_EXACT` and
`UNPORTED_PREFIXES` and shrink with each phase.

**Template spike (issue #80, question 2).** The Go dashboard runs the existing
40 Jinja2 templates directly through `github.com/nikolalohinski/gonja/v2`
instead of porting them to `html/template`. Four targeted shims in
`internal/web/templates.go` cover what `gonja/v2` omits: N-tuple `for`
unpacking (`base.html`, `_list.html`), top-level `from`/`import`/`set`/`macro`
statements in child templates that extend `base.html`, module-scoped
`from ... import ...` for sibling and chained macros (`_trace.html`,
`_macros.html`, `_list.html`, `_tile.html`), and preserving the safe flag on
block-`set` captures (`crumbs_html` in `base.html`). `internal/web/template_spike_test.go`
verifies all 40 templates parse and tests `base.html`, `_macros.html` and
`detail.html` under the race detector.

## Obsidian

Hidden automatically: `_system/` is in `.obsidian/app.json` →
`userIgnoreFilters`, and `"showUnsupportedFiles": false` keeps the non-markdown
code files out of the file explorer. No extra configuration needed.
