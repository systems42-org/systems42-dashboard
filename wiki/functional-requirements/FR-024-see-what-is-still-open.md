---
id: FR-024
type: functional-requirement
title: See what is still open
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-001-search-the-wiki]]", "[[FR-018-orientation-on-the-first-page]]", "[[FR-019-section-at-a-glance]]", "[[FR-021-sort-lists]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]", "[[STK-019-auditors-and-quality-assurance]]"]
tags: ["functional-requirement", "issues"]
stereotype: epic
parent: []
priority: Must
release: unscheduled
lane: backbone
order: 24
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# See what is still open

## Epic: Summary

As a [[STK-001-product-owners|product owner]] I want **to see which questions about the system are still open, overall and where they matter**, so that **nobody treats an open point as settled**.

**PROBLEM / GOAL**

Open questions live in the wiki as issues. A reader needs them in one list, on the pages they affect and on the sections those pages belong to.

These rules hold for every feature below:

- **Read only.** Issues are created and changed only in the wiki. The dashboard shows them and never creates or changes one ([[CON-002-dashboard-never-writes-to-the-wiki]]).
- **Sorted like every list.** The issue list sorts by several columns, such as status › severity ([[FR-021-sort-lists]]).
- **Found by search.** Search covers issues like every other page ([[FR-001-search-the-wiki]]).
- **Counted on sections.** Each section shows its open issue count ([[FR-019-section-at-a-glance]]), and the first page shows the open questions ([[FR-018-orientation-on-the-first-page]]).

**Success metric(s).** On a test wiki, every open issue is reachable from the issue list, from each page it points at, and from each section those pages belong to.

**Scope.** in: showing issues · out: creating, editing or closing issues, and due dates. The wiki is not a project management tool.

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-025-issue-list-with-filters]], [[FR-026-issues-carry-a-category]], [[FR-027-issues-on-the-page-they-affect]], [[FR-028-who-answers-an-issue]].

> [!note] Open points
> None.

## History

> Extracted from the dashboard code on 2026-11-10 and rewritten as needs on 2026-11-12 ([[SRC-015-see-what-is-still-open]]). Shaped with Gernot Starke in Q1 to Q4 ([[SRC-016-grilling-session-on-open-issues]]).
