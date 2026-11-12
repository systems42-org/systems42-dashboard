---
id: CON-002
type: constraint
title: The dashboard never writes to the wiki
status: draft
created: 2026-11-10
updated: 2026-11-11
sources: ["[[SRC-004-goals-of-the-systems42-dashboard]]", "[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-012-conversation-on-tailoring-and-the-view]]"]
related: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[STK-003-requirements-engineers]]", "[[STK-006-ai-agents]]", "[[GOAL-001-trusted-answers]]"]
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
- [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]] moves the view
  settings out of the wiki's repository. Then the dashboard writes nothing there,
  and the exception for `_system/dashboard.yaml` falls away.
