---
id: FR-053
type: functional-requirement
title: Reach the session controls and the theme from one menu
status: draft
created: 2026-11-19
updated: 2026-11-19
sources: ["[[SRC-034-dashboard-requirements-moved-from-meta]]", "[[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]"]
related: ["[[STK-008-workshop-participants-and-facilitators]]", "[[STK-023-keyholder]]", "[[FR-046-shared-session-in-a-workshop]]"]
tags: [functional-requirement, page-frame]
notation: agile
level: story
parent: ["[[FR-013-header-and-footer-on-every-page]]"]
building-blocks: []
priority: Could
release: unscheduled
lane: backbone
order: 53
goal: ["[[GOAL-002-show-what-systems42-can-do]]"]
---

# Reach the session controls and the theme from one menu

## Story

> follows [[user-story-format]], [[INVEST]]

As a [[STK-008-workshop-participants-and-facilitators|workshop facilitator]] I want **one menu on every page that holds the controls of the session and the theme**, so that **the header and the footer stay free of them**.

**Acceptance criteria.** > follows [[acceptance-criteria]]

- **Given** any page **when** I open the menu **then** it offers the View, the theme, who is connected, reloading the wiki from disk and, for the Keyholder only, Disconnect all ([[FR-046-shared-session-in-a-workshop]]).
- **Given** I choose the other theme **then** every page is shown in it, and the choice is kept in my browser.
- **Given** a reader who is not the Keyholder **then** the menu shows neither the View's changes nor Disconnect all as available.

**Scope.** in: the menu · out: the header entries and the footer items ([[FR-013-header-and-footer-on-every-page]]).

## Hierarchy

- **Parent:** [[FR-013-header-and-footer-on-every-page]]
- **Children:** none.

> [!note] Open points
> - The shape of the menu, for example a hamburger, is left open.
> - Built today: a menu opens from the header with Configure, the theme switch (kept in the browser), Who's here, Help, Metamodel, Reload and, for the Keyholder only, Disconnect all. The criteria hold. Two differences: the first entry is still called Configure, not View ([[FR-046-shared-session-in-a-workshop]]), and Help and Metamodel are in the menu but not in the criteria.

## History

> Moved from the Systems42 method wiki (meta DR-033, point 5) on 2026-11-19. FR-013 had left the menu out of scope. Peter Gerstbach decided on 2026-11-19: a Could story under FR-013; a help page is not needed, FR-010 to FR-012 carry it ([[SRC-035-grilling-session-on-the-requirements-moved-from-meta]]).
