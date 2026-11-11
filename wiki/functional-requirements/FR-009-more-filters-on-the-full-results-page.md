---
id: FR-009
type: functional-requirement
title: More filters on the full results page
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-006-grilling-session-on-search]]"]
related: ["[[FR-006-tags-and-fields-are-searched]]", "[[STK-001-product-owners]]", "[[STK-003-requirements-engineers]]"]
tags: ["functional-requirement", "search"]
stereotype: feature
parent: ["[[FR-001-search-the-wiki]]"]
priority: Could
release: unscheduled
lane: backbone
order: 9
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# More filters on the full results page

## Story

As a [[STK-003-requirements-engineers]] **requirements engineer** I want **to narrow the full results by status, priority or tag**, so that **I get a precise list, such as all open issues about search**.

**PROBLEM / GOAL**

Today `/search` offers type facets only. Product owners and requirements engineers want precise lists. A filter syntax in the search box (`status:open`) would serve them, but newcomers and workshop participants don't know such a syntax.

- `/search` gets filters for status, priority and tag next to the type facets.
- The search box keeps no filter syntax.

**Success metric(s).** On a fixed test wiki, choosing a status filter on `/search` leaves only hits with that status.

**Scope.** in: `/search` · out: filter syntax in the search box, and filters in the popup.

## Hierarchy

- **Parent:** [[FR-001-search-the-wiki]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Filter syntax was rejected in Q5 of [[SRC-006-grilling-session-on-search]]. Gernot Starke proposed filters on the full results page instead. This is a Could, not a non-goal, because it is cheap.
