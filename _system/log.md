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
