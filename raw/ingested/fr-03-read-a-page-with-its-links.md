# Read a page with its links

Extracted on 2026-11-10 from the dashboard code (`_system/apps/dashboard/`) and the goals. "Today" describes what the code does. "Gaps" come from `raw/ingested/goals2.md` and were not rechecked. Nobody has agreed this requirement yet.

**Requirement.** A reader opens one wiki page and sees its text, what it links to and what links to it.

**Serves.** GOAL-003 Answers without asking a colleague.

**For.** Everyone who reads the dashboard.

## Today

- Every wiki page has a stable address: `/page/<folder>/<name>`, or `/functional-requirements/<name>` for functional requirements.
- The page head shows type, ID, status, created and updated dates, tags and the source chips.
- The dashboard renders the markdown body. Wikilinks become links to the target page. Fenced `mermaid` blocks render as diagrams.
- Below the text, "Links to" and "Linked from" list the related pages, grouped by page type (`detail.html`).

## Gaps

- Links to method terms such as `[[INVEST]]` or `[[MoSCoW]]` render without link or explanation.
- "Linked from" shows a resolved issue like an open one.
