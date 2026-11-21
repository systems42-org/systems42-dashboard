---
id: FR-028
type: functional-requirement
title: Who answers an issue
status: draft
created: 2026-11-12
updated: 2026-11-20
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-025-issue-list-with-filters]]", "[[FR-026-issues-carry-a-category]]", "[[STK-001-readers]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[ISS-007-issue-category-and-owner-belong-in-meta]]"]
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

As a [[STK-001-readers|product owner]] I want **to see who is expected to answer each issue**, so that **I spot the open points nobody takes care of**.

**PROBLEM / GOAL**

- The issue list and each issue page show the issue's `owner:` value (a person name or stakeholder link) when present ([[FR-025-issue-list-with-filters]]).
- An issue without an owner shows "nobody yet". A reader can filter the list to these issues.
- On a wiki whose issues do not carry `owner:`, the dashboard degrades cleanly without errors.
- Defining the `owner:` field and the no-due-dates rule belongs to Systems42 (`meta`), not to the dashboard ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[ISS-007-issue-category-and-owner-belong-in-meta]]).

**Success metric(s).** On a test wiki whose issues carry `owner:`, every issue shows its owner or "nobody yet", and the "nobody yet" filter leaves only issues without one. On a wiki without `owner:`, the issue list loads with no errors.

**Scope.** in: displaying and filtering `owner:` in the dashboard · out: defining the `owner:` field (Systems42, [[ISS-007-issue-category-and-owner-belong-in-meta]]), due dates, reminders and assigning owners from the dashboard.

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

> [!note] Open points
> `owner:` is proposed upstream in Systems42 ([meta issue #53](https://github.com/systems42-org/meta/issues/53), [[ISS-007-issue-category-and-owner-belong-in-meta]]).

## History

> Gernot Starke dropped "by when", because the wiki is not for project management ([[SRC-015-see-what-is-still-open]]). Owner field and "nobody yet" in Q3 of [[SRC-016-grilling-session-on-open-issues]]. On 2026-11-20 the field definition moved to [[ISS-007-issue-category-and-owner-belong-in-meta]] (`meta#53`), keeping only dashboard display and filtering here.
