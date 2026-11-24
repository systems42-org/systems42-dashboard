# Changelog

What changed in the Systems42 **product** — the method files a project ships
with: `AGENTS.md`, templates, anchors, workflows, skills, dashboard, docs. One
entry per user-visible change, newest first. Decisions behind the changes are
decision records in the Systems42 meta repository's `wiki/decisions/` (cited
here as DR-NNN; they do not ship); day-to-day operations on *this* wiki's content are in
`_system/log.md`, not here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Unreleased changes sit at the top until the next Starter Kit release.

## [Unreleased]

### Fixed
- Dashboard: a date that is none (`created: 2026-13-01`, `2026-02-30`) in one wiki page, in `wiki.yaml` or in a metamodel file no longer answers every route with an error. The value stays as the text that was written, and the other fields of the file count. Bytes that are not UTF-8 in `wiki.yaml`, a metamodel file or an anchor no longer do so either: that file is ignored. For each such file the log names the file and the problem, and it now does so for malformed YAML and for wiki pages that are not UTF-8 as well (#176).
- Dashboard: the term network lists the page types behind its "More" button in alphabetical order, as the Go dashboard does. Before, the order followed the links of the terms, so the two dashboards differed.
- Dashboard: a term page shows the term's kind and aliases, and for a structured term its attributes and its relationships with type, linked target and multiplicity. The term list has a Kind column and a kind filter (`?kind=entity`, `?kind=none`) that works together with the status filter. Before, both pages left these frontmatter fields out (#177).
- Dashboard: `search_plain()` in `app.py` now strips Markdown emphasis and backticks as intended instead of matching the later `_emphasis()` regex of the same name.
- Launcher: `./dashboard.sh uv` loads only the dashboard's own modules. Started from a folder that holds an `app.py` or `preflight.py`, it used to load those instead. Relative path settings such as `WIKI_CONFIG` still mean the folder they were given in. When the port is busy, the message names Ctrl+C for a uv start, not only `./dashboard.sh down`, which needs Docker.
- Dashboard: a wikilink inside inline code or a fenced code block shows as written, on wiki pages and on /metamodel, instead of as an escaped link tag. A `~~~` fence renders as code instead of being joined into the paragraph around it.
- Dashboard: Reload now also clears the cached metamodel and anchor pages, and a wiki page rewritten with the same mtime but a different size is read again without a reload (#58).
- Dashboard: a functional requirement page renders in 12 ms instead of 35 ms, because each page's links are worked out once. Deleted pages and anchors leave the parse caches, the caches take a lock under gunicorn's four threads, and link titles come from the same pages the lists show (#68).
- Dashboard: the Keyholder keeps the rights while their tab is in the background. Only a tab that closes or stops pinging for 90 s hands them on.
- Dashboard: `DASH_NO_SHUTDOWN=1` keeps the dashboard running after the last browser tab has closed, in the Python and the Go dashboard, and `dashboard.sh` hands it to the container. The watchdog now starts with the server (`gunicorn.conf.py`, `python app.py`) and stops only the Gunicorn master that started it. Before, `import app` started it, so a site export or a test that ran longer than 90 s sent SIGTERM to itself and to its parent process (#182).
- Launcher: `dashboard.sh` names the container after the wiki's folder plus a checksum of its path, so two wikis in folders of the same name no longer stop each other. `down`, `logs`, `clean` and a new start also handle this wiki's container under the old name.
- Dashboard: `/goals` shows the objective cards and the goal coverage matrix when no vision page exists yet.
- Dashboard: the requirement hierarchy shows every live Agile feature and story once. A feature the story map cannot place under an epic or a use case is listed under "Orphaned requirements" with its stories, and its page shows them in the breakdown and the detail diagram. Before, the story of a feature without a parent showed nowhere but the flat list, and so did features and stories in a `parent:` cycle or under a page that takes no such child (#179).
- Dashboard: `*emphasis*` in a quality scenario no longer breaks a link that contains a `*`.
- Dashboard: the view dialog can save when the browser blocks session storage.
- Dashboard: the "Disconnect all" question counts the other clients, without the facilitator's own tab.
- Dashboard: `/ping`, `/leaving`, `/settings` and `/disconnect-all` answer 400 to a JSON body that is not an object, and the session stays as it was. An array, a string, a number or a boolean ended in HTTP 500 in the Python dashboard, and the Go dashboard read it as an empty body (#184).
- Dashboard: `/req42/<slug>` answers 404 for the arc42 sections, which live under `/arc42/`.
- Dashboard: `/issues?section=` ignores case, so `c2` filters like `C2`.
- Dashboard: the issue filters work in the static demo of the website. A changed filter stays on the demo's issue list, the list shows the issues the address asks for, also after a reload and with a sort order, and a section's issue count opens that section's open issues. Before, a changed filter led to `/issues` outside `/demo/`, a page that does not exist, and every address showed all issues. The site build now fails on a demo script that leaves `/demo/` (#181).
- Dashboard: the metamodel page links a projection's route only when it is a path on this site.
- Dashboard: the View dialog puts section ids and titles in as text, so
  markup in a framework file cannot reach the page.
- Dashboard: no page scrolls sideways on a 320 px phone screen (QR-001,
  issue #64). Below 640 px the nav entries move into the menu. Tables in page
  text and diagrams scroll inside their own box. `/metamodel`, `/join` and the
  About page fit the screen.
- Dashboard: on a functional requirement page the sources row no longer overlaps the row of pills above it.
- Dashboard: a functional requirement page shows its created date, updated date and tags under the title, like every other page. The requirement view left them out. A blank `created:` or `updated:` no longer shows as "None" (#183).

### Added
- Website: a "42" button in the header opens the 42 family, as on systems42.org: arc42, req42 and Systems42, each with its link. On a phone the three links are in the menu.
- Method: the Recover loop from meta (alias archeology). The `recover` skill and `_system/workflows/recover.md` recover the abstractions of existing code into a report for Capture, and write no wiki pages. `capture.md` says how a recovery report's open gaps are handled.
- Docs: `docs/INSTALL.md` says the app is supported on macOS and the programs for Linux and Windows come without support.
- Dashboard: `/arc42/strategy` shows arc42 section 4 (A1): the pages in `wiki/solution-strategy/` (type `solution-strategy`, prefix `SOL`), each with its state, its successor, its `drivers:` and the decisions it summarises. A1 links there once the metamodel captures the section. Strategy pages count under *Addressed by* like the other architecture pages (DR-040, issue #101).
- Docs: `docs/INSTALL.md` says step by step how to install, start, stop, update and remove the dashboard in its three forms (Docker, uv, app). The website shows it at `/docs/install/`.
- Docs: `site/README.md` says how the website is built.
- Distribution: branded macOS `.dmg` installer with Systems42 volume icon and drag-to-Applications Finder layout (`_system/apps/dashboard/macos/build-app.sh`), standalone static Go release binaries for Linux (`amd64`, `arm64`) and Windows (`amd64`) in `.github/workflows/release.yml`, and macOS `.dmg` plus Go binary download cards on `dashboard.systems42.org/downloads/`.
- Dashboard (Go, Phases 6 to 8): universal macOS desktop app (`Systems42 Dashboard.app` and `.dmg`, `make app-bundle`) with native AppKit menu-bar launcher, folder picker, Finder drag-and-drop, recent wikis in `~/Library/Application Support/Systems42 Dashboard/recent.json`, free port per wiki (`--port 0 --ready-json`), `--check` CON-005 preflight JSON, Homebrew cask (`_system/apps/dashboard/macos/Casks/systems42-dashboard.rb`), GitHub Actions macOS release packaging with optional Apple Developer ID signing and notarisation (`.github/workflows/release.yml`), PR parity checklist (`.github/PULL_REQUEST_TEMPLATE.md`), three-way startup documentation (`README.md`, `docs/GETTING-STARTED.md`, `help.md`), and the Go app requirements summary (`docs/go-dashboard-requirements-summary.md`) (FR-055, DR-007, issue #80).
- Dashboard (Go, footer): replaced the duplicate "Go" text next to the Go logo with "Built with" followed by the Go logo.
- Dashboard (Go, Phases 4 and 5): full search index, synonym groups, filters and facets in `internal/search` wired into `/search` and `/search.json` (with all 42 `tests/test_search_examples.py` queries verified against both Python and Go), plus `/join`, `/who`, `/help`, `/about`, `/about/files/<path>` (with relative URL rewriting, inert file CSP and symlink escape refusal), `GET`/`POST /settings` (session view hiding by the facilitator, FR-046) and the FR-050 self-shutdown watchdog in `internal/session` and `cmd/systems42-dashboard`. All 644 route parity checks pass across 7 wikis with 0 unported routes remaining (FR-055, DR-007, issue #80).
- Dashboard (Go, Phase 3): live Mermaid and cytoscape projections in `internal/project` (context diagram and flows, entity class diagram with bounded-context and focus filters, goals tree and goal-coverage matrix, Agile story map and FR detail subtrees, building-block white boxes, deployment diagrams and hints, runtime sequence diagrams and hints, crosscutting concepts, and the force-directed term network with per-term ego graphs), wired into `/goals`, `/entity-diagram`, `/data-model`, `/graph/domain-terms`, `/graph/glossary`, `/req42/scope`, `/req42/models`, `/req42/functional-requirements`, `/req42/backlog`, `/functional-requirements/<stem>`, `/arc42/building-blocks`, `/arc42/deployment`, `/arc42/runtime`, `/arc42/concepts`, and the projection-bearing `/page/` detail routes (579 parity checks across 7 wikis, FR-055, DR-007, issue #80).
- Dashboard (Go, Phase 2): full metamodel reader (`Load`, `Notations`, `Anchors`, `TypeForFolder`), area views (`/req42`, `/arc42`, `/commons`), generic block and section routes (`/req42/quality`, `/req42/constraints`, `/section/<id>`), `/metamodel` (including its cytoscape type-and-relation graph and live examples), `/method`, `/changes`, `/issues` (server-side filters in the address), `/stakeholders`, `/decisions` (and `/adrs` redirect), `/domain-terms` (and `/glossary` redirect), hostile-vault checks on every Phase 2 route, and 358 route parity checks across 7 wikis (FR-055, DR-007, issue #80).
- Dashboard (Go, Phase 1): Markdown rendering with `goldmark`, wikilinks (pages, sources and method anchors), Obsidian callouts, table wrapping, HTML sanitiser (`internal/render`), `/page/<folder>/<stem>` and `/source/<stem>` detail views with provenance, relations, traceability and issue panels, legacy ADR/FR/use-case redirects, Go hostile-vault security tests (`internal/web/hostile_vault_test.go`), and parity checks across all detail and source routes without diagram projections. Enlarged the Go logo in the footer and aligned the footer sub-line on one baseline (FR-055, DR-007, issue #80).
- Dashboard (Go, Phase 0): Go module under `_system/apps/dashboard/` (`cmd/systems42-dashboard/`, `internal/wiki`, `internal/metamodel`, `internal/web`), embedded static/brand/template assets via `go:embed`, CON-005 preflight, `wiki.yaml` reader, home page, `make app-start` (`./dashboard.sh app-start`), shared Jinja2 templates via `gonja/v2` (answering issue #80 question 2), Python vs Go parity test (`tests/test_parity.py`), and a `go` job in `.github/workflows/ci.yml` (FR-055, DR-007, issue #80).
- Dashboard: the diagram on a functional requirement's page also shows the building blocks whose `drivers:` name the requirement, with a dashed edge (FR-047, #66). A requirement without children shows the diagram when it has building blocks. Every page in the diagram is also a text link below it.
- Launcher: `./dashboard.sh uv` (also `make uv`) starts the release a wiki names with [uv](https://docs.astral.sh/uv/) instead of Docker, for machines where no container engine runs, such as a virtual machine. Every release from the next one on carries a wheel for it (FR-054, DR-007).
- Dashboard repository: GitHub Actions runs `./dashboard.sh test` on every pull
  request and push to `main` (`.github/workflows/ci.yml`). The test summary
  counts and names skipped scripts (exit code 77) instead of counting them as
  passed.
- Dashboard repository: `make test` runs the browser test
  (`test_mermaid_browser.py`). The Docker test stage installs Playwright 1.63.0
  from `requirements-dev.txt` and its headless Chromium.
- Dashboard: this release supports metamodel version 0.1 (FR-043). When the
  repository's metamodel declares another version or none, the footer says so
  and links to `/metamodel#version`, which names both versions and what to do.
  The dashboard reads `version:` from `_system/metamodel/metamodel-version.md`,
  else from `meta-metamodel.md`.
- Dashboard: `/method` explains the three loops capture, inspect and clarify
  on one screen (FR-011). The footer of every page links it. While ISS-002 is
  open, the clarify part says the loop is being defined and links that issue.
- Dashboard repository: a release takes `make version V=1.2.3`, a merge and
  `make publish`. `version` raises `VERSION` and opens the pull request.
  `publish` sets and pushes the tag only when the release does not exist yet
  and is not lower than the newest one, `CHANGELOG.md` names it and the tests
  pass. Both bring `main` up to date first, and every refusal says what to do
  next.

### Changed
- Dashboard release 0.14.9 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.8 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.7 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.6 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.5 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.4 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.14.3 (`_system/apps/dashboard/VERSION`).
- Dashboard: the home page, Help and the README no longer call Requirements and Architecture "peaks" or the column between them the "valley", since the Chart mark replaced the Peaks mark. Commons is "shared by both areas" (Python and Go).
- Website: the line under the hero buttons says how many pages of requirements and architecture the demo holds. It no longer counts "views", the exported HTML files.
- Dashboard release 0.14.2 (`_system/apps/dashboard/VERSION`).
- Website: the hero and the page headers show the Chart mark's six columns in mint and sky instead of the two peaks. The columns grow from left to right as in the dashboard's intro, not under reduced motion. On a phone all six columns show. The card titles carry a small column instead of a triangle.
- Dashboard brand: the Chart mark replaces the Peaks mark (FR-032). An axis with six columns, each a green Requirements block and a blue Architecture block, coloured by `--area-req`, `--area-arc` and `--ink`. Commons red is gone. The favicon is a reduced mark with three solid columns. The intro draws the axis, then grows the columns from left to right, about 2 s. `docs/brand/` adds a lockup with the wordmark "systems42 DASHBOARD" for use outside the dashboard. The Mac app icon still shows the peaks ([#172](https://github.com/systems42-org/systems42-dashboard/issues/172)).
- Website: the home page drops the card with four numbers, among them "0 install steps". The two peaks now stand free in the hero, and one line under the buttons says what the demo shows.
- Website: dashboard.systems42.org uses the colours of the Systems42 logo on large areas. Header, hero and page headers are navy with the two peaks in mint green and sky blue, the section on getting started is mint, and headings use the dashboard's display face. On a phone the home page no longer scrolls sideways.
- Docs: the dashboard README and the Go summary no longer name a Homebrew cask as a way to install the app. The cask file is prepared, but no tap offers it yet.
- Dashboard release 0.14.0 (`_system/apps/dashboard/VERSION`).
- `make` lists its targets in two groups: those for every Systems42 wiki and those for the dashboard's repository only.
- This repository's own wiki follows meta's current method ([#103](https://github.com/systems42-org/systems42-dashboard/issues/103)): domain terms, requirement notations, the arc42 types of meta DR-040. Q42 quality requirements and C6 named "Issues" stay until [meta#35](https://github.com/systems42-org/meta/issues/35) settles them. The entity diagram takes its section from its route, so its breadcrumb works without a `data-models/` folder (Python and Go).
- Dashboard: crosscutting concepts are read from `wiki/crosscutting-concepts/` (type `crosscutting-concept`), no longer from `wiki/concepts/`. Move your `CC-` pages to the new folder (DR-040, issue #100).
- Dashboard: a runtime scenario names the functional requirement or activity model it carries out in `realizes:`, no longer in `drivers:`. The scenario page lists them under *Realizes*, the requirement or activity model page lists the scenario under *Realized by*, and a scenario no longer shows under *Addressed by*. Rename `drivers:` to `realizes:` in your runtime scenarios (DR-040, issue #102).
- Dashboard: a use case page lists the features and stories under it as *Refined by*, not *Realized by*. *Realized by* now always means the runtime scenarios that carry it out.
- Dashboard release 0.13.0 (`_system/apps/dashboard/VERSION`).
- Dashboard: the multi-column sort presets of the section lists (FR-021) live in the dashboard (`SORT_PRESETS` in `app.py`), not in the metamodel (CON-006). The Domain Terms list takes `domain-term` when the metamodel has that type. The type key `sort_orders:` and its lint check are gone from `_system/metamodel/`, as in the Systems42 meta repository; delete it from your type pages if you added it.
- Issues: `category:` and `owner:` follow the Systems42 metamodel (meta pull request 55). The category `systems42` is now `method`, both fields are optional, and `owner:` takes a `[[STK-...]]` link only. Rename `category: systems42` to `method` in your issues. The dashboard still shows an owner written as a plain name.
- Dashboard: the sections come from the repository's metamodel
  (`_system/metamodel/frameworks/`, FR-044), not from a list in `catalog.py`.
  A renamed or added section shows on the home page, the area pages and in
  the lists without a code change, and the header takes the new titles of C5,
  C6 and C7. A section the dashboard has no
  view for gets a generic tile and list at `/section/<id>`, in the area of its
  framework file. Pages in `wiki/use-cases/` now count in R3.
- Metamodel lint: it no longer imports the dashboard's `catalog.py` and runs
  without dashboard code (ISS-005).

### Removed
- Wiki: 23 stakeholders merged into 7 (meta issue #38). Retired IDs, never
  reused: STK-002, STK-003, STK-004, STK-005, STK-006, STK-007, STK-009,
  STK-011, STK-014, STK-015, STK-016, STK-017, STK-018, STK-019, STK-021,
  STK-022.
- This repository no longer creates project wikis: `_system/scripts/new-project.sh`,
  its test `test-new-project.sh`, `migrate-decisions.py` and the `new-project`
  skill are gone. New projects come from the Systems42 meta repository.
- Dashboard: wikis on the old schema are no longer supported. Migrate them
  with meta's `migrate-requirements` and `migrate-domain-terms` first. The
  dashboard no longer reads `wiki/glossary/`, `wiki/data-models/` or
  `wiki/use-cases/`, knows no `GLO-` or `DM-` pages, and draws no `<<term>>`
  stubs in the entity diagram. Entity attributes come from `attributes:`
  only, relationships from `to`, `label` and `multiplicity` only (the
  `**Attributes.**` bullet list and the `target`, `verb` and `cardinality`
  keys are gone). `/glossary`, `/graph/glossary`, `/data-model` and
  `/page/use-cases/<id>` answer 404 instead of redirecting. Use cases with a
  `UC-` ID in `wiki/functional-requirements/` still work (DR-038, DR-039).
- Dashboard: the old redirects `/adrs`, `/page/adr/<stem>` and `/req42/backlog`
  are gone and answer 404. Use `/decisions`, `/page/decisions/<DR>` and
  `/req42/functional-requirements`.

### Changed
- Dashboard: the first page shows the first sentence of the vision under the
  system's name, and the tagline only when there is no vision (FR-018). Each
  area tile lists its sections with their counts.
- Dashboard: section tiles on the area pages show a count, the maturity bar
  and the open-issue link, and no page names (FR-019). R1 counts its goal
  pages. C6 counts all issues and shows the open ones as its flag. The R1
  claim line, the R3 breakdown by epic, feature, story and use case and the
  C3 note on the context page are gone from the tiles.
- Dashboard: breadcrumbs, footer links, sort headers and tile links are at
  least 24 x 24 px, and no text outside a diagram is smaller than 12 px
  (QR-001). A diagram first shows whole, and the reader zooms and pans it by touch.
  The term network, the deployment view and node pages, the functional
  requirements and the scope page list every page their diagram draws as a
  text link under it.
- Dashboard release 0.12.0 (`_system/apps/dashboard/VERSION`).
- Dashboard: the Configure dialog is now called View, and the view lives in
  the running dashboard only (FR-046, DR-002). The dashboard writes no file
  any more. After a restart everything the project uses shows again.
  `_system/dashboard.yaml` is no longer read. A wiki on this release or a
  newer one can delete the file. The launcher creates it no longer and mounts
  it only where it exists, for releases up to 0.11.4. The variable
  `DASHBOARD_CONFIG` is gone.
- Dashboard release 0.11.4 (`_system/apps/dashboard/VERSION`).
- Dashboard: the shipped brand shows the Peaks intro again (FR-032). Release
  0.11.3 had replaced it with the systems42 logo and a fly-in wordmark, which
  changed every wiki without a brand of its own. That intro now lives in the
  Systems42 meta repository's own brand folder. A wiki that wants another look
  names its own folder in `brand:` (FR-031).
- Dashboard release 0.11.3 (`_system/apps/dashboard/VERSION`).
- Dashboard: the systems42 brand has a new intro. The systems42 logo builds
  itself (the arches swing in, the ribbon twists into place), then the letters
  of the wordmark "systems42" fly in, spinning, and land; about 2 s, then a
  fade. The earlier intro, in which the Peaks mark builds itself, is kept as
  `brands/systems42/intro-peaks.html`; the dashboard reads only `intro.html`,
  so renaming it back restores it.
- Dashboard release 0.11.2 (`_system/apps/dashboard/VERSION`).
- Dashboard release 0.11.0 (`_system/apps/dashboard/VERSION`): requirement
  notations (DR-038), ported from the Systems42 meta repository.
- Dashboard: functional requirements follow requirement notations (DR-038).
  Every FR page names its `notation:` (`agile`, `use-case`, `ears`, `prose`
  or a project's own) and one of that notation's `level:` values. The story
  map on `/req42/functional-requirements` places only Agile epics, features
  and stories. An Agile feature or story may name a use case at level `sea`
  or `fish` as `parent:`: that use case is a root beside the epics, and its
  page lists what realizes it under "Realized by"; a feature there with
  `goal: []` serves the use case's goals (never those of a `kite` use case).
  Every other requirement,
  and every page without a known notation or level, is listed under
  "Outside the Agile hierarchy" and is never treated as Agile. The flat list
  shows notation and level instead of the stereotype.
- Dashboard: use cases are functional requirements in the `use-case`
  notation (levels `kite`, `sea`, `fish`) and live in
  `wiki/functional-requirements/`. They open at `/functional-requirements/<id>`,
  count on the Functional Requirements tile and are columns of the goal
  coverage matrix. A link to `/page/use-cases/<id>` redirects there (HTTP
  301) once the page has moved. The section no longer reads
  `wiki/use-cases/`.
- Dashboard: `/metamodel` shows the requirement notations instead of the
  altitude (granularity) scale: levels, extra fields and the level-marked page
  sections of each file in `_system/metamodel/notations/` and a project's own
  `_system/notations/`. `default_notation:` in `_system/wiki.yaml` marks the
  default (`agile` when unset). Rules show the notation and level they apply to.
- Dashboard: the goal coverage matrix lists requirements of other notations
  (EARS, prose) that serve a goal under "other requirements". Search indexes
  `notation:` and `level:`.
- A wiki still on the old schema (`stereotype: epic|feature|story`,
  `wiki/use-cases/`, `_system/metamodel/altitude.md`) still opens without
  errors, but its requirements are not placed until migrated with
  `migrate-requirements` (Systems42 meta, `_system/scripts/new-project.sh`):
  every FR is listed outside the Agile hierarchy, use cases are plain pages
  outside the Functional Requirements section, and `/metamodel` shows no
  notations. This repository's own wiki and schema are migrated separately.

### Security
- Dashboard release 0.11.1 (`_system/apps/dashboard/VERSION`): hardening
  after 0.10.1 (issue #34):
  - A brand's `intro.html` runs in a sandboxed frame, in an origin of its
    own. It cannot read the page, call the dashboard, use the viewer's
    storage or load anything. Existing intros keep working. The home page
    now decides when an intro shows (once per tab, never under reduced
    motion) and removes it after 4 seconds at the latest. See
    `brands/README.md`.
  - Wiki content can no longer make a viewer's browser fetch from outside. An
    image with a remote `src` loses it and shows its alt text. On the About
    page a style with `url()` is dropped.
  - Every HTML page carries a Content Security Policy: script only from the
    dashboard's files and its templates' own inline blocks, nothing loaded
    from outside.
  - The build is pinned: Flask's own dependencies by version, the base image
    by digest. The container no longer runs as root. `dashboard.sh` starts it
    as the calling user. A wiki with an older `dashboard.sh` on Linux should
    take the new one, or the Configure dialog may fail to save.
- Dashboard release 0.10.1 (`_system/apps/dashboard/VERSION`): the security
  fixes of the Systems42 meta repository's dashboard, ported to this copy.
- Dashboard dependencies updated past published advisories: Markdown 3.7 →
  3.11.2 (CVE-2025-69534, parser crash on malformed HTML-like input), Flask
  3.0.3 → 3.1.3 (CVE-2026-27205; the dashboard does not use `session`, so not
  exploitable here), vendored mermaid 11.15.0 → 11.17.2 (five advisories fixed
  in 11.16.1: CSS injection, prototype pollution, XY/radar DoS; bundled
  DOMPurify 3.4.0 → 3.4.12). Also PyYAML 6.0.2 → 6.0.3 and gunicorn 23.0.0 →
  26.2.0 (no advisories; the container now passes `--no-control-socket`).
- Dashboard: wiki content can no longer run script in a viewer's browser.
  Rendered markdown and snippets (definitions, snapshots, PAM bullets, quality
  scenarios, the vision), the metamodel's prose and the About page go through
  an allow-list sanitizer (new dependency `nh3`); wikilink labels, aliases,
  anchor names and plain-text frontmatter values (goal metric, target,
  baseline; a source's ingested pages) are escaped. Tables, footnotes,
  `<kbd>` and mermaid blocks render as before; HTML comments and unknown tags
  (e.g. a bare `<file>` placeholder, which the browser already hid) are
  dropped. `id` and `class` keep only the values the dashboard's own markup
  emits (footnote anchors, wikilinks, anchor links, code blocks), so a page
  cannot take over the settings dialog or filter buttons. The About page keeps
  its inline layout styles. A new test renders every route against a vault
  whose every text field is hostile, and fails when a route is added without
  being rendered there.
- Dashboard: `/page/<folder>/<stem>` only serves the wiki's own content
  folders; `..` or `.` as folder used to reach a markdown file beside wiki/.
  The files served as they are, `/brand/<file>` and `/about/files/<path>`,
  carry a sandboxing Content-Security-Policy and `nosniff`, so an SVG or HTML
  file opened directly cannot run script with the dashboard's rights.
- Dashboard: symlinks that lead out of the wiki are no longer followed. A
  committed page such as `wiki/glossary/GLO-002-x.md -> /outside/notes.md`
  was served on `/page` and listed in search, and a linked folder passed as a
  wiki folder; pages and provenance records are now read only when their
  resolved path stays inside `wiki/` (or `raw/sources/`). Symlinks that point
  elsewhere inside the wiki still work.
- Dashboard: every HTML page sends `Content-Security-Policy: frame-ancestors
  'none'` and `X-Frame-Options: DENY`, so no other site can frame the
  dashboard and trick a viewer into clicking its controls. A decision-record
  link on `/metamodel` is escaped like every other wiki link.
- Not covered: a brand's `intro.html` is inserted as it is, script included,
  as `brands/README.md` specifies; it stays trusted content, to be reviewed
  like code.

### Changed
- Dashboard release 0.10.0 (`_system/apps/dashboard/VERSION`): unified
  domain terms with the terminology graph and entity diagram (meta #36), the
  renamed domain-term routes, and the atrium brand out of the image (FR-032).
- Dashboard: the image ships one brand, `systems42`. The atrium brand moved
  to the isaqb-atrium repository, which names its own folder in `brand:`
  (FR-032). A wiki that still says `brand: atrium` shows the systems42 brand
  and the dashboard logs a warning.
- Domain-term routes now use "/domain-terms", "/graph/domain-terms" and
  "/entity-diagram". The previous URLs redirect with HTTP 301 and preserve
  query parameters. This brings the route rename forward from the later
  dashboard work proposed in meta #36, as requested during implementation.
- Domain Terms shows the terminology graph and Supporting Models shows the
  entity diagram from the same pages. Vaults using the previous glossary
  and data-model folders still open (meta #36).
- Dashboard: `dashboard.sh` is now a launcher (FR-042). It starts the
  published image that `dashboard_version:` in `_system/wiki.yaml` names,
  `ghcr.io/systems42-org/dashboard:<version>`, instead of building the code
  in the wiki. `./dashboard.sh update` names the newest release. A wiki
  needs no dashboard code except this script. `dashboard_version: local`
  builds from `_system/apps/dashboard/`, which only the dashboard's
  repository has. There, `rebuild`, `local` and `test` moved to
  `_system/apps/dashboard/dev.sh` and still run through `./dashboard.sh`.
- Dashboard: one mount. The container gets the wiki repository read-only at
  `/repo`, with `_system/dashboard.yaml` writable, and finds every folder
  below it. The image sets only `REPO_DIR`. `compose.yaml` is gone. A
  folder's own variable (`WIKI_DIR`, `DOCS_DIR` and the others) still wins
  when set.
- Dashboard: it works on Systems42 wikis only (CON-005). When `wiki/`,
  `raw/`, `_system/wiki.yaml`, `_system/metamodel/` or `_system/anchors/` is
  missing, it names what is missing and stops.
- Dashboard: `make clean` removes the container and the locally built image.
  It leaves a pulled release image, which other wikis may use.
- Dashboard, Vision & Goals: the goal coverage matrix follows Systems42's
  goal coverage projection (FR-036). Columns are the epics and use cases,
  headed by their real IDs. Each header links its page and shows the title on
  hover or focus. Enablers are epics in lane platform or display that serve no
  goal, grouped on the right. An epic that names no goal stays in the main
  group, marked "no goal". A goal that no requirement serves at all gets a
  quiet row and the note "No requirement yet". A goal served only by features
  or stories is no gap: its row names them, as in "Served by features FR-021,
  FR-036". The "Agreed only" filter applies to the matrix too, with its own
  buttons for the same `?status=`. It then counts agreed pages only, also in
  the notes. A `goal:` counts only when it links an existing objective. Each
  goal card's "drives" list still names every requirement that serves the
  goal, so every mark is also there as text. On a phone the goal column
  leaves room for the marks. The goal and epic map on the functional
  requirements page shows epics without a goal under "No goal", no longer
  under "Platform / Enabler".
- Dashboard brand: the brand slot moved from `static/brand/` and
  `templates/_brand_intro.html` to `_system/apps/dashboard/brands/<name>/`. A
  brand's intro is now one self-contained `intro.html`, inserted as it is. The
  contract is in `brands/README.md`. An intro may declare its own colours as
  `--brand-*` custom properties, once per theme.
- An issue page shows category, severity, kind and owner under its ID, and
  "nobody yet" when no one owns it (FR-026, FR-028).
- The issue list shows category and owner, "nobody yet" for an issue without
  one (FR-025, FR-026, FR-028). It filters by status, category, severity,
  section and owner, the filters combine and the address carries them, as
  `/issues?category=systems42&owner=none`. "Open" means every status except
  `resolved` and `wontfix`, the same on tiles, the first page, the list and
  each page, so an issue with a missing or unknown status stays visible. Each
  row's ID and title open the issue page, the inline
  pane is gone. `?filter=open` still works and means `?status=open`.
- Every section list uses the shared list layer (FR-021, FR-022): an order
  picker with the type's sort orders, "Agreed only", and every column
  sortable. Functional requirements get a flat list under the hierarchy,
  Vision & Goals a list of every goal, the arc42 views a list next to their
  trees. Quality requirements show priority
  as a column. Domain Terms drop their own sort buttons: "Added" is a column
  now, and its header gives newest or oldest first. Decision and issue titles
  link their pages.
- Search forgives typos and word forms (FR-002): `keyholdr` finds Keyholder,
  `requirement engineer` finds "Requirements engineers". Words of 4 to 7
  letters allow one wrong letter, longer words two. Short words and IDs match
  only exactly or as a prefix, and an ID's number alone (`023`) finds it.
  An exact hit, in any place, always ranks above a word form or a typo.
- Search knows the wiki's other names (FR-003): a page's `aliases:` find
  the page, and a glossary term's name and aliases count as one word, so
  searching for an alias also finds pages that use only the term's name.
  Alias hits rank below exact hits.
- Search takes questions (FR-004): filler words such as `who`, `the` and
  `is` don't count, so `who starts the app` finds the Keyholder. Pages with
  only some of the words now show too, after every page with all of them.
- Every search hit that isn't an exact match says why it is there (FR-005),
  in the popup and on `/search`: "typo: keyholdr → Keyholder", "word form:
  starts → started", "via alias of Keyholder" or "matches 1 of 2 words".
- Search finds pages by their labels (FR-006): `tags`, `status`,
  `stereotype`, `priority`, `kind`, `state`, `category` and `dimensions`.
  `Must` finds every page with `priority: Must`. A field hit ranks below a
  title hit and above a hit in the body text. Link fields, dates and raw
  markdown are no longer searched. In the body, a link reads as its label
  or the page title, and a link to a source as the source's ID
  (`SRC-006`), so file names add no noise.
- Each hit on `/search` shows the sentence where the query matched, with
  the matching words highlighted (FR-007). A title hit shows the page's
  first sentence. The popup stays compact and shows no passage.
- `/search` lists "Related pages" below the hits (FR-008): up to 5 pages
  one link away from a title or alias hit, each with "linked from <ID>".
  A page that is a hit already is not repeated. The popup shows none.
- `/search` filters by status, priority and tag next to the type facets
  (FR-009). The filters combine. The search box keeps no filter syntax.
- Quality requirements are classified by Q42 dimensions (DR-003): the
  template and the metamodel replace the single ISO 25010 `attribute:` with
  `dimensions:`, a list of one or more of reliable, flexible, maintainable,
  efficient, usable, safe, secure, suitable, operable. The dashboard's quality
  list shows one badge per dimension. The Q42 and req42 anchors, `AGENTS.md`
  and `docs/req42/README.md` follow. Projects with `attribute:` move it to
  `dimensions:` when they sync the method.
- One name per section everywhere (FR-017): the header, breadcrumbs, headings
  and the section map take their labels from `catalog.py`. C5 is "Domain
  Terms" (was "Glossary" in the header), C6 is "Issues" (was "Risks &
  Assumptions" in the catalog, the metamodel and the section map). The third
  area is "Commons" in the wiki too.
- Breadcrumbs follow where a page belongs (FR-020): `Home › Area › Section ›
  Page`, with `›` as separator. Wiki pages no longer show "Search" as their
  parent. Sources, the metamodel and the changes page read `Home › Page`.
- The header marks its entry on every page of that section, wiki pages and the
  term network included (FR-014).
- The first page's center tile shows the last 4 changes instead of 5, links to
  the new changes page and no longer counts pages (FR-018).
- A page's note that it follows a standard (`> follows [[MADR]]`) shows as a
  quiet "Format: MADR" label in the page head, no longer as a box before the
  text. Several notes give one label each, a trailing note such as "section 5,
  black box" stays beside the label. Only a quote line of its own that starts
  with a lowercase "follows" counts, and without a link only a few words. Code
  and ordinary quotes stay as they are, and search leaves out the same lines.
  Wiki files are unchanged (FR-035).
- "Links to" and "Linked from" show a linked issue's status, and a resolved
  or wontfix issue is dimmed as closed, the same as in the issues panel. A
  functional requirement page now has both lists too (FR-034).
- A wikilink to a source record in the text (`[[SRC-022-…]]`) leads to its
  record under `/source/`, titled by the record. It used to be plain text.
  A link to a source that does not exist stays plain text (FR-034).

### Added
- Dashboard browser test `tests/test_mermaid_browser.py`: checks in headless
  Chromium that the vendored mermaid draws the context diagram, the entity
  diagram and fenced blocks, re-renders on a theme switch without JavaScript
  errors, and matches the version in `static/vendor/README.md`. Its Playwright
  dependency is in the new development-only `requirements-dev.txt`; without it
  the test skips.
- Dashboard: a release workflow. A git tag `vX.Y.Z` that matches `VERSION`
  runs the tests, publishes the image for amd64 and arm64 and creates the
  GitHub release (DR-004, FR-030).
- Dashboard: `make test` (`./dashboard.sh test`) runs the dashboard's test
  scripts in Docker, on the Python and the libraries of the shipped image. It
  lists the scripts that failed and exits 1 if any did. No local Python is
  needed. The `Dockerfile` has a `test` stage for it, and the shipped image is
  unchanged.
- `/metamodel` has an Anchors section: one entry per file in
  `_system/anchors/` (`#anchor-madr`) with its name, short definition, the
  types it applies to and its outside reference. Every wikilink to an anchor's
  title or alias, in any case, leads to its entry, with the definition as the
  link's title. On `/metamodel` the "Standards" chips lead there too (FR-035).
- Branding is configuration. Three optional keys in `_system/wiki.yaml`:
  `brand:` names an example brand (`systems42`, the default, or `atrium`) or a
  folder of the wiki repository such as `brand/`, `intro: off` hides the home
  page intro, `dashboard_version:` names the dashboard release the wiki uses.
  Switching brands is one changed key and a reload. The dashboard only reads a
  wiki's brand folder (mounted at `/repo`, read-only, under Docker). A folder
  outside the repository, missing or incomplete shows `systems42` and logs a
  warning.
- The dashboard has a release number, `_system/apps/dashboard/VERSION`
  (0.9.0), shown in the footer. When `dashboard_version:` names another release,
  one footer line says so.
- Every wiki page lists the issues that link to it, open ones first and then
  by severity, each with status and severity (FR-027). A page without an open
  issue says "No open issues point at this page." Functional requirement
  pages included.
- The shared list layer `static/list-view.js` replaces `table-sort.js`
  (FR-021, FR-022). A list sorts by several columns: shift-click a header to
  add it as the next key. A list can offer its type's sort orders and an
  "Agreed only" filter. The address keeps both, as `?sort=priority:asc,order:asc`
  and `?status=accepted`, so a copied link shows the same list.
- `sort_orders:` on metamodel type pages (FR-021): the useful orders for a
  list of that type, such as priority › release › order for functional
  requirements and status › severity for issues. The lint checks that every
  key is a field of the type.
- `/changes`: every wiki page, most recently changed first (FR-018).
- `/issues?section=<ID>`: only the open issues that point at that section's
  pages. A section tile's open issue count links there (FR-019).
- A 404 page with header and footer (FR-013).
- Issue fields `category:` (requirements, architecture, commons,
  content, orga, systems42; exactly one) and `owner:` (who is expected to
  answer; empty means nobody yet), in the issue template and the metamodel,
  with the new relation `owner`. No due date field. Asked for by FR-026 and
  FR-028.
- Writing style guide: `_system/writing-style.md` is binding for every text in
  the repository. `AGENTS.md` points to it, `CLAUDE.md` imports it, and
  `new-project.sh` ships it. The page size of about 300 words is a suggestion,
  not a limit.

### Fixed
- Dashboard: one broken page no longer takes every page down. Frontmatter
  that is not a mapping counts as empty, a blank `title:` falls back to the
  file name, a single value where a list belongs (`parent: 7`, `tags: draft`,
  `beneficiary: "[[STK-…]]"`) is read as a one-item list, and bytes that are
  not UTF-8 show as U+FFFD.
- Dashboard: a method anchor's definition as a link title dropped its
  markdown links into the page text (DR-003, QR-001, QR-002, `/metamodel`).
- `./dashboard.sh local` installs the requirements again when
  `requirements.txt` changed (an existing `.venv` started without `nh3`),
  Ctrl+C stops the server instead of leaving it running, and a port that
  already answers is refused instead of reported as a fresh start.
- The disconnect test no longer SIGTERMs its parent (a test runner);
  `tests/conftest.py` stops pytest from running several test scripts in one
  process.
- The dashboard did not start in Docker. The anchors folder (FR-035) had no
  mount and no variable, so the container stopped at startup while `make dev`
  still said it was running. The anchors are now mounted at `/anchors`, and
  `make dev` reports a container that stopped, with the end of its log.
- `/metamodel`: a row opened by its address (`#type-goal`, `#anchor-madr`)
  stops below the sticky header instead of under it.
- Vision & Goals: the goal coverage matrix stays inside its card. With many
  functional requirements it scrolls inside the card, the goal column stays put,
  and the page no longer scrolls sideways. Goal titles read in page ink instead
  of the browser's default link blue. The matrix lead no longer cites DR-018
  and DR-011, which this wiki does not have.
- `/goals`: the vision card showed only the first paragraph under `## Vision`,
  so a vision that opened with a note (`> …`) showed the note and nothing else.
  It now shows every prose paragraph and skips notes, comments and the
  template's hints. Each goal title links to its page, and the Vision node of
  the goal tree is clickable. `tests/test_vision_card.py`.
- Callouts with no title on the marker line (`> [!note]` followed by the
  text) showed their first text line as a bold label with a stray `>`. They
  now show the type as the label ("Note", "Assumption") and the text below.
  This affected GOAL-003 to GOAL-007, CON-001 and five stakeholder pages.
  `tests/test_callouts.py`.

### Changed
- Dashboard: the header nav is now Requirements · Architecture · Glossary ·
  Decisions · Issues (before: Goals · Stakeholders · Functional Reqs · Quality ·
  Issues). The footer holds formalities only: "Read-only dashboard for
  Systems42 LLM wiki", linked to a new help section on the LLM wiki, the
  refresh time without time zone, the client count, Metamodel, Help and a
  Python logo. Its content links are gone, because the header has them. The
  footer dot stops and turns grey when the connection is lost.
- Capture workflow: a requirement may name a technology where requirements and
  architecture overlap, or where the project's subject is technology. Before,
  technology names were allowed on architecture pages only.
- `grilling` skill: brought up to date with upstream `mattpocock/skills`. Each
  question is now worded so that "yes" accepts the recommended answer, and
  fact-finding sub-agents start with a fresh context window.
- Dashboard brand: the Peaks mark replaces the placeholder. Requirements and
  Architecture are two peaks over Commons as the ground, the home page as a
  picture. A two-second intro builds it (ground, then the peaks), once per tab,
  skipped under reduced motion. Brand guide: `docs/brand/README.md`, linked from
  the hero via `about:` in `wiki.yaml`.
- Dashboard brand: the atrium mark, favicon, logo animation and brand guide are
  gone. Mark, favicon and an optional home-page intro now sit in one slot,
  `static/brand/` (contract in its README) plus an optional
  `templates/_brand_intro.html`, so a rebrand replaces files and touches no
  template. The mark is a placeholder for now: the home page's three areas as
  tiles. `/about` no longer animates anything.
- Make `AGENTS.md` the shared source for schema and project rules. `CLAUDE.md`
  imports it for Claude Code; skills live canonically under `.agents/skills/`
  with `.claude/skills/` compatibility symlinks. Preserve Atrium's project
  conventions in the shared file and keep project decision links out of shipped
  method documentation.

### Added
- `make clean` (`./dashboard.sh clean`) removes what can be rebuilt: this wiki's
  dashboard container and image, `.venv`, `__pycache__` and `.DS_Store`. It never
  touches `wiki/`, `raw/`, `docs/`, `sandbox/`, settings or harvest patches.
- Sortable tables: click a column header on Stakeholders, Quality, Constraints,
  Scope, Glossary, Decisions and Issues to sort, click again to flip. IDs sort
  naturally, influence, interest and severity by rank (first click: highest
  first), status by lifecycle, and empty cells stay last. `static/table-sort.js`, which also
  replaces the data-model page's own sort script.
- atrium logo intro: the lockup's twelve pieces (rooms, courtyard, letters,
  i-dot) spiral in from the edges and form the logo in about a second. Shown as
  a splash on the home page once per browser tab (click or any key skips it),
  and in place of the static lockup image on `/about` (plays when scrolled into
  view, click replays). Off under `prefers-reduced-motion`.
  `static/atrium-intro.js`, `templates/_atrium_lockup.html`.
- Incremental search in the topbar: typing shows the top 8 ranked matches in a
  popup (↑/↓ to move, Enter opens the highlighted result, Enter with none
  highlighted or Cmd/Ctrl-Enter opens the full `/search` page, Esc closes).
  Index served at `/search.json`; ranking shared with `/search` in
  `static/search-rank.js`.

### Changed
- Dashboard Quality section (`/req42/quality`): each quality requirement now
  shows its ISO 25010 attribute, priority and Q42 quality scenario (source, stimulus,
  environment, response, measure), and its title links to the page. Titles in
  every req42 section list are now links.
- Dashboard glossary: long alias lists wrap inside the Term column instead of
  widening it until the definitions are pushed off the card.
- Dashboard presence: names and the facilitator role are sticky for the
  session. A tab keeps its first name, and the role passes on only when
  its holder is gone, never back. Before, the role was recomputed on every
  ping, so after Yoda left, a second tab flipped between "Yoda" and its own
  nickname. The heir keeps its own name.
- Quality scenarios are called **Q42 quality scenarios**
  ([quality.arc42.org](https://quality.arc42.org)), never "ATAM": new anchor
  `_system/anchors/q42.md`, heading "Scenario (Q42 quality scenario)" in the
  quality-requirement template and on every QR page; CLAUDE.md, metamodel,
  report workflow, req42 anchor and docs follow. Name only — the five scenario
  parts are unchanged.
- Features and stories may refine a use case: `parent:` may name a `[[UC-...]]`
  (never for an epic). The use case's page shows a projected *Realized by* panel,
  `/req42/functional-requirements` counts its stories and features, an FR's
  breadcrumb ends at its use case, and a story under a use case with `goal: []`
  serves the use case's goals instead of counting as an enabler. Metamodel:
  `rel-parent` edge, FR and use-case types, goal coverage, the goal-trace rule and
  `altitude` updated; FR and use-case templates follow. (DR-011, amended)
- Use cases are functional requirements: the use-case type moves from req42
  block 05 (Supporting Models, R4) to block 04 (Functional Requirements, R3) and
  gains a `goal:` list (`0..*`). The R3 tile and `/req42/functional-requirements`
  list use cases, and the R3 headline counts all functional requirements (FR pages
  plus use cases), naming only the kinds that exist; goal coverage, the R1 tile, `/goals` and the goal map count
  them. (DR-011)
- Quality goals and quality requirements are one concept: arc42's *quality
  goals* (1.2) are the highest-priority quality requirements. The QR template
  title placeholder, metamodel naming, capture workflow and arc42 anchor say so;
  no separate `quality-goal` field and no quality-tree view are planned.

### Added
- arc42 Deployment View (A3), Runtime View (A4), Crosscutting Concepts (A5):
  content types **deployment node** (`DN`, `wiki/deployment-nodes/`), **runtime
  scenario** (`RS`, `wiki/runtime-scenarios/`), **crosscutting concept** (`CC`,
  `wiki/concepts/`) with templates; `/arc42/deployment` (one lifecycle-marked diagram),
  `/arc42/runtime`, `/arc42/concepts`; sequence diagram and `uses:` consistency
  hints on scenario pages, deployment subtree on node pages; *Governed by*,
  *Deployed on*, *Takes part in*, *Replaced by* / *Replaces* panels. Metamodel
  relations `applies-to`, `steps`, `hosts`, `connects`; projections
  `sequence-diagram`, `deployment-diagram`, `governed-by`; rule
  `runtime-matches-uses`. (DR-010)
- `state: current | target` and `superseded-by:` on every architecture page
  (A2–A5), so today's landscape and the target live side by side. (DR-010)
- arc42 diagrams drop nothing silently: malformed `steps:` / `connects:` entries,
  empty or dangling ends, cross-state edges and non-block `hosts:` show as hints
  on the scenario page, the node page and `/arc42/deployment`. Concept
  `category` matches ignoring case; an unknown value is shown. Plain-text step
  ends keep `/`. The `connects:` note appears on the edge label.
- `state: outdated | current | planned | target`. The deployment and
  building-block views draw all states in one picture: current plain, planned
  and target dashed, outdated or deprecated grey, a dotted *replaced by* edge,
  with a legend. Decision records show *Replaced by* / *Replaces*. DR-004
  amended: historical architecture stays on record. (DR-010)
- arc42 Building Block View (A2): content type **building block** (`BB`,
  `wiki/building-blocks/`, `_templates/building-block.md`) — one page per block,
  levels via `parent:`, dependencies via `uses:`, `decisions:`, `location`;
  `/arc42/building-blocks` with the level tree and the level-1 white box; block
  pages with their projected white box. New `arc42` anchor. (DR-009)
- `drivers:` on decision records and building blocks: the goals, use cases, FRs,
  QRs and constraints they rest on; requirement pages show the inverse as
  **Addressed by**. Metamodel relations `drivers`, `uses`, `shaped-by`;
  projections `bb-tree`, `whitebox`, `addressed-by`. Building blocks are a
  layer in the glossary term network.

### Changed
- req42 block 04 is now named **Functional Requirements** everywhere (the 2026
  edition of req42 renamed it from "Product Backlog"; "backlog" is reserved for
  a ranked projection over the hierarchy, never stored). Touches `CLAUDE.md`,
  the FR template (`release:` default `unscheduled`), anchors, workflows, the
  `requirements-wiki` skill, docs and the dashboard: nav label "Functional
  Reqs", route `/req42/functional-requirements` with a 301 from `/req42/backlog`,
  page and breadcrumb titles, Python and CSS identifiers, tests. Stale type
  lists in `capture.md` and the skill (user story / feature as separate types)
  corrected to the one-type model. (Harvested from isaqb-atrium.)

### Added
- `_system/metamodel/`: the wiki's metamodel made explicit (DR-035). A
  framework-agnostic meta-meta language (`meta-metamodel.md`: type, relation,
  framework, projection, anchor, altitude-scale, rule) and its instances as one
  markdown page each with machine-readable frontmatter: 14 types, 12 relations,
  3 frameworks (req42 / arc42 / commons, 18 sections), 6 projections, an
  altitude scale that records the open use-case ↔ epic question, 3 rules.
  `_system/scripts/metamodel-lint.py` diffs it against `_templates/`, the wiki
  folders, the anchors and the dashboard catalog; shipped as a product path.
  (Harvested from isaqb-atrium.)
- Dashboard `/metamodel` (menu, footer, `/help`): the metamodel explained — the
  types as a cytoscape network grouped by section with the relations as
  labelled arrows, and tables for types (definition, fields, a live example page
  from the vault), relations, projections, the granularity scale with its open
  use-case ↔ epic question, rules and the meta-meta language. Read live from
  `_system/metamodel/` (`metamodel.py`); mounted into the container. Colour
  tokens for the types the term network has none for. (Harvested from
  isaqb-atrium.)
- `new-project.sh migrate-decisions` / `make migrate-decisions TARGET=<dir>`:
  moves an older project's own ADRs from `_system/adr/` to
  `wiki/decisions/DR-NNN` (same number, `aliases: [ADR-NNNN]`, MADR sections),
  drops the inherited ADR-0001 to 0003, rewrites links and the index, and
  removes `_system/adr/`, uncommitted for review. `sync` refuses a project
  that still has `_system/adr/` and names the command. (DR-034)
- Decision records as a content type: `wiki/decisions/`, IDs `DR-NNN`,
  template `_templates/decision-record.md`, shape per the new `[[MADR]]` anchor
  (`_system/anchors/madr.md`). Fields `kind` (architecture | business |
  undefined), `decided`, optional `decision-makers` / `consulted` / `informed`,
  `amends`, `superseded-by`. (FR-009, DR-034)
- `CLAUDE.md` convention **Decisions**: a record qualifies only if it is
  cross-cutting, expensive to reverse and a real choice among named
  alternatives; standing rules are requirements, field additions and renames
  are changelog entries. Replaces "never invent fields without an ADR". (DR-034)
- Dashboard: section C7 *Decisions* in Commons at `/decisions`, filterable by
  kind and searchable by former ADR number. (FR-009)
- Dashboard: an optional `/about` page. `about:` in `_system/wiki.yaml` names a
  markdown page under `docs/` (e.g. a brand guide); the hero mark and a text
  link under the tagline lead there, and the files it links to under `docs/`
  (`../` included) are served with it. `about_label:` sets the link text.
  `docs/` is mounted read-only; paths leading out of it, by `..` or by symlink,
  are refused. Harvested from isaqb-atrium.
- `new-project.sh harvest` / `make harvest TARGET=<dir>`: the way back from a
  spawned project. Diffs the product paths into a git-applicable patch here,
  lists the project's new `wiki/` folders and its own ADRs with the next free
  number; writes nothing else. Documented in the skill, the guide and the
  READMEs (DR-031 amendment).
- `_system/scripts/new-project.sh` and the `new-project` skill: create a fresh
  wiki from this one (`new`) carrying the method files and none of the content,
  or refresh those method files in a wiki created that way (`sync`). ADRs are
  inherited on creation and never synced. Tested by
  `_system/scripts/test-new-project.sh`. (DR-031, resolves ISS-006)
- `make new TARGET=<dir> NAME="<System>" [TAGLINE="..."]` and
  `make sync TARGET=<dir>`, wrapping the script.
- `CHANGELOG.md` (this file), shipped with every project.
- Dashboard: Configure dialog (facilitator only) writes a hide list to
  `_system/dashboard.yaml`, which is hand-editable; hidden sections keep their
  routes and search hits. `make new` creates the file, `make sync` leaves it
  alone. The dashboard is no longer strictly read-only: this is the one file it
  writes. (DR-033)

### Changed
- A spawned project inherits no decision records (before: ADR-0001 to 0003);
  `wiki/decisions/` starts empty, `make sync` and `make harvest` no longer
  handle `_system/adr/`, and harvest lists the project's decision records
  instead. Shipped Markdown no longer cites decisions by number and states its
  rules in place; `test-new-project.sh` checks that. (DR-034, amends DR-031)
- Dashboard: A6 *Architecture Decisions* leaves the Architecture area (now
  A1-A5); `/adrs` and `/page/adr/<stem>` redirect to `/decisions` and to the
  record that kept the ADR's number.
- Recorded here instead of as decisions (former ADRs re-filed under DR-034):
  the stakeholder template's optional `aliases:` field (ADR-0010); the
  functional-requirement `lane:` field, backbone | platform | display
  (ADR-0017); the rename of the ingest loop to **capture** and of the audit
  loop to **inspect**, storage names such as `raw/ingested/` unchanged
  (ADR-0029, ADR-0030).
- Dashboard term network (DR-023 amendment): nodes are card-coloured boxes
  with a thick type-coloured frame, styled from the theme tokens in both
  themes; neighbour labels show ID plus a clipped title with the full title on
  hover; no overlapping boxes after expanding a layer.

### Fixed
- The Domain Terms tile in Commons is clickable as a whole, like its neighbours,
  and still offers the term network link.
- Decision and issue titles wrap, so a long one no longer pushes the Status
  column out of the table.
- Dashboard: the data-model class diagram drew a title with an umlaut as a
  broken identifier (`Durchführungsart` → `DurchfHrungsart`). Identifiers are
  now transliterated (ä→ae, ö→oe, ü→ue, ß→ss, other diacritics stripped) and
  every class whose identifier differs from its title carries the title as a
  mermaid class label, so multi-word titles read as written too. Harvested
  from isaqb-atrium.
- The Obsidian vault settings (`.obsidian/`, excluded files and themes) now
  ship with a spawned project; the guide had relied on them without the
  allow-list carrying them.

### Changed
- Dashboard follows the Systems42 sections diagram: one section catalog with
  three areas (Requirements, Architecture, Commons) and eighteen sections
  replaces the eleven req42-ordered home tiles. (DR-033)
- Dashboard: two-level navigation. Home shows Requirements and Architecture as
  two peaks, a valley with vault status, latest changes, open issues and ADRs,
  and Commons underneath; `/req42`, `/arc42` and `/commons` are area pages and
  breadcrumbs gain the area level. Section routes are unchanged; `/req42` is now
  the Requirements area page, not the reading-order overview. (DR-033)
- Dashboard: Architecture ships visible and empty ("not captured yet"). (DR-033)
- Dashboard: the hamburger menu (Configure, Theme, Who's here, Help, Reload,
  Disconnect all) replaces the footer buttons; new `/help` page explains the
  dashboard and the sections model. (DR-033)
- Dashboard: area colours (green Requirements, blue Architecture, red
  organisation) on tile eyebrows, area headings and a thin bar under the topbar.
  (DR-033)
- Dashboard: the Systems42 mark replaces the placeholder eye artwork in the
  hero, the topbar and the favicon (`static/systems42-logo.svg`,
  `static/systems42-favicon.png`).
- Dashboard: the topbar brand is omitted on the home page, where the hero
  already shows mark and name. (DR-032)
- Dashboard: the nav drops from nine entries to five — Goals · Stakeholders ·
  Backlog · Quality · Issues. Scope, Glossary, ADRs and the req42 reading-order
  page stay on the home tiles and gain a footer link row. (DR-032;
  superseded by DR-033)
- Dashboard: ⌘K (Ctrl K on Windows/Linux) focuses search; `/` no longer does.
  (DR-032)
- `docs/GETTING-STARTED.md`: "Starting over" now describes spawning a fresh
  project instead of the removed `reset.sh`; file tree updated.

### Removed
- `_system/adr/` and its Nygard template: the records moved to
  `wiki/decisions/` with their numbers (ADR-NNNN → DR-NNN, `aliases:
  [ADR-NNNN]`). (DR-034)
- Dashboard placeholder artwork `etsu-logo.png` and `etsu-favicon.png`.
