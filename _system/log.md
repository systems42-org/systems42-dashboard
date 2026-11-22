# Log

Append-only. One entry per operation. Keep the prefix exact so the log is
greppable: `grep '^## \[' _system/log.md | tail -5`.

<!-- Format (indented so the grep above does not match it):
    ## [YYYY-MM-DD] <op> | <subject>
    - Source / scope, grill gate, created, updated, issues, open questions
-->

## [2026-11-10] new-project | Systems42 Dashboard
- Created with `_system/scripts/new-project.sh new` from atrium-main @ ec95003.
- Product paths copied (schema, templates, anchors, workflows, skills, dashboard, docs). No decision records are inherited: `wiki/decisions/` starts empty and this project's own decisions start at DR-001.
- `wiki/` and `raw/` start empty. Next step: `_system/workflows/bootstrap.md`.

## [2026-11-10] capture | Stakeholders of the Systems42 dashboard
- Source: `raw/01-stakeholders.md`, edited by Gernot Starke, now [[SRC-001-stakeholders-of-the-systems42-dashboard]] in `raw/ingested/`. The answers from the grilling session are [[SRC-002-grilling-session-on-stakeholders]].
- Grill gate: grill-requirements found nothing to clash with (the wiki held only DR-001). Gernot Starke answered Q1 to Q14 one at a time, so no question went unasked.
- Decisions in the session:
  - Q1: the scope statement is a constraint, not a decision record. The dashboard serves workshops, demos and everyday work, and it is not production-ready for every environment.
  - Q2: one page per group. Groups that overlap link to each other.
  - Q3: two groups added as assumptions, builders of project-specific dashboards and prospective adopters.
  - Q4 and Q5: the facilitator is the person who leads a workshop. The dashboard right is renamed Keyholder (handed over by the session systems42-dashboard-3f, which wrote nothing). There is no "Facilitator role" glossary term.
  - Q6: no login for now, a login could be added later. Both go into CON-001.
  - Q7: the Keyholder is the person who started the dashboard app.
  - Q8: AI agents are a stakeholder hidden from the context diagram.
  - Q9: influence and interest as in the proposed table.
  - Q10: three context nodes, Reader, Keyholder and Operator. 006, 012, 020 and 021 are hidden.
  - Q11: the testers and newcomers gaps are concerns only. The goals capture picks them up.
  - Q11: sponsors and management dropped. Q12: the numbers have no gap.
  - Q10 label: the Reader node reads "Reader, e.g. product owners, requirements engineers, development teams". A comma, because the diagram drops a trailing parenthesis.
  - Q13: this session is recorded as SRC-002.
  - Q14: commit only after the report, in two separate commits.
- Created: STK-001 to STK-023, [[CON-001-proof-of-concept-not-production-ready]], [[ISS-001-who-holds-the-keys-in-parallel-work]], SRC-001, SRC-002. Updated: `_system/index.md`.
- Issues: ISS-001 (open). Gernot Starke asked for it as a reminder.
- Parked: rename "facilitator" to "Keyholder" in the dashboard (`README.md`, `help.md`, the `dashboard.yaml` header comment, `app.py`, `tests/test_presence.py`). It needs a PR. The README also says the role "passes once", but the code passes it every time the holder leaves.
- Parked: the stakeholder template's `nature` has no value for systems such as AI agents (noted on STK-006). That is a schema change and needs a PR.

## [2026-11-10] capture | Vision of the Systems42 dashboard
- Source: `raw/02-vision.md`, personal communication of the Systems42 team, now [[SRC-003-vision-of-the-systems42-dashboard]] in `raw/ingested/`.
- Grill gate: the wiki had no goal, so nothing clashed. Gernot Starke answered Q1 to Q6 one at a time, so no Issue was needed.
- Decisions:
  - Q1: a Moore sentence on top of the unchanged paragraph. The category is "read-only view of the Systems42 wiki", naming requirements and architecture equally, as the session systems42-dashboard-c2 proposed. No "Unlike" clause.
  - Q2: the beneficiaries are the Reader group and the Keyholder, summarised in the text.
  - Q3: the title is "Trusted answers about requirements and architecture".
  - Q4: the vision was chosen on 2026-11-10 from three alternatives (all three in the git history of `raw/02-vision.md`). No decision record, because rewording a vision is cheap.
  - Q5 and Q6: a new objective, "Show what Systems42 can do", under the vision. It has no metric yet, and no open point is wanted.
- Created: [[GOAL-001-trusted-answers]], [[GOAL-002-show-what-systems42-can-do]], SRC-003. Updated: `_system/index.md`.

## [2026-11-10] capture | Goals of the Systems42 dashboard
- Source: `raw/goals2.md`, written by the session systems42-dashboard-c2 with Gernot Starke, now [[SRC-004-goals-of-the-systems42-dashboard]] in `raw/ingested/`.
- Grill gate: checked against GOAL-001, GOAL-002, CON-001 and the stakeholders. Gernot Starke answered Q1 to Q6 one at a time, so no Issue was needed.
- Decisions:
  - Q1: O1 to O5 become GOAL-003 to GOAL-007 under the vision. Targets are proposals, and no baseline has been measured.
  - Q2: O3's metric is now the share of `drivers:` links shown on both linked pages, target 100 %, checkable by a test. It replaces the page count, which presupposed one chain view.
  - Q3 and Q5: the old goals G01 to G36 and their gap lines are removed completely. No G numbers in the wiki and no later capture from them. `raw/03-goals.md` stays deleted (it is in git history).
  - Q4: G32 becomes [[CON-002-dashboard-never-writes-to-the-wiki]]. The dashboard writes only `_system/dashboard.yaml` (checked in `app.py`).
  - Q6: workshops are covered by CON-001, GOAL-002 and GOAL-003. No change to the vision and no extra goal.
- Created: GOAL-003 to GOAL-007, CON-002, SRC-004. Updated: `_system/index.md`, and the `related:` lists of STK-003, STK-006, STK-023 and GOAL-001 (links to CON-002).

## [2026-11-10] decision | DR-001 English, brief and plain
- Decided by Gernot Starke in a working session. Recorded as accepted on branch `decisions`, for review by PR.
- Created: [[DR-001-english-brief-plain-writing]]. Updated: `_system/index.md`.
- No source record: the decision came as a direct instruction, so the page shows as unsourced.

