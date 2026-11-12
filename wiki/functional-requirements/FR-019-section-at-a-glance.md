---
id: FR-019
type: functional-requirement
title: Section at a glance
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[FR-018-orientation-on-the-first-page]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Must
release: unscheduled
lane: backbone
order: 19
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]", "[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Section at a glance

## Story

As a [[STK-004-development-teams]] **developer** I want **to see how much a section holds and how far it is agreed, before I open it**, so that **I pick the right section and know how much to trust it**.

**PROBLEM / GOAL**

Each section shows:

- **Count.** How many pages it has, shown prominently.
- **Maturity.** A small bar showing how its pages split by status (draft, review, accepted).
- **Click.** A click opens the section's list.

Nothing more. The section stays quick to scan.

**Success metric(s).** On a test wiki, each section shows its page count, and the parts of its bar match the status split of its pages. A click opens its list.

**Scope.** in: every section of every area · out: page names on the section.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Shaped in Q4 of [[SRC-014-grilling-session-on-browsing]]. Gernot Starke chose count and bar only, without page names.
