---
id: FR-051
type: functional-requirement
title: Reveal related page types layer by layer
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-013-people-learning-or-presenting-systems42]]", "[[FR-040-two-views-of-the-same-terms]]", "[[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]]", "[[QR-001-usable-on-phone-and-tablet]]"]
tags: [functional-requirement, domain-terms]
notation: agile
level: story
parent: ["[[FR-040-two-views-of-the-same-terms]]"]
priority: Should
release: unscheduled
lane: backbone
order: 51
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Reveal related page types layer by layer

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-013-people-learning-or-presenting-systems42|person presenting Systems42]] I want **the term network to start with the terms only and to add other page types one layer at a time**, so that **my audience follows how the vocabulary connects to stakeholders, goals and the rest**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** the term network **when** it opens **then** it shows the terms and the links between them, nothing else.
- **Given** a button for a page type, such as data models, stakeholders, interfaces or goals **when** I switch it on **then** the pages of that type next to the shown terms appear, and the others stay as they were. Switching it off removes them.
- **Given** the buttons **then** they are also the legend: each shows its type's frame colour and the number of links it adds.
- **Given** a link between two terms **then** it is drawn once and has no direction, and it comes from the `related:` field, never from a wikilink in the text.
- **Given** any node **then** its type is told by the colour of its frame and, for a term, its state (agreed, draft, deprecated, assumption) by the style of its frame; its size follows the number of its links; its label is always visible.
- **Given** I point at a node **then** its neighbours stand out and the rest dims.
- **Given** the light and the dark theme **then** the network reads the same in both.

## Hierarchy

- **Parent:** [[FR-040-two-views-of-the-same-terms]]
- **Children:** none.

> [!note] Open points
> None. Every node also stays reachable as a text link ([[QR-001-usable-on-phone-and-tablet]]).

## History

> Moved from the Systems42 method wiki (meta DR-023, the term network) on 2026-11-19, where the requirements were part of a decision record. Peter Gerstbach decided on 2026-11-19: they are requirements here; only the pattern behind them is a decision ([[DR-006-interactive-diagrams-are-projected-on-the-server-and-laid-out-in-the-browser]], [[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
