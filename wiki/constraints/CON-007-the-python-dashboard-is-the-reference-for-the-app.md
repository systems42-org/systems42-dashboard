---
id: CON-007
type: constraint
title: The Python dashboard is the reference for the app
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]"]
related: ["[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[FR-055-an-installable-dashboard-app]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[SOL-002-three-ways-to-run-the-dashboard]]"]
tags: [constraint]
category: organizational
---

# The Python dashboard is the reference for the app

**Constraint.** A feature exists in the Python dashboard before the app gets it. Where the two differ, the Python dashboard is right.

**Rationale / origin.** Two implementations must show the same pages ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]). Gernot Starke named the Python dashboard as the reference ([[SRC-039-solution-strategy-of-the-dashboard]], [[SRC-040-grilling-session-on-the-solution-strategy]]).

**Impact.** A test compares the pages of both for the same wiki. When it fails, the app is changed ([[FR-055-an-installable-dashboard-app]]).
