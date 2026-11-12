---
id: FR-028
type: functional-requirement
title: Who answers an issue
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-025-issue-list-with-filters]]", "[[FR-026-issues-carry-a-category]]", "[[STK-001-product-owners]]"]
tags: ["functional-requirement", "issues"]
stereotype: feature
parent: ["[[FR-024-see-what-is-still-open]]"]
priority: Should
release: unscheduled
lane: backbone
order: 28
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Who answers an issue

## Story

As a [[STK-001-product-owners|product owner]] I want **to see who is expected to answer each issue**, so that **I spot the open points nobody takes care of**.

**PROBLEM / GOAL**

- Every issue can name its owner: the person or stakeholder group expected to answer it, written like `raised-by:`.
- The issue list and each issue page show the owner ([[FR-025-issue-list-with-filters]]).
- An issue without an owner shows "nobody yet". A reader filters the list to these issues.
- There are no due dates. The wiki is not a project management tool.

**Success metric(s).** On a test wiki, every issue shows its owner or "nobody yet", and the "nobody yet" filter leaves only issues without one.

**Scope.** in: every issue · out: due dates, reminders and assigning owners from the dashboard.

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

> [!note] Open points
> The `owner:` field goes into the issue template and the metamodel in the same PR as `category:` ([[FR-026-issues-carry-a-category]]).

## History

> Gernot Starke dropped "by when", because the wiki is not for project management ([[SRC-015-see-what-is-still-open]]). Owner field and "nobody yet" in Q3 of [[SRC-016-grilling-session-on-open-issues]].
