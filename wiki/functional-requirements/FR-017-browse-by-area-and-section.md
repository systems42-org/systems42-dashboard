---
id: FR-017
type: functional-requirement
title: Browse by area and section
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-001-search-the-wiki]]", "[[FR-013-header-and-footer-on-every-page]]", "[[STK-015-newcomers]]", "[[STK-008-workshop-participants]]"]
tags: ["functional-requirement", "navigation"]
stereotype: epic
parent: []
priority: Must
release: unscheduled
lane: backbone
order: 17
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Browse by area and section

## Epic: Summary

As a [[STK-015-newcomers|newcomer]] who doesn't know the right word I want **to reach any page in three steps: area, section, page**, so that **I find answers even when search can't help me**.

**PROBLEM / GOAL**

Browsing is the second way in, next to search ([[FR-001-search-the-wiki]]). A reader starts on the first page, picks an area (Requirements, Architecture, Commons), then a section, then a page.

One rule holds for every feature below: **a section carries the same name wherever it appears**, so the reader recognises the page a link leads to.

**Success metric(s).** From the first page, every page of a test wiki is reachable in at most three clicks.

**Scope.** in: the first page, areas, sections and their lists · out: the header on every page ([[FR-013-header-and-footer-on-every-page]]).

## Hierarchy

- **Parent:** none (epic).
- **Children:** projected from the `parent:` backlinks: [[FR-018-orientation-on-the-first-page]], [[FR-019-section-at-a-glance]], [[FR-020-know-where-you-are]], [[FR-021-sort-lists]], [[FR-022-lists-keep-sort-and-filter-in-their-address]], [[FR-023-areas-and-sections-follow-the-tailoring]], [[FR-034-read-a-page-with-its-links]].

> [!note] Open points
> None.

## History

> Extracted from the dashboard code on 2026-11-10 and rewritten as needs on 2026-11-11 ([[SRC-013-browse-by-area-and-section]]). Shaped with Gernot Starke in Q1 to Q6 ([[SRC-014-grilling-session-on-browsing]]).
