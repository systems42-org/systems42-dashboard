---
id: DR-002
type: decision-record
title: Tailoring belongs to Systems42, the view belongs to the dashboard
status: accepted
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-012-conversation-on-tailoring-and-the-view]]"]
related: ["[[STK-023-keyholder]]", "[[STK-003-requirements-engineers]]", "[[STK-006-ai-agents]]", "[[FR-001-search-the-wiki]]", "[[FR-012-guided-path-through-the-wiki]]"]
tags: [decision-record]
aliases: []
kind: architecture
decided: 2026-11-11
decision-makers: [Gernot Starke]
consulted: [Claude]
informed: []
drivers: ["[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[GOAL-001-trusted-answers]]", "[[GOAL-002-show-what-systems42-can-do]]"]
amends: []
superseded-by: []
---

# Tailoring belongs to Systems42, the view belongs to the dashboard

> follows [[MADR]]

## Context and Problem Statement

In the real Systems42 the metamodel is configurable. A project or product adapts it to its needs and may leave out parts of requirements, architecture or commons.

The dashboard's Configure dialog hides areas and sections and saves the choice in `_system/dashboard.yaml`, a file inside the wiki's repository. So a choice made for one workshop lands in the project's history and looks like a project decision.

Two decisions share one dialog and one file:

| | Tailoring | View |
|---|---|---|
| Question | Which parts of the method does this project use? | What does this audience see right now? |
| Owner | The project | Whoever runs the session ([[STK-023-keyholder]]) |
| Lifetime | Permanent | One workshop or demo |
| Effect | A left-out part does not exist for the project | A hidden part still exists and search finds it |

Where does each belong?

## Decision Drivers

- The AI agent ([[STK-006-ai-agents]]) must know which parts the project uses, so capture writes no pages for left-out parts and inspect does not report them as missing.
- The dashboard is a read-only view ([[CON-002-dashboard-never-writes-to-the-wiki]], [[GOAL-001-trusted-answers]]).
- A presenter must be able to focus a demo without changing the project ([[GOAL-002-show-what-systems42-can-do]]).

## Considered Options

1. **One mechanism.** Configure keeps writing `_system/dashboard.yaml` in the repository, and that file also serves as the tailoring.
2. **Split by owner.** Tailoring sits in the Systems42 schema next to the metamodel and changes by PR. The view belongs to the dashboard and is kept outside the wiki's repository.
3. **Tailoring only.** Configure is removed, and every session shows everything the project uses.

## Decision Outcome

Chosen option: **2, split by owner**, because each decision then lives with the people who own it and lasts as long as it should. The project's choice is versioned and reviewed like every schema change. A workshop choice leaves no trace in the project.

The two are linked by one rule: the view can only hide what the tailoring includes. The dashboard never offers a part the project left out.

### Consequences

- Good: the AI agent, the dashboard and the people read the same tailoring from one place.
- Good: once the view leaves the repository, the dashboard writes nothing there, and [[CON-002-dashboard-never-writes-to-the-wiki]] holds without its exception.
- Good: "configurable" has one meaning. The dialog gets a name of its own, such as "View".
- Bad: the existing `_system/dashboard.yaml` must be migrated, and the Configure dialog changes.
- Bad: a view setting can no longer be shared through the repository.

### Confirmation

- A test shows that the dashboard writes no file inside the wiki's repository.
- A test shows that the view dialog offers no part the tailoring leaves out.
- The metamodel lint checks the tailoring against the metamodel.

## Pros and Cons of the Options

- **Option 1.** Good: nothing to change. Bad: workshop choices pollute the project history, and the AI agent cannot tell a project decision from a demo setting.
- **Option 2.** Good: clear owners and lifetimes. Bad: migration work, two settings to explain.
- **Option 3.** Good: simplest. Bad: a presenter cannot focus a demo, which works against [[GOAL-002-show-what-systems42-can-do]].

## More Information

Follow-ups, each through its own change:
- Where exactly the tailoring sits in the schema, and its format (schema change, by PR).
- Whether the view lasts for one dashboard run or is kept in a local file outside git.
- Renaming the Configure dialog (a `CHANGELOG.md` entry).
- Tightening [[CON-002-dashboard-never-writes-to-the-wiki]] once the view has moved.
- The requirements go into `raw/fr-02-browse-by-area-and-section.md` (tailoring) and `raw/fr-12-shared-session-in-a-workshop.md` (view) when they are captured.
