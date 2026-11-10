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

### Added
- Writing style guide: `_system/writing-style.md` is binding for every text in
  the repository. `AGENTS.md` points to it, `CLAUDE.md` imports it, and
  `new-project.sh` ships it. The page size of about 300 words is a suggestion,
  not a limit.

### Changed
- `grilling` skill: brought up to date with upstream `mattpocock/skills`. Each
  question is now worded so that "yes" accepts the recommended answer, and
  fact-finding sub-agents start with a fresh context window.
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
  Scope, Glossary and Decisions to sort, click again to flip. IDs sort
  naturally, influence and interest by rank (first click: high first), status
  by lifecycle, and empty cells stay last. `static/table-sort.js`, which also
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
- Decision titles wrap, so a long one no longer pushes the Status column out of
  the table.
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
