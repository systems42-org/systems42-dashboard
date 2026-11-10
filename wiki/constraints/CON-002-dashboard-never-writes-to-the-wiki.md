---
id: CON-002
type: constraint
title: The dashboard never writes to the wiki
status: draft
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-004-goals-of-the-systems42-dashboard]]", "[[SRC-001-stakeholders-of-the-systems42-dashboard]]"]
related: ["[[STK-003-requirements-engineers]]", "[[STK-006-ai-agents]]", "[[GOAL-001-trusted-answers]]"]
tags: [constraint]
category: technical
---

# The dashboard never writes to the wiki

**Constraint.** The dashboard never changes the wiki's content, that is `wiki/` and
`raw/`. The only file it writes is `_system/dashboard.yaml`, its own visibility
settings, when the Keyholder ([[STK-023-keyholder]]) saves them.

**Rationale / origin.** The wiki files are the shared record that people and AI
agents ([[STK-006-ai-agents]]) write. A viewer that writes could damage them
([[SRC-004-goals-of-the-systems42-dashboard]]). The vision calls the dashboard a
read-only view ([[GOAL-001-trusted-answers]]).

**Impact.**
- Every correction happens outside the dashboard, as requirements engineers
  ([[STK-003-requirements-engineers]]) note.
- Status changes, such as promoting a page to `accepted`, also happen outside it.
