---
id: CON-004
type: constraint
title: The dashboard shows the metamodel, it does not define it
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-022-grilling-session-on-reading-a-page]]"]
related: ["[[FR-035-method-terms-lead-to-their-definition]]", "[[GOAL-006-source-and-status-on-every-statement]]", "[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[STK-012-maintainers]]"]
tags: [constraint]
category: organizational
---

# The dashboard shows the metamodel, it does not define it

**Constraint.** This wiki holds requirements for the dashboard only. A requirement for the Systems42 metamodel, its templates or its anchors belongs to Systems42 itself, in `systems42-org/meta`.

**The test.** Would the requirement still hold if the dashboard did not exist, for example in Obsidian or for an AI agent?
- **Yes:** it is a Systems42 requirement. Here it appears at most as an issue with category `systems42`, pointing to Systems42. Example: every anchor has a short definition.
- **No:** it is a dashboard requirement and lives here. Example: every anchor link leads to its definition.

**Rationale / origin.** Gernot Starke asked to separate the two clearly when the dashboard showed "follows MADR" without explaining MADR ([[SRC-022-grilling-session-on-reading-a-page]]). The same line runs through [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]: the tailoring belongs to Systems42, the view to the dashboard.

**Impact.**
- Dashboard requirements say how the dashboard shows what the metamodel defines, and never define a type, field, relation or anchor themselves.
- [[GOAL-006-source-and-status-on-every-statement]] is more a goal of Systems42 than of the dashboard. Its dashboard part is showing source and status.
