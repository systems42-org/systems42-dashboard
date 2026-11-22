---
id: FR-026
type: functional-requirement
title: Issues carry a category
status: draft
created: 2026-11-12
updated: 2026-11-21
sources: ["[[SRC-015-see-what-is-still-open]]", "[[SRC-016-grilling-session-on-open-issues]]"]
related: ["[[FR-025-issue-list-with-filters]]", "[[FR-017-browse-by-area-and-section]]", "[[STK-001-readers]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[ISS-007-issue-category-and-owner-belong-in-meta]]"]
tags: ["functional-requirement", "issues"]
notation: agile
level: feature
parent: ["[[FR-024-see-what-is-still-open]]"]
priority: Should
release: unscheduled
lane: backbone
order: 26
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Issues carry a category

## Story

As a [[STK-001-readers|product owner]] I want **every issue to show which part of the work it touches**, so that **I hand it to the right people**.

**PROBLEM / GOAL**

- The dashboard shows each issue's `category:` value in the issue list and on the issue page, and lets the reader filter the issue list by category ([[FR-025-issue-list-with-filters]]).
- The dashboard shows `category:` separately from `kind:` (`question`, `contradiction`, `gap`, `ambiguity`, `risk`).
- On a wiki whose issues carry no `category:` field, the dashboard degrades cleanly without errors.
- Defining the `category:` field and its allowed values belongs to Systems42 (`meta`), not to the dashboard ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]], [[ISS-007-issue-category-and-owner-belong-in-meta]]).

**Success metric(s).** On a test wiki whose issues carry `category:`, every issue shows its category and filtering by a category leaves only its issues. On a wiki without `category:`, the issue list loads with no errors.

**Scope.** in: displaying and filtering `category:` in the dashboard · out: defining the `category:` field or its taxonomy (Systems42, [[ISS-007-issue-category-and-owner-belong-in-meta]]).

## Hierarchy

- **Parent:** [[FR-024-see-what-is-still-open]]
- **Children:** none.

## History

> Gernot Starke named the categories requirements, architecture, commons, content, orga and systems42 ([[SRC-015-see-what-is-still-open]]). One category per issue, Should, in Q2 and Q4 of [[SRC-016-grilling-session-on-open-issues]]. On 2026-11-20 the field definition moved to [[ISS-007-issue-category-and-owner-belong-in-meta]] (`meta#53`), keeping only dashboard display and filtering here. On 2026-11-21 Systems42 adopted the field ([meta pull request 55](https://github.com/systems42-org/meta/pull/55)): the category `systems42` is named `method`, and the field is optional.
