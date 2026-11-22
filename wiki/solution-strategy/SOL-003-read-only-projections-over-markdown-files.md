---
id: SOL-003
type: solution-strategy
title: Read-only projections over Markdown files
status: draft
created: 2026-11-22
updated: 2026-11-22
sources: ["[[SRC-039-solution-strategy-of-the-dashboard]]", "[[SRC-040-grilling-session-on-the-solution-strategy]]", "[[SRC-046-grilling-session-on-modularizing-the-solution-strategy]]"]
related: ["[[BB-001-python-dashboard]]", "[[BB-003-go-dashboard]]", "[[EIF-001-systems42-wiki]]"]
tags: [solution-strategy]
drivers: ["[[GOAL-001-trusted-answers]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
decisions: ["[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]"]
state: current
superseded-by:
---

# Read-only projections over Markdown files

> follows [[arc42]] (section 4)

## Strategy

- **No database, one source of truth** ([[CON-002-dashboard-never-writes-to-the-wiki]]) → the dashboard reads the Markdown files of [[EIF-001-systems42-wiki]] directly and has no database or persistent cache. Derived search indexes and workshop session state live only in memory.
- **Every view is computed on demand** ([[GOAL-001-trusted-answers]], [[CON-002-dashboard-never-writes-to-the-wiki]]) → lists, matrices, story maps and diagrams are projected from the pages and their typed links on every load. Nothing drawn is stored, so no overview or diagram can drift from the wiki. Interactive networks follow [[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]].
