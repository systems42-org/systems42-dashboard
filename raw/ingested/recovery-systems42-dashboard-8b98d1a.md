---
title: Recovery report — systems42-dashboard 8b98d1a
author: agent (Claude Code, Claude Opus 5.5), for Peter Gerstbach
date: 2026-11-21
repository: systems42-org/systems42-dashboard
revision: 8b98d1a0918ec06adcd49a2eb30dd031dd94997a
scope: the whole repository
depth: level 1
---

# Recovery report — systems42-dashboard 8b98d1a

Made with the Recover loop (`systems42-org/meta`, `_system/workflows/recover.md`).
Every finding is an abstraction; code names appear only as evidence. Labels:
**observed** (a check ran), **read** (inferred from the code), **assumed**.

## Scope and evidence

- **Wiki first.** This wiki is rich in goals (8), stakeholders (7), functional
  requirements (62), constraints (6) and decision records (7). It has no
  context page, external interfaces, building blocks, domain terms, data
  models, concepts, runtime scenarios or deployment nodes. The dig went
  deepest where the wiki is empty, and compared where it is rich.
- **Read:** the launcher, the web application and its helper modules, the
  container build, the package definition, the CI workflows, the website
  builder's structure, the test names, both READMEs.
- **Not read:** templates, browser scripts, stylesheets, test bodies (except
  where a check ran them).
- **Working tree:** clean apart from an untracked trial report in `raw/`,
  outside the code.
- **Checks run (observed):** five, listed under Constraints and Quality hints.
  The check scripts stayed outside this repository.

## Goals and stakeholders

Questions only; see gaps 1 and 2.

## Context and external interfaces

The dashboard has **two external systems** (read):

1. **The wiki repository it shows.** In, read-only: the pages, the source
   records, the metamodel, the method anchors, the docs and the wiki's
   configuration. This is the dashboard's whole input. Evidence: the
   repository paths the application reads from its environment; the launcher
   mounts the repository read-only.
2. **GitHub, as code host and release platform.** In: the newest release
   version on request, the container image on first start, the Python wheel
   for the start without a container. Out: test runs on every change, the
   release (image, wheel) for each version tag, and the public website with
   its static demo. Evidence: the launcher's release addresses, the three CI
   workflows.

At runtime the dashboard sends nothing out: no call to an outside service
was found (read). Browsers on the local network are its users, not external
systems; they belong to the stakeholders as what they receive.

## Constraints

| Constraint | Result | Evidence |
|---|---|---|
| CON-002 the dashboard never writes to the wiki | **holds (observed)** | All 34 GET pages without parameters plus 3 with parameters answered without error; no file in the repository changed size or time. Writing requests change only memory or stop the process (read). |
| CON-005 Systems42 derivatives only | **holds (observed)** | The start check, run against a folder with only `wiki/`, named the four missing parts and stopped (exit 1). |
| CON-004 shows the metamodel, does not define it | **holds (observed)** | In a copy of this wiki, renaming one section in the metamodel changed its title on the home page; the old title was gone. |
| CON-006 the dashboard depends on the metamodel, never the reverse | **method side holds (observed); dashboard side in question** | The method lint here and in meta ran without any dashboard code, and neither imports it. On the dashboard side, a presentation table is keyed by the metamodel's section ids (read); see gap 5. |
| CON-003 Docker and uv are the supported starts | **not checked** | Docker is not available on the machine of this run, and the uv start would download a release; neither ran. |
| CON-001 proof of concept | **not checkable** | Organisational; no code check applies. |

Candidate constraints the code obeys but the wiki does not name (read):

- **Reproducible builds:** every library is pinned, the indirect ones too,
  and the container's base image is pinned by digest. The wheel and the
  image must hold the same files; a test enforces it.
- **Least privilege in the container:** the dashboard runs as an
  unprivileged user.

## Quality hints

- **Safety against hostile wiki content** (security). Wiki text comes from
  emails and tickets, so the dashboard renders markup inert and keeps every
  file request inside its folder. **Observed:** the hostile-vault test ran and
  passed. No quality requirement names this; [[STK-020-data-protection-and-security-officers]]
  names network exposure, not content. Measure: a gap.
- **Fast enough at workshop scale** (performance). Pages are parsed on every
  request with a cache, and a performance test exists for the issue list
  (read). No quality requirement or measure.
