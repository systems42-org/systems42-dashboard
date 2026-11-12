# Close the Requirement Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Systems42 dashboard meet the requirements captured in its own wiki, after the quick wins of PR #13.

**Architecture:** Five independent work packages (WP1 to WP5), each one branch and one PR. They can run in parallel by different agents. Only WP5 Task 2 reads what WP4 Task 2 produces (`is_left_out`). Each task adds a no-pytest test file under `_system/apps/dashboard/tests/`, then the code.

**Tech Stack:** Python 3 and Flask (`_system/apps/dashboard/app.py`, `catalog.py`, `metamodel.py`), Jinja templates, plain JavaScript in `static/` (no build step, no framework), CSS in `static/style.css`. JS logic is tested under node (v26 installed) from a Python test, as `tests/test_search_popup.py` does.

**Spec:** the requirement pages in `wiki/`. Read each task's pages first: PROBLEM / GOAL, Success metric(s) and Scope are the acceptance criteria.
- Search: `wiki/functional-requirements/FR-001` to `FR-009`
- Method: `FR-010` to `FR-012`, `FR-018`
- Browsing and lists: `FR-017` to `FR-023`
- Issues: `FR-024` to `FR-028`
- Mobile: `wiki/quality-requirements/QR-001`
- Rules: `wiki/constraints/CON-001`, `CON-002`, `wiki/decisions/DR-002`, `DR-003`

The gap audit of 2026-11-12, which this plan closes, is summarised per task under "Today".

## Global Constraints

- **Delivery:** every change under `_system/`, `_templates/`, `AGENTS.md` goes by PR. Only the human merges. One PR per work package. Wiki pages at `draft` may be edited on `main` directly.
- **CHANGELOG:** every user-visible change gets an entry in `CHANGELOG.md` under `[Unreleased]`.
- **Run tests from `_system/apps/dashboard`:** `for t in tests/test_*.py; do .venv/bin/python $t || echo FAIL $t; done`. `test_design_tokens.py` failed before this plan. Every other test must pass.
- **Lint:** `.venv/bin/python ../../scripts/metamodel-lint.py` prints `metamodel-lint: OK`.
- **Template contract:** `tests/test_template_contract.py` fails if `app.py` reads a frontmatter key that no template in `_templates/` declares. A new field goes into the template and `_system/metamodel/types/` first.
- **No network at runtime (CON-001):** no CDN. A library goes into `static/vendor/` with its licence.
- **Copy:** UI text and docs follow `_system/writing-style.md` (DR-001): brief, plain English, no dashes or semicolons as punctuation.
- **Names:** section names come only from `catalog.py` (FR-017). Areas are Requirements, Architecture, Commons. C5 is "Domain Terms", C6 is "Issues". Never type a section name into a template.
- **Paths:** breadcrumbs are `Home › Area › Section › Page`, separator `›` (FR-020). Use `catalog.section_for_path(path)`, `catalog.section_href(section)` and `app._section_crumb(folder)` from PR #13.
- **Read only (CON-002):** the dashboard writes no file inside the wiki's repository.
- **Shared working copy:** another agent may work in the main checkout. Work in a git worktree. A worktree has no `.venv`. Use the main checkout's `_system/apps/dashboard/.venv/bin/python` by absolute path.

## Review Focus

- **Empty wiki.** A fresh vault with no glossary, no issues and no aliases must render search, lists and the issue page without errors. Add each new route to `tests/test_empty_vault.py`.
- **Non-ASCII words.** Typo distance, word forms and sorting must treat `Ärztin` as one word, and must not crash on accents. WP1 Task 3 and WP2 Task 2 each test one such word.
- **Bad query strings.** `/issues?section=XYZ`, `?status=bogus`, `?sort=nosuchcol` show the unfiltered list, never a 500. WP2 Task 3 and Task 4 test one each.
- **Bad frontmatter values.** An issue with a missing or unknown `category`, `status` or `severity` still lists, with an empty cell. WP2 Task 4 tests it.
- **Hidden plus left-out sections.** A section hidden by the view stays reachable by its address (FR-022). A section left out by the tailoring shows the "not used" note (FR-023). WP4 Task 2 tests both on the same fixture.

