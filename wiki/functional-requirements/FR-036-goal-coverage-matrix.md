---
id: FR-036
type: functional-requirement
title: Goal coverage matrix
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-023-goal-coverage-matrix]]", "[[SRC-024-grilling-session-on-the-goal-coverage-matrix]]"]
related: ["[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[QR-001-usable-on-phone-and-tablet]]", "[[FR-022-lists-keep-sort-and-filter-in-their-address]]", "[[STK-001-product-owners]]", "[[STK-002-business-analysts]]"]
tags: ["functional-requirement", "goals"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Should
release: unscheduled
lane: backbone
order: 36
goal: ["[[GOAL-004-requirements-with-reasons-and-checks]]"]
---

# Goal coverage matrix

## Story

As a [[STK-001-product-owners|product owner]] I want **to see at a glance which requirements serve which goal**, so that **I spot goals nothing serves yet and requirements that serve no goal**.

**PROBLEM / GOAL**

- At the bottom of Vision & Goals, the dashboard shows Systems42's goal coverage projection as a matrix. Systems42 defines what it contains: goals as rows, epics and use cases as columns, and what counts as a gap ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]).
- A mark sits where a requirement serves a goal.
- A goal row without any mark stands out, so a goal that nothing serves is easy to see.
- Enablers (epics in the platform or display lane) form their own group of columns, set apart.
- An epic that should serve a goal but names none is marked as breaking the Systems42 rule, not shown as an enabler.
- Each column shows the requirement's real ID, such as `FR-024` or `UC-003`. Hover or focus shows its title, and a click opens it. Each row's goal links its goal page.
- The matrix stays inside its own box. With many columns it scrolls there, the goal column stays put, and the page never scrolls sideways ([[QR-001-usable-on-phone-and-tablet]]).
- Every mark is also reachable as text on the same page: each goal card lists the requirements that serve it.
- The "Agreed only" filter applies here too ([[FR-022-lists-keep-sort-and-filter-in-their-address]]).

**Success metric(s).** On a test wiki with 7 goals and 60 requirements, the page does not scroll sideways at 320 and at 1280 CSS pixels, and the goal column stays readable while the columns scroll. For every mark, the requirement's page names that goal, and the other way round. A goal without any requirement is visibly marked.

**Scope.** in: showing the projection on Vision & Goals · out: deciding what the projection contains (Systems42), counts per row, the matrix on area pages, quality requirements and constraints in the matrix, editing.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

## History

> Raised by Gernot Starke on 2026-11-13 together with a layout fix for the matrix ([[SRC-023-goal-coverage-matrix]]). GOAL-004, Should, under FR-017, no row counts and only on Vision & Goals, in questions 1 to 3 of [[SRC-024-grilling-session-on-the-goal-coverage-matrix]]. Rows, columns and enablers follow Systems42's projection `proj-goal-coverage`.
