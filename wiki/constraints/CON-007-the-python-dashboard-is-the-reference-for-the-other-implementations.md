---
id: CON-007
type: constraint
title: The Python dashboard is the reference for the other implementations
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]", "[[SRC-049-grilling-session-on-the-mac-native-app]]"]
related: ["[[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]", "[[FR-055-an-installable-dashboard-app]]", "[[CON-003-docker-is-the-supported-way-to-run-it]]", "[[SOL-002-three-ways-to-run-the-dashboard]]", "[[FR-065-a-mac-native-dashboard-app]]"]
tags: [constraint]
category: organizational
---

# The Python dashboard is the reference for the other implementations

**Constraint.** The Python, the Go and the Swift dashboard are equal products: each is a supported way to show a wiki. For what a page shows, the Python dashboard is the reference. A feature exists there before another implementation gets it. Where they differ, the Python dashboard is right.

**Rationale / origin.** Three implementations must show the same content ([[DR-007-the-dashboard-gets-a-uv-start-and-a-second-implementation-in-go]]). Gernot Starke named the Python dashboard as the reference ([[SRC-039-solution-strategy-of-the-dashboard]], [[SRC-040-grilling-session-on-the-solution-strategy]]).

**Impact.**
- A test compares the pages of the Python and the Go dashboard for the same wiki. When it fails, the Go dashboard is changed ([[FR-055-an-installable-dashboard-app]]).
- The Swift app produces no HTML. Its content is compared with data taken from the Go dashboard, which the test above holds to the Python dashboard ([[FR-065-a-mac-native-dashboard-app]]).
- On 2026-11-22 Gernot Starke set the three as equal products and kept the Python dashboard as the reference ([[SRC-049-grilling-session-on-the-mac-native-app]]).
