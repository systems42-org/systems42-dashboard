---
id: FR-047
type: functional-requirement
title: See the requirements hierarchy as a diagram
status: draft
created: 2026-10-13
updated: 2026-11-19
sources: ["[[SRC-034-pages-moved-from-meta]]"]
related: ["[[STK-002-business-analysts]]", "[[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]"]
tags: [functional-requirement]
stereotype: story
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Should
release: unscheduled
lane: display
order: 47
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# See the requirements hierarchy as a diagram

## Story

As a [[STK-002-business-analysts|business analyst]] I want **to see the requirements hierarchy as a diagram, and a detail diagram for one element**, so that **I grasp the structure at a glance instead of reading lists**.

**Acceptance criteria.**
- **Given** a wiki with a requirements hierarchy **when** I open it **then** it is drawn as a diagram, with the level names the metamodel defines ([[CON-004-the-dashboard-shows-the-metamodel-it-does-not-define-it]]).
- **Given** I select one element **when** its detail diagram opens **then** it shows the element's children and its building blocks.
- **Given** a page changes **when** I reload **then** the diagram shows the change. Diagrams are drawn from the pages, never by hand.

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> - Built in part: the goals diagram, the story map and the building-block tree. The detail diagram for one element is not built.
> - The goal is a proposal by Claude.

## History

> Moved from meta [FR-012](https://github.com/systems42-org/meta/blob/main/wiki/functional-requirements/FR-012-visualise-the-requirements-hierarchy.md) on 2026-11-19 and shortened.
