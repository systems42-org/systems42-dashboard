---
id: FR-052
type: functional-requirement
title: See a term's neighbourhood on its page
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-001-readers]]", "[[FR-039-the-term-page]]", "[[FR-051-reveal-related-page-types-layer-by-layer]]"]
tags: [functional-requirement, domain-terms]
notation: agile
level: story
parent: ["[[FR-040-two-views-of-the-same-terms]]"]
building-blocks: []
priority: Should
release: unscheduled
lane: backbone
order: 52
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# See a term's neighbourhood on its page

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-001-readers|business analyst]] I want **each term page to show the term and the terms next to it as a small network**, so that **I see what the term sits among without leaving the page**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** a term page **when** it is shown **then** a network above the definition shows the term, marked, and the terms it links to directly.
- **Given** the page **then** the same buttons as in [[FR-051-reveal-related-page-types-layer-by-layer]] add the neighbours of other page types, one layer at a time.
- **Given** I tap a node **then** its page opens.
- **Given** the network **then** a link leads to the whole term network.

## Hierarchy

- **Parent:** [[FR-040-two-views-of-the-same-terms]]
- **Children:** none.

> [!note] Open points
> None.

## History

> Moved from the Systems42 method wiki (meta DR-023, amendment of 2026-06-25) on 2026-11-19 ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
