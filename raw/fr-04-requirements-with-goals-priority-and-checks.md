# See requirements with their goals, priority and checks

Extracted on 2026-11-10 from the dashboard code (`_system/apps/dashboard/`) and the goals. "Today" describes what the code does. "Gaps" come from `raw/ingested/goals2.md` and were not rechecked. Nobody has agreed this requirement yet.

**Requirement.** For every requirement the reader sees what is demanded, which goal it serves, how important it is and how it is checked.

**Serves.** GOAL-004 Requirements with their reasons and their checks.

**For.** Product owners, business analysts, testers, development teams.

## Today

- `/req42/functional-requirements` lists the epics and use cases, each with priority, release, status and the number of features and stories below it.
- The same page draws which epics and use cases serve which goal, from each requirement's `goal:` field.
- An epic or feature page shows its own breakdown into features and stories as a diagram and as cards, and the path up to its epic (`fr_view()`).
- Features and stories whose `parent:` points nowhere are listed as orphaned requirements.
- `/goals` shows the vision, each objective with purpose, advantage, metric, baseline and beneficiaries, the requirements it drives and a goal coverage matrix.
- The quality requirements list shows each scenario's attribute, priority and its five scenario parts (`_qr_details()`).

## Gaps

- No filter by priority, release or status, so "the requirements of the next release" has no direct answer.
- No page collects acceptance criteria or shows which requirements lack them. Testers are the least well-served group.
