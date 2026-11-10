---
id: STK-006
type: stakeholder
title: AI agents
status: draft
created: 2026-11-10
updated: 2026-11-10
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]"]
related: []
tags: ["stakeholder"]
aliases: []
role: AI agent that writes the wiki files
influence: low
interest: low
provides: []
receives: []
nature: person
context_role: none
---

# AI agents

**Snapshot.** AI agents never use the dashboard. They read and write the files in `wiki/` directly and write most of what the dashboard shows. The file format is the contract between them and the dashboard.

**Goals.**
- None from the dashboard itself.

**Concerns / pains.**
- None recorded yet.

**Interactions.** None recorded yet.

**Note.** `nature` allows only `person` or `organization`, and an AI agent is neither. The page keeps the default. It has no effect, because `context_role: none` hides the agents from the context diagram. A third value such as `system` would change the schema and is parked.
