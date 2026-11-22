---
id: SOL-004
type: solution-strategy
title: The metamodel drives the dashboard
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]"]
related: ["[[BB-001-python-dashboard]]", "[[BB-003-go-dashboard]]", "[[EIF-001-systems42-wiki]]"]
tags: [solution-strategy]
drivers: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[CON-005-the-dashboard-works-on-systems42-derivatives-only]]", "[[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]", "[[FR-043-the-dashboard-checks-the-metamodel-version]]", "[[FR-044-sections-come-from-the-repositorys-metamodel]]"]
decisions: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]"]
state: current
superseded-by:
---

# The metamodel drives the dashboard

> follows [[arc42]] (section 4)

## Strategy

- **Schema read at runtime, not hardcoded** ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[CON-005-the-dashboard-works-on-systems42-derivatives-only]], [[CON-006-the-dashboard-depends-on-the-metamodel-never-the-reverse]]) → both [[BB-001-python-dashboard]] and [[BB-003-go-dashboard]] read types, fields, sections and allowed values from `_system/metamodel/` in [[EIF-001-systems42-wiki]] and check the metamodel version on startup ([[FR-043-the-dashboard-checks-the-metamodel-version]], [[FR-044-sections-come-from-the-repositorys-metamodel]]).
- **Tailoring by configuration, view per session** → each project adapts its name, brand and active sections in wiki configuration files without changing dashboard code, while workshop presenters hide sections temporarily in their session. Decided in [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]].
