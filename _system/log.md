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
