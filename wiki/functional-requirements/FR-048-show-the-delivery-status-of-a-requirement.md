---
id: FR-048
type: functional-requirement
title: Show the delivery status of a requirement
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-008-workshop-participants-and-facilitators]]", "[[GOAL-006-source-and-status-on-every-statement]]", "[[FR-047-see-the-requirements-as-a-story-map]]"]
tags: [functional-requirement, story-map]
notation: agile
level: story
parent: ["[[FR-047-see-the-requirements-as-a-story-map]]"]
building-blocks: []
priority: Could
release: unscheduled
lane: backbone
order: 48
goal: ["[[GOAL-006-source-and-status-on-every-statement]]"]
---

# Show the delivery status of a requirement

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-008-workshop-participants-and-facilitators|workshop facilitator]] I want **the dashboard to show and filter requirements by delivery status**, so that **I see what is implemented, partial or outdated without opening each page**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** requirements have delivery values **when** I open a requirement in the dashboard **then** its delivery status is shown as a badge.
- **Given** requirements have different delivery values **when** I filter the dashboard by delivery status **then** only the matching requirements are shown.

## Hierarchy

- **Parent:** [[FR-047-see-the-requirements-as-a-story-map]]
- **Children:** none.

> [!note] Open points
> - Not built. The delivery fields come from the Systems42 method ([meta FR-031, Track requirement delivery](https://github.com/systems42-org/meta/blob/main/wiki/functional-requirements/FR-031-track-requirement-delivery.md)), whose Implement loop is still being built. The dashboard reads the fields once the metamodel declares them ([[ISS-004-where-the-metamodel-declares-its-version]]).

## History

> Moved from the Systems42 method wiki (meta FR-034) on 2026-11-19. Peter Gerstbach decided on 2026-11-19: a story under the story map, Could, depends on meta's Implement loop ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
