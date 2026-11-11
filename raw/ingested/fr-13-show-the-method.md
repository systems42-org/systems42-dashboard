# Show the method

Proposed on 2026-11-11 by Claude, for GOAL-002. "Today" was checked against the dashboard's routes and page headings, not in depth. Nobody has agreed this requirement yet.

**Requirement.** In a few minutes, a presenter shows on a real wiki how Systems42 works: a raw source becomes typed, linked pages with source and status, traced from goal to requirement to architecture.

The dashboard explains the three loops that keep the wiki alive, by their principles, not their inner working:

- **Capture.** A human drops a raw source into the inbox. The AI grills it against the wiki, then turns it into typed, linked pages, and records where each page came from.
- **Inspect.** The wiki is checked against fixed rules, after each capture, at intervals or on request. Findings such as contradictions, broken links or untestable requirements become questions.
- **Clarify.** Open questions go to a human, who decides. The answer flows back into the pages. Whatever stays unanswered is kept as an Issue.

The reader sees how the loops connect: capture and inspect feed clarify, and clarify feeds the pages.

**Serves.** GOAL-002 Show what Systems42 can do.

**For.** People learning or presenting Systems42, prospective adopters, workshop facilitators.

## Today

- `/help` explains how to read the dashboard and the Systems42 model in brief.
- `/metamodel` shows the types, relations, projections and rules, with examples from the live wiki.
- `/req42` and `/arc42` show the two frameworks' sections, and each page shows its sources and status.
- `/source/<id>` shows where a page came from.

## Gaps

- The dashboard does not explain the capture, inspect and clarify loops. It shows only their result. The principles are in `_system/workflows/capture.md` and `inspect.md`. Clarify has no workflow file of its own.
- There is no guided path for a demo, so the presenter has to know which pages to open in which order. See fr-14.