---

## WP1 Search (FR-001 to FR-009)

**Today:** `static/search-rank.js` (62 lines) does case-insensitive substring matching. Every query word must appear. The index (`build_search_records`, `app.py`) holds id, title, aliases and raw markdown body, wikilink targets included. There are no typos, word forms, filler words, reason notes, field hits, passages, related pages or filters other than type.

**Approach:** keep ranking client-side, shared by the popup (`search-popup.js`) and `/search` (`templates/search.html`). The server enriches the index. The ranker gains a match function that reports *how* a word matched, so the tier and the reason note come from one place.

### Task 1: Fixed test wiki and node harness

**Files:**
- Create: `tests/fixtures/search-wiki/` with pages for every example query of FR-002 to FR-008: `stakeholders/STK-023-keyholder.md` (title "Keyholder", `aliases: [Jedi Master]`, body says "the person that started the dashboard app"), `STK-003-requirements-engineers.md`, `STK-020` to `STK-022`, a glossary term with an alias used in another page that only names the term, pages containing `test` and `text`, a page with `priority: Must`, a page tagged `navigation`
- Create: `tests/search_harness.js`: loads `static/search-rank.js` with a stub `window`, reads records JSON from stdin, a query from argv, prints `[{id, score, note}]`
- Create: `tests/test_search_examples.py`: builds records from the fixture via `app.build_search_records()`, runs the harness per query, asserts top-3 positions

**Interfaces:**
- Produces: `run_query(q: str) -> list[dict]` helper in `test_search_examples.py` that every later WP1 task's tests call.

- [ ] Write `test_keyholder_exact_first`: `run_query("keyholder")[0]["id"] == "STK-023"`. Run: PASS today.
- [ ] Add every success-metric query of FR-002 to FR-008 as one test each, named `test_fr00N_<what>`. They fail today, which is expected. Each later task makes its own tests pass.
- [ ] Commit `test: fixed search wiki and node harness (FR-001)`

### Task 2: Richer index

**Files:** Modify `app.py` `build_search_records`. Test: `tests/test_search_index.py`

