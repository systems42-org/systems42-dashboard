---
id: FR-023
type: functional-requirement
title: Areas and sections follow the tailoring
status: draft
created: 2026-11-12
updated: 2026-11-12
sources: ["[[SRC-013-browse-by-area-and-section]]", "[[SRC-014-grilling-session-on-browsing]]"]
related: ["[[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]", "[[FR-012-guided-path-through-the-wiki]]", "[[STK-011-people-who-set-up-a-project-wiki]]"]
tags: ["functional-requirement", "navigation"]
stereotype: feature
parent: ["[[FR-017-browse-by-area-and-section]]"]
priority: Should
release: unscheduled
lane: backbone
order: 23
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Areas and sections follow the tailoring

## Story

As a [[STK-011-people-who-set-up-a-project-wiki]] **person setting up a project wiki** I want **the dashboard to show only the sections my project uses**, so that **readers don't stumble over parts of the method we left out**.

**PROBLEM / GOAL**

In Systems42 the metamodel is configurable. A project adapts it to its needs ([[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]]).

- The three areas (requirements, architecture, shared content) always exist.
- A project may leave out sections inside an area.
- A left-out section appears nowhere: not on the first page, in the header, in counts, lists or the guided path ([[FR-012-guided-path-through-the-wiki]]).
- An address that points to a left-out section shows "This part is not used in this project" instead of an error.
- Browsing works in the same three steps for every tailoring.

**Success metric(s).** On a test wiki with one section left out, that section appears nowhere, the three areas still show, and its address shows the note.

**Scope.** in: sections inside the areas · out: leaving out whole areas, and the view a session host sets (DR-002).

## Hierarchy

- **Parent:** [[FR-017-browse-by-area-and-section]]
- **Children:** none.

> [!note] Open points
> Where the tailoring sits in the schema and in which format is a follow-up of DR-002.

## History

> Added to the source by Gernot Starke on 2026-11-11. In [[SRC-014-grilling-session-on-browsing]] he limited it to sections inside the areas. Should, because this wiki uses every section.