- **Offline use** is covered: [[FR-029-the-dashboard-as-a-product]] says the
  dashboard runs without network after its first start (read). The manual
  trial had wrongly reported this as a gap.

## Building blocks (level 1)

Six black boxes (read):

| Block | Responsibility | uses |
|---|---|---|
| Launcher | Starts the release a wiki names, in a container or without; stops, cleans, updates the named release | Web dashboard |
| Web dashboard | Serves every view of the wiki, the shared session and the start check | Metamodel adapter |
| Metamodel adapter | Turns the repository's metamodel into the sections, types and anchors the views use | — |
| Browser client | Interactive parts in the browser: search ranking, sorting, diagrams, the presence signal | Web dashboard |
| Website builder | Builds the public website and a static demo of a wiki | Web dashboard |
| Release pipeline | Tests every change; publishes image, wheel and website | Web dashboard, Website builder |

The Web dashboard is one large unit with about fifteen responsibilities.
Whether it divides into level-2 blocks, and how, is a design question the code
does not settle (gap 7).

## Features

Covered by the wiki (read, after reading each page): search, browsing by area
and section, the first page with the latest changes, a page with its links and
sources, issues, goal coverage, domain terms in two views, the story map, the
method and its anchors, the shared workshop session, the menu, the self-stop,
branding, releases and the launcher, the start without a container, and the
public website.

Missing — capabilities the code offers that no requirement names (read):

1. **See the architecture views:** building-block white boxes, crosscutting
   concepts, runtime scenarios, deployment, and the context diagram.
   [[FR-047-see-the-requirements-as-a-story-map]] excludes "other diagrams".
2. **Read the backlog in priority order.**
3. **Read the project's own About page** and the files it links.
4. **Read the whole metamodel as a reference.** [[FR-035-method-terms-lead-to-their-definition]]
   covers only its anchor entries.
5. **Read the help.** [[FR-053-reach-the-session-controls-and-the-theme-from-one-menu]]
   puts Help in the menu, but no requirement says what it contains.

## Cited requirement IDs

The code and the two READMEs cite 51 IDs. The READMEs were written alongside
the requirements, so they are trace claims, not evidence (read).