## [2026-11-11] capture | Search the wiki
- Source: `raw/fr-01-search-the-wiki.md`, extracted from the dashboard code on 2026-11-10, now [[SRC-005-search-the-wiki]] in `raw/ingested/`. The grilling answers are [[SRC-006-grilling-session-on-search]].
- Grill gate: checked against GOAL-003, CON-001, CON-002, DR-001 and the search code. Gernot Starke answered Q1 to Q10 one at a time, so no Issue was needed.
- Decisions:
  - Q1: the "wow" is that a reader finds the page without knowing the wiki's word (GOAL-003). Typo tolerance comes with it as a baseline. An answer instead of a list is a later extra.
  - Q2: related words come only from the wiki (aliases, glossary, links). An embedding model and AI answers are Won't, because they are not affordable for now. "Must be good enough for now."
  - Q3: typo rule. Up to 3 letters and IDs exact or prefix, 4 to 7 letters one edit, 8 or more two edits, English word forms count as one word, exact hits always rank first.
  - Q4: tags and the readable fields are searched. Link fields, dates and display fields are not. A field hit ranks between title and body.
  - Q5: no filter syntax in the search box. Gernot Starke proposed filters on the full results page instead (Could).
  - Q6: every non-exact hit shows its reason, in the popup and on `/search`. Only `/search` shows the highlighted passage.
  - Q7: a "Related pages" group holds the one-step neighbours of title or alias hits, at most 5, on `/search` only.
  - Q8: an automated test on a fixed test wiki with example queries, plus the GOAL-003 workshop check.
  - Q9: filler words are dropped. Pages with all words come first, pages with most words follow with a note.
  - Q10: one epic with eight features, one page each, linked to the epic by `parent:` (Gernot Starke's wish). Four Must, three Should, one Could.
- Created: [[FR-001-search-the-wiki]] (epic), FR-002 to FR-009 (features), SRC-005, SRC-006. Updated: `_system/index.md`.
- Note: FR-003 depends on the glossary, which is still empty. Its value grows once `raw/fr-10-domain-terms-and-their-network.md` is captured.

## [2026-11-11] capture | Show the method
- Source: `raw/fr-13-show-the-method.md`, proposed by Claude for GOAL-002, now [[SRC-007-show-the-method]] in `raw/ingested/`. The grilling answers are [[SRC-008-grilling-session-on-showing-the-method]].
- Grill gate: checked against GOAL-002, the source pages and the `/help` work of another session. Gernot Starke answered Q1 to Q4 one at a time.
- Decisions:
  - Q1: one epic, [[FR-010-show-the-method]], with the feature [[FR-011-explain-the-three-loops]]. The guided path from fr-14 becomes a second feature when captured. What already works gets no feature.
  - Q2: FR-011 states the principles of capture and inspect only. Gernot Starke and the Systems42 team take over clarify, so it became [[ISS-002-define-the-clarify-loop]] (also a Todoist task in his systems42 project).
  - Q3: the explanation fits on one screen and is reachable from every page. 4 of 5 test readers new to Systems42 name the three loops with their input and output after 2 minutes.
  - Q4: epic and feature are Should. A demo does not fail without the explanation.
- Rule from Gernot Starke: requirements state the need, never how the dashboard looks today, because nobody will remember "today" later. The "Today" mentions in FR-001 to FR-004, FR-006, FR-007 and FR-009 were rewritten as needs.
- Created: FR-010, FR-011, ISS-002, SRC-007, SRC-008. Updated: FR-001 to FR-004, FR-006, FR-007, FR-009, `_system/index.md`.
- Open: ISS-002, decided by Gernot Starke and the Systems42 team.

## [2026-11-11] capture | Guided path through the wiki
- Source: `raw/fr-14-guided-path.md`, proposed by Claude at Gernot Starke's request, now [[SRC-009-guided-path-through-the-wiki]] in `raw/ingested/`. The answers are in [[SRC-008-grilling-session-on-showing-the-method]].
- Grill gate: checked against FR-010, FR-011, GOAL-002, GOAL-003 and the Keyholder. Gernot Starke answered Q1 to Q4 one at a time, so no Issue was needed.
- Decisions:
  - Q1: one path for newcomers and presenters.
  - Q2: fixed order set by the method, content from the wiki, empty steps and sections hidden in Configure left out.
  - Q3: each step has one or two fixed sentences on what the reader sees and why, next and back, the position, and a way back after looking around.
  - Q4: 4 of 5 test readers walk the path in 10 minutes and answer three orientation questions. Should, under FR-010. A Must would need its own epic under GOAL-003.
- Created: [[FR-012-guided-path-through-the-wiki]], SRC-009. Updated: FR-010 (children), SRC-008, `_system/index.md`.

## [2026-11-11] capture | Header and footer on every page
- Source: `raw/header-footer.md`, written on 2026-11-11 from a conversation about the page frame, now [[SRC-010-header-and-footer-on-every-page]] in `raw/ingested/`. The grilling answers are [[SRC-011-grilling-session-on-header-and-footer]].
- Grill gate: checked against the goals, CON-002, FR-001, the inbox sources and `base.html`. Gernot Starke answered Q1 to Q5 one at a time, so no Issue was needed.
- Decisions:
  - Q1: one feature with three stories, linked by `parent:`. The phrase "the header links to wiki content only" is dropped, because the header also holds search, the menu and the nickname. Requirements in this project may name a technology, and the capture workflow now allows such exceptions (`CHANGELOG.md`).
  - Q2: feature and header story serve GOAL-003, the footer story GOAL-006 and GOAL-002, the liveness story GOAL-002.
  - Q3: Commons has no header entry, by choice. It is reached from the home page.
  - Q4: on a lost connection the dot stops and turns grey, and "offline" replaces the client count. The banner and the grey page stay.
  - Q5: feature and header story are Must, footer and liveness stories are Should.
- Created: [[FR-013-header-and-footer-on-every-page]] (feature), FR-014 to FR-016 (stories), SRC-010, SRC-011. Updated: `_system/index.md`.
- Inbox sources corrected on Gernot Starke's instruction: `raw/fr-02-browse-by-area-and-section.md` names the new header entries, and `raw/fr-07-find-a-decision-and-its-reasons.md` no longer lists the missing Decisions entry as a gap.
- Note: the "Open" section of the archived source still lists the Commons entry and the grey dot as open. Q3 and Q4 settled both. `raw/fr-12-shared-session-in-a-workshop.md` also claims the client count, and should link to FR-015 when captured.
- The dashboard code was changed the same day to match (header nav, footer, help section on the LLM wiki). It goes to review as a PR, with the relaxed rule in the capture workflow.

## [2026-11-11] promote | GOAL-001, GOAL-002 and GOAL-003 accepted
- Gernot Starke accepted the vision [[GOAL-001-trusted-answers]] and the objectives [[GOAL-002-show-what-systems42-can-do]] and [[GOAL-003-answers-without-asking-a-colleague]]. He also agreed GOAL-003's target, 8 of 10.
- GOAL-003: "Proposed target" became "Target", and the note now says only that no baseline has been measured yet.
- GOAL-002 is accepted without a metric, as decided in its capture.
- Updated: the three goal pages, `_system/index.md`. Delivered by PR, as the commit policy asks for promotions.

## [2026-11-11] decision | DR-002 tailoring and view
- Gernot Starke stated that the real Systems42 metamodel is configurable per project and asked how to handle the Configure dialog, which sits between Systems42 and the dashboard. He accepted the split by owner.
- Created: [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]], SRC-012. Updated: [[CON-002-dashboard-never-writes-to-the-wiki]] (impact), `_system/index.md`.
- Follow-ups named in DR-002: where the tailoring sits in the schema, where the view is kept, renaming the dialog, tightening CON-002. Requirements go into fr-02 (tailoring) and fr-12 (view) at their capture.
- Delivered by PR, because the record is accepted.

