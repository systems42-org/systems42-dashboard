---
id: FR-047
type: functional-requirement
title: See the requirements as a story map
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-002-business-analysts]]", "[[FR-017-browse-by-area-and-section]]", "[[FR-036-goal-coverage-matrix]]", "[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]"]
tags: [functional-requirement, story-map]
notation: agile
level: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
building-blocks: []
priority: Should
release: unscheduled
lane: backbone
order: 47
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# See the requirements as a story map

## Story

As a [[STK-002-business-analysts|business analyst]] I want **to see the requirements hierarchy as a diagram, and a detail diagram for an element I select**, so that **I grasp the structure at a glance instead of reading lists**.

**PROBLEM / GOAL**

- The functional requirements show as a hierarchy: goals, then epics, features and stories, drawn from each page's `parent:` and `goal:` fields.
- The diagram uses the project's own level names.
- Selecting one element shows a detail diagram: its children and the building blocks it is linked to.
- A changed page changes the diagram. Nobody redraws it by hand.
- The wikis the dashboard shows have building blocks, so the detail diagram shows them, whether or not this wiki has any.

**Success metric(s).** On a test wiki with epics, features, stories and building blocks, every requirement appears once in the hierarchy under its parent, and the detail diagram of any element lists exactly its children and its linked building blocks.

**Scope.** in: the hierarchy, the detail diagram · out: editing requirements in a diagram, other diagrams ([[FR-036-goal-coverage-matrix]], [[FR-040-two-views-of-the-same-terms]]).

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** [[FR-048-show-the-delivery-status-of-a-requirement]]

> [!note] Open points
> - Built today: the goals diagram, one card per epic with its counts, and a breakdown page per epic. Not built: the detail diagram with children and building blocks.

## History

> Moved from the Systems42 method wiki (meta FR-012) on 2026-11-19, where it was a story of the dashboard feature. Peter Gerstbach decided on 2026-11-19: it is a feature here, the detail diagram with building blocks stays in the requirement because the wikis the dashboard shows have them, Should ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
