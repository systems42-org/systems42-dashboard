---
id: CON-002
type: constraint
title: The dashboard never writes to the wiki
status: draft
created: 2026-11-10
updated: 2026-11-19
sources: ["[[SRC-004-goals-of-the-systems42-dashboard]]", "[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-012-conversation-on-tailoring-and-the-view]]", "[[SRC-033-grilling-session-on-the-shared-session]]"]
related: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[STK-003-requirements-engineers]]", "[[STK-006-ai-agents]]", "[[GOAL-001-trusted-answers]]", "[[FR-046-shared-session-in-a-workshop]]"]
tags: [constraint]
category: technical
---

# The dashboard never writes to the wiki

**Constraint.** The dashboard never changes the wiki's content, that is `wiki/` and
`raw/`. It writes no file in the wiki's repository.

**Rationale / origin.** The wiki files are the shared record that people and AI
agents ([[STK-006-ai-agents]]) write. A viewer that writes could damage them
([[SRC-004-goals-of-the-systems42-dashboard]]). The vision calls the dashboard a
read-only view ([[GOAL-001-trusted-answers]]).

**Impact.**
- Every correction happens outside the dashboard, as requirements engineers
  ([[STK-003-requirements-engineers]]) note.
- Status changes, such as promoting a page to `accepted`, also happen outside it.
- Until release 0.11.4 the dashboard wrote one file, `_system/dashboard.yaml`, the view the
  Keyholder saved. [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]] moved the
  view out of the repository. It now lives in the running dashboard only
  ([[FR-046-shared-session-in-a-workshop]]).