## [2026-11-12] capture | Browse by area and section
- Source: `raw/fr-02-browse-by-area-and-section.md`, rewritten as needs on 2026-11-11 at Gernot Starke's request (no "Today" section), now [[SRC-013-browse-by-area-and-section]] in `raw/ingested/`. The answers are [[SRC-014-grilling-session-on-browsing]].
- Grill gate: checked against GOAL-003 to GOAL-007, FR-001, FR-012, FR-013 and DR-002. Gernot Starke answered Q1 to Q6 one at a time, so no Issue was needed.
- Decisions:
  - Q1: one epic with features. "Same name everywhere" is a rule on the epic. The need on empty sections was removed from the source.
  - Q2: goals per feature. A status filter ("agreed only") was added for GOAL-006.
  - Q3: the first page shows the vision sentence, the guided path link, the areas, and a center tile with the last 3 to 4 changes (linking to a changes page of the wiki) and the open questions. No page count in the center tile.
  - Q4: a section shows only its page count and a maturity bar.
  - Q5: the path follows where a page belongs. List addresses carry sort and filter. "Share" was renamed, because the dashboard sends nothing.
  - Q6: sorting is Must and works on several columns, with useful sort orders per type from the metamodel. The three areas always exist, only sections inside them can be left out. Four Must, two Should.
- Created: [[FR-017-browse-by-area-and-section]] (epic), FR-018 to FR-023 (features), SRC-013, SRC-014. Updated: `_system/index.md`.
- Parked: sort orders per type in the metamodel (schema change, PR) on FR-021. The tailoring format, a follow-up of DR-002, on FR-023. DR-002 came in through PR #10, merged before this commit.

## [2026-11-12] capture | See what is still open
- Source: `raw/fr-09-open-issues-overall-and-per-section.md`, rewritten as needs on 2026-11-12 at Gernot Starke's request (no "Today" section, categories added, "by when" dropped), now [[SRC-015-see-what-is-still-open]] in `raw/ingested/`. The answers are [[SRC-016-grilling-session-on-open-issues]].
- Grill gate: checked against GOAL-006, FR-001, FR-018, FR-019, FR-021, FR-022 and CON-002. Sort, search and read only were already covered and are linked, not repeated. Gernot Starke answered Q1 to Q4 one at a time, so no Issue was needed.
- Decisions:
  - Q1: one epic with four features. FR-019 amended: each section shows its open issue count, which opens the issue list for that section.
  - Q2: one category per issue from a fixed list (requirements, architecture, shared content, content, orga, systems42). Category is not kind, so a risk stays a kind.
  - Q3: an `owner:` field, "nobody yet" when empty and filterable. No due dates.
  - Q4: three Must, two Should. The issue list's own filters go into its address. FR-022 stays limited to the status filter.
- Created: [[FR-024-see-what-is-still-open]] (epic), FR-025 to FR-028 (features), SRC-015, SRC-016. Updated: [[FR-019-section-at-a-glance]], `_system/index.md`.
- Parked: `category:` and `owner:` on the issue template and in the metamodel (schema change, one PR with a CHANGELOG entry), noted on FR-026 and FR-028.

## [2026-11-12] update | Issue category and owner
- PR #11 added `category:` and `owner:` to the issue template and the metamodel (FR-026, FR-028). Gernot Starke asked for it to be opened and merged.
- Updated: open points of [[FR-026-issues-carry-a-category]] and [[FR-028-who-answers-an-issue]] closed. [[ISS-001-who-holds-the-keys-in-parallel-work]] category requirements, owner nobody yet. [[ISS-002-define-the-clarify-loop]] category systems42, owner Gernot Starke and team, as he said they take over the clarify loop.

## [2026-11-12] capture | Usable on phone and tablet
- Source: `raw/qr-01-usable-on-phone-and-tablet.md`, raised by Gernot Starke and drafted by Claude, now [[SRC-017-usable-on-phone-and-tablet]] in `raw/ingested/`. The answers are [[SRC-018-grilling-session-on-phone-and-tablet]]. The first quality requirement of the wiki.
- Grill gate: checked against the QR template, the Q42 anchor, GOAL-003 and GOAL-007. No overlap or conflict. Gernot Starke answered Q1 to Q5 one at a time, so no Issue was needed.
- Decisions:
  - Q1: quality requirements are classified by Q42 dimensions (`dimensions:`, one or more), not by one ISO 25010 attribute. This one is usable and flexible.
  - Q2: recorded as [[DR-003-quality-requirements-are-classified-by-q42-dimensions]]. Main reason: Q42 allows several dimensions, ISO 25010 forces a strict hierarchy and a single attribute.
  - Q3: narrowest width 320 CSS pixels, after WCAG 1.4.10 Reflow.
  - Q4: diagrams are best effort on phone and tablet. Every diagram node is also reachable as a text link.
  - Q5: Should, testable.
- Created: [[QR-001-usable-on-phone-and-tablet]], SRC-017, SRC-018. Updated: `_system/index.md`.
- Parked: the schema change (template, metamodel, Q42 anchor, AGENTS.md, dashboard) and DR-003 go by PR. Until it is merged, the `dimensions:` field is not in the template and the DR-003 links do not resolve.

