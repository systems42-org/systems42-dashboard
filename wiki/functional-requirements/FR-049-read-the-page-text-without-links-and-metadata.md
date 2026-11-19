---
id: FR-049
type: functional-requirement
title: Read the page text without links and metadata
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-001-readers]]", "[[FR-034-read-a-page-with-its-links]]", "[[CON-002-dashboard-never-writes-to-the-wiki]]"]
tags: [functional-requirement, page-frame]
notation: agile
level: story
parent: ["[[FR-034-read-a-page-with-its-links]]"]
building-blocks: []
priority: Should
release: unscheduled
lane: backbone
order: 49
goal: ["[[GOAL-003-answers-without-asking-a-colleague]]"]
---

# Read the page text without links and metadata

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-001-readers|domain expert]] reading a page I want **to hide cross-references and metadata in the text**, so that **the requirement reads cleanly**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** a page whose text has wikilinks and ID references **when** I switch the filter on **then** the text shows plain wording, without square brackets or IDs.
- **Given** I reload the page or come back later in the same browser **then** my setting is kept.
- **Given** another viewer **then** my setting does not change what they see.

**Scope.** in: the text of one page · out: lists, search hits and diagrams.

## Hierarchy

- **Parent:** [[FR-034-read-a-page-with-its-links]]
- **Children:** none.

> [!note] Open points
> None. The setting lives in the browser, so the dashboard writes nothing ([[CON-002-dashboard-never-writes-to-the-wiki]]).

## History

> An explicit wish of Peter Hruschka at the team meeting of 2026-10-12, priority "Hoch" in its minutes (meta `raw/ingested/entscheidungen-meeting-12-10-2026.md`). It was meta FR-013 until 2026-11-19. Peter Gerstbach decided on 2026-11-19: a story under FR-034, Should, only the text of a page ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
