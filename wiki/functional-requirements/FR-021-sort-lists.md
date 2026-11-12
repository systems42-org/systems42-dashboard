---
id: FR-021
type: functional-requirement
title: Sort lists
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-022-lists-keep-sort-and-filter-in-their-address]]", "[[STK-001-product-owners]]", "[[STK-005-testers]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 21
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]", "[[GOAL-004-requirements-with-reasons-and-checks]]"]
---

# Sort lists

## Story

As a [[STK-001-product-owners]] **product owner** I want **to sort a list by several columns at once, such as priority, then release, then order**, so that **I see the list in the order my work needs**.

**PROBLEM / GOAL**

- Every section list sorts by several columns at once. Rows equal in the first column are ordered by the second, and so on.
- The metamodel says, per page type, which sort orders are useful. For example, requirements by priority › release › order, and issues by status › severity. Each list offers those orders.
- Any single column can be sorted as well.
- Each row opens its page.

**Success metric(s).** On a test wiki, each list offers the metamodel's sort orders for its type, a two-column sort orders ties by the second column, and every single column sorts.

**Scope.** in: every section list · out: sorting search results ([[FR-001-search-the-wiki]] ranks them).

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> Recording sort orders per type in the metamodel is a schema change. It needs its own PR once this feature is built.

## History

> Gernot Starke made sorting a Must and asked for several columns, with the useful sort orders coming from the metamodel ([[SRC-014-grilling-session-on-browsing]], Q6).
