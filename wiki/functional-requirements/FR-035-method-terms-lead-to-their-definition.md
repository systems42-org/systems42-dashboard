---
id: FR-035
type: functional-requirement
title: Method terms lead to their definition
status: draft
created: 2026-11-13
updated: 2026-11-13
sources: ["[[SRC-021-read-a-page-with-its-links]]", "[[SRC-022-grilling-session-on-reading-a-page]]"]
related: ["[[FR-034-read-a-page-with-its-links]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]", "[[STK-013-people-learning-or-presenting-systems42]]"]
tags: ["functional-requirement", "method"]
stereotype: feature
parent: ["[[FR-010-show-the-method]]"]
priority: Should
release: unscheduled
lane: backbone
order: 35
goal: ["[[GOAL-002-show-what-systems42-can-do]]", "[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Method terms lead to their definition

## Story

As a [[STK-015-newcomers|newcomer]] I want **a method term such as MADR, INVEST or MoSCoW to lead to its definition**, so that **I understand what the page follows without searching elsewhere**.

**PROBLEM / GOAL**

- Systems42 defines its method standards as anchors in its metamodel. The dashboard shows them, it does not define them ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]).
- The metamodel page has an entry for every anchor: its name, its short definition, the page types it applies to and its outside reference.
- Every link to an anchor, such as `[[MADR]]`, leads to that entry, on every page.
- A page's note that it follows a standard ("follows MADR") shows as a small label in the page head, linking to the entry, not as a box before the content.

**Success metric(s).** On a test wiki, every anchor link on every page leads to an entry with a definition, and no page shows a "follows" note as a box.

**Scope.** in: showing anchors and linking to them · out: writing or changing the anchors themselves, which is Systems42's part.

## Hierarchy

- **Parent:** [[FR-010-show-the-method]]
- **Children:** none.

## History

> Gernot Starke asked on 2026-11-13 why "follows MADR" shows as a box while MADR is not explained ([[SRC-022-grilling-session-on-reading-a-page]]). The gap was already noted in [[SRC-021-read-a-page-with-its-links]]. Split and Should agreed in question 2.
