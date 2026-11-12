---
id: FR-020
type: functional-requirement
title: Know where you are
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-001-search-the-wiki]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 20
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Know where you are

## Story

As a [[STK-008-workshop-participants]] **workshop participant** I want **every page to show where it belongs**, so that **I don't get lost after a few clicks and can always go one level up**.

**PROBLEM / GOAL**

- Every page shows its path: area › section › page. Each part is a link.
- The path follows where the page belongs, not how the reader got there. A page found through search ([[FR-001-search-the-wiki]]) shows the same path as one opened from its list.
- Pages outside the sections, such as search, help or the changes page, show "Home › page".

**Success metric(s).** On a test wiki, a page opened from search and from its list shows the same path, every part of the path opens its level, and a page outside the sections shows "Home › page".

**Scope.** in: every page of the dashboard · out: a history of the pages the reader visited.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Sharpened in Q5 of [[SRC-014-grilling-session-on-browsing]].