## [2026-11-12] decision | DR-003 Q42 dimensions
- Gernot Starke chose Q42 dimensions over one ISO 25010 attribute while capturing [[QR-001-usable-on-phone-and-tablet]]: Q42 allows several dimensions on one requirement, ISO 25010 forces a strict hierarchy and a single attribute.
- Created: [[DR-003-quality-requirements-are-classified-by-q42-dimensions]]. Updated: QR template and metamodel (`attribute:` → `dimensions:`), Q42 and req42 anchors, `AGENTS.md`, `docs/req42/README.md`, the dashboard's quality list and its test, `CHANGELOG.md`, `_system/index.md`.
- Delivered by PR, because the record is accepted and the schema changes.

## [2026-11-12] update | Area name Commons, section names
- Gernot Starke chose "Commons" for the third area, the dashboard's name, over "shared content". C5 is "Domain Terms" everywhere, because Systems42 will likely join data-model terms and glossary into a metaclass "domain term". C6 stays "Issues".
- Updated: [[FR-017-browse-by-area-and-section]], [[FR-018-orientation-on-the-first-page]], [[FR-023-areas-and-sections-follow-the-tailoring]], [[FR-026-issues-carry-a-category]]. The category value `shared-content` becomes `commons`, and DR-002's wording follows, in PR #13 with the dashboard quick wins.

## [2026-11-13] capture | The dashboard as a product
- Source: `raw/fr-15-dashboard-as-a-product.md`, raised by Gernot Starke and drafted by Claude, now [[SRC-019-the-dashboard-as-a-product]] in `raw/ingested/`. The answers are [[SRC-020-grilling-session-on-the-dashboard-as-a-product]].
- Grill gate: checked against the goals, CON-001, CON-002 and the stakeholders. No conflict. Gernot Starke answered questions 1 to 7 one at a time, so no Issue was needed.
- Decisions:
  - Q1: serves GOAL-002 and a new goal, a reusable, consistent and efficient way into any Systems42 wiki. GOAL-006 is more a goal of the Systems42 approach than of the dashboard.
  - Q2: one epic with four features, plus a constraint (Docker) and a quality requirement (runs alike).
  - Q3: three keys in `_system/wiki.yaml`: `dashboard_version:`, `brand:`, `intro:`. Implemented in PR #19.
  - Q4: Windows is ignored for now.
  - Q5: `./dashboard.sh local` stays as an unsupported developer fallback.
  - Q6: no offline installation. Participants start once with network before a workshop.
  - Q7: releases are container images per git tag, pinned by `dashboard_version:`. Recorded short as DR-004.
- Created: [[GOAL-008-one-way-into-every-systems42-wiki]], [[FR-029-the-dashboard-as-a-product]] (epic), FR-030 to FR-033 (features), [[CON-003-docker-is-the-supported-way-to-run-it]], [[QR-002-runs-alike-on-linux-and-macos]], SRC-019, SRC-020. Updated: `_system/index.md`.
- Proposals, not yet agreed: Should for the epic and all four features, the metric and target of GOAL-008.
- Parked: DR-004 goes by PR. Until it is merged, its links do not resolve.

## [2026-11-13] decision | DR-004 releases as container images
- Gernot Starke chose container images per release, pinned by `dashboard_version:`, over submodule, copy and package, in question 7 of [[SRC-020-grilling-session-on-the-dashboard-as-a-product]]. Kept short at his request.
- Created: [[DR-004-releases-are-container-images-pinned-per-wiki]]. Updated: `_system/index.md`. Delivered by PR, because the record is accepted.
## [2026-11-13] update | Priorities of the dashboard as a product
- Gernot Starke agreed Should for [[FR-029-the-dashboard-as-a-product]], FR-030, FR-032 and FR-033, and raised [[FR-031-branding-is-configuration]] to Must.
- Updated: FR-029 open points closed, FR-031 priority, `_system/index.md`.

## [2026-11-13] update | GOAL-008 without metric
- Gernot Starke set the proposed counting metric aside. [[GOAL-008-one-way-into-every-systems42-wiki]] has no metric and no target for now.

## [2026-11-13] capture | Read a page with its links
- Source: `raw/fr-03-read-a-page-with-its-links.md`, extracted from the code on 2026-11-10, now [[SRC-021-read-a-page-with-its-links]] in `raw/ingested/`. Its "Today" part was rewritten as needs. The answers are [[SRC-022-grilling-session-on-reading-a-page]].
- Trigger: Gernot Starke asked why "follows MADR" shows as a box and that MADR is not explained.
- Grill gate: anchors are already a metamodel construct (`meta-metamodel.md` section 5, files in `_system/anchors/`), but the dashboard neither links nor shows them. Gernot Starke answered both questions, so no Issue was needed.
- Decisions:
  - Q1: dashboard requirements and Systems42 (metamodel) requirements are separated by one test: would it still hold without the dashboard? Recorded as [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]].
  - Q2: two features. [[FR-034-read-a-page-with-its-links]] under FR-017, Must. [[FR-035-method-terms-lead-to-their-definition]] under FR-010, Should.
- Created: FR-034, FR-035, CON-004, SRC-021, SRC-022. Updated: FR-010 and FR-017 child lists, `_system/index.md`.

## [2026-11-13] capture | Goal coverage matrix
- Source: `raw/fr-16-goal-coverage-matrix.md`, raised by Gernot Starke and drafted by Claude, now [[SRC-023-goal-coverage-matrix]] in `raw/ingested/`. The answers are [[SRC-024-grilling-session-on-the-goal-coverage-matrix]].
- Grill gate: Systems42 already defines the matrix as the projection `proj-goal-coverage`, so by [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] its content is Systems42's part and the draft's question on columns falls away. Enablers follow the metamodel (platform or display lane), and a backbone epic with `goal: []` breaks `rule-fr-traces-to-goal`. Gernot Starke answered questions 1 to 3, so no Issue was needed.
- Decisions: Q1 serves GOAL-004. Q2 a feature under FR-017, Should. Q3 no counts per row, only on Vision & Goals.
- Created: [[FR-036-goal-coverage-matrix]], SRC-023, SRC-024. Updated: FR-017 child list, `_system/index.md`.
- Noticed for Systems42, not filed: `proj-goal-coverage` cites DR-018 and DR-011, which exist only in isaqb-atrium.

