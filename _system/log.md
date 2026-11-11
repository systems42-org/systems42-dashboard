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