- **Wrong** (resolves here to a different requirement): `FR-004` at the
  notation default (means meta's notation choice), `FR-023` at the project
  notations (means meta's notations), and `FR-009` at the decision list
  (means meta's decision records). The other `FR-009` citation, at the
  search filters, is right.
- **Foreign** (belongs to meta): `DR-013`, `DR-014`, `DR-016`, `DR-018`,
  `DR-019`, `DR-026`, `DR-027`, `DR-034`, `DR-035`, `DR-038`, `DR-039`.
  `DR-010` belongs to isaqb-atrium. `DR-012` exists in both with different
  meanings.
- **Dangling:** `DR-022`, `DR-023`, `DR-033`, and in the app README
  `DR-025`. They were retired from meta when the dashboard requirements moved
  here (meta#49) and never re-created.
- Not citations: example IDs inside docstrings.

## Comparison with the wiki

- **Covered:** CON-002, CON-004, CON-005 (observed); the features listed as
  covered; offline use.
- **Missing:** the context and both external interfaces; six level-1
  building blocks; two candidate constraints; two quality requirements; five
  capabilities.
- **In conflict:**
  - [[ISS-005-the-method-lint-imports-dashboard-code]] is open, but the lint
    no longer imports dashboard code (observed).
  - CON-006 says the dashboard holds no section ids, yet its presentation
    table is keyed by them (read).
- **Delivery evidence:** see *Delivery candidates*.

## Delivery candidates

This wiki's metamodel has no delivery fields yet: it has no requirement
notations and no `implementable_levels` (read). So no requirement here can
record a delivery state, and an Implement backfill needs that part of the
metamodel first (gap 9).

Built as far as the code shows (read), with no delivery recorded:

- **Stories:** [[FR-050-stop-the-dashboard-when-nobody-is-watching]],
  [[FR-053-reach-the-session-controls-and-the-theme-from-one-menu]].
- **Features without stories under them:**
  [[FR-018-orientation-on-the-first-page]], [[FR-030-numbered-releases]],
  [[FR-031-branding-is-configuration]], [[FR-035-method-terms-lead-to-their-definition]],
  [[FR-036-goal-coverage-matrix]], [[FR-042-start-a-pinned-release-with-one-command]],
  [[FR-054-a-start-without-a-container-engine]].
- **Features with stories under them, none recording delivery:**
  [[FR-034-read-a-page-with-its-links]], [[FR-040-two-views-of-the-same-terms]],
  [[FR-046-shared-session-in-a-workshop]], [[FR-047-see-the-requirements-as-a-story-map]].

Recover sets no delivery state; these are candidates for Implement.

## Gaps

Numbered top-down. Asked one at a time: **intent** gaps as open questions
with existing pages that may apply (candidates only where they fit well),
**choice** gaps with options and a recommendation.

1. **Intent — safety against hostile content.** The code treats wiki text as
   untrusted (markup rendered inert, file requests kept inside their folder),
   and a test enforces it. Why does the dashboard need this, and for whom?
   May apply: [[STK-020-data-protection-and-security-officers]] (candidate; its
   concern today is network exposure, not content), [[GOAL-001-trusted-answers]],
   [[CON-001-proof-of-concept-not-production-ready]].
   **Answer:** It protects workshop participants from malicious content in
   the sources the wiki is captured from. The dashboard is also published on
   the public website as a demo ([[FR-058-a-demo-to-try-without-installing]]),
   so it must be safe for anyone to look at: website visitors are protected
   too. (Fact checked: website visitors have no stakeholder page of their
   own; today they are part of [[STK-013-people-learning-or-presenting-systems42]],
   and [[FR-057-overview-of-the-dashboard-on-the-website]] and
   [[FR-061-legal-and-project-information-on-the-website]] call them
   visitors.)
   **Follow-up (choice):** website visitors as their own stakeholder, or
   part of STK-013? **Answer:** they stay in
   [[STK-013-people-learning-or-presenting-systems42]]; the safety concern
   is added there.
2. **Intent — the Keyholder's rights.** The Keyholder is whoever's tab says
   so; nothing checks it. Is that acceptable, and under which conditions?
   May apply: [[STK-023-keyholder]], [[FR-046-shared-session-in-a-workshop]],
   [[CON-001-proof-of-concept-not-production-ready]], [[STK-020-data-protection-and-security-officers]].
   Facts given before the answer: the reason is only a code comment (no
   token or cookie by design; an address check cannot tell the Keyholder's
   own request from tunnelled traffic under Docker Desktop's network
   translation); the public demo is a static snapshot without a server, so
   it has no Keyholder.
   **Answer:** Acceptable, as an accepted risk of
   [[CON-001-proof-of-concept-not-production-ready]] in a workshop session
   like [[FR-046-shared-session-in-a-workshop]].
3. **Choice — context.** (a) one context page with two external interfaces,
   the wiki repository and GitHub; (b) GitHub split into code hosting,
   registry and website hosting; (c) no context page yet.
   → Recommended: (a).
   May apply: [[GOAL-008-one-way-into-every-systems42-wiki]],
   [[DR-004-releases-are-container-images-pinned-per-wiki]],
   [[FR-062-the-website-is-built-and-published-from-the-repository]].
   **Answer:** (a).
4. **Intent — reproducible builds and least privilege.** Everything is pinned
   down to the base image, and the container runs unprivileged. Are these
   rules the dashboard must keep, and why?
   May apply: [[DR-004-releases-are-container-images-pinned-per-wiki]],
   [[QR-002-runs-alike-on-linux-and-macos]], [[STK-012-maintainers]], [[STK-010-operators]].
   **Answer:** No real requirement beyond the state of the art, as far as
   the human can tell; they are not sure, as it is outside their expertise.
   **Open:** to be confirmed by someone with that expertise.
5. **Choice — CON-006 and the presentation table** (asked first as intent,
   rephrased as a choice). The dashboard keys route, colours and, for three
   out-of-scope sections, the tile text by the metamodel's section ids; a
   section the table does not know falls back to the generic route and its
   area's colours (read: `catalog.py`). CON-006 says "no section ids" but
   also "presentation stays in the dashboard". (a) sharpen CON-006: the
   dashboard may key presentation by section id, as long as an unknown
   section still shows through the fallback; (b) keep the wording and record
   the table as a violation. → Recommended: (a).
   May apply: [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]],
   [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]],
   [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]].
   **Answer:** (a).
6. **Intent — speed.** How fast must a page answer, for how large a wiki, in
   which situation?
   May apply: [[STK-008-workshop-participants-and-facilitators]],
   [[QR-001-usable-on-phone-and-tablet]]. No candidate measure exists in the wiki.
   Fact given before the answer: a test asks for under 1.5 seconds per page
   with 200 issues and a warm cache (read: `tests/test_issue_perf.py`).
   **Answer:** 1.5 seconds is fine for a workshop wiki. Page speed is not
   important now; the hard part is reading everything and getting the
   abstractions.
7. **Choice — building blocks.** (a) capture the six level-1 blocks and leave
   the Web dashboard as one black box; (b) capture them and recover the Web
   dashboard one level deeper next; (c) none yet.
   → Recommended: (a).
   May apply: [[DR-004-releases-are-container-images-pinned-per-wiki]]
   (driver for Launcher and Release pipeline),
   [[FR-062-the-website-is-built-and-published-from-the-repository]]
   (driver for Website builder).
   **Answer:** (a).
8. **Intent — the five capabilities without a requirement** (architecture
   views, backlog in priority order, About page, metamodel reference, help).
   Which of them are wanted, and what is each for?
   May apply: [[GOAL-005-architecture-traced-to-requirements]] (candidate for the
   architecture views), [[STK-013-people-learning-or-presenting-systems42]]
   (names the help and metamodel pages), [[STK-010-operators]] (names the About
   page), [[FR-047-see-the-requirements-as-a-story-map]], [[FR-035-method-terms-lead-to-their-definition]],
   [[FR-053-reach-the-session-controls-and-the-theme-from-one-menu]].
   **Answer 8.1 (architecture views):** all five views are required, used
   by almost all stakeholders, mostly by architects and maintainers.
   (Fact: this wiki has no architect stakeholder page; maintainers are
   [[STK-012-maintainers]].)
   **Answer 8.2 (backlog in priority order):** wanted, to plan and refine
   requirements and to prioritize; used mostly by product owners, business
   analysts and requirements engineers, but by most other stakeholders too.
   (Fact: this wiki has no stakeholder page for product owners, business
   analysts or requirements engineers.)
   **Answer 8.3 (About page):** wanted, to explain the brand and the
   project, for readers ([[STK-001-readers]]).
   **Answer 8.4 (metamodel reference):** wanted, to learn and explain the
   method, for [[STK-013-people-learning-or-presenting-systems42]] and many
   other stakeholders.
   **Answer 8.5 (help):** to learn and explain the dashboard and the
   method, for everyone.
9. **Choice — delivery backfill.** (a) bring meta's delivery fields and
   notations into this wiki's metamodel first, then backfill the candidates
   with Implement; (b) backfill nothing for now; (c) record delivery in
   another way.
   → Recommended: (a).
   Fact found in the closing round: after the pinned revision, `main`
   synced the method from meta (b9a0dc0, #103, 2026-11-22). This wiki now
   has the notations, delivery fields and `implementable_levels: [story]`;
   at 8b98d1a it had none (checked: no notation files). Only stories can
   record delivery, so the seven features without stories need stories
   first. Option (a)'s first step is done; the gap is asked again as:
   (a) backfill with Implement, one story per run, starting with the built
   stories FR-050 and FR-053; (b) backfill nothing for now.
   May apply: [[FR-048-show-the-delivery-status-of-a-requirement]].
   **Answer:** (a), as separate Implement runs after this closing round.
10. **Choice — ISS-005.** The lint no longer imports dashboard code
   (observed). (a) resolve it with this evidence; (b) leave it open.
   → Recommended: (a).
    Facts found in the closing round: ISS-005 is still open on `main`;
    meta#40, which it raised, was closed on 2026-11-18; meta no longer holds
    `_system/apps`.
    May apply: [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]],
    [[FR-044-sections-come-from-the-repositorys-metamodel]].
    **Answer:** (b), leave it open.
11. **Choice — wrong, foreign and dangling IDs in the code.** (a) one Issue:
    prefix foreign IDs, correct the wrong ones, replace or drop the dangling
    ones; (b) fix them directly in the next dashboard change; (c) leave them.
    → Recommended: (a).
    **Answer:** (a).
