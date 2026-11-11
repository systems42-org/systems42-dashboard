---
id: FR-016
type: functional-requirement
title: See whether the page is still connected
status: draft
created: 2026-11-11
updated: 2026-11-11
sources: ["[[SRC-010-header-and-footer-on-every-page]]", "[[SRC-011-grilling-session-on-header-and-footer]]"]
related: ["[[STK-008-workshop-participants]]", "[[STK-007-workshop-facilitators]]", "[[FR-015-read-the-formalities-in-the-footer]]"]
tags: ["functional-requirement", "page-frame"]
stereotype: story
parent: ["[[FR-013-header-and-footer-on-every-page]]"]
priority: Should
release: unscheduled
lane: backbone
order: 16
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# See whether the page is still connected

## Story

As a [[STK-008-workshop-participants]] **workshop participant** I want **to see at a glance whether my page is still connected to the dashboard**, so that **I don't discuss a page that no longer updates**.

> follows [[user-story-format]]

**Acceptance criteria.**

- **Given** a page that is connected to the dashboard server **when** it is shown **then** a coloured dot in the footer moves.
- **Given** a page that has lost the connection **when** the loss is noticed **then** the dot stops moving and turns grey.
- **Given** a page that has lost the connection **when** the loss is noticed **then** the word "offline" replaces the client count ([[FR-015-read-the-formalities-in-the-footer]]).
- **Given** a page that has lost the connection **when** the loss is noticed **then** the banner at the top of the page and the grey page stay as they were before 2026-11-11.

## Hierarchy

- **Parent:** [[FR-013-header-and-footer-on-every-page]]
- **Children:** none.

> [!note] Open points
> None.

## History

> The moving dot that stops was asked for by Gernot Starke ([[SRC-010-header-and-footer-on-every-page]]). The grey dot and "offline" were added by Claude and confirmed in Q4 ([[SRC-011-grilling-session-on-header-and-footer]]).