## [2026-11-13] issue | Goal coverage projection cites foreign decisions
- Gernot Starke asked to file what the fr-16 capture noticed for Systems42. Filed here with category systems42, as [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] prescribes.
- Created: [[ISS-003-goal-coverage-projection-cites-decisions-from-another-wiki]]. Updated: `_system/index.md`.

## [2026-11-14] update | Gap rule of the goal coverage matrix
- Gernot Starke decided: a goal that at least one feature serves is not a gap. Only a goal no requirement serves is one.
- Updated: [[FR-036-goal-coverage-matrix]]. [[ISS-003-goal-coverage-projection-cites-decisions-from-another-wiki]] now also covers the gap definition and links meta issue #37, opened at his request. The dashboard change goes into PR #22.

## [2026-11-14] capture | Domain terms and their two views
- Source: `raw/fr-10-domain-terms-and-their-network.md`, extracted from the code on 2026-11-10 and rewritten on 2026-11-14 for the planned merge of glossary terms and data models (systems42-org/meta#36), now [[SRC-025-domain-terms-and-their-two-views]] in `raw/ingested/`. The answers are [[SRC-026-grilling-session-on-domain-terms]].
- Grill gate: by [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]] the type is Systems42's, so the requirement covers showing it only. Gernot Starke answered questions 1 to 4, so no Issue was needed.
- Decisions:
  - Q1: serves GOAL-003.
  - Q2: one epic, Must, with four features: the term list (Must), the term page (Must), two views (Should), definition in place (Should).
  - Q3: a bridge now. Glossary terms show as terms without kind, data-model entities as `entity`, until Systems42 has the type.
  - Q4: the data model (entity diagram) stays in Supporting Models (R4). C5 holds the list, the pages and the terminology network. Recorded on meta#36 too.
- Created: [[FR-037-domain-terms]] (epic), FR-038 to FR-041 (features), SRC-025, SRC-026. Updated: `_system/index.md`.
- Related: an implementation plan for the Systems42 side is posted on meta#36.

## [2026-11-17] capture | Dashboard distribution and its contract with the metamodel
- Source: `raw/dashboard-distribution-and-metamodel-contract.md`, notes drafted by Claude and edited by Gernot Starke, now [[SRC-027-dashboard-distribution-and-metamodel-contract]] in `raw/ingested/`. The answers are [[SRC-028-grilling-session-on-dashboard-distribution]].
- Grill gate: own repository, image and no copied code were already in DR-004 and FR-029. One line of the source is wrong: the three metamodels (meta, this repository, isaqb-atrium) declare the same sections. They differ in the title of C6 and the scope of A3 to A5. The source is left as it is, and FR-044 states the checked fact. Gernot Starke answered questions 1 to 8.
- Decisions:
  - Q1: the repository question is a decision record, DR-005, with two alternatives.
  - Q2: the launcher is one feature, Should. Wikis hold no dashboard code except the launcher, currently `dashboard.sh`, which a Makefile may call. `update` is written by the launcher, so CON-002 holds.
  - Q3: the version check names no file. `metamodel-version.md` is proposed to Systems42, because a file name should say what the file holds.
  - Q4: on a mismatch a notice on every page, never a refusal. A missing version counts as a mismatch.
  - Q5: one constraint (CON-006), one feature (FR-044, Must), one issue for Systems42.
  - Q6: the dashboard is tested against meta's metamodel.
  - Q7: the atrium brand moves into isaqb-atrium (FR-032 changed). A prompt template for a brand, Could.
  - Q8: CON-005 as worded. Docker only for now, other engines stay an open issue.
