---
id: STK-012
type: stakeholder
title: Maintainers
status: draft
created: 2026-11-10
updated: 2026-11-21
sources: ["[[SRC-001-stakeholders-of-the-systems42-dashboard]]", "[[SRC-002-grilling-session-on-stakeholders]]", "[[SRC-037-a-public-website-for-the-dashboard]]", "[[SRC-038-grilling-session-on-the-public-website]]"]
related: ["[[STK-010-operators]]", "[[CON-001-proof-of-concept-not-production-ready]]", "[[FR-062-the-website-is-built-and-published-from-the-repository]]"]
tags: ["stakeholder"]
aliases: ["Builders of project-specific dashboards"]
role: Maintainer
influence: high
interest: high
provides: []
receives: []
nature: person
context_role: none
---

# Maintainers

> [!assumption]
> The builders of project-specific dashboards are not in the source. They were added in the grilling session ([[SRC-002-grilling-session-on-stakeholders]]) and have not been checked with anyone in that group.

**Snapshot.** Maintainers change the dashboard and the Systems42 method. Builders of project-specific dashboards build their own dashboard on the same wiki files ([[CON-001-proof-of-concept-not-production-ready]]) and depend on the same file format and metamodel.

**Goals.**
- Publish the public website with each change, without a manual step ([[FR-062-the-website-is-built-and-published-from-the-repository]]).
- Change the dashboard and the method without breaking existing project wikis or the dashboards built on their files.

**Concerns / pains.**
- A format change reaches every wiki and every dashboard built on it.
