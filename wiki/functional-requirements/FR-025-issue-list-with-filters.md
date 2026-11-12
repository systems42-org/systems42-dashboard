---
id: FR-025
type: functional-requirement
title: Issue list with filters
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-019-section-at-a-glance]]", "[[FR-021-sort-lists]]", "[[FR-022-lists-keep-sort-and-filter-in-their-address]]", "[[FR-026-issues-carry-a-category]]", "[[FR-028-who-answers-an-issue]]", "[[STK-003-requirements-engineers]]"]
tags: ["functional-requirement", "issues"]
stereotype: feature
parent: ["[[FR-024-see-what-is-still-open]]"]
priority: Must
release: unscheduled
lane: backbone
order: 25
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Issue list with filters

## Story

As a [[STK-003-requirements-engineers|requirements engineer]] I want **one list of all issues that I can narrow down**, so that **I see exactly the open points I have to work on**.

**PROBLEM / GOAL**

- One list holds every issue, with its status, severity, kind, category and owner. Each row opens its issue.
- The list shows how many issues are open, and how many in total.
- A reader filters it by status, category, severity, section and owner. Filters combine.
- The section filter keeps the issues that point at pages of that section. A section's open issue count opens the list with this filter ([[FR-019-section-at-a-glance]]).
- The address carries every filter, as with sort and status filter on every list ([[FR-022-lists-keep-sort-and-filter-in-their-address]]).

**Success metric(s).** On a test wiki, each filter alone and two filters together leave only the matching issues. The open count matches the issues with status `open` or `in-progress`. The address, opened in another browser, shows the same issues.

**Scope.** in: the issue list · out: sorting (see [[FR-021-sort-lists]]) and search (see [[FR-001-search-the-wiki]]).

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Shaped in Q1 and Q4 of [[SRC-016-grilling-session-on-open-issues]]. The filters other than status belong here, not in FR-022, because only issues have them.