**Interfaces:**
- Produces: each record gains `plain` (body with markdown, wikilink targets and HTML removed, `[[X|label]]` → `label`, lower-cased), `aliases: list[str]`, `fields: dict[str, list[str]]` (keys `tags, status, stereotype, priority, kind, state, category, dimensions`, values lower-cased, missing keys left out), `links: list[str]` (IDs one link step away, both directions, from `link_index`), `synonyms: list[list[str]]` on the index root (each glossary term's title plus its aliases). `/search.json` returns `{"records": [...], "synonyms": [...]}`, and `search-popup.js` reads that new shape.
- `text` stays for compatibility until Task 7, then is removed.

- [ ] Tests: `plain` of a page linking `[[STK-023-keyholder|Keyholder]]` contains `keyholder` and not `stk-023-keyholder`. `fields["priority"] == ["must"]`. `links` of STK-023 contains every page that links it. `synonyms` contains `["keyholder", "jedi master"]` when the fixture glossary defines that term.
- [ ] Implement, run, commit `search: plain text, fields, links and synonyms in the index`.

### Task 3: Typos and word forms (FR-002)

**Files:** Modify `static/search-rank.js`. Test: `test_search_examples.py`

**Interfaces:**
- Produces in `search-rank.js`: `matchWord(qword, word) -> {kind: "exact"|"prefix"|"form"|"typo", from, to} | null` and `stem(word) -> string`.
- Rules from FR-002: words of 3 letters or fewer and IDs (`/^[a-z]+-\d+$/`) match only exactly or as a prefix. 4 to 7 letters allow Damerau-Levenshtein distance 1. 8 or more allow 2. `stem` strips, in order, `ing`, `ed`, `es`, `s` when at least 3 letters remain. Two words match as `form` when their stems are equal.
- Tier order: an exact hit always outranks a form or typo hit at the same place (FR-002 last rule).

- [ ] Tests pass: `keyholdr` → STK-023 in top 3. `stakholdrs` → an STK page in top 3. `requirement engineer` → STK-003 in top 3. `STK-02` → STK-020 to STK-023 first. `test` ranks the `test` page above the `text` page. Also `ärztn` matches `ärztin`.
- [ ] Commit `search: typo tolerance and word forms (FR-002)`.

### Task 4: Aliases and glossary synonyms (FR-003)

- [ ] Tests: `Jedi Master` → STK-023 in top 3, scored below an exact title hit for the same query. A query for a glossary alias finds the page that only uses the term's name.
- [ ] In `rank(records, q, synonyms)`, expand each query word to its synonym group before matching. Add an `alias` tier below `exact` title. Commit `search: aliases and glossary synonyms (FR-003)`.

### Task 5: Questions and partial matches (FR-004)

- [ ] Tests: `who starts the app` → STK-023 in top 3. For `keyholder workshop`, pages with both words rank above pages with one, and those show the note `matches 1 of 2 words`. The query `the a` still returns results.
- [ ] Add `STOP_WORDS` (who what when where why how the a an is are does do of to in on for and or with) to `search-rank.js`. Drop them unless the query has nothing else. Pages with all remaining words come first. Partial pages follow, ranked by the number of matched words. Commit `search: filler words and partial matches (FR-004)`.

### Task 6: Reason note (FR-005)

**Interfaces:** `rank` returns `{rec, score, note}`. `note` is `null` for an exact hit, else one of `typo: keyholdr → keyholder`, `word form: starts → started`, `via alias of Keyholder`, `matches 2 of 3 words`, `linked from STK-023` (Task 9).

- [ ] Tests: every non-exact example hit carries its note, and no exact hit carries one. Render the note in `search-popup.js` and `templates/search.html` as `<span class="hit-note">`. A test in `test_search_popup.py` asserts the class exists in both. Commit `search: reason for every non-exact hit (FR-005)`.

### Task 7: Fields (FR-006, Should)

- [ ] Tests: `Must` finds every fixture page with `priority: Must`. A tag hit ranks above a body-only hit and below a title hit.
- [ ] Add a `field` tier between title and body. Remove `text`. Update FR-006 on `main`: the field list says `dimensions` instead of `attribute` (DR-003). Commit `search: tags and fields (FR-006)`.

### Task 8: Passage on /search (FR-007, Should)

- [ ] Test: every `/search` hit for a body query shows a `<p class="hit-passage">` containing `<mark>` around the query word. A title hit shows the page's first sentence. The popup has no passage.
- [ ] Split `plain` into sentences client-side. Escape the text before inserting `<mark>`. Commit `search: highlighted passage (FR-007)`.

### Task 9: Related pages (FR-008, Should)

- [ ] Test: query `keyholder` on `/search` shows `<section class="related-pages">` below the hits, with at most 5 pages, none of them a hit, each with note `linked from STK-023`. The popup shows none. Only title and alias hits pull in neighbours.
- [ ] Commit `search: related pages group (FR-008)`.

### Task 10: Filters on /search (FR-009, Could)

- [ ] Test: choosing status `accepted` leaves only accepted hits. Filters for status, priority and tag sit next to the type facets. The search box has no filter syntax.
- [ ] Commit `search: status, priority and tag filters (FR-009)`. Then open the WP1 PR.

---

## WP2 Lists and issues (FR-021, FR-022, FR-024 to FR-028)

**Today:** `static/table-sort.js` sorts one column, and only tables with `data-sort` headers. The issue list has no sortable headers. No list puts sort or filter into the address. The issue list filters only All, Open and Closed, shows no category or owner, and opens rows in a pane. Issue pages show only the status. Issues reach a page only through the general relations panel, and not at all on FR pages.

### Task 1: Sort orders in the metamodel (FR-021, schema)

**Files:** Modify `_system/metamodel/meta-metamodel.md` (document the type key `sort_orders`), every `_system/metamodel/types/type-*.md` that has a list, `_system/scripts/metamodel-lint.py`, `metamodel.py`. Test: `tests/test_metamodel_lint.py`

**Interfaces:** `sort_orders: [{label: str, keys: [field, ...]}]` on a type page. Values: functional-requirement `Priority › release › order` = `[priority, release, order]`. Issue `Status › severity` = `[status, severity]`. Decision-record `Newest first` = `[decided]`. Glossary-term `A to Z` = `[title]`. Stakeholder `Influence › interest` = `[influence, interest]`. Quality-requirement `Priority` = `[priority]`. Produces `metamodel.sort_orders(type_name) -> list[dict]`.

- [ ] Test: the lint fails when a `sort_orders` key names a field that is neither in the type's `fields` nor universal. Implement, commit `schema: sort orders per type (FR-021)`.

### Task 2: Shared list layer

**Files:** Create `static/list-view.js` (replaces `table-sort.js`, keep its `data-sort` contract), test `tests/test_list_view.py` (node harness like WP1 Task 1).

**Interfaces:**
- Markup: `<table data-list="<type>" data-sort-orders='<json from metamodel.sort_orders>'>`, rows carry `data-status`.
- Address: `?sort=<key>:<asc|desc>,<key>:<asc|desc>` and `?status=accepted|all`. Written with `history.replaceState` on every change, read on load.
- Status filter "Agreed only" keeps rows with `data-status="accepted"` (FR-022).
- Produces `S42List.sortRows(rows, [{key, dir}])` for tests.

- [ ] Tests: a two-key sort orders ties by the second key. `sortRows` puts empty cells last in both directions. `Ärztin` sorts next to `Arzt`. An unknown sort key leaves the server order.
- [ ] Commit `lists: multi-column sort, sort orders, status filter, address (FR-021, FR-022)`.

### Task 3: Every section list uses the layer

**Files:** templates `glossary.html`, `stakeholders.html`, `decisions.html`, `req42_block.html`, `issues.html`, `data_model.html`, `functional-requirements.html` (add a flat sortable table under the hierarchy), the arc42 list templates (add a table where there is none).

- [ ] Test `tests/test_lists_everywhere.py`: each section route's HTML has one `table[data-list]`, its sort-order picker lists the metamodel's orders, every `th` has `data-sort`, every row links its page. `/req42/quality?sort=nosuchcol:asc` returns 200.
- [ ] Commit `lists: every section list sorts and filters (FR-021, FR-022)`.

### Task 4: Issue list (FR-025, FR-026, FR-028)

**Files:** `app.py` `issues_view`, `templates/issues.html`. Test: `tests/test_issue_list.py`

**Interfaces:** items gain `category`, `owner` (string, `""` when empty), `sections: list[str]` (section IDs whose pages the issue links). Query parameters: `status`, `category`, `severity`, `section` (from PR #13), `owner` (`none` = nobody yet). They combine with AND and go into the address like Task 2.

- [ ] Tests: columns Category and Owner exist, and an issue without `owner:` shows `nobody yet`. `?category=systems42` leaves ISS-002 only (fixture). `?owner=none&severity=minor` combines. Open count counts `open` and `in-progress` only. An issue with `category: bogus` lists with an empty category cell. Each row's ID and title link the issue page, and the inline pane is removed.
- [ ] Commit `issues: category, owner and filters (FR-025, FR-026, FR-028)`.

### Task 5: Issue page fields (FR-026, FR-028)

- [ ] Test: `/page/issues/ISS-002-…` shows category, severity, kind and owner in its header, owner `nobody yet` when empty. Commit `issues: fields on the issue page`.

### Task 6: Issues on the page they affect (FR-027)

**Files:** `app.py` new `open_issues_for(stem) -> list[dict]` (`id, title, status, severity, url`, open first then by severity), `templates/detail.html`, `templates/fr.html`, new partial `templates/_page_issues.html`.

- [ ] Tests: STK page linked by an issue shows `<section class="page-issues">` with that issue, status and severity. An FR page linked only from an issue's `related:` shows it too. A page without issues shows "No open issues". Closed issues come after open ones.
- [ ] Commit `issues: open issues on every page they affect (FR-027)`. Then open the WP2 PR.

---

## WP3 Mobile (QR-001)

**Today, measured at 320 px:** `/goals` scrolls to 2104 px (goal matrix `overflow: visible`). Every FR page scrolls to 384 px (`.detail-head` flex without wrap). `/join` 386 px (grid `1fr` without `minmax(0, 1fr)`). `/about` 358 px (markdown table without a wrapper). `/metamodel` 325 px (`.mm-universal-item` `white-space: nowrap`). The nav never collapses and hides three entries off-screen. Breadcrumb, footer and sort-header links are 14 to 20 px high. Labels are 10.6 to 11.5 px. The glossary graph, deployment view, FR goal nodes and context stakeholders have nodes without text links. Mermaid diagrams shrink to the screen with no pan or zoom.

### Task 1: Layout test at 320 px

**Files:** Create `tests/test_mobile_layout.py`. It starts the app on a free port with `tests/fixtures/wiki` and `tests/fixtures/arc42-views/wiki`, drives headless Chromium through Playwright, and skips with a message when Playwright is missing.

- [ ] Assert for every route in `ROUTES` (every `@app.route` without parameters plus one page per folder): `document.documentElement.scrollWidth <= 320`. Every `a, button` outside running text (`p a`, `li > a.wl` excluded) has a bounding box of at least 24 × 24 px. Computed `font-size` of visible text is at least 12 px.
- [ ] Run: FAILS on the pages above. Commit `test: mobile layout at 320 px (QR-001)`.

### Task 2: No sideways scroll

- [ ] Fix in `static/style.css`: `.goal-matrix-card { overflow-x: auto }`. `.detail-head { flex-wrap: wrap }`. At `max-width: 780px` `.join { grid-template-columns: minmax(0, 1fr) }`. Wrap tables rendered from markdown in `<div class="table-scroll">` in `render_markdown`. `.mm-universal-item { white-space: normal }`. Run Task 1: the width assertions pass. Commit.

### Task 3: Header collapses

- [ ] At `max-width: 640px` the nav entries move behind a "Menu" button (`aria-expanded`, `aria-controls`) in `base.html`. Without JS the entries wrap onto a second row. Test: at 320 px all five entries are reachable after one tap. Commit.

### Task 4: Touch targets and text size

- [ ] Pad `.crumbs a`, footer links, `.th-sort`, `a.area-section-link`, `a.term-link` to at least 24 px high. Raise badge, pill and `ml-id` sizes to 12 px. Run Task 1: all assertions pass. Commit.

### Task 5: Diagram nodes as text links

- [ ] Test per page: every node ID drawn on `/graph/glossary`, `/arc42/deployment`, `/page/deployment-nodes/*`, `/req42/functional-requirements` and `/req42/scope` appears as an `<a>` to its page elsewhere on the same page. Add a "Shown in the diagram" list under each diagram from the same data that builds it. Commit.

### Task 6: Diagrams on small screens (best effort)

- [ ] Below 780 px, render Mermaid with `useMaxWidth: false` inside `<div class="diagram-scroll">` (`overflow: auto`, `touch-action: pan-x pan-y pinch-zoom`). A diagram then keeps its natural size and pans by touch instead of shrinking. No new library. Commit, then open the WP3 PR.

---

## WP4 Tailoring and view (FR-023, DR-002, CON-001, CON-002)

**Today:** the tailoring is hard-coded as `scope` in `catalog.py`. Left-out sections R2, R5 and R6 still show on `/`, `/req42` and in the Configure dialog. There is no "not used" page. Configure writes `_system/dashboard.yaml` inside the repository and offers every section.

> [!important] Decide first (human)
> - **D1. Where the tailoring lives.** Proposal: the `scope: in | out` already on every block in `_system/metamodel/frameworks/fw-*.md` *is* the tailoring. A project changes it by PR. `catalog.py` reads it instead of keeping its own copy.
> - **D2. Where the view lives.** Proposal: outside the repository, in `~/.config/systems42/<wiki name>/view.yaml`, overridable by `DASHBOARD_CONFIG`. The dashboard refuses a path inside the wiki's repository.
> - **D3. The dialog's name.** Proposal: "View".
> Record the answers in DR-002's "More Information" through a PR before starting Task 2.

### Task 1: Catalog reads the tailoring

- [ ] Test `tests/test_tailoring.py`: with a fixture framework file setting C2 `scope: out`, `catalog.SECTION_BY_ID["C2"]["scope"] == "out"`. The lint fails when `catalog.py` and the framework files disagree on IDs.
- [ ] `catalog.py` loads `scope` from the framework blocks through `metamodel.py` at import time. The three areas always exist (FR-023). Commit.

### Task 2: Left-out sections appear nowhere

**Interfaces:** Produces `catalog.is_left_out(section_id) -> bool`, used by WP5 Task 2.

- [ ] Tests: a left-out section is absent from `/`, its area page, the header, every count, `/search` results and the view dialog. `/section/<ID>` for a left-out section returns 200 with "This part is not used in this project". A section hidden by the view still answers at its own address (FR-022).
- [ ] Add the route `/section/<id>`, which redirects to the section's page when it is used. Commit.

### Task 3: View outside the repository

- [ ] Tests: the default view path is outside `WIKI_DIR` and outside the repository root. Setting `DASHBOARD_CONFIG` inside the repository makes `POST /settings` answer 409 and write nothing. The dialog and its texts say "View" (D3). `base.html` no longer mentions `_system/dashboard.yaml`.
- [ ] Migrate on start: an existing `_system/dashboard.yaml` is read once into the new location and reported on the first page. Never delete it automatically. Commit.

### Task 4: Constraints follow

- [ ] On `main`, set CON-002 to say the exception for `_system/dashboard.yaml` is gone (the page is `draft`).
- [ ] CON-001: `/help`, `README.md` and `/join` say "No login. Use it only on a trusted network." Test it in `test_help.py`. Commit, then open the WP4 PR.

---

## WP5 Method, guided path and first page (FR-010 to FR-012, FR-018, FR-019)

**Today:** no explanation of the loops, no guided path. The first page shows the tagline instead of the vision sentence, has no guided-path link and no page counts per section. Several section tiles list page names (R1, R3, C1, C2, C4, C7), R1 has no count, and C6 counts open issues instead of pages.

### Task 1: The three loops (FR-011)

- [ ] Test `tests/test_method.py`: `/method` returns one screen of text with three headed parts Capture, Inspect and Clarify, and a sentence on how they feed each other. Clarify shows the note "Being defined by the Systems42 team" and links ISS-002 while ISS-002 is open. The footer of every page links `/method`.
- [ ] Copy for Capture and Inspect comes from FR-011's bullets, unchanged in meaning. Commit.

### Task 2: Guided path (FR-012)

**Interfaces:** `GUIDED_STEPS` in `app.py`, in FR-012's order: `[("vision", text), ("R1", text), ("C4", text), ("C3", text), ("R3", text), ("A2", text), ("C7", text), ("C6", text), ("method", text)]`. `vision` shows the vision goal page, `R1` the objectives, `method` the page from Task 1. `text` is the one or two sentences per step, the same for every project. Route `/tour/<n>`.

- [ ] Tests: steps of sections with no pages, hidden by the view or left out (`catalog.is_left_out`, WP4) are skipped, and the numbering closes up. Each step shows "Step n of m", Next and Back, and the section's own pages. `/tour` resumes at the last step, kept in `localStorage` key `s42-tour-step`, with step 1 as the fallback.
- [ ] Commit.

### Task 3: First page and section tiles (FR-018, FR-019)

- [ ] Tests in `test_home_layout.py`: the hero shows the first sentence of GOAL-001's vision, and the tagline only when there is no vision. A "Take the guided path" link opens `/tour`. Each area tile lists its sections with their page counts. Section tiles on area pages show count, maturity bar and the open-issue link only: no page-name rows, R1 counts its pages, C6 counts issues and shows open as the flag.
- [ ] Commit, then open the WP5 PR.

---

## Not in this plan

- **Joining data-model terms and the glossary** into one metaclass "domain term" (Gernot Starke, 2026-11-12, likely). That is a Systems42 metamodel change and needs its own decision record first.
- **The clarify loop itself** (ISS-002), owned by Gernot Starke and team.
- **The FR-010 demo metric,** which waits for GOAL-002's metric to be agreed.