- Created: [[DR-005-the-dashboard-lives-in-its-own-repository]] (review), [[CON-005-the-dashboard-works-on-systems42-derivatives-only]], [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]], [[FR-042-start-a-pinned-release-with-one-command]], [[FR-043-the-dashboard-checks-the-metamodel-version]], [[FR-044-sections-come-from-the-repositorys-metamodel]], [[FR-045-a-prompt-template-for-a-brand]], SRC-027, SRC-028.
- Issues raised: [[ISS-004-where-the-metamodel-declares-its-version]] (meta #39), [[ISS-005-the-method-lint-imports-dashboard-code]] (meta #40), [[ISS-006-other-container-engines-than-docker]] (#24). All three were asked first and opened at Gernot Starke's request.
- Updated: FR-029 (launcher wording, children), FR-031, FR-032, CON-003, FR-017 child list, FR-023 and CON-004 (links), `_system/index.md`.
- Parked: sync this repository's metamodel from meta. Move meta's dashboard requirements and decisions here (DR-005). Type prefixes and labels in `app.py` fall under CON-006 and have no requirement yet. The priority of FR-043 follows its epic and was not asked.

## [2026-11-18] change | CON-001 states what the missing login means for the settings
- Source: issue #34, point 5, raised by Gernot Starke. No file in `raw/`, no grill: one accepted limit, stated where the issue asks for it.
- Updated: CON-001 (one impact line). Points 1 to 4 and 6 of the issue are code, pull request #37.

## [2026-11-18] capture | The published image (SRC-029)
- Source: a request by Gernot Starke in chat, no file in `raw/`. Grill gate: the wiki was checked first (DR-004, FR-030, FR-042 exist, none states what the published image must offer), then four questions in one round, all answered. No Issues.
- Human decisions (2026-11-18): extend FR-030 instead of a new page. Priority Must. The image is pulled without a login. It runs on amd64 and arm64.
- Created: SRC-029. Updated: FR-030 (three lines, success metric, scope, priority Should to Must), `_system/index.md`.
- Checked against today's state: release 0.11.2 holds an amd64 and an arm64 image and is pulled without a login. Older releases were not checked again.

## [2026-11-19] capture | Default brand and instance brands
- Source: `raw/default-brand-and-instance-brands.md`, a note drafted by Claude at Gernot Starke's request, now [[SRC-030-default-brand-and-instance-brands]] in `raw/ingested/`. The answers are [[SRC-031-grilling-session-on-the-default-brand]].
- Grill gate: FR-031 and FR-032 already hold the rule (a wiki names its own brand folder or gets the default). Three points were missing and one question was open. Gernot Starke answered questions 1 to 4 in one round. No Issues.
- Decisions:
  - Q1: a project created from meta shows the default brand.
  - Q2: the look of one wiki never goes into the shipped brand. The maintainers may still change the default for all wikis.
  - Q3: the line on brand files as trusted content is replaced by the isolated intro.
  - Q4: FR-032 names the meta brand.
- Created: SRC-030, SRC-031. Updated: FR-031, FR-032, `_system/index.md`.
- Background: release 0.11.3 shipped meta's intro as the default (pull request #43). Pull request #46 restored the Peaks intro, meta pull request #46 gave meta its own brand folder.

## [2026-11-19] capture | Shared session in a workshop
- Source: `raw/fr-12-shared-session-in-a-workshop.md`, extracted from the dashboard code on 2026-11-10, now [[SRC-032-shared-session-in-a-workshop]] in `raw/ingested/`. The answers are [[SRC-033-grilling-session-on-the-shared-session]].
- Grill gate: the source's "Today" list was checked against the code of release 0.11.4 and still holds. The client count is already FR-015. DR-002 had left the view's place, lifetime and dialog name open. Gernot Starke answered questions 1 to 6 in two rounds. No new Issues.
- Decisions:
  - Q1: one feature under FR-010, no epic of its own.
  - Q2: GOAL-002 covers workshops. The vision stays as it is.
  - Q3: Should.
  - Q4: ISS-001 resolved with option 1. The code stays: the first tab holds the rights, "Yoda" names only the first holder.
  - Q5: the view lasts until the dashboard stops and is written to no file.
  - Q6: the dialog is called View.
- Created: [[FR-046-shared-session-in-a-workshop]], SRC-032, SRC-033.
- Updated: ISS-001 (resolved), STK-023, CON-002 (one impact line), FR-010 (child list), FR-015 and FR-023 (links), `_system/index.md`.
- Parked: Q5 and Q6 are not built. Configure still saves to `_system/dashboard.yaml`, noted in FR-046. DR-002 is accepted and was not edited, so it does not link FR-046. The success metric of FR-046 is a proposal by Claude.

## [2026-11-19] capture | Dashboard requirements that still lived in meta
- Source: `raw/dashboard-requirements-moved-from-meta.md`, now [[SRC-034-dashboard-requirements-moved-from-meta]] in `raw/ingested/`. The answers are [[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]. Origin: meta issue #49, sub-issue of meta #38.
- Grill gate: compared twelve meta pages with this wiki after pulling it (FR-046 had just been captured and covers the QR join, the connected tabs, the Keyholder, the View and Disconnect all). Peter Gerstbach answered eight questions.
- Decisions:
  - Q1: new pages use the DR-038 form (`notation: agile`, `level:`), so #33 has less to migrate.
  - Q2: meta FR-013 is a Should story under FR-034, only the text of a page; an explicit wish of Peter Hruschka (minutes of 2026-10-12, "Hoch").
  - Q3: meta FR-012 is a feature under FR-017 with the detail diagram and building blocks; the wikis the dashboard shows have them.
  - Q4: meta FR-034 is a Could story, not built, depends on meta's Implement loop.
  - Q5: meta QR-004 is one quality requirement, QR-003.
  - Q6: meta DR-022 (self-shutdown) is a requirement, not a decision record: FR-050 under FR-046, can be switched off when the dashboard starts.
  - Q7: meta DR-023 (term network): the requirements go to FR-040, FR-051 and FR-052; only the pattern becomes a small decision record, DR-006.
  - Q8: the key ⌘K goes into FR-001; the menu is FR-053 (Could); no help page; the five nav entries of meta DR-032 are not taken, FR-014 stands.
- Created: [[FR-047-see-the-requirements-as-a-story-map]], [[FR-048-show-the-delivery-status-of-a-requirement]], [[FR-049-read-the-page-text-without-links-and-metadata]], [[FR-050-stop-the-dashboard-when-nobody-is-watching]], [[FR-051-reveal-related-page-types-layer-by-layer]], [[FR-052-see-a-terms-neighbourhood-on-its-page]], [[FR-053-reach-the-session-controls-and-the-theme-from-one-menu]], [[QR-003-works-in-every-current-browser]], [[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]], SRC-034, SRC-035.
- Updated: FR-001 (⌘K), FR-013, FR-017, FR-034, FR-040 (edge rule), FR-046 (child lists and a link to FR-050), `_system/index.md`.
- Checked against the code of release 0.11.4: the context diagram, the data model, the goals diagram and the requirement breakdown are Mermaid, the term network and the metamodel page are cytoscape (DR-006); the menu of FR-053 exists with all its entries. Closing round: goals of the new pages confirmed by Peter Gerstbach; FR-040 and FR-046 are Gernot Starke's pages and were changed only in their child lists, a link and one edge rule. meta removes its copies in a pull request after this lands.

## [2026-11-19] inspect | Stakeholders merged, 23 to 7
- Origin: meta issue #38, step 3. Gernot Starke decided group by group.
- Decisions:
  - Readers: STK-002 to 005, 009 and 014 to 019 merge into [[STK-001-readers]]. Their roles become aliases, and four concerns stay.
  - Workshop: STK-007 merges into [[STK-008-workshop-participants-and-facilitators]].
  - Method audience: STK-022 (prospective adopters, an assumption) is dropped. [[STK-013-people-learning-or-presenting-systems42]] stays.
  - Operators: STK-011 merges into [[STK-010-operators]].
  - Maintainers: STK-021 merges into [[STK-012-maintainers]].
  - STK-006 (AI agents) is dropped. STK-020 and STK-023 stay.
- Updated: every link to a retired ID, `_system/index.md`. User stories keep their role as the link label. FR-011 and FR-033 had STK-022 as actor and now name STK-013. The `make new` and `make sync` mentions left with the merged pages, because those targets no longer exist here.
- Not changed: `raw/sources/` and older log entries still name the retired IDs.

## [2026-11-19] inspect | STK-001 and STK-023 promoted
- Gernot Starke promoted [[STK-001-readers]] and [[STK-023-keyholder]] to `accepted`.
- STK-023 gets the alias "Yoda". Its naming paragraph now says both aliases name the role.

## [2026-11-20] inspect | Boundary alignment with systems42-org/meta
- Gernot Starke reviewed the boundary drift between this wiki and `systems42-org/meta` (`CON-004`, `CON-006`) and settled four items:
  1. Q42 `dimensions:` (`DR-003`): `meta` leads on QR classification. Commented on `meta#35`, deprecated local [[DR-003-quality-requirements-are-classified-by-q42-dimensions]] and raised [[ISS-008-q42-dimensions-belong-in-meta]].
  2. Issue `category:` and `owner:` (`FR-026`, `FR-028`): proposed upstream in `meta#53`, raised [[ISS-007-issue-category-and-owner-belong-in-meta]], narrowed [[FR-025-issue-list-with-filters]], [[FR-026-issues-carry-a-category]] and [[FR-028-who-answers-an-issue]] to dashboard display and filtering with graceful fallback when absent.
  3. `sort_orders:` (`FR-021`): moved to dashboard presentation (`CON-006`), removing the metamodel schema requirement from [[FR-021-sort-lists]].
  4. External scope: trimmed [[FR-032-example-brands-to-try]] to the shipped `systems42` default brand, deprecated [[FR-033-runnable-dashboard-in-the-starter-kit]] (moved starter-kit assembly to `meta#54`, kept zero-config start in [[FR-042-start-a-pinned-release-with-one-command]] and [[FR-029-the-dashboard-as-a-product]]), and reframed [[GOAL-006-source-and-status-on-every-statement]] to the dashboard's display and agreed-only filtering role.
- Warned on `systems42-dashboard#33` about the three local metamodel divergences before syncing `_system/metamodel/` from `meta`.
- Created: [[ISS-007-issue-category-and-owner-belong-in-meta]], [[ISS-008-q42-dimensions-belong-in-meta]].
- Updated: DR-003, FR-021, FR-025, FR-026, FR-028, FR-029, FR-032, FR-033, FR-042, GOAL-006, `_system/index.md`.

## [2026-11-20] capture | Running without a container engine: uv and a Go app
- Origin: Gernot Starke, chat of 2026-11-20 ([[SRC-036-grilling-session-on-running-without-a-container-engine]]). Some people run their wiki inside a virtual machine, where no container engine starts.
- Decisions:
  - uv is a second supported way to start the Python dashboard, next to `make dev`.
  - uv gets the release as a wheel from the GitHub release, not from a git tag and not from PyPI.
  - A second implementation in Go becomes an installable app, macOS first. Claude recommended packaging the Python dashboard instead. Gernot Starke chose Go and accepts the extra work.
  - One installed app shows every wiki and tells a differing release. It does not fetch the release a wiki names.
  - Recorded as [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]], which amends DR-004.
- Created: [[FR-054-a-start-without-a-container-engine]], [[FR-055-an-installable-dashboard-app]], [[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]], SRC-036.
- Updated: CON-003 (title and text: Docker and uv), QR-002 (scenario and measure), FR-029 (rule, scope, children), FR-042 (scope), STK-010 (concern), `_system/index.md`.
- Open: whether the Go app shows the pages in the browser or in its own window. Asked, not yet answered, noted on FR-055. The priorities of FR-054 and FR-055 (Should) are Claude's proposal.
- Code: `./dashboard.sh uv` and the wheel are in the same pull request. The plan for the Go app is issue #80.

## [2026-11-21] inspect | FR-046: who gets the keys when the holder leaves
- Origin: issue #56, the rule question left open by pull request #72.
- Decision (Gernot Starke, 2026-11-21): the earliest tab still connected gets the rights, also when it held them before. A returning holder counts as newly connected. A session always has a Keyholder.
- Updated: [[FR-046-shared-session-in-a-workshop]] (Keyholder rule, history). No code change: the dashboard already works this way, and two new tests in `tests/test_presence.py` hold it.
- Not changed: [[STK-023-keyholder]] is `accepted` and still says "the rights never go back to an earlier holder". It needs the same wording, by promotion.

## [2026-11-21] capture | A public website for the dashboard
- Source: `raw/ingested/public-website-for-the-dashboard.md` ([[SRC-037-a-public-website-for-the-dashboard]]), written on 2026-11-21 from Gernot Starke's requirement and the existing site in `site/`. Grilling: [[SRC-038-grilling-session-on-the-public-website]].
- Decisions (Gernot Starke, 2026-11-21):
  - Goal: GOAL-002. The downloads also serve GOAL-008. No new goal.
  - Audience: people who consider using Systems42 become an alias of STK-013. STK-022 is not brought back.
  - The static export is, for now, only the way this site gets its demo. Publishing any wiki is out of scope.
  - The demo shows the dashboard's own wiki. The maintainers switch it only when the other wiki's owner agrees.
  - No measure of its own: QR-001 applies to the site.
  - Gernot Starke keeps the imprint and the privacy notice correct.
  - Priorities: epic Should, demo and legal information Must, the other features Should.
  - The three gaps of the site are open points on the pages and GitHub issue #86.
- Created: [[FR-056-a-public-website-for-the-dashboard]], [[FR-057-overview-of-the-dashboard-on-the-website]], [[FR-058-a-demo-to-try-without-installing]], [[FR-059-downloads-on-the-website]], [[FR-060-documentation-on-the-website]], [[FR-061-legal-and-project-information-on-the-website]], [[FR-062-the-website-is-built-and-published-from-the-repository]], SRC-037, SRC-038.
- Updated: STK-013 (alias, snapshot, goal), STK-012 (goal), CON-001 (the demo), QR-001 (applies to the site), `_system/index.md`.
- Issues: none. Every question was answered.
- IDs: FR-054, FR-055, SRC-036 and DR-007 are taken by pull request #81, which is not merged, so this capture starts at FR-056 and SRC-037.
- Not changed: GOAL-002 and GOAL-008 are served through the `goal:` field of the new pages.

## [2026-11-21] inspect | Issue schema taken over from systems42-org/meta
- Origin: [meta pull request 55](https://github.com/systems42-org/meta/pull/55), which adopts `category:` and `owner:` for issues.
- Schema: `type-issue.md`, `rel-owner.md` and `_templates/issue.md` now match meta. The category `systems42` is `method`, both fields are optional, `owner:` takes a stakeholder link only.
- Updated: six issues from `category: systems42` to `method`. Seven issues from the owner "Gernot Starke" or "Gernot Starke and team" to [[STK-012-maintainers]] (Claude's choice of stakeholder, to be checked).
- Resolved: [[ISS-007-issue-category-and-owner-belong-in-meta]].
- Updated: [[FR-026-issues-carry-a-category]], [[FR-028-who-answers-an-issue]], [[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]].
- No code change: the dashboard reads the category values from the metamodel. It still shows an owner written as a plain name.

## [2026-11-21] inspect | FR-047: building blocks in the detail diagram
- Origin: issue #66.
- Code: the diagram on a requirement's page draws its children and the building blocks whose `drivers:` name it. Test: `tests/test_fr_detail_diagram.py`.
- Updated: [[FR-047-see-the-requirements-as-a-story-map]] (open points, history).
- Removed: the field `building-blocks: []` from FR-047 to FR-053. The template does not define it, and nothing read it.
- Claude's choices, to be checked: a static Mermaid diagram instead of an interactive one, and the block's `drivers:` as the only source of the link.
- Not built: [[FR-048-show-the-delivery-status-of-a-requirement]]. It waits for the delivery fields of the Systems42 metamodel.

## [2026-11-22] sync | Systems42 method from meta (#103)
- Migrated with meta's `migrate-requirements` (62 FRs to `notation:` + `level:`, DR-038) and `migrate-domain-terms` (empty `glossary/`, `data-models/`, `use-cases/` gone, DR-039); `wiki/concepts/` renamed to `wiki/crosscutting-concepts/` (DR-040); then `make sync` from meta.
- Kept, not overwritten: README, CHANGELOG, Makefile, `dashboard.sh`, `.gitignore`, `.obsidian/`, `CLAUDE.md`, `_system/README.md`; the writing-style and language rules in `AGENTS.md`; Q42 (`_system/anchors/q42.md`, `dimensions:` on quality requirements) and C6 titled "Issues" until [meta#35](https://github.com/systems42-org/meta/issues/35).
- Dropped in the sync: `_system/metamodel/altitude.md` (a proposed granularity scale). Meta leads the metamodel, so it does not come back.
- App tests that pinned the old metamodel follow the new one; the app's copies of the method tests are removed, they live in `_system/scripts/tests/`.

## [2026-11-22] capture | Solution strategy of the dashboard
- Sources: [[SRC-039-solution-strategy-of-the-dashboard]], [[SRC-040-grilling-session-on-the-solution-strategy]].
- Created: [[SOL-001-systems42-dashboard]] (state current), [[QR-004-the-wikis-content-stays-on-the-machine]], [[CON-007-the-python-dashboard-is-the-reference-for-the-app]], [[CC-001-tests-of-the-python-dashboard-are-plain-scripts]].
- Updated: [[CON-003-docker-is-the-supported-way-to-run-it]] (new title, names the constraint only), and links on STK-020, CON-001, FR-055, DR-007.
- Decided by Gernot Starke: Docker is the primary form, uv is for machines without a container engine, the app runs on macOS. A constraint page names the constraint and says nothing about plans or status. "Nothing goes to a third party" is a quality requirement with priority Must, because the strategy rests on requirements. Projection and server rendering get no decision record of their own. The Python dashboard is the reference for the app. Tests as plain scripts are a crosscutting concept for the Python dashboard only.
- Already on record, linked only: release per wiki (DR-004, DR-007), no access control (CON-001), text next to every diagram (QR-001, DR-006), tailoring by configuration (DR-002).
- Docs: `docs/INSTALL.md` says the programs for Linux and Windows come without support.

## [2026-11-22] capture | Managing development with make
- Sources: [[SRC-041-managing-development-with-make]], [[SRC-042-grilling-session-on-development-with-make]].
- Created: [[FR-063-manage-development-with-make]], a feature under FR-029 for the maintainers.
- Updated: [[FR-029-the-dashboard-as-a-product]] (children).
- Decided by Gernot Starke: one feature that states the rules and names the targets per task area, without restating what each does. It covers four task areas (run, test and clean, website, releases), not every command of the launcher.
- Closing round: Gernot Starke confirmed priority Should. Claude's choices, to be checked: the goal [[GOAL-008-one-way-into-every-systems42-wiki]], and `app-bundle` listed under releases although the source does not name it.

## [2026-11-22] capture | Context and Level 1 building blocks of the dashboard
- Sources: [[SRC-043-context-of-the-systems42-dashboard]] (`raw/ingested/context.md`), [[SRC-044-building-blocks-of-the-systems42-dashboard]] (`raw/ingested/building-blocks.md`), [[SRC-045-grilling-session-on-context-and-building-blocks]].
- Created: [[CTX-001-systems42-dashboard-context]], [[EIF-001-systems42-wiki]], [[BB-001-python-dashboard]], [[BB-002-uv-cli-and-package-wrapper]], [[BB-003-go-dashboard]], [[BB-004-macos-native-app]], [[BB-005-wiki-launcher-and-make-facade]], [[BB-006-public-website-builder]].
- Updated: [[CC-001-tests-of-the-python-dashboard-are-plain-scripts]] (`applies-to` now names [[BB-001-python-dashboard]]), `_system/index.md`.
- Decided by Gernot Starke in grilling: keep all three interacting user roles (Reader, Operator, Keyholder) on the context diagram. Model the macOS native app as `state: current` for the shipped AppKit menu-bar shell wrapping Go. Group `dashboard.sh` with the user-facing `Makefile` targets as one Level 1 block (repo-only development targets are already captured in [[FR-063-manage-development-with-make]]). Include the public website builder (`site/`) at Level 1.
- Issues: none raised. Every question was answered in grilling.

## [2026-11-22] inspect | Solution strategy modularized into focused pages and decision records
- Source: [[SRC-046-grilling-session-on-modularizing-the-solution-strategy]] (item-by-item review of all eight points of the former SOL-001).
- Retired: `SOL-001` (`SOL-001-systems42-dashboard.md`, draft). ID retired and not reused.
- Created strategy pages (`state: current`, `status: draft`): [[SOL-002-three-ways-to-run-the-dashboard]], [[SOL-003-read-only-projections-over-markdown-files]] (combining no-database read-only storage and on-the-fly projections), [[SOL-004-the-metamodel-drives-the-dashboard]], [[SOL-005-local-and-offline-execution]].
- Created decision records (`kind: architecture`, `status: draft`): [[DR-008-public-website-is-built-by-a-custom-python-script-for-github-pages]], [[DR-009-pages-are-rendered-on-the-server-from-html-templates]] (recorded as a normal DR rather than a strategy pillar because upcoming implementations may change UI rendering).
- Kept in existing decision record only: repository separation from Systems42 stays in [[DR-005-the-dashboard-lives-in-its-own-repository]] and [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]], removed from solution strategy.
- Updated: links from BB-001 to BB-006, CON-003, CON-007, CC-001, QR-004 and `_system/index.md`. Older provenance records (SRC-039, SRC-040) and older log entries keep their historical reference to SOL-001.
